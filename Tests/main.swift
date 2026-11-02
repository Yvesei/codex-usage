import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError(message)
    }
}

let result: [String: Any] = [
    "rateLimitsByLimitId": [
        "other": [
            "limitName": "Special quota",
            "normalModelSlug": "example-model",
            "primary": ["usedPercent": 90, "windowDurationMins": 300],
            "secondary": ["usedPercent": 50, "windowDurationMins": NSNull()] as [String: Any]
        ] as [String: Any],
        "codex": [
            "planType": "plus",
            "primary": ["usedPercent": 25, "windowDurationMins": 300, "resetsAt": 1_800_000_000],
            "secondary": ["usedPercent": 40, "windowDurationMins": 10_080]
        ]
    ],
    "accountId": "account-a",
    "accountEmail": "user@example.com",
    "rateLimitResetCredits": ["availableCount": 2]
]

let parser = UsageParser()
let snapshot = try parser.parse(result)
expect(snapshot.fiveHour?.remainingPercent == 75, "The Codex bucket should take precedence.")
expect(snapshot.weekly?.remainingPercent == 60, "The weekly allowance should be read from the Codex bucket.")
expect(snapshot.plan == "plus", "The plan should be retained.")
expect(snapshot.accountId == "account-a", "The account identity should be retained.")
expect(snapshot.accountEmail == "user@example.com", "The account email should be retained.")
expect(snapshot.resetCredits == 2, "The reset credit count should be retained.")
expect(snapshot.additionalBuckets.count == 1, "Each separate bucket should be retained.")
let additional = snapshot.additionalBuckets[0]
expect(additional.name == "Special quota", "The quota name belongs to its own bucket.")
expect(additional.model == "example-model", "The model belongs to its own bucket.")
expect(additional.fiveHour?.remainingPercent == 10, "Separate quotas must keep their own usage.")
expect(additional.secondary?.durationMinutes == nil, "An unknown duration must remain unknown.")

let cached = CachedUsage(snapshot: snapshot, refreshedAt: Date(timeIntervalSince1970: 1_800_000_000))
let data = try JSONEncoder().encode(cached)
let restored = try JSONDecoder().decode(CachedUsage.self, from: data)
expect(restored.snapshot.fiveHour?.remainingPercent == 75, "Saved readings should round-trip.")
expect(restored.snapshot.accountId == "account-a", "Saved readings should retain their account identity.")
expect(restored.snapshot.additionalBuckets[0].model == "example-model", "Saved readings should retain separate quotas.")

let oldData = """
{"snapshot":{"fiveHour":{"usedPercent":10},"models":[]},"refreshedAt":0}
""".data(using: .utf8)!
let oldCache = try JSONDecoder().decode(CachedUsage.self, from: oldData)
expect(oldCache.snapshot.fiveHour?.remainingPercent == 90, "Older saved readings should remain readable.")
expect(oldCache.snapshot.accountId == nil, "Older saved readings have an unknown account.")
expect(oldCache.snapshot.additionalBuckets.isEmpty, "Older saved readings have no separate buckets.")

let unknownDuration: [String: Any] = [
    "rateLimits": ["primary": ["usedPercent": 30, "windowDurationMins": NSNull()] as [String: Any]]
]
let unknownSnapshot = try parser.parse(unknownDuration)
expect(unknownSnapshot.fiveHour == nil, "Unknown duration must not be called a five-hour window.")
expect(unknownSnapshot.otherWindows.count == 1, "An unknown duration should not hide reported usage.")

let invalid: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 120, "windowDurationMins": 300]]]
do {
    _ = try parser.parse(invalid)
    fatalError("Invalid percentages should not replace the cached reading.")
} catch UsageParserError.invalidResponse {
    print("Usage parser and cache checks passed.")
}
