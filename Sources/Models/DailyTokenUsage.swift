import Foundation

struct DailyTokenBucket: Codable, Equatable {
    let startDate: String
    let tokens: Int64
}

struct DailyTokenUsage: Codable, Equatable {
    let accountEmail: String?
    let buckets: [DailyTokenBucket]?
    let fetchedAt: Date
}

enum DailyTokenParserError: Error {
    case invalidResponse
}

struct DailyTokenParser {
    private struct Response: Decodable {
        let result: Payload
    }

    private struct Payload: Decodable {
        let dailyUsageBuckets: [DailyTokenBucket]?
    }

    func parse(_ data: Data, accountEmail: String?, fetchedAt: Date = Date()) throws -> DailyTokenUsage {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let buckets = response.result.dailyUsageBuckets

        for bucket in buckets ?? [] {
            guard bucket.tokens >= 0, isValidDate(bucket.startDate) else {
                throw DailyTokenParserError.invalidResponse
            }
        }

        return DailyTokenUsage(accountEmail: accountEmail, buckets: buckets, fetchedAt: fetchedAt)
    }

    private func isValidDate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              value.utf8.allSatisfy({ (48...57).contains($0) || $0 == 45 }),
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              year > 0 else {
            return false
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else {
            return false
        }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == year && actual.month == month && actual.day == day
    }
}
