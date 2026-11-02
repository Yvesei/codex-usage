import Foundation
import UserNotifications

final class UsageAlerts: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var alertedWindows: Set<String> = []
    private var permissionCallbacks: [(Bool) -> Void] = []
    private var isCheckingPermission = false

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        permissionCallbacks.append(completion)

        guard !isCheckingPermission else {
            return
        }

        isCheckingPermission = true
        center.getNotificationSettings { [weak self] settings in
            guard let self else {
                return
            }

            if settings.authorizationStatus == .notDetermined {
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    self.finishPermissionRequest(granted)
                }
            } else {
                let granted = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
                self.finishPermissionRequest(granted)
            }
        }
    }

    private func finishPermissionRequest(_ granted: Bool) {
        DispatchQueue.main.async {
            let callbacks = self.permissionCallbacks
            self.permissionCallbacks.removeAll()
            self.isCheckingPermission = false

            for callback in callbacks {
                callback(granted)
            }
        }
    }

    func check(_ snapshot: UsageSnapshot, threshold: Int) {
        checkWindow(snapshot.fiveHour, name: "5-hour", accountId: snapshot.accountId, threshold: threshold)
        checkWindow(snapshot.weekly, name: "Weekly", accountId: snapshot.accountId, threshold: threshold)
    }

    private func checkWindow(_ window: UsageWindow?, name: String, accountId: String?, threshold: Int) {
        guard let window, window.remainingPercent <= threshold else {
            return
        }

        let reset = window.resetsAt?.timeIntervalSince1970 ?? 0
        let key = "\(accountId ?? "unknown")-\(name)-\(reset)-\(threshold)"

        guard !alertedWindows.contains(key) else {
            return
        }

        alertedWindows.insert(key)
        let content = UNMutableNotificationContent()
        content.title = "Codex usage is low"
        content.body = "\(name) allowance: \(window.remainingPercent)% remaining."
        content.sound = .default
        let request = UNNotificationRequest(identifier: key, content: content, trigger: nil)
        center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
