import AppKit
import UserNotifications

extension Data {
    /// APNs device token as lowercase hex (no spaces) — matches server storage format.
    var hexEncodedString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let pushClient = PushAPIClient(
        baseURL: BackendConfig.baseURL,
        deviceToken: BackendConfig.deviceToken
    )

    private var apnsDeviceToken: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Task { await requestNotificationPermission() }
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                DispatchQueue.main.async {
                    NSApplication.shared.registerForRemoteNotifications()
                }
            }
        } catch {
            // Notifications not allowed (no entitlement, or dev account not set up)
            // App continues normally — push is optional
            print("[AppDelegate] Notifications unavailable (expected if not set up yet): \(error)")
        }
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.hexEncodedString
        self.apnsDeviceToken = hex

        let bundleId = Bundle.main.bundleIdentifier ?? "mansur.BocilDashboard"
        #if DEBUG
        let environment = PushEnvironment.sandbox
        #else
        let environment = PushEnvironment.production
        #endif

        Task {
            do {
                _ = try await pushClient.register(
                    apnsDeviceToken: hex,
                    bundleId: bundleId,
                    environment: environment
                )
                print("[AppDelegate] Push device registered: \(hex)")
            } catch {
                print("[AppDelegate] Push registration failed: \(error)")
            }
        }
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[AppDelegate] Failed to register for remote notifications: \(error)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notification banner + sound even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        handleReminderDeepLink(userInfo: userInfo)
    }

    private func handleReminderDeepLink(userInfo: [AnyHashable: Any]) {
        guard let companion = userInfo["companion"] as? [String: Any],
              companion["type"] as? String == "reminder",
              let kind = companion["kind"] as? String,
              let id = companion["id"] as? String
        else { return }

        // Post notification for views to observe and navigate
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("ReminderTapped"),
                object: nil,
                userInfo: ["kind": kind, "id": id]
            )
        }
    }

    /// Unregister push device on logout (call this from SettingsView or auth cleanup)
    func unregisterPushDevice() async {
        guard let token = apnsDeviceToken else { return }
        do {
            try await pushClient.unregister(apnsDeviceToken: token)
            print("[AppDelegate] Push device unregistered")
        } catch {
            print("[AppDelegate] Push unregister failed: \(error)")
        }
    }
}
