import Foundation

/// Every call here is `auth: 'paper'` server-side — a real access token or a guest
/// token both work identically, and `APIClient` always attaches whatever token
/// `SessionStore` currently holds. Nothing in this file cares which kind it is.
enum PaperAPI {
    /// Idempotent bootstrap: the caller's oldest active portfolio, or a fresh
    /// starter one. Call this on cold launch (with whatever token — or none — is
    /// currently stored) to get a tradeable portfolio id with no separate "log in
    /// first" step, then persist `guestToken` via `SessionStore` when present.
    static func starter() async throws -> StarterPaperPortfolioResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/portfolios/starter", method: "POST", attachToken: SessionStore.shared.token != nil),
            as: StarterPaperPortfolioResponse.self
        )
    }

    static func snapshot(portfolioId: String) async throws -> PaperSnapshotResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/portfolios/\(portfolioId)"),
            as: PaperSnapshotResponse.self
        )
    }

    static func trades(portfolioId: String) async throws -> [PaperTrade] {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/portfolios/\(portfolioId)/trades"),
            as: PaperTradesResponse.self
        ).trades
    }

    static func quote(portfolioId: String, body: PaperQuoteBody) async throws -> PaperQuoteResponse {
        try await APIClient.shared.send(
            Endpoint(
                path: "/paper/portfolios/\(portfolioId)/quote",
                method: "POST",
                body: APIClient.shared.encode(body)
            ),
            as: PaperQuoteResponse.self
        )
    }

    static func execute(portfolioId: String, body: ExecutePaperTradeBody) async throws -> ExecutePaperTradeResponse {
        try await APIClient.shared.send(
            Endpoint(
                path: "/paper/portfolios/\(portfolioId)/trades",
                method: "POST",
                body: APIClient.shared.encode(body)
            ),
            as: ExecutePaperTradeResponse.self
        )
    }

    static func reset(portfolioId: String) async throws {
        try await APIClient.shared.sendIgnoringResponse(
            Endpoint(path: "/paper/portfolios/\(portfolioId)/reset", method: "POST")
        )
    }
}
