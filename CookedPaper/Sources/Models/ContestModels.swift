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

    var tierLabel: String { "$" + tier.uppercased() }
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
