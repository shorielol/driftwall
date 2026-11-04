import AppKit
import ServiceManagement
import UserNotifications

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns a user-facing error message, or nil on success.
    static func set(enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            AppLog.info("Launch at login \(enabled ? "enabled" : "disabled")")
            return nil
        } catch {
            AppLog.error("Launch at login change failed: \(error.localizedDescription)")
            return "macOS didn't allow Driftwall to change its login item. Move Driftwall to Applications, then try again."
        }
    }
}

enum DropNotifier {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func announce(dropID: String, count: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "A fresh drop just landed"
        content.body = "\(count) new live wallpapers are ready to preview."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "drop-\(dropID)", content: content, trigger: nil)
        try? await center.add(request)
    }
}
