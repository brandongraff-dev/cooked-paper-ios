import Foundation
import Observation

/// The signed-in account's one paper portfolio. `PaperAPI.starter()` is idempotent
/// and safe to call on every launch — it returns the account's existing portfolio
/// once one exists, and creates it (with $10,000) the first time. `snapshot` is REST-driven (refreshed after every trade and on pull-to-
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
            guard SessionStore.shared.isSignedIn else {
                isBootstrapping = false
                return
            }
            let starter = try await PaperAPI.starter()
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

    /// After sign-in (or reset): drop the in-memory snapshot and load the account's
    /// portfolio from scratch.
    func resetAndRebootstrap() async {
        snapshot = nil
        LiveSocket.shared.disconnect()
        await bootstrap()
    }

    /// After sign-out or account deletion.
    func signedOut() {
        snapshot = nil
        error = nil
        LiveSocket.shared.disconnect()
    }
}
