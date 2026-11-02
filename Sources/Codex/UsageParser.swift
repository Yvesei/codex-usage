import CoreFoundation
import Foundation

enum UsageParserError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        return "Codex returned an incomplete usage response."
    }
}

struct UsageParser {
    func parse(_ result: [String: Any]) throws -> UsageSnapshot {
        let buckets = dictionary(result, "rateLimitsByLimitId", "rate_limits_by_limit_id")
        guard let selection = selectBucket(from: result, buckets: buckets) else {
            throw UsageParserError.invalidResponse
        }
        let bucket = selection.bucket
        guard bucket.keys.contains("primary") || bucket.keys.contains("secondary") else {
            throw UsageParserError.invalidResponse
        }

        let primary = try parseWindow(bucket["primary"])
        let secondary = try parseWindow(bucket["secondary"])
        let windows = [primary, secondary].compactMap { $0 }
        let fiveHour = windows.first { $0.durationMinutes == 300 }
        let weekly = windows.first { $0.durationMinutes == 10_080 }
        let plan = string(bucket, "planType", "plan_type")
        let allowed = bool(result, "ordinaryUsageAllowed", "ordinary_usage_allowed")
        let otherWindows = windows.filter {
            return $0.durationMinutes != 300 && $0.durationMinutes != 10_080
        }
        let additionalBuckets = try parseAdditionalBuckets(buckets, excluding: selection.key)
        let accountId = string(result, "accountId", "account_id")
        let accountEmail = string(result, "accountEmail", "account_email")
        let resetCredits = try parseResetCredits(result)

        return UsageSnapshot(
            fiveHour: fiveHour,
            weekly: weekly,
            plan: plan,
            allowed: allowed,
            otherWindows: otherWindows,
            additionalBuckets: additionalBuckets,
            accountId: accountId,
            accountEmail: accountEmail,
            resetCredits: resetCredits
        )
    }

    private func selectBucket(
        from result: [String: Any],
        buckets: [String: Any]?
    ) -> (bucket: [String: Any], key: String?)? {
        if let codex = buckets?["codex"] as? [String: Any] {
            return (codex, "codex")
        }

        if let legacy = dictionary(result, "rateLimits", "rate_limits") {
            let limitId = string(legacy, "limitId", "limit_id")
            return (legacy, limitId)
        }

        // Older responses can contain the snapshot directly.
        if result.keys.contains("primary") || result.keys.contains("secondary") {
            return (result, nil)
        }

        // A single named bucket is unambiguous even if it has a different ID.
        if let buckets = buckets,
           buckets.count == 1,
           let entry = buckets.first,
           let bucket = entry.value as? [String: Any] {
            return (bucket, entry.key)
        }

        return nil
    }

    private func parseWindow(_ value: Any?) throws -> UsageWindow? {
        guard let value = value, !(value is NSNull) else {
            return nil
        }
        guard let window = value as? [String: Any],
              let used = number(window, "usedPercent", "used_percent"),
              used.isFinite,
              (0...100).contains(used) else {
            throw UsageParserError.invalidResponse
        }

        let durationValue = number(window, "windowDurationMins", "window_duration_mins")
        if hasValue(window, "windowDurationMins", "window_duration_mins") && durationValue == nil {
            throw UsageParserError.invalidResponse
        }
        let duration: Int?
        if let durationValue = durationValue {
            guard durationValue.isFinite,
                  durationValue > 0,
                  durationValue <= Double(Int32.max),
                  durationValue.rounded(.towardZero) == durationValue else {
                throw UsageParserError.invalidResponse
            }
            duration = Int(durationValue)
        } else {
            duration = nil
        }

        let resetValue = number(window, "resetsAt", "resets_at")
        if hasValue(window, "resetsAt", "resets_at") && resetValue == nil {
            throw UsageParserError.invalidResponse
        }
        let resetsAt: Date?
        if let resetValue = resetValue {
            guard resetValue.isFinite, resetValue >= 0 else {
                throw UsageParserError.invalidResponse
            }
            let seconds = resetValue > 20_000_000_000 ? resetValue / 1_000 : resetValue
            resetsAt = Date(timeIntervalSince1970: seconds)
        } else {
            resetsAt = nil
        }

        return UsageWindow(
            usedPercent: used,
            durationMinutes: duration,
            resetsAt: resetsAt
        )
    }

    private func parseAdditionalBuckets(
        _ buckets: [String: Any]?,
        excluding selectedKey: String?
    ) throws -> [UsageBucket] {
        guard let buckets else {
            return []
        }

        var parsed: [UsageBucket] = []
        for key in buckets.keys.sorted() {
            guard key != selectedKey else {
                continue
            }
            guard let bucket = buckets[key] as? [String: Any],
                  bucket.keys.contains("primary") || bucket.keys.contains("secondary") else {
                throw UsageParserError.invalidResponse
            }

            let entry = UsageBucket(
                id: key,
                name: string(bucket, "limitName", "limit_name"),
                model: string(bucket, "normalModelSlug", "normal_model_slug"),
                primary: try parseWindow(bucket["primary"]),
                secondary: try parseWindow(bucket["secondary"])
            )
            parsed.append(entry)
        }
        return parsed
    }

    private func parseResetCredits(_ result: [String: Any]) throws -> Int? {
        guard let summary = dictionary(result, "rateLimitResetCredits", "rate_limit_reset_credits") else {
            return nil
        }
        guard hasValue(summary, "availableCount", "available_count") else {
            return nil
        }
        guard let value = number(summary, "availableCount", "available_count"),
              value.isFinite,
              value >= 0,
              value <= Double(Int32.max),
              value.rounded(.towardZero) == value else {
            throw UsageParserError.invalidResponse
        }
        return Int(value)
    }

    private func dictionary(_ object: [String: Any], _ key: String, _ alternate: String) -> [String: Any]? {
        return (object[key] ?? object[alternate]) as? [String: Any]
    }

    private func string(_ object: [String: Any], _ key: String, _ alternate: String) -> String? {
        return (object[key] ?? object[alternate]) as? String
    }

    private func bool(_ object: [String: Any], _ key: String, _ alternate: String) -> Bool? {
        return (object[key] ?? object[alternate]) as? Bool
    }

    private func number(_ object: [String: Any], _ key: String, _ alternate: String) -> Double? {
        let value = object[key] ?? object[alternate]
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else {
                return nil
            }
            return number.doubleValue
        }
        if let text = value as? String {
            return Double(text)
        }
        return nil
    }

    private func hasValue(_ object: [String: Any], _ key: String, _ alternate: String) -> Bool {
        guard let value = object[key] ?? object[alternate] else {
            return false
        }
        return !(value is NSNull)
    }
}
