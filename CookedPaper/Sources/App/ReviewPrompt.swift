import Foundation

/// When to ask for an App Store review: right after a profitable sell or close
/// (spot or leverage) — never after a loss — at most once every 90 days, and only
/// for a signed-in account. The ask itself is SwiftUI's `requestReview`, which iOS
/// may still decline to show.
enum ReviewPrompt {
    private static let lastRequestedKey = "review.lastRequestedAt"
    static let minimumInterval: TimeInterval = 90 * 86_400

    static func shouldRequest(afterProfit isProfitable: Bool, now: Date = Date()) -> Bool {
        guard isProfitable, SessionStore.shared.isSignedIn else { return false }
        #if DEBUG
        // A review sheet would sit over UI-test runs.
        if MockAPI.isEnabled { return false }
        #endif
        guard let last = UserDefaults.standard.object(forKey: lastRequestedKey) as? Date else { return true }
        return now.timeIntervalSince(last) >= minimumInterval
    }

    static func markRequested(now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: lastRequestedKey)
    }
}
