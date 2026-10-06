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

    /// Beat the Monkey: the share of ranked traders above the house bot. Public.
    static func monkeyStanding(window: LeaderboardWindow = .all) async throws -> PaperMonkeyStanding {
        try await APIClient.shared.send(
            Endpoint(
                path: "/paper/leaderboard/monkey",
                query: ["window": window.rawValue],
                attachToken: false
            ),
            as: PaperMonkeyStanding.self
        )
    }
}
