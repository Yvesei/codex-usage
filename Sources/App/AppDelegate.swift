import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let reader = CodexUsageReader()
    private let cache = UsageCache()
    private let dailyReader = DailyTokenReader()
    private let dailyCache = DailyTokenCache()
    private let preferences = UsagePreferences()
    private let alerts = UsageAlerts()
    private let menuBuilder = UsageMenuBuilder()

    private var statusItem: NSStatusItem!
    private var snapshot: UsageSnapshot?
    private var refreshedAt: Date?
    private var isRefreshing = false
    private var errorMessage: String?
    private var notificationMessage: String?
    private var cacheWarning: String?
    private var dailyUsage: DailyTokenUsage?
    private var dailyError: String?
    private var dailyCacheWarning: String?
    private var isDailyRefreshing = false
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureActions()

        if let saved = cache.load() {
            snapshot = saved.snapshot
            refreshedAt = saved.refreshedAt
            cacheWarning = "Saved reading · checking the current account"
        }

        if let saved = dailyCache.load() {
            dailyUsage = saved
            dailyCacheWarning = "Saved token activity · checking the current account"
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(macDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        render()
        alerts.requestPermission { _ in }
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func configureActions() {
        menuBuilder.onRefresh = { [weak self] in
            self?.refresh()
        }
        menuBuilder.onQuit = {
            NSApplication.shared.terminate(nil)
        }
        menuBuilder.onShowBothChanged = { [weak self] value in
            self?.preferences.showBothWindows = value
            self?.render()
        }
        menuBuilder.onAlertThresholdChanged = { [weak self] threshold in
            guard let self else {
                return
            }

            if let threshold {
                self.preferences.alertThreshold = threshold
                self.setAlertsEnabled(true)
            } else {
                self.setAlertsEnabled(false)
            }
        }
        reader.onAccountRead = { [weak self] email in
            self?.checkSavedAccount(email)
        }
        dailyReader.onAccountRead = { [weak self] email in
            self?.checkDailyAccount(email)
        }
    }

    private func checkDailyAccount(_ email: String?) {
        guard let savedEmail = dailyUsage?.accountEmail else {
            return
        }
        guard let email, email.caseInsensitiveCompare(savedEmail) == .orderedSame else {
            dailyUsage = nil
            dailyCacheWarning = nil
            dailyCache.clear()
            render()
            return
        }
    }

    private func checkSavedAccount(_ email: String?) {
        guard let email else {
            snapshot = nil
            refreshedAt = nil
            cacheWarning = nil
            cache.clear()
            dailyUsage = nil
            dailyCacheWarning = nil
            dailyCache.clear()
            render()
            return
        }

        guard let savedEmail = snapshot?.accountEmail else {
            return
        }

        if email.caseInsensitiveCompare(savedEmail) != .orderedSame {
            snapshot = nil
            refreshedAt = nil
            cacheWarning = nil
            cache.clear()
            render()
        }
    }

    private func setAlertsEnabled(_ enabled: Bool) {
        guard enabled else {
            preferences.alertsEnabled = false
            notificationMessage = nil
            render()
            return
        }

        alerts.requestPermission { [weak self] granted in
            guard let self else {
                return
            }

            self.preferences.alertsEnabled = granted
            self.notificationMessage = granted ? nil : "Notifications are off"
            self.render()
        }
    }

    @objc private func macDidWake() {
        refresh()
    }

    private func refresh() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        errorMessage = nil
        refreshDailyUsage()
        render()

        reader.read { [weak self] result in
            guard let self else {
                return
            }

            self.isRefreshing = false

            switch result {
            case .success(let snapshot):
                let now = Date()
                self.snapshot = snapshot
                self.refreshedAt = now
                self.cacheWarning = nil
                self.cache.save(snapshot, at: now)

                if self.preferences.alertsEnabled {
                    self.alerts.check(snapshot, threshold: self.preferences.alertThreshold)
                }
            case .failure(let error):
                self.errorMessage = self.message(for: error)
                if self.snapshot != nil {
                    self.cacheWarning = "Saved reading · current account or workspace not yet verified"
                }
            }

            self.render()
        }
    }

    private func refreshDailyUsage() {
        guard !isDailyRefreshing else {
            return
        }

        isDailyRefreshing = true
        dailyError = nil
        dailyReader.read { [weak self] result in
            guard let self else {
                return
            }

            self.isDailyRefreshing = false
            switch result {
            case .success(let usage):
                if let email = usage.accountEmail,
                   let quotaEmail = self.snapshot?.accountEmail,
                   email.caseInsensitiveCompare(quotaEmail) != .orderedSame {
                    self.dailyUsage = nil
                    self.dailyCache.clear()
                    self.dailyCacheWarning = nil
                    self.dailyError = "Account changed. Refresh to update token activity."
                } else if usage.buckets == nil, self.dailyUsage?.buckets != nil {
                    self.dailyError = "Daily token activity is unavailable."
                    self.dailyCacheWarning = "Showing saved token activity"
                } else {
                    self.dailyUsage = usage
                    self.dailyCacheWarning = nil
                    self.dailyCache.save(usage)
                }
            case .failure(let error):
                self.dailyError = (error as? LocalizedError)?.errorDescription ?? "Couldn't update token activity."
                if self.dailyUsage != nil {
                    self.dailyCacheWarning = "Saved token activity · current account not yet verified"
                }
            }
            self.render()
        }
    }

    private func message(for error: Error) -> String {
        return (error as? LocalizedError)?.errorDescription ?? "Couldn't update usage. Please try again."
    }

    private func render() {
        let fiveHour = snapshot?.fiveHour?.remainingPercent
        let weekly = snapshot?.weekly?.remainingPercent
        statusItem.button?.image = UsageStatusIcon.make(fiveHour: fiveHour, weekly: weekly)
        statusItem.button?.title = statusTitle(fiveHour: fiveHour, weekly: weekly)
        statusItem.button?.toolTip = "Codex usage remaining"

        var state = UsageMenuState(
            snapshot: snapshot,
            refreshedAt: refreshedAt,
            isRefreshing: isRefreshing,
            errorMessage: errorMessage,
            cacheWarning: cacheWarning,
            showBothPercentages: preferences.showBothWindows,
            alertsEnabled: preferences.alertsEnabled,
            alertThreshold: preferences.alertThreshold
        )
        state.dailyUsage = dailyUsage
        state.dailyError = dailyError
        state.dailyCacheWarning = dailyCacheWarning
        state.isDailyRefreshing = isDailyRefreshing
        let menu = menuBuilder.makeMenu(for: state)
        if let notificationMessage {
            let item = NSMenuItem(title: notificationMessage, action: nil, keyEquivalent: "")
            item.isEnabled = true
            let settingsIndex = menu.indexOfItem(withTitle: "Settings")
            let insertionIndex = settingsIndex >= 0 ? settingsIndex : menu.numberOfItems
            menu.insertItem(item, at: insertionIndex)
        }
        statusItem.menu = menu
    }

    private func statusTitle(fiveHour: Int?, weekly: Int?) -> String {
        let short = fiveHour.map { "\($0)%" } ?? "—"
        guard preferences.showBothWindows else {
            return short
        }

        let long = weekly.map { "\($0)%" } ?? "—"
        return "5h \(short) · 7d \(long)"
    }

}
