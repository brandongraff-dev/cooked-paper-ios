import Foundation
import Observation
import SwiftUI

/// Why the paywall is showing. Each reason gets its own headline, so the offer
/// meets the person at the moment that brought them there.
enum PaywallReason: Equatable {
    /// After sign-in, once. Closable: the app is usable on the free tier.
    case onboarding
    /// The day's free trades are used up.
    case outOfTrades
    /// The account's full-access days just ended.
    case fullAccessEnded
    /// Right after a sell at a profit, on the free tier.
    case afterWin
    /// A Pro-only feature, named for the headline ("Leverage", "Price alerts").
    case locked(String)
}

/// The free tier: full access for the account's first three days, then three
/// trades (buys) a day in the main portfolio. Selling is never limited: a limit
/// must not trap anyone in a position they want out of. Pro (any subscription)
/// lifts every limit.
///
/// Enforced here, on the device, the same way the subscription itself is — the API
/// deliberately has no paywall (`packages/billing/src/entitlements.ts`). Both inputs
/// are server-side facts, so reinstalling doesn't reset them: the full-access window
/// starts at the account's `createdAt`, and today's count comes from the
/// portfolio's own trade history (`GET /paper/portfolios/:id/trades`).
///
/// Duel trades don't count: a duel is someone's friend inviting them in, and that
/// has to work without paying.
@Observable
@MainActor
final class FreeTier {
    static let shared = FreeTier()

    static let freeTradesPerDay = 3
    static let fullAccessDays = 3

    /// Main-portfolio buys executed today, as of the last count.
    private(set) var countedTrades = 0
    /// The day `countedTrades` is for; a count from yesterday reads as zero.
    private var countedDay: Date?

    private enum Keys {
        static let firstLaunch = "freeTier.firstLaunch"
    }

    private init() {}

    var isPro: Bool { SubscriptionStore.shared.isSubscribed }

    /// When the account's full access ends: three days after it was created, or
    /// after this device first ran the app when the server hasn't said yet.
    var fullAccessEndsAt: Date {
        let start = SessionStore.shared.accountCreatedAt ?? firstLaunch
        return Calendar.current.date(byAdding: .day, value: Self.fullAccessDays, to: start) ?? start
    }

    var isInFullAccess: Bool { Date() < fullAccessEndsAt }

    /// Free tier with the daily limit in force.
    var isLimited: Bool { !isPro && !isInFullAccess }

    var tradesToday: Int {
        guard let countedDay, Calendar.current.isDateInToday(countedDay) else { return 0 }
        return countedTrades
    }

    var tradesLeftToday: Int { max(0, Self.freeTradesPerDay - tradesToday) }

    /// Whether a main-portfolio buy may be placed now.
    var canTrade: Bool { !isLimited || tradesLeftToday > 0 }

    /// Recounts today's trades from the server. Quietly keeps the old count when
    /// the request fails: a network error must not hand out extra trades, nor take
    /// away ones the person has.
    func refresh() async {
        guard let portfolioId = SessionStore.shared.activePortfolioId,
              let trades = try? await PaperAPI.trades(portfolioId: portfolioId)
        else { return }
        let calendar = Calendar.current
        countedTrades = trades.filter { trade in
            trade.side == .buy
                && CompeteDate.parse(trade.executedAt).map(calendar.isDateInToday) == true
        }.count
        countedDay = Date()
    }

    /// A main-portfolio buy just filled.
    func recordTrade() {
        countedTrades = tradesToday + 1
        countedDay = Date()
    }

    /// First run on this device, kept in the Keychain so deleting the app doesn't
    /// restart the window. Only used until the account's `createdAt` is known.
    private var firstLaunch: Date {
        if let stored = KeychainStore.get(Keys.firstLaunch), let seconds = TimeInterval(stored) {
            return Date(timeIntervalSince1970: seconds)
        }
        let now = Date()
        KeychainStore.set(String(now.timeIntervalSince1970), for: Keys.firstLaunch)
        return now
    }
}

/// Shows `content` to Pro, and the paywall to everyone else. For screens that are
/// Pro-only outright (leverage, price alerts), presented as a sheet.
struct ProGate<Content: View>: View {
    /// The feature's name, for the paywall headline.
    let feature: String
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if FreeTier.shared.isPro {
            content()
        } else {
            PaywallView(reason: .locked(feature)) { dismiss() }
        }
    }
}
