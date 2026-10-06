import Foundation

/// Which paper portfolio a trade ticket acts on. `.main` (the default everywhere)
/// is the account's own portfolio — `SessionStore.activePortfolioId` and
/// `PortfolioStore`, exactly as before duels existed. `.duel` is one duel's
/// portfolio: its id, its snapshot (for cash and holdings) and its refresh, with
/// nothing read from or written to the main portfolio.
enum TradePortfolioContext {
    case main
    case duel(DuelPortfolioStore)

    var portfolioId: String? {
        switch self {
        case .main: SessionStore.shared.activePortfolioId
        case .duel(let store): store.portfolioId
        }
    }

    var snapshot: PaperSnapshotResponse? {
        switch self {
        case .main: PortfolioStore.shared.snapshot
        case .duel(let store): store.snapshot
        }
    }

    var isMain: Bool {
        if case .main = self { return true }
        return false
    }

    /// The small outlined tag next to the balance on a ticket.
    var badge: String {
        switch self {
        case .main: "PAPER"
        case .duel(let store): store.label
        }
    }

    func refreshAfterTrade() async {
        switch self {
        case .main: await PortfolioStore.shared.refreshAfterTrade()
        case .duel(let store): await store.refresh()
        }
    }

    /// A duel-specific refusal in plain words (trading outside the duel's window),
    /// or nil to use the caller's usual message.
    func message(for error: Error) -> String? {
        guard !isMain, let apiError = error as? APIError else { return nil }
        for key in [apiError.code, apiError.reason].compactMap({ $0 }) {
            if let sentence = CompeteErrorText.sentence(for: key) { return sentence }
        }
        return nil
    }
}
