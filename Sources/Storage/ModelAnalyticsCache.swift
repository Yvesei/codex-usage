import Foundation

struct ModelAnalyticsCache {
    private let key = "lastModelAnalytics"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(for identity: ModelAnalyticsIdentity) -> ModelAnalyticsSnapshot? {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(ModelAnalyticsSnapshot.self, from: data),
              snapshot.accountID == identity.accountID,
              snapshot.userID == identity.userID else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: ModelAnalyticsSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
