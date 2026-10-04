import Foundation
import Observation

/// The signed-in account's one paper portfolio (or, before sign-in, the guest
/// session's — see `bootstrapGuestIfPossible`). `PaperAPI.starter()` is idempotent
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
    /// The server refused to start a guest session (guests are switched off), so
    /// onboarding has to sign in before trading. Nil until a guest start was tried.
    private(set) var guestsRefused: Bool?

    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?

    private init() {}

    func bootstrapIfNeeded() async {
        guard snapshot == nil else { return }
        await bootstrap()
    }

    /// One bootstrap at a time: a second caller (the shell's `.task` racing a
    /// sign-in's rebootstrap) waits for the first instead of calling `starter`
    /// before the guest claim has landed — on a brand-new account that would mint
    /// an empty $10,000 portfolio that then outranks the claimed one.
    func bootstrap() async {
        if let bootstrapTask {
            await bootstrapTask.value
            return
        }
        let task = Task { await self.performBootstrap() }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
    }

    private func performBootstrap() async {
        isBootstrapping = true
        error = nil
        do {
            guard SessionStore.shared.isSignedIn else {
                isBootstrapping = false
                return
            }
            // Claim first, so the guest's portfolio is the account's oldest (and so
            // the one `starter` returns) when the account is new.
            await claimGuestPortfoliosIfNeeded()
            let starter = try await PaperAPI.starter()
            SessionStore.shared.setActivePortfolio(starter.portfolio.id)
            try await refresh()
            LiveSocket.shared.connectAndSubscribe(portfolioId: starter.portfolio.id)
        } catch {
            self.error = error.localizedDescription
        }
        isBootstrapping = false
    }

    // MARK: - Guest sessions

    /// Starts (or resumes) a guest paper portfolio for someone who hasn't signed in,
    /// so onboarding and the paywall can trade before any account exists. True when
    /// there's a portfolio to trade in. False when the server refuses guests
    /// (`guestsRefused`) or can't be reached — callers fall back to signing in first.
    /// Signed-in callers just get their own portfolio.
    func bootstrapGuestIfPossible() async -> Bool {
        if SessionStore.shared.isSignedIn {
            await bootstrapIfNeeded()
            return SessionStore.shared.activePortfolioId != nil
        }
        if guestsRefused == true { return false }
        if SessionStore.shared.isGuest, snapshot != nil, SessionStore.shared.activePortfolioId != nil {
            return true
        }
        // Two tries: an expired guest token (7 days) gets one 401, is dropped, and a
        // fresh session is minted with no token at all.
        for attempt in 0..<2 {
            do {
                let starter = try await PaperAPI.starter()
                if let minted = starter.guestToken, !minted.isEmpty {
                    SessionStore.shared.adoptGuest(token: minted)
                }
                // No token sent and none minted: there is no guest to be.
                guard SessionStore.shared.guestToken != nil else {
                    guestsRefused = true
                    return false
                }
                guestsRefused = false
                SessionStore.shared.setActivePortfolio(starter.portfolio.id)
                try? await refresh()
                isBootstrapping = false
                LiveSocket.shared.connectAndSubscribe(portfolioId: starter.portfolio.id)
                return true
            } catch APIError.server(let status, _) where status == 401 {
                if attempt == 0, SessionStore.shared.guestToken != nil {
                    SessionStore.shared.clearGuest()
                    continue
                }
                // No token and still 401: "Sign in with Apple or Google to start
                // paper trading." — guests are off on this server.
                guestsRefused = true
                return false
            } catch {
                return false
            }
        }
        return false
    }

    /// After a sign-in: moves the guest's portfolio (and so its positions) into the
    /// account, then forgets the guest token. A token the server can no longer
    /// verify is dropped too; a network failure keeps it for the next bootstrap.
    private func claimGuestPortfoliosIfNeeded() async {
        guard SessionStore.shared.isSignedIn, let guestToken = SessionStore.shared.guestToken else { return }
        do {
            _ = try await PaperAPI.claimGuest(guestToken: guestToken)
            SessionStore.shared.clearGuest()
        } catch APIError.server(let status, _) where (400..<500).contains(status) {
            SessionStore.shared.clearGuest()
        } catch {
            // Offline or a server error: try again on the next bootstrap.
        }
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
    /// portfolio from scratch — claiming a guest portfolio first, if there is one.
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
