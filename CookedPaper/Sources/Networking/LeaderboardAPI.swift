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
}
