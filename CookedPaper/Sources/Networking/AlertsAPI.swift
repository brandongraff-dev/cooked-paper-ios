import Foundation

/// `/social/alerts*` is `auth: 'bearer'` — unlike every `/paper/*` route, a guest
/// token is rejected server-side (the same exception `WatchlistAPI` documents for
/// `/watchlist/*`). Every call here checks `SessionStore.shared.isGuest` first and
/// throws `APIError.unauthenticated` locally, matching how a guest is gated ahead of
/// `WatchlistAPI`/`TokenDetailView`'s star toggle, rather than letting a guest's
/// request round-trip to the backend just to learn the same thing from a 401.
enum AlertsAPI {
    static func list() async throws -> [PriceAlert] {
        guard !SessionStore.shared.isGuest else { throw APIError.unauthenticated }
        return try await APIClient.shared.send(
            Endpoint(path: "/social/alerts"),
            as: AlertListResponse.self
        ).alerts
    }

    /// Always creates a `price_crossed` rule — the only kind this app builds or
    /// renders as editable (see `AlertModels.swift`). `channel` is always `.inApp`:
    /// this app has no push-notification registration wired up anywhere (no APNs
    /// entitlement, no `registerPushToken` call), so `.push` would be accepted by the
    /// backend and then silently never delivered.
    static func create(
        name: String,
        mint: String,
        direction: AlertRule.Direction,
        priceUsd: Decimal
    ) async throws -> PriceAlert {
        guard !SessionStore.shared.isGuest else { throw APIError.unauthenticated }
        let body = CreateAlertBody(
            name: name,
            rule: .priceCrossed(mint: mint, direction: direction, priceUsd: priceUsd),
            channel: .inApp,
            cooldownSeconds: 300
        )
        return try await APIClient.shared.send(
            Endpoint(path: "/social/alerts", method: "POST", body: APIClient.shared.encode(body)),
            as: AlertResponse.self
        ).alert
    }

    static func delete(id: String) async throws -> PriceAlert {
        guard !SessionStore.shared.isGuest else { throw APIError.unauthenticated }
        return try await APIClient.shared.send(
            Endpoint(path: "/social/alerts/\(id)", method: "DELETE"),
            as: AlertResponse.self
        ).alert
    }
}
