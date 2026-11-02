import Foundation

struct UsageCache {
    private let key = "lastUsageSnapshot"
    private let defaults = UserDefaults.standard

    func load() -> CachedUsage? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(CachedUsage.self, from: data)
    }

    func load(forAccountId accountId: String) -> CachedUsage? {
        guard let cached = load(), cached.snapshot.accountId == accountId else {
            return nil
        }
        return cached
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    func save(_ snapshot: UsageSnapshot, at date: Date) {
        let cached = CachedUsage(snapshot: snapshot, refreshedAt: date)

        guard let data = try? JSONEncoder().encode(cached) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
