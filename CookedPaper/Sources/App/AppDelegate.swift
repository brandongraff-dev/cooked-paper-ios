import UIKit
import UserNotifications

/// UIKit's half of push notifications, attached through
/// `@UIApplicationDelegateAdaptor`: the APNs token callbacks, and the notification
/// center delegate that shows banners in the foreground and turns a tapped alert
/// into a token deep link.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set before launch finishes so a tap that launched the app is delivered.
        UNUserNotificationCenter.current().delegate = self
        Task { await PushRegistrar.shared.registerIfAuthorized() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistrar.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulators without push support and unsigned builds land here; alerts
        // still save server-side and the next launch tries again.
    }
}

// `nonisolated`, and calling the completion handlers synchronously: the system may
// call these off the main thread, and nothing here needs main-actor state except
// the router, which is reached with an explicit hop.
extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Banners while the app is open, too — a price alert is worth seeing now.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// A push with a top-level `"mint"` opens that token, as
    /// `cookedpaper://token/<mint>` would; `"duelId"` opens that duel and
    /// `"achievementId"` the achievements grid.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let mint = userInfo["mint"] as? String
        let duelId = userInfo["duelId"] as? String
        let achievementId = userInfo["achievementId"] as? String
        if let duelId, !duelId.isEmpty {
            Task { @MainActor in
                DeepLinkRouter.shared.openDuel(id: duelId)
            }
        } else if let achievementId, !achievementId.isEmpty {
            Task { @MainActor in
                DeepLinkRouter.shared.openAchievements()
            }
        } else if let mint, !mint.isEmpty {
            Task { @MainActor in
                DeepLinkRouter.shared.openToken(mint: mint)
            }
        }
        completionHandler()
    }
}
