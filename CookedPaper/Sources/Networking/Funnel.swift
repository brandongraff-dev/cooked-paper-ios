import Foundation

/// The conversion funnel: a handful of named steps (install → onboarding → paywall →
/// trial → paid), sent to `POST /events` so the drop-off between them can be
/// measured. Best effort by design: events are batched, sent in the background, and
/// dropped on failure; nothing here can block or break a screen.
///
/// Each event carries an anonymous device id (a random UUID made on first launch,
/// never the IDFA) and, when signed in, the account's token so the server can tie
/// the steps to an account.
@MainActor
enum Funnel {
    enum Event: String {
        case appOpened = "app_opened"
        case onboardingStarted = "onboarding_started"
        case onboardingCompleted = "onboarding_completed"
        case paywallShown = "paywall_shown"
        case paywallClosed = "paywall_closed"
        case trialStarted = "trial_started"
        case subscribed = "subscribed"
        case offerShown = "offer_shown"
        case upsellTapped = "upsell_tapped"
        case firstTrade = "first_trade"
    }

    private struct Item: Encodable {
        let name: String
        let at: String
        let props: [String: String]
    }

    private struct Batch: Encodable {
        let deviceId: String
        let events: [Item]
    }

    private static var queue: [Item] = []
    private static var flushTask: Task<Void, Never>?
    private static let deviceKey = "funnel.deviceId"
    private static let onceKey = "funnel.once."

    static var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: deviceKey) { return existing }
        let fresh = UUID().uuidString.lowercased()
        UserDefaults.standard.set(fresh, forKey: deviceKey)
        return fresh
    }

    static func track(_ event: Event, _ props: [String: String] = [:]) {
        #if DEBUG
        if MockAPI.isEnabled { return }
        #endif
        let at = Date().formatted(.iso8601)
        queue.append(Item(name: event.rawValue, at: at, props: props))
        scheduleFlush()
    }

    /// Tracks `event` the first time only, on this device (first trade, first open).
    static func trackOnce(_ event: Event, _ props: [String: String] = [:]) {
        let key = onceKey + event.rawValue
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        track(event, props)
    }

    private static func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task {
            // A short pause gathers a screen's worth of steps into one request.
            try? await Task.sleep(for: .seconds(queue.count >= 20 ? 0 : 3))
            guard !Task.isCancelled else { return }
            await flush()
        }
    }

    private static func flush() async {
        guard !queue.isEmpty else { return }
        let events = Array(queue.prefix(50))
        queue.removeFirst(events.count)
        let client = APIClient.shared
        let endpoint = Endpoint(
            path: "events",
            method: "POST",
            body: client.encode(Batch(deviceId: deviceId, events: events)),
            signsOutOnUnauthorized: false
        )
        try? await client.sendIgnoringResponse(endpoint)
        if !queue.isEmpty { scheduleFlush() }
    }
}
