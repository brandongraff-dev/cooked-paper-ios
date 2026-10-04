import Foundation

/// Every call here is `auth: 'paper'` server-side and runs as the signed-in account,
/// or as the guest paper session before sign-in (`SessionStore.bearerToken`).
enum PaperAPI {
    /// Idempotent bootstrap: the caller's oldest active portfolio, or a fresh
    /// starter one ($10,000) the first time. Called with no token at all, it mints
    /// a guest session (`guestToken`) — when the server has guests enabled; with
    /// them off it answers 401.
    static func starter() async throws -> StarterPaperPortfolioResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/portfolios/starter", method: "POST"),
            as: StarterPaperPortfolioResponse.self
        )
    }

    /// Moves the guest session's portfolios into the signed-in account. A 401 here
    /// can mean the *guest* token expired, so it must not sign the account out.
    static func claimGuest(guestToken: String) async throws -> ClaimGuestPaperPortfoliosResponse {
        try await APIClient.shared.send(
            Endpoint(
                path: "/paper/portfolios/claim",
                method: "POST",
                body: APIClient.shared.encode(ClaimGuestPaperPortfoliosBody(guestToken: guestToken)),
                signsOutOnUnauthorized: false
            ),
            as: ClaimGuestPaperPortfoliosResponse.self
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

    // MARK: - Leverage

    static func leverageConfig() async throws -> PaperLeverageConfigResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/leverage/config"),
            as: PaperLeverageConfigResponse.self
        )
    }

    static func leverageQuote(portfolioId: String, body: PaperLeverageQuoteBody) async throws -> PaperLeverageQuoteResponse {
        try await APIClient.shared.send(
            Endpoint(
                path: "/paper/portfolios/\(portfolioId)/leverage/quote",
                method: "POST",
                body: APIClient.shared.encode(body)
            ),
            as: PaperLeverageQuoteResponse.self
        )
    }

    static func openLeveraged(portfolioId: String, body: OpenPaperLeveragedBody) async throws -> PaperLeveragedMutationResponse {
        try await APIClient.shared.send(
            Endpoint(
                path: "/paper/portfolios/\(portfolioId)/leverage/positions",
                method: "POST",
                body: APIClient.shared.encode(body)
            ),
            as: PaperLeveragedMutationResponse.self
        )
    }

    static func closeLeveraged(portfolioId: String, positionId: String, body: ClosePaperLeveragedBody) async throws -> PaperLeveragedMutationResponse {
        try await APIClient.shared.send(
            Endpoint(
                path: "/paper/portfolios/\(portfolioId)/leverage/positions/\(positionId)/close",
                method: "POST",
                body: APIClient.shared.encode(body)
            ),
            as: PaperLeveragedMutationResponse.self
        )
    }
}
