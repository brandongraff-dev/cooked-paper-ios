import Foundation

/// `auth: 'public'` server-side — ranks are visible to a guest exactly like a real
/// account, so this never attaches a token.
enum LeaderboardAPI {
    static func paperLeaderboard(window: LeaderboardWindow = .all, limit: Int = 50) async throws -> PaperLeaderboardResponse {
        try await APIClient.shared.send(
            Endpoint(
                path: "/paper/leaderboard",
                query: ["window": window.rawValue, "limit": String(limit)],
                attachToken: false
            ),
            as: PaperLeaderboardResponse.self
        )
    }

    /// Your recap for a `YYYY-MM` month (UTC). Bearer.
    static func recap(month: String) async throws -> PaperRecap {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/recap", query: ["month": month]),
            as: PaperRecap.self
        )
    }

    /// What a ranked trader holds now. Public; 404 when they're unranked or hide balances.
    static func traderPositions(portfolioId: String) async throws -> PaperTraderPositions {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/leaderboard/portfolios/\(portfolioId)/positions", attachToken: false),
            as: PaperTraderPositions.self
        )
    }
}
