import Foundation

/// Unlike every other route this app calls, `/watchlist/*` is `auth: 'bearer'`
/// specifically — a guest token is rejected server-side. Callers must check
/// `SessionStore.shared.isGuest` before invoking these (see `DiscoverView`,
/// `TokenDetailView`) rather than relying on the resulting 401 to gate the UI.
enum WatchlistAPI {
    /// The caller's full watchlist — there is no single-mint "is this watched" route,
    /// so callers needing initial star state (Discover, TokenDetail) fetch the whole
    /// list and check membership themselves.
    static func list() async throws -> WatchlistResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/watchlist"),
            as: WatchlistResponse.self
        )
    }

    static func add(mint: String) async throws -> WatchlistMutationResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/watchlist/\(mint)", method: "POST"),
            as: WatchlistMutationResponse.self
        )
    }

    static func remove(mint: String) async throws -> WatchlistMutationResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/watchlist/\(mint)", method: "DELETE"),
            as: WatchlistMutationResponse.self
        )
    }
}
