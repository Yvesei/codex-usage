import Foundation

struct ModelAnalyticsParser {
    private struct Response: Decodable {
        let units: String?
        let data: [Record]
    }

    private struct Record: Decodable {
        let date: String
        let models: [Model]?
        let attribution: [Attribution]?
    }

    private struct Model: Decodable {
        let model: String
        let credits: Double?
    }

    private struct Attribution: Decodable {
        let model: String?
        let value: Double
    }

    func parse(
        _ data: Data,
        accountID: String,
        userID: String,
        dates: [String],
        fetchedAt: Date = Date()
    ) throws -> ModelAnalyticsSnapshot {
        guard dates.count == 7, Set(dates).count == 7 else {
            throw ModelAnalyticsError.invalidResponse
        }

        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ModelAnalyticsError.invalidResponse
        }
        guard response.data.count <= 1000 else {
            throw ModelAnalyticsError.invalidResponse
        }

        let requestedDates = Set(dates)
        var records: [Record] = []
        for record in response.data {
            let day = String(record.date.prefix(10))
            guard Self.isDate(day) else {
                throw ModelAnalyticsError.invalidResponse
            }
            if requestedDates.contains(day) {
                records.append(record)
            }
        }

        let attributed = !records.isEmpty && records.allSatisfy { $0.attribution != nil }
        var valuesByDate: [String: [String: Double]] = [:]
        for record in records {
            let day = String(record.date.prefix(10))
            let items: [ModelUsageValue]
            if attributed, let attribution = record.attribution {
                guard attribution.count <= 1000 else {
                    throw ModelAnalyticsError.invalidResponse
                }
                items = attribution.map { item in
                    ModelUsageValue(model: item.model ?? "Unknown", value: item.value)
                }
            } else if let models = record.models {
                guard models.count <= 1000 else {
                    throw ModelAnalyticsError.invalidResponse
                }
                items = try models.map { item in
                    guard let amount = item.credits else {
                        throw ModelAnalyticsError.invalidResponse
                    }
                    return ModelUsageValue(model: item.model, value: amount)
                }
            } else {
                throw ModelAnalyticsError.invalidResponse
            }

            var totals = valuesByDate[day] ?? [:]
            for item in items {
                let name = item.model.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name.count <= 200, item.value.isFinite, item.value >= 0 else {
                    throw ModelAnalyticsError.invalidResponse
                }
                let total = (totals[name] ?? 0) + item.value
                guard total.isFinite else {
                    throw ModelAnalyticsError.invalidResponse
                }
                totals[name] = total
            }
            valuesByDate[day] = totals
        }

        let days = dates.map { day -> ModelUsageDay in
            guard let totals = valuesByDate[day] else {
                return ModelUsageDay(date: day, models: nil)
            }
            let models = totals.keys.sorted().map { model in
                ModelUsageValue(model: model, value: totals[model]!)
            }
            return ModelUsageDay(date: day, models: models)
        }

        let unit: String
        if !attributed && response.units == "credits" {
            unit = "Credits"
        } else if response.units == nil || response.units == "percent" || attributed {
            unit = "Relative usage"
        } else {
            unit = "Usage"
        }

        return ModelAnalyticsSnapshot(accountID: accountID, userID: userID, days: days, unit: unit, fetchedAt: fetchedAt)
    }

    private static func isDate(_ value: String) -> Bool {
        guard value.count == 10 else {
            return false
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else {
            return false
        }
        return formatter.string(from: date) == value
    }
}
