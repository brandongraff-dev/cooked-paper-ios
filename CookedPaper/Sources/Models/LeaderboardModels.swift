import Foundation

/// `GET /paper/leaderboard`'s `window` query param. `all` is season-to-date (the
/// current UTC calendar month), never since-inception — labeled "This month" so the
/// UI doesn't imply a longer history than the backend actually ranks.
enum LeaderboardWindow: String, CaseIterable, Identifiable {
    case day = "24h"
    case week = "7d"
    case month = "30d"
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: "24h"
        case .week: "7d"
        case .month: "30d"
        case .all: "This month"
        }
    }
}

struct PaperLeaderboardEntry: Decodable, Identifiable {
    var id: String { portfolioId }
    let rank: Int
    let portfolioId: String
    let username: String
    let provenance: String
    let returnPct: MeasuredPct
    let roundTripCount: Int
    let maxDrawdownPct: MeasuredPct
    let resetCount: Int
    @DecimalString var startingBalanceUsd: Decimal
    let createdAt: String
}

struct PaperLeaderboardResponse: Decodable {
    let window: String
    let season: String
    let entries: [PaperLeaderboardEntry]
    let rankedCount: Int
    let emergingCount: Int
    let computedAt: String
}
