import Foundation
import Observation

/// The app's one active paper portfolio. `PaperAPI.starter()` is idempotent and safe
/// to call on every cold launch — it returns the caller's existing portfolio once one
/// exists, so this bootstraps a brand-new guest exactly once and is a no-op
/// thereafter. `snapshot` is REST-driven (refreshed after every trade and on pull-to-
/// refresh); live price color comes separately from `LiveSocket.shared.latestTick` —
/// see `Features/Portfolio/PortfolioView.swift` for how the two are merged for
/// display without this store needing to reconcile them itself.
@Observable
@MainActor
final class PortfolioStore {
    static let shared = PortfolioStore()

    private(set) var snapshot: PaperSnapshotResponse?
    private(set) var isBootstrapping = true
    private(set) var error: String?

    private init() {}

    func bootstrapIfNeeded() async {
        guard snapshot == nil else { return }
        await bootstrap()
    }

    func bootstrap() async {
        isBootstrapping = true
        error = nil
        do {
            let starter = try await PaperAPI.starter()
            if let guestToken = starter.guestToken, SessionStore.shared.isGuest {
                SessionStore.shared.adoptGuestToken(guestToken)
            }
            SessionStore.shared.setActivePortfolio(starter.portfolio.id)
            try await refresh()
            LiveSocket.shared.connectAndSubscribe(portfolioId: starter.portfolio.id)
        } catch {
            self.error = error.localizedDescription
        }
        isBootstrapping = false
    }

    func refresh() async throws {
        guard let id = SessionStore.shared.activePortfolioId else { return }
        snapshot = try await PaperAPI.snapshot(portfolioId: id)
    }

    /// Called right after a fill so the positions list / cash balance reflect it
    /// immediately rather than waiting for the next live tick or manual refresh.
    func refreshAfterTrade() async {
        try? await refresh()
    }

    /// After sign-out: drop the in-memory snapshot and re-run the full bootstrap,
    /// which mints a fresh guest session against whatever `SessionStore` now holds
    /// (nothing, post-`clear()`).
    func resetAndRebootstrap() async {
        snapshot = nil
        LiveSocket.shared.disconnect()
        await bootstrap()
    }
}
