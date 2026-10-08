import Foundation

// MARK: - Challenges

/// The rules a challenge is judged by: thresholds, not measurements.
struct ChallengeRules: Decodable, Hashable {
    @DecimalString var profitTargetPct: Decimal
    @DecimalString var maxLossPct: Decimal
    let days: Int
}

/// A prop-firm style challenge on paper (`GET /paper/challenges`).
struct Challenge: Decodable, Identifiable, Hashable {
    let id: String
    let tier: String
    /// active, passed, failed, expired, abandoned
    let status: String
    let rules: ChallengeRules
    @DecimalString var startingBalanceUsd: Decimal
    @DecimalString var targetEquityUsd: Decimal
    @DecimalString var floorEquityUsd: Decimal
    @OptionalDecimalString var equityUsd: Decimal?
    @OptionalDecimalString var returnPct: Decimal?
    let portfolioId: String?
    let startedAt: String
    let endsAt: String
    let finishedAt: String?

    var isActive: Bool { status == "active" }
    var endDate: Date? { CompeteDate.parse(endsAt) }
    var startDate: Date? { CompeteDate.parse(startedAt) }

    /// "$50K"
    var tierLabel: String { "$" + tier.uppercased() }

    /// 0...1: where equity sits between the floor (0) and the target (1).
    var progress: Double? {
        guard let equityUsd else { return nil }
        let span = targetEquityUsd - floorEquityUsd
        guard span > 0 else { return nil }
        let value = NSDecimalNumber(decimal: (equityUsd - floorEquityUsd) / span).doubleValue
        return min(max(value, 0), 1)
    }

    var statusTitle: String {
        switch status {
        case "passed": "Passed"
        case "failed": "Failed"
        case "expired": "Ran out of time"
        case "abandoned": "Abandoned"
        default: "Live"
        }
    }
}

struct ChallengeTierOffer: Decodable, Identifiable, Hashable {
    var id: String { tier }
    let tier: String
    @DecimalString var startingBalanceUsd: Decimal
    let rules: ChallengeRules
    /// The tier to pass first (the ladder); nil for the first rung or an older server.
    let requires: String?
    let unlocked: Bool?

    var tierLabel: String { "$" + tier.uppercased() }
    var isUnlocked: Bool { unlocked ?? true }
    var requiresLabel: String? { requires.map { "$" + $0.uppercased() } }
}

struct ChallengeListResponse: Decodable {
    let active: Challenge?
    let history: [Challenge]
    let tiers: [ChallengeTierOffer]
    let passed: Int
    let attempts: Int
    let disclaimer: String?
}

struct ChallengeResponse: Decodable {
    let challenge: Challenge
}

struct CreateChallengeBody: Encodable {
    let tier: String
}

// MARK: - Streamer overlay

/// `GET`/`POST /paper/overlay/key`: the overlay page for OBS, or nulls before one exists.
struct OverlayKey: Decodable {
    let key: String?
    let url: String?
}

// MARK: - Rooms

struct RoomSummary: Decodable, Identifiable, Hashable {
    struct Host: Decodable, Hashable { let username: String }

    let id: String
    /// event (scheduled by Cooked, open to all) or host (a streamer's, by code)
    let kind: String
    let title: String
    let host: Host?
    @DecimalString var startingBalanceUsd: Decimal
    let startsAt: String
    let endsAt: String
    /// scheduled, live, finished
    let status: String
    let participantCount: Int
    let joined: Bool
    let inviteCode: String?

    var startDate: Date? { CompeteDate.parse(startsAt) }
    var endDate: Date? { CompeteDate.parse(endsAt) }
    var isLive: Bool { status == "live" }
    var isFinished: Bool { status == "finished" }
}

struct RoomStanding: Decodable, Identifiable, Hashable {
    var id: Int { rank }
    let rank: Int
    let username: String
    let isHost: Bool
    let isYou: Bool
    @OptionalDecimalString var returnPct: Decimal?
}

struct RoomDetail: Decodable {
    struct Me: Decodable {
        let rank: Int?
        @OptionalDecimalString var returnPct: Decimal?
        let portfolioId: String?
    }

    let id: String
    let kind: String
    let title: String
    let host: RoomSummary.Host?
    @DecimalString var startingBalanceUsd: Decimal
    let startsAt: String
    let endsAt: String
    let status: String
    let participantCount: Int
    let joined: Bool
    let inviteCode: String?
    let standings: [RoomStanding]
    let me: Me?
    let beatingHost: Int?
    let sampleSize: Int
    let disclaimer: String?

    var startDate: Date? { CompeteDate.parse(startsAt) }
    var endDate: Date? { CompeteDate.parse(endsAt) }
    var isLive: Bool { status == "live" }
    var isFinished: Bool { status == "finished" }
}

struct RoomListResponse: Decodable {
    let live: [RoomSummary]
    let upcoming: [RoomSummary]
    let mine: [RoomSummary]
}

struct RoomResponse: Decodable {
    let room: RoomDetail
}

struct CreateRoomBody: Encodable {
    let title: String
    let startsAt: String
    let durationMinutes: Int
}

struct JoinRoomBody: Encodable {
    let inviteCode: String
}

// MARK: - Squads

struct SquadSummary: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let memberCount: Int
    let openProposals: Int
}

struct SquadListResponse: Decodable {
    let squads: [SquadSummary]
}

struct SquadProposal: Decodable, Identifiable, Hashable {
    let id: String
    let proposer: String
    let side: String
    let tokenMint: String
    let symbol: String?
    @OptionalDecimalString var notionalUsd: Decimal?
    let sellPercent: Int?
    /// open, executed, rejected, expired, failed
    let status: String
    let yes: Int
    let no: Int
    let needed: Int
    let myVote: String?
    let createdAt: String
    let expiresAt: String
    let failure: String?

    var isOpen: Bool { status == "open" }
    var expiryDate: Date? { CompeteDate.parse(expiresAt) }

    /// "Buy $250 of WIF" / "Sell 50% of BONK"
    var summary: String {
        let coin = symbol ?? "a coin"
        if side == "buy" {
            return "Buy \(notionalUsd.map { PriceFormat.usd($0) } ?? "?") of \(coin)"
        }
        return "Sell \(sellPercent ?? 100)% of \(coin)"
    }
}

struct Squad: Decodable {
    struct Member: Decodable, Hashable {
        let username: String
        let isOwner: Bool
    }
    struct Position: Decodable, Identifiable, Hashable {
        var id: String { tokenMint }
        let tokenMint: String
        let symbol: String?
        @DecimalString var valueUsd: Decimal
        @OptionalDecimalString var unrealizedReturnPct: Decimal?
    }

    let id: String
    let name: String
    let owner: String
    let members: [Member]
    let inviteCode: String
    let portfolioId: String?
    @OptionalDecimalString var returnPct: Decimal?
    @OptionalDecimalString var equityUsd: Decimal?
    @OptionalDecimalString var cashUsd: Decimal?
    let positions: [Position]
    let open: [SquadProposal]
    let recent: [SquadProposal]
    let maxMembers: Int
}

struct SquadResponse: Decodable {
    let squad: Squad
}

struct CreateSquadBody: Encodable { let name: String }
struct JoinSquadBody: Encodable { let inviteCode: String }
struct SquadVoteBody: Encodable { let vote: String }
struct ProposeSquadTradeBody: Encodable {
    let side: String
    let tokenMint: String
    var notionalUsd: String?
    var sellPercent: Int?
}

// MARK: - Crash Replay

struct ReplaySummary: Decodable, Identifiable, Hashable {
    let id: String
    let number: Int
    /// medium, hard, brutal
    let difficulty: String
    let candleCount: Int
    @OptionalDecimalString var bestReturnPct: Decimal?
    let players: Int
    /// Closes from the run's first third, for the card. Absent on older servers.
    let teaser: [Double]?
}

struct ReplayListResponse: Decodable {
    let scenarios: [ReplaySummary]
    @DecimalString var startingBalanceUsd: Decimal
}

/// A scenario to play: `[open, high, low, close]` per hourly candle, rescaled to start at 100.
struct ReplayScenario: Decodable {
    let id: String
    let number: Int
    let difficulty: String
    let candles: [[Double]]
    @DecimalString var startingBalanceUsd: Decimal
}

struct ReplayAction: Codable, Hashable {
    let candle: Int
    let side: String
    let fraction: Double
}

struct SubmitReplayBody: Encodable {
    let actions: [ReplayAction]
}

struct ReplayResult: Decodable, Hashable {
    struct Reveal: Decodable, Hashable {
        let name: String
        let symbol: String
        let date: String
        let story: String
    }

    @DecimalString var returnPct: Decimal
    @DecimalString var holdReturnPct: Decimal
    /// survived or cooked
    let verdict: String
    let reveal: Reveal
    let rank: Int
    let sampleSize: Int

    var survived: Bool { verdict == "survived" }
}
