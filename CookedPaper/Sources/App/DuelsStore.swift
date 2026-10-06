import Foundation
import Observation

/// The account's duels (`GET /paper/duels`) and record (`/paper/duels/stats`),
/// shared by the Duels list and every duel detail screen. `paper:duel` socket
/// events land in `apply(_:)`: the event's duel is published as `lastEvent` (so an
/// open detail screen updates at once) and the list reloads quietly behind it.
@Observable
@MainActor
final class DuelsStore {
    static let shared = DuelsStore()

    private(set) var lists: DuelListResponse?
    private(set) var stats: DuelStats?
    private(set) var isLoading = false
    /// The server has no duels routes yet (404).
    private(set) var isUnavailable = false
    private(set) var errorMessage: String?
    /// The most recent duel pushed over the socket, and a counter that changes with
    /// every event so screens can `onChange` on it.
    private(set) var lastEvent: Duel?
    private(set) var eventVersion = 0

    private init() {}

    func load() async {
        guard SessionStore.shared.isSignedIn else { return }
        isLoading = lists == nil
        errorMessage = nil
        do {
            let fresh = try await DuelsAPI.list()
            lists = fresh
            isUnavailable = false
            // The record is a nicety: a failure there never blanks the list.
            stats = (try? await DuelsAPI.stats()) ?? stats
        } catch let error where error.isNotFound {
            isUnavailable = true
        } catch {
            if lists == nil { errorMessage = CompeteErrorText.message(for: error) }
        }
        isLoading = false
    }

    /// The auto-refresh: no loading state, keeps what's shown on failure.
    func refreshSilently() async {
        guard SessionStore.shared.isSignedIn, !isLoading else { return }
        if let fresh = try? await DuelsAPI.list() {
            lists = fresh
            errorMessage = nil
        }
        if let freshStats = try? await DuelsAPI.stats() {
            stats = freshStats
        }
    }

    /// A `paper:duel` socket event.
    func apply(_ duel: Duel) {
        lastEvent = duel
        eventVersion += 1
        Task { await refreshSilently() }
    }

    /// After any action (accept, create, …): keep the list in step.
    func didChange(_ duel: Duel) {
        lastEvent = duel
        eventVersion += 1
        Task { await refreshSilently() }
    }

    func signedOut() {
        lists = nil
        stats = nil
        lastEvent = nil
        isUnavailable = false
        errorMessage = nil
    }
}

/// A duel's own paper portfolio (one per player, $1,000, created when the duel
/// starts). Trading screens reach it through `TradePortfolioContext.duel`, so a
/// duel trade never touches `PortfolioStore` — the main portfolio.
@Observable
@MainActor
final class DuelPortfolioStore {
    let portfolioId: String
    /// The duel's id, or the contest's (challenge, room) for a contest portfolio.
    let duelId: String
    /// The tag on a trade ticket: "DUEL", "CHALLENGE", "ROOM".
    let label: String

    private(set) var snapshot: PaperSnapshotResponse?
    private(set) var errorMessage: String?

    init(portfolioId: String, duelId: String, label: String = "DUEL") {
        self.portfolioId = portfolioId
        self.duelId = duelId
        self.label = label
    }

    func refresh() async {
        do {
            snapshot = try await PaperAPI.snapshot(portfolioId: portfolioId)
            errorMessage = nil
        } catch {
            if snapshot == nil { errorMessage = error.localizedDescription }
        }
    }
}
