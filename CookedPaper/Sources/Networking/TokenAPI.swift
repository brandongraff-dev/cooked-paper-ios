import Foundation

/// Token facts, price, and chart data — all `auth: 'public'` server-side, so these
/// work before any session exists (the Discover tab's token detail can be opened
/// straight from a cold launch, mid-onboarding).
enum TokenAPI {
    static func profile(mint: String) async throws -> TokenProfileResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/tokens/\(mint)/profile", attachToken: false),
            as: TokenProfileResponse.self
        )
    }

    /// `getTokenCandles` is the single chart data source — it transparently falls
    /// back to relayed GeckoTerminal candles server-side when our own trade-folded
    /// series is empty, which is true for almost every token per project memory.
    static func candles(mint: String, interval: CandleInterval, limit: Int = 200) async throws -> TokenCandlesResponse {
        try await APIClient.shared.send(
            Endpoint(
                path: "/tokens/\(mint)/candles",
                query: ["interval": interval.rawValue, "limit": String(limit)],
                attachToken: false
            ),
            as: TokenCandlesResponse.self
        )
    }

    static func priceability(mint: String) async throws -> PaperTokenPriceability {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/tokens/\(mint)/priceable", attachToken: false),
            as: PaperTokenPriceability.self
        )
    }

    static func search(_ query: String) async throws -> [TokenSearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return try await APIClient.shared.send(
            Endpoint(path: "/tokens/search", query: ["q": query, "limit": "30"], attachToken: false),
            as: TokenSearchResponse.self
        ).results
    }

    static func logoURL(mint: String) -> URL {
        APIConfig.baseURL.appendingPathComponent("/tokens/\(mint)/logo")
    }
}

enum DiscoverAPI {
    /// One call returns all five feeds this app uses (`popular`/`most_held` are also
    /// available but not surfaced as tabs — trim scope, not payload). Cached
    /// server-side for ~60s; there's no reason to poll faster than that.
    static func paperDiscover(window: String = "24h") async throws -> PaperDiscoverResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/discover", query: ["window": window, "limit": "30"], attachToken: false),
            as: PaperDiscoverResponse.self
        )
    }
}
