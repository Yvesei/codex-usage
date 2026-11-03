import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError(message)
    }
}

func parse(_ text: String, dates: [String]) throws -> ModelAnalyticsSnapshot {
    return try ModelAnalyticsParser().parse(
        Data(text.utf8),
        accountID: "account-one",
        userID: "user-one",
        dates: dates
    )
}

let formatter = ISO8601DateFormatter()
let instant = formatter.date(from: "2026-11-03T00:10:00Z")!
let dates = AnalyticsDateRange(endingAt: instant, timeZone: TimeZone(secondsFromGMT: 0)!).dates
check(dates == ["2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03"], "Seven inclusive UTC dates")
let paris = TimeZone(identifier: "Europe/Paris")!
let localInstant = formatter.date(from: "2026-11-02T23:30:00Z")!
let parisDates = AnalyticsDateRange(endingAt: localInstant, timeZone: paris).dates
check(parisDates.last == "2026-11-03", "Axis ends on the local calendar date")

let legacy = try parse("""
{
  "units": "credits",
  "data": [
    {"date":"2026-11-02", "models":[{"model":"alpha","credits":2.5},{"model":"beta","credits":1}]},
    {"date":"2026-11-03T00:00:00Z", "models":[{"model":"alpha","credits":3}]},
    {"date":"2026-11-03", "models":[{"model":"alpha","credits":4}]}
  ]
}
""", dates: dates)
check(legacy.days.count == 7, "Every calendar date is present")
check(legacy.days[4].models == nil, "Missing data must remain unavailable")
check(legacy.days[5].models == [ModelUsageValue(model: "alpha", value: 2.5), ModelUsageValue(model: "beta", value: 1)], "Models preserved")
check(legacy.days[6].models == [ModelUsageValue(model: "alpha", value: 7)], "Duplicate dates and models combine")
check(legacy.unit == "Credits", "Units are not labelled as tokens")

let attributed = try parse("""
{"units":"percent", "data":[{"date":"2026-11-03", "models":[{"model":"alpha"}], "attribution":[{"model":"alpha","value":12.5},{"model":"beta","value":4}]}]}
""", dates: dates)
check(attributed.days[6].models?.count == 2, "Attribution is preferred over legacy model rows")
check(attributed.unit == "Relative usage", "Percentage report has relative units")

let empty = try parse("{\"data\":[]}", dates: dates)
check(empty.days.allSatisfy { $0.models == nil }, "Missing reports are not zero usage")

for bad in [
    "{\"data\":[{\"date\":\"2026-11-03\",\"models\":[{\"model\":\"alpha\",\"credits\":-1}]}]}",
    "{\"data\":[{\"date\":\"2026-11-03\",\"models\":[{\"model\":\"alpha\"}]}]}",
    "{\"data\":[{\"date\":\"2026-02-30\",\"models\":[]}]}",
    "{\"data\":[{\"date\":\"2026-11-03\"}]}"
] {
    do {
        _ = try parse(bad, dates: dates)
        fatalError("Invalid analytics were accepted")
    } catch ModelAnalyticsError.invalidResponse {
        continue
    }
}

let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
defer {
    try? FileManager.default.removeItem(at: tempDirectory)
}

let claims: [String: Any] = [
    "email": "test@example.invalid",
    "https://api.openai.com/auth": ["chatgpt_user_id": "user-one", "chatgpt_account_id": "account-one"]
]
let claimData = try JSONSerialization.data(withJSONObject: claims)
let payload = claimData.base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
let auth: [String: Any] = [
    "auth_mode": "chatgpt",
    "tokens": ["id_token": "header.\(payload).signature", "access_token": "dummy", "account_id": "account-one"]
]
let authData = try JSONSerialization.data(withJSONObject: auth)
try authData.write(to: tempDirectory.appendingPathComponent("auth.json"))
let credentials = try CodexAnalyticsCredentials.load(environment: ["CODEX_HOME": tempDirectory.path])
check(credentials.identity.accountID == "account-one", "Account identity is read from the selected Codex home")
check(credentials.identity.userID == "user-one", "User identity is required for account isolation")

print("Model analytics parser checks passed.")
