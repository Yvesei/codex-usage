import Foundation

struct ModelUsageValue: Codable, Equatable {
    let model: String
    let value: Double
}

struct ModelUsageDay: Codable, Equatable {
    let date: String
    let models: [ModelUsageValue]?
}

struct ModelAnalyticsSnapshot: Codable, Equatable {
    let accountID: String
    let userID: String
    let days: [ModelUsageDay]
    let unit: String
    let fetchedAt: Date
}

struct ModelAnalyticsIdentity: Equatable {
    let accountID: String
    let userID: String
    let email: String?
}

enum ModelAnalyticsError: Error {
    case signInRequired
    case accountChanged
    case requestFailed
    case invalidResponse
}

struct AnalyticsDateRange {
    let dates: [String]

    init(endingAt now: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let today = calendar.startOfDay(for: now)
        dates = (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            return formatter.string(from: date)
        }
    }
}
