import Foundation

/// `POST /watchlist/:mint` and `DELETE /watchlist/:mint` share this shape — `addedAt`
/// is null exactly when `watching` is false, never a stale date from before removal.
struct WatchlistMutationResponse: Decodable {
    let mint: String
    let watching: Bool
    let addedAt: String?
}

/// One row of `GET /watchlist`. The server response (`WatchlistItem` in
/// `packages/api-types/src/discover.ts`) also carries `symbol`/`name`/`safety`/
/// `metrics`/`launch` — this only decodes the two fields the client needs to know
/// which mints are currently watched; `Decodable` ignores the rest.
struct WatchlistItem: Decodable, Identifiable {
    var id: String { mint }
    let mint: String
    let addedAt: String
}

/// `GET /watchlist` — the caller's full watchlist, used to hydrate the star state on
/// Discover/TokenDetail. `auth: 'bearer'` like the rest of `/watchlist/*`; never
/// called for a guest session.
struct WatchlistResponse: Decodable {
    let items: [WatchlistItem]
}
