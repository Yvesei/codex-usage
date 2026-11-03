import AppKit

struct UsageMenuState {
    let snapshot: UsageSnapshot?
    let refreshedAt: Date?
    let isRefreshing: Bool
    let errorMessage: String?
    let cacheWarning: String?
    let showBothPercentages: Bool
    let alertsEnabled: Bool
    let alertThreshold: Int
    var modelUsage: ModelAnalyticsSnapshot? = nil
    var modelError: String? = nil
    var isModelRefreshing = false
}

final class UsageMenuBuilder: NSObject {
    var onRefresh: (() -> Void)?
    var onQuit: (() -> Void)?
    var onShowBothChanged: ((Bool) -> Void)?
    var onAlertThresholdChanged: ((Int?) -> Void)?

    private var showBothPercentages = true

    func makeMenu(for state: UsageMenuState) -> NSMenu {
        showBothPercentages = state.showBothPercentages

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = 320

        if let snapshot = state.snapshot {
            let summary = NSMenuItem()
            summary.view = UsageSummaryView(snapshot: snapshot, refreshedAt: state.refreshedAt)
            menu.addItem(summary)
            addAdditionalLimits(snapshot, to: menu)
            addAccountDetails(snapshot, to: menu)
        }

        menu.addItem(.separator())
        let dailyItem = NSMenuItem()
        dailyItem.view = DailyTokenUsageView(usage: state.modelUsage, isRefreshing: state.isModelRefreshing)
        menu.addItem(dailyItem)

        if state.isRefreshing || needsRefresh(state) {
            menu.addItem(.separator())
            addStatus(state, to: menu)
        }
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = makeSettingsMenu(state)
        menu.addItem(settingsItem)

        let refreshItem = actionItem("Refresh Now", action: #selector(refresh))
        refreshItem.isEnabled = !state.isRefreshing
        menu.addItem(refreshItem)
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Codex Usage", action: #selector(quit), key: "q"))
        return menu
    }

    private func addWindow(_ window: UsageWindow?, title: String, to menu: NSMenu) {
        guard let window else {
            addInformation("\(title): Unavailable", to: menu)
            return
        }

        let used = Int(window.usedPercent.rounded())
        addInformation("\(title): \(window.remainingPercent)% remaining · \(used)% used", to: menu)

        if let reset = window.resetsAt {
            let resetDate = formattedReset(reset, window: window)
            let relative = relativeDate(reset)
            addInformation("    Resets \(resetDate) (\(relative))", to: menu)
        }
    }

    private func addAdditionalLimits(_ snapshot: UsageSnapshot, to menu: NSMenu) {
        guard !snapshot.otherWindows.isEmpty || !snapshot.additionalBuckets.isEmpty || !snapshot.models.isEmpty else {
            return
        }

        let submenu = NSMenu()
        submenu.autoenablesItems = false

        for window in snapshot.otherWindows {
            addWindow(window, title: title(for: window), to: submenu)
        }

        for bucket in snapshot.additionalBuckets {
            let name = bucket.name ?? bucket.model ?? bucket.id
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            let bucketMenu = NSMenu()
            bucketMenu.autoenablesItems = false

            if let model = bucket.model, model != name {
                addInformation("Model: \(model)", to: bucketMenu)
            }

            for window in bucket.windows {
                addWindow(window, title: title(for: window), to: bucketMenu)
            }

            if bucket.windows.isEmpty {
                addInformation("No limit details reported", to: bucketMenu)
            }

            item.submenu = bucketMenu
            submenu.addItem(item)
        }

        if !snapshot.models.isEmpty {
            let modelsItem = NSMenuItem(title: "Models", action: nil, keyEquivalent: "")
            let modelsMenu = NSMenu()
            modelsMenu.autoenablesItems = false

            for model in snapshot.models {
                addInformation(model, to: modelsMenu)
            }

            modelsItem.submenu = modelsMenu
            submenu.addItem(modelsItem)
        }

        menu.addItem(.separator())
        let item = NSMenuItem(title: "Additional Limits", action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    private func addAccountDetails(_ snapshot: UsageSnapshot, to menu: NSMenu) {
        var details: [String] = []

        if let credits = snapshot.resetCredits {
            details.append("Reset credits: \(credits)")
        }

        if snapshot.allowed == false {
            details.append("Included usage is currently unavailable")
        }

        guard !details.isEmpty else {
            return
        }

        menu.addItem(.separator())

        for detail in details {
            addInformation(detail, to: menu)
        }
    }

    private func needsRefresh(_ state: UsageMenuState) -> Bool {
        let usageNeedsRefresh = !state.isRefreshing && (
            state.errorMessage != nil || state.cacheWarning != nil || state.snapshot == nil
        )
        let modelNeedsRefresh = !state.isModelRefreshing && (
            state.modelError != nil || state.modelUsage == nil
        )
        return usageNeedsRefresh || modelNeedsRefresh
    }

    private func addStatus(_ state: UsageMenuState, to menu: NSMenu) {
        if state.isRefreshing {
            addInformation("Updating usage…", to: menu)
        }

        if needsRefresh(state) {
            addInformation("Please refresh", to: menu)
        }
    }

    private func makeSettingsMenu(_ state: UsageMenuState) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let showBoth = actionItem("Show Both Percentages", action: #selector(toggleShowBoth))
        showBoth.state = state.showBothPercentages ? .on : .off
        menu.addItem(showBoth)

        let alerts = NSMenuItem(title: "Low Usage Alerts", action: nil, keyEquivalent: "")
        let alertsMenu = NSMenu()
        alertsMenu.autoenablesItems = false

        let off = actionItem("Off", action: #selector(disableAlerts))
        off.state = state.alertsEnabled ? .off : .on
        alertsMenu.addItem(off)

        let ten = actionItem("At 10% Remaining", action: #selector(alertAtTenPercent))
        ten.state = state.alertsEnabled && state.alertThreshold == 10 ? .on : .off
        alertsMenu.addItem(ten)

        let five = actionItem("At 5% Remaining", action: #selector(alertAtFivePercent))
        five.state = state.alertsEnabled && state.alertThreshold == 5 ? .on : .off
        alertsMenu.addItem(five)

        alerts.submenu = alertsMenu
        menu.addItem(alerts)
        return menu
    }

    private func addInformation(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = true
        menu.addItem(item)
    }

    private func actionItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func title(for window: UsageWindow) -> String {
        guard let minutes = window.durationMinutes else {
            return "Other limit"
        }

        if minutes == 300 {
            return "5-hour limit"
        }

        if minutes == 10_080 {
            return "Weekly limit"
        }

        if minutes % 1_440 == 0 {
            return "\(minutes / 1_440)-day limit"
        }

        if minutes % 60 == 0 {
            return "\(minutes / 60)-hour limit"
        }

        return "\(minutes)-minute limit"
    }

    private func formattedReset(_ date: Date, window: UsageWindow) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")

        if let minutes = window.durationMinutes, minutes >= 1_440 {
            formatter.dateFormat = "d MMM, yyyy 'at' HH:mm"
        } else {
            formatter.dateFormat = "HH:mm"
        }

        return formatter.string(from: date)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @objc private func refresh() {
        onRefresh?()
    }

    @objc private func quit() {
        onQuit?()
    }

    @objc private func toggleShowBoth() {
        onShowBothChanged?(!showBothPercentages)
    }

    @objc private func disableAlerts() {
        onAlertThresholdChanged?(nil)
    }

    @objc private func alertAtTenPercent() {
        onAlertThresholdChanged?(10)
    }

    @objc private func alertAtFivePercent() {
        onAlertThresholdChanged?(5)
    }
}
