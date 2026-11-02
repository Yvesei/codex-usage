import Foundation

final class UsagePreferences {
    private let defaults = UserDefaults.standard
    private let showBothKey = "showBothWindows"
    private let alertsKey = "usageAlertsEnabled"
    private let thresholdKey = "usageAlertThreshold"

    var showBothWindows: Bool {
        get {
            if defaults.object(forKey: showBothKey) == nil {
                return true
            }
            return defaults.bool(forKey: showBothKey)
        }
        set {
            defaults.set(newValue, forKey: showBothKey)
        }
    }

    var alertsEnabled: Bool {
        get {
            return defaults.bool(forKey: alertsKey)
        }
        set {
            defaults.set(newValue, forKey: alertsKey)
        }
    }

    var alertThreshold: Int {
        get {
            let value = defaults.integer(forKey: thresholdKey)
            return value == 5 ? 5 : 10
        }
        set {
            defaults.set(newValue == 5 ? 5 : 10, forKey: thresholdKey)
        }
    }
}
