import Foundation

struct DailyTokenCache {
    private let key = "lastDailyTokenUsage"
    private let defaults = UserDefaults.standard

    func load() -> DailyTokenUsage? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(DailyTokenUsage.self, from: data)
    }

    func save(_ usage: DailyTokenUsage) {
        guard usage.accountEmail != nil else {
            clear()
            return
        }
        guard let data = try? JSONEncoder().encode(usage) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
