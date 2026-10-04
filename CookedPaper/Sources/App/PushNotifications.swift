import Foundation
import UIKit
import UserNotifications

/// APNs registration. Permission is asked for at a moment of intent — creating a
/// price alert, or after a trade — never at launch. Once granted, the device
/// registers on every launch (Apple can rotate the token) and the hex token is sent
/// to `POST /social/apns-tokens` whenever there's a signed-in account: on
/// registration, after every sign-in, and on each launch. Sign-out revokes it
/// first (`POST /social/apns-tokens/revoke`) so the next person on this phone
/// doesn't get the previous account's alerts.
@MainActor
final class PushRegistrar {
    static let shared = PushRegistrar()

    private enum Keys {
        static let deviceToken = "push.apnsDeviceToken"
    }

    /// The last APNs token this device was given, lowercase hex. Persisted so
    /// sign-out can revoke it even in a launch where APNs hasn't called back yet.
    private(set) var deviceToken: String?

    private init() {
        deviceToken = UserDefaults.standard.string(forKey: Keys.deviceToken)
    }

    /// Which APNs gateway the token belongs to: DEBUG builds carry the
    /// `development` aps-environment, so their tokens are sandbox tokens.
    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    /// No permission prompts or APNs registration in UI-test runs: a system alert
    /// would sit over the walkthrough, and the mock has no device to push to.
    private static var isDisabled: Bool {
        #if DEBUG
        return MockAPI.isEnabled
        #else
        return false
        #endif
    }

    // MARK: - Permission and registration

    /// At launch: re-registers when permission was already given, never prompts.
    func registerIfAuthorized() async {
        guard !Self.isDisabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if Self.isAllowed(settings.authorizationStatus) {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// The high-intent ask. Prompts only if the person has never been asked (iOS
    /// shows the prompt once); registers if notifications are, or become, allowed.
    func requestPermissionIfNeeded() async {
        guard !Self.isDisabled else { return }
        // `current()` per call rather than one local carried across awaits, so no
        // non-Sendable reference is handed to two async calls in a row.
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        default:
            if Self.isAllowed(settings.authorizationStatus) {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// True when the person turned notifications off for this app, so screens
    /// that create alerts can say an alert won't reach them.
    func notificationsDenied() async -> Bool {
        guard !Self.isDisabled else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .denied
    }

    /// True only while iOS would still show its prompt — the moment for a soft
    /// "want a reminder?" ask first.
    func canAskPermission() async -> Bool {
        guard !Self.isDisabled else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .notDetermined
    }

    // MARK: - Local reminders

    static let trialReminderID = "trial.reminder"

    /// One local notification two days before a free trial converts (day 5 of a
    /// 7-day trial), when notifications are allowed. Replaces any earlier one.
    func scheduleTrialReminder(trialDays: Int, renewalPrice: String) async {
        guard !Self.isDisabled, trialDays > 0 else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard Self.isAllowed(settings.authorizationStatus) else { return }
        let daysBefore = min(2, max(0, trialDays - 1))
        let fireAfter = TimeInterval(trialDays - daysBefore) * 86_400
        let content = UNMutableNotificationContent()
        content.title = daysBefore == 1 ? "Your free trial ends tomorrow" : "Your free trial ends in \(daysBefore) days"
        content.body = "After that it's \(renewalPrice). Cancel anytime in Settings → Apple ID → Subscriptions."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, fireAfter), repeats: false)
        let request = UNNotificationRequest(identifier: Self.trialReminderID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.trialReminderID])
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    // MARK: - Token

    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    func didRegister(deviceToken data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = hex
        UserDefaults.standard.set(hex, forKey: Keys.deviceToken)
        Task { await uploadIfSignedIn() }
    }

    /// Sends the token to the account that's signed in now. Failures are left for
    /// the next launch or sign-in to retry; nothing on screen depends on it.
    func uploadIfSignedIn() async {
        guard SessionStore.shared.isSignedIn, let deviceToken else { return }
        try? await SocialAPI.registerAPNsToken(deviceToken, environment: Self.environment)
    }

    /// Call before clearing the session on sign-out, while the token still works.
    func revokeForSignOut() async {
        guard SessionStore.shared.isSignedIn, let deviceToken else { return }
        try? await SocialAPI.revokeAPNsToken(deviceToken)
    }
}
