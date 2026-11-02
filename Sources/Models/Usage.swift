import Foundation

struct UsageWindow: Codable {
    let usedPercent: Double
    let durationMinutes: Int?
    let resetsAt: Date?

    var remainingPercent: Int {
        let remaining = 100 - usedPercent
        let rounded = Int(remaining.rounded())
        return max(0, min(100, rounded))
    }
}

struct UsageBucket: Codable {
    let id: String
    let name: String?
    let model: String?
    let primary: UsageWindow?
    let secondary: UsageWindow?

    var windows: [UsageWindow] {
        return [primary, secondary].compactMap { $0 }
    }

    var fiveHour: UsageWindow? {
        return windows.first { $0.durationMinutes == 300 }
    }

    var weekly: UsageWindow? {
        return windows.first { $0.durationMinutes == 10_080 }
    }
}

struct UsageSnapshot: Codable {
    let fiveHour: UsageWindow?
    let weekly: UsageWindow?
    let plan: String?
    let allowed: Bool?
    let models: [String]
    let otherWindows: [UsageWindow]
    let additionalBuckets: [UsageBucket]
    let accountId: String?
    let accountEmail: String?
    let resetCredits: Int?

    init(
        fiveHour: UsageWindow?,
        weekly: UsageWindow?,
        plan: String?,
        allowed: Bool?,
        models: [String] = [],
        otherWindows: [UsageWindow] = [],
        additionalBuckets: [UsageBucket] = [],
        accountId: String? = nil,
        accountEmail: String? = nil,
        resetCredits: Int? = nil
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.plan = plan
        self.allowed = allowed
        self.models = models
        self.otherWindows = otherWindows
        self.additionalBuckets = additionalBuckets
        self.accountId = accountId
        self.accountEmail = accountEmail
        self.resetCredits = resetCredits
    }

    private enum CodingKeys: String, CodingKey {
        case fiveHour, weekly, plan, allowed, models, otherWindows
        case additionalBuckets, accountId, accountEmail, resetCredits
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try values.decodeIfPresent(UsageWindow.self, forKey: .fiveHour)
        weekly = try values.decodeIfPresent(UsageWindow.self, forKey: .weekly)
        plan = try values.decodeIfPresent(String.self, forKey: .plan)
        allowed = try values.decodeIfPresent(Bool.self, forKey: .allowed)
        models = try values.decodeIfPresent([String].self, forKey: .models) ?? []
        otherWindows = try values.decodeIfPresent([UsageWindow].self, forKey: .otherWindows) ?? []
        additionalBuckets = try values.decodeIfPresent([UsageBucket].self, forKey: .additionalBuckets) ?? []
        accountId = try values.decodeIfPresent(String.self, forKey: .accountId)
        accountEmail = try values.decodeIfPresent(String.self, forKey: .accountEmail)
        resetCredits = try values.decodeIfPresent(Int.self, forKey: .resetCredits)
    }
}

struct CachedUsage: Codable {
    let snapshot: UsageSnapshot
    let refreshedAt: Date
}
