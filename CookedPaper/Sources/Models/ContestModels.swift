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
