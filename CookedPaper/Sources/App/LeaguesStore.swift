import Foundation
import Observation

/// The account's friend leagues (`GET /paper/leagues`), shared by the Leagues list
/// and the screens that create, join, leave or change one — each of those calls
/// `refreshSilently()` so the list is current when the person comes back to it.
@Observable
@MainActor
final class LeaguesStore {
    static let shared = LeaguesStore()

    private(set) var leagues: [League]?
    private(set) var isLoading = false
    /// The server has no leagues routes yet (404).
    private(set) var isUnavailable = false
    private(set) var errorMessage: String?

    private init() {}

    func load() async {
        guard SessionStore.shared.isSignedIn else { return }
        isLoading = leagues == nil
        errorMessage = nil
        do {
            leagues = try await LeaguesAPI.list()
            isUnavailable = false
        } catch let error where error.isNotFound {
            isUnavailable = true
        } catch {
            if leagues == nil { errorMessage = CompeteErrorText.message(for: error, in: .league) }
        }
        isLoading = false
    }

    /// No loading state; keeps what's shown on failure.
    func refreshSilently() async {
        guard SessionStore.shared.isSignedIn, !isLoading,
              let fresh = try? await LeaguesAPI.list() else { return }
        leagues = fresh
        errorMessage = nil
    }

    /// A league changed on another screen (renamed, new code): update it in place.
    func didChange(_ league: League) {
        guard var current = leagues else { return }
        if let index = current.firstIndex(where: { $0.id == league.id }) {
            current[index] = league
        } else {
            current.insert(league, at: 0)
        }
        leagues = current
    }

    /// Left or deleted.
    func didRemove(leagueId: String) {
        leagues?.removeAll { $0.id == leagueId }
    }

    func signedOut() {
        leagues = nil
        isUnavailable = false
        errorMessage = nil
    }
}
