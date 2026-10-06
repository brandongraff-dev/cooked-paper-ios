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
    let resetCount: Int
    let createdAt: String
    /// The house bot ("The Monkey", trades at random). Optional so an older server
    /// that doesn't send it still decodes.
    let isBot: Bool?

    var isHouseBot: Bool { isBot == true }
}

/// `GET /paper/recap`: one month of your main portfolio, percentages only.
struct PaperRecap: Decodable {
    struct Trade: Decodable, Hashable {
        let tokenMint: String
        let symbol: String?
        @DecimalString var returnPct: Decimal
    }
    struct MostTraded: Decodable, Hashable {
        let tokenMint: String
        let symbol: String?
        let tradeCount: Int
    }
    struct Personality: Decodable, Hashable {
        let id: String
        let title: String
        let description: String
    }
    struct Monkey: Decodable, Hashable {
        @DecimalString var returnPct: Decimal
        let beatMonkey: Bool?
    }
    struct DailyCall: Decodable, Hashable {
        let played: Int
        let correct: Int
    }

    let month: String
    let returnPct: MeasuredPct
    let tradeCount: Int
    let roundTripCount: Int
    let winRatePct: MeasuredPct
    let bestTrade: Trade?
    let worstTrade: Trade?
    let mostTraded: MostTraded?
    let avgHoldMinutes: Int?
    let personality: Personality
    let monkey: Monkey?
    let dailyCall: DailyCall
}

/// One open position of a ranked trader: shares and returns only, never amounts.
struct PaperTraderPosition: Decodable, Identifiable {
    var id: String { tokenMint }
    let tokenMint: String
    let symbol: String?
    let name: String?
    @DecimalString var sharePct: Decimal
    @OptionalDecimalString var unrealizedReturnPct: Decimal?
}

/// `GET /paper/leaderboard/portfolios/:id/positions`.
struct PaperTraderPositions: Decodable {
    let entry: PaperLeaderboardEntry
    let positions: [PaperTraderPosition]
    @DecimalString var cashSharePct: Decimal
    let sampleSize: Int
}

/// `GET /paper/leaderboard/monkey`: how many ranked people beat the house bot.
struct PaperMonkeyStanding: Decodable {
    let window: String
    /// Nil while the monkey hasn't closed enough round trips to rank.
    let monkey: PaperLeaderboardEntry?
    /// People ranked in the window (the monkey isn't one).
    let sampleSize: Int
    let beatingMonkey: Int?
    @OptionalDecimalString var beatingPct: Decimal?
}

struct PaperLeaderboardResponse: Decodable {
    let window: String
    let season: String
    let entries: [PaperLeaderboardEntry]
    let rankedCount: Int
    let emergingCount: Int
    let computedAt: String
}
