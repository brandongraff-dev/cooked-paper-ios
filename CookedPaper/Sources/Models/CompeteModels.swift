import Foundation

// Seasons, achievements and head-to-head duels ("Compete"). Every shape here
// mirrors the shared compete spec the backend implements: camelCase JSON, decimals
// as strings, ISO-8601 timestamps. Ids that the server may grow (tiers, statuses)
// stay raw `String`s with a typed view on top, so a value this build doesn't know
// yet degrades to a neutral rendering instead of failing the whole decode.

// MARK: - Seasons

struct Season: Decodable, Hashable, Identifiable {
    /// `"2026-10"` — a UTC calendar month.
    let id: String
    let number: Int
    /// `"Season 10 · October 2026"`.
    let label: String
    let startsAt: String
    let endsAt: String

    var endDate: Date? { CompeteDate.parse(endsAt) }
}

/// The season tier ids. `unknown` covers anything a newer server adds.
enum SeasonTier: String, CaseIterable {
    case michelin
    case headChef = "head_chef"
    case sousChef = "sous_chef"
    case lineCook = "line_cook"
    case prepCook = "prep_cook"
    case unranked
    case unknown

    init(id: String?) {
        self = id.flatMap(SeasonTier.init(rawValue:)) ?? .unknown
    }

    /// The fallback name when the server's `tiers` list doesn't carry this one.
    var defaultName: String {
        switch self {
        case .michelin: "Michelin"
        case .headChef: "Head Chef"
        case .sousChef: "Sous Chef"
        case .lineCook: "Line Cook"
        case .prepCook: "Prep Cook"
        case .unranked: "Unranked"
        case .unknown: "Ranked"
        }
    }
}

struct SeasonTierInfo: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    /// The percentile ceiling for the tier (1 = top 1%). Lenient: absent, null or
    /// a non-number reads as nil.
    let topPercent: Double?

    private enum CodingKeys: String, CodingKey {
        case id, name, topPercent
    }

    init(id: String, name: String, topPercent: Double?) {
        self.id = id
        self.name = name
        self.topPercent = topPercent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? SeasonTier(id: id).defaultName
        topPercent = (try? container.decodeIfPresent(Double.self, forKey: .topPercent)) ?? nil
    }

    var tier: SeasonTier { SeasonTier(id: id) }
}

struct SeasonNextTier: Decodable, Hashable {
    let id: String
    /// The rank to reach for that tier (e.g. 13 when rank 13 is the top 1%).
    let rankNeeded: Int
}

struct SeasonStanding: Decodable {
    let qualified: Bool
    let rank: Int?
    let of: Int?
    @OptionalDecimalString var percentile: Decimal?
    let tier: String
    @OptionalDecimalString var returnPct: Decimal?
    let roundTrips: Int?
    let minRoundTrips: Int?
    let nextTier: SeasonNextTier?
}

struct SeasonTopEntry: Decodable, Identifiable {
    var id: String { "\(rank)-\(username)" }
    let rank: Int
    let username: String
    let displayName: String?
    let avatarSeed: String?
    @OptionalDecimalString var returnPct: Decimal?
    let tier: String
}

/// `GET /paper/seasons/current`.
struct SeasonCurrentResponse: Decodable {
    let season: Season
    let tiers: [SeasonTierInfo]
    let me: SeasonStanding?
    let top: [SeasonTopEntry]
}

struct SeasonHistoryEntry: Decodable, Identifiable {
    var id: String { season.id }
    let season: Season
    let rank: Int
    let of: Int
    let tier: String
    @OptionalDecimalString var returnPct: Decimal?
}

/// `GET /paper/seasons/history`.
struct SeasonHistoryResponse: Decodable {
    let seasons: [SeasonHistoryEntry]
}

/// `GET /paper/seasons/:id/results`.
struct SeasonResultsResponse: Decodable {
    let season: Season
    let results: [SeasonTopEntry]
}

// MARK: - Achievements

enum AchievementTier: String {
    case bronze, silver, gold, legendary

    init(id: String) {
        self = AchievementTier(rawValue: id) ?? .bronze
    }

    var title: String {
        switch self {
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .legendary: "Legendary"
        }
    }
}

struct AchievementProgress: Decodable, Hashable {
    let current: Double
    let target: Double

    /// 0...1, for a progress bar.
    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, current / target))
    }
}

struct Achievement: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let tier: String
    /// An SF Symbol name (see `AchievementBadge` for the fallback).
    let icon: String
    let unlocked: Bool
    let unlockedAt: String?
    let seen: Bool?
    let progress: AchievementProgress?

    var tierKind: AchievementTier { AchievementTier(id: tier) }
}

/// `GET /paper/achievements`.
struct AchievementsResponse: Decodable {
    let achievements: [Achievement]
    let unlockedCount: Int
    let total: Int
}

/// `POST /paper/achievements/seen`.
struct AchievementsSeenBody: Encodable {
    let ids: [String]
}

/// `paper:achievement` on the `/paper` socket.
struct AchievementEvent: Decodable {
    let achievement: Achievement
}

// MARK: - Duels

enum DuelStatus: String {
    case pending, active, finished, declined, cancelled, expired, unknown

    init(id: String) {
        self = DuelStatus(rawValue: id) ?? .unknown
    }
}

/// How a finished duel went for the person looking at it.
enum DuelOutcome {
    case won, lost, draw

    var letter: String {
        switch self {
        case .won: "W"
        case .lost: "L"
        case .draw: "D"
        }
    }

    var title: String {
        switch self {
        case .won: "You won"
        case .lost: "You lost"
        case .draw: "Draw"
        }
    }
}

/// The three durations the server accepts, in hours.
enum DuelDuration: Int, CaseIterable, Identifiable {
    case hour = 1
    case day = 24
    case week = 168

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .hour: "1h"
        case .day: "24h"
        case .week: "7d"
        }
    }

    var longLabel: String {
        switch self {
        case .hour: "1 hour"
        case .day: "24 hours"
        case .week: "7 days"
        }
    }

    /// "24h" for a known duration, "<n>h" otherwise.
    static func label(hours: Int) -> String {
        DuelDuration(rawValue: hours)?.label ?? "\(hours)h"
    }
}

struct DuelPlayer: Decodable, Hashable {
    let userId: String
    let username: String
    let displayName: String?
    let avatarSeed: String?
    /// Null until the duel starts (both portfolios are created at accept).
    let portfolioId: String?
    /// Live while active, final once finished, null while pending.
    @OptionalDecimalString var returnPct: Decimal?
    @OptionalDecimalString var equityUsd: Decimal?

    var handle: String { "@\(username)" }
    var shownName: String { displayName.flatMap { $0.isEmpty ? nil : $0 } ?? handle }
    var seed: String { avatarSeed ?? userId }
}

struct Duel: Decodable, Identifiable, Hashable {
    let id: String
    let status: String
    let durationHours: Int
    let createdAt: String
    let startsAt: String?
    let endsAt: String?
    let finishedAt: String?
    /// Only for the challenger while pending; else null.
    let inviteCode: String?
    let challenger: DuelPlayer
    /// Null for an open invite nobody has joined yet.
    let opponent: DuelPlayer?
    /// `"challenger"` or `"opponent"` — which side the caller is.
    let you: String
    /// `"challenger"`, `"opponent"`, `"draw"` or null.
    let winner: String?
    @DecimalString var startingBalanceUsd: Decimal

    static func == (lhs: Duel, rhs: Duel) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
            && lhs.challenger == rhs.challenger && lhs.opponent == rhs.opponent
            && lhs.winner == rhs.winner && lhs.endsAt == rhs.endsAt
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var state: DuelStatus { DuelStatus(id: status) }
    var isChallenger: Bool { you == "challenger" }
    var me: DuelPlayer? { isChallenger ? challenger : opponent }
    var them: DuelPlayer? { isChallenger ? opponent : challenger }
    var endDate: Date? { endsAt.flatMap(CompeteDate.parse) }
    var startDate: Date? { startsAt.flatMap(CompeteDate.parse) }
    var durationLabel: String { DuelDuration.label(hours: durationHours) }

    /// Nil until the duel has a result.
    var outcome: DuelOutcome? {
        guard let winner else { return nil }
        if winner == "draw" { return .draw }
        return winner == you ? .won : .lost
    }

    /// Whoever is ahead on return right now; nil when tied or unmeasured.
    var leader: DuelLeader? {
        guard let mine = me?.returnPct, let theirs = them?.returnPct else { return nil }
        let gap = mine - theirs
        if abs(NSDecimalNumber(decimal: gap).doubleValue) < 0.01 { return .tied }
        return gap > 0 ? .me : .them
    }

    /// The invite's shareable web link, when there is one.
    var inviteURL: URL? {
        inviteCode.flatMap { URL(string: "https://cooked.trade/d/\($0)") }
    }
}

enum DuelLeader {
    case me, them, tied
}

struct DuelResponse: Decodable {
    let duel: Duel
}

/// `GET /paper/duels`. Lenient: a missing bucket is empty.
struct DuelListResponse: Decodable {
    var active: [Duel]
    var incoming: [Duel]
    var outgoing: [Duel]
    var finished: [Duel]

    private enum CodingKeys: String, CodingKey {
        case active, incoming, outgoing, finished
    }

    init(active: [Duel] = [], incoming: [Duel] = [], outgoing: [Duel] = [], finished: [Duel] = []) {
        self.active = active
        self.incoming = incoming
        self.outgoing = outgoing
        self.finished = finished
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        active = try container.decodeIfPresent([Duel].self, forKey: .active) ?? []
        incoming = try container.decodeIfPresent([Duel].self, forKey: .incoming) ?? []
        outgoing = try container.decodeIfPresent([Duel].self, forKey: .outgoing) ?? []
        finished = try container.decodeIfPresent([Duel].self, forKey: .finished) ?? []
    }

    var isEmpty: Bool { active.isEmpty && incoming.isEmpty && outgoing.isEmpty && finished.isEmpty }

    var all: [Duel] { active + incoming + outgoing + finished }
}

/// `GET /paper/duels/stats`.
struct DuelStats: Decodable {
    let wins: Int
    let losses: Int
    let draws: Int
    let currentStreak: Int
    let bestStreak: Int
}

/// `POST /paper/duels`. A nil `opponentUsername` (sent as JSON null) creates an
/// open invite link.
struct CreateDuelBody: Encodable {
    let opponentUsername: String?
    let durationHours: Int

    private enum CodingKeys: String, CodingKey {
        case opponentUsername, durationHours
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let opponentUsername {
            try container.encode(opponentUsername, forKey: .opponentUsername)
        } else {
            try container.encodeNil(forKey: .opponentUsername)
        }
        try container.encode(durationHours, forKey: .durationHours)
    }
}

/// `POST /paper/duels/join`.
struct JoinDuelBody: Encodable {
    let inviteCode: String
}

/// `paper:duel` on the `/paper` socket.
struct DuelEvent: Decodable {
    let duel: Duel
}

// MARK: - Leagues

/// A friend league: a private leaderboard joined by invite code, ranked on each
/// member's main-portfolio return for the current season.
struct League: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let ownerUsername: String?
    let isOwner: Bool
    /// The current code; may be null for a member if the server only shows it to
    /// the owner.
    let inviteCode: String?
    let memberCount: Int
    let maxMembers: Int?
    let createdAt: String?
    let season: Season?
    /// Null while you haven't qualified this season.
    let yourRank: Int?

    var inviteURL: URL? {
        inviteCode.flatMap { URL(string: "https://cooked.trade/l/\($0)") }
    }
}

struct LeagueStanding: Decodable, Identifiable, Hashable {
    var id: String { userId }
    let rank: Int?
    let userId: String
    let username: String
    let displayName: String?
    let avatarSeed: String?
    @OptionalDecimalString var returnPct: Decimal?
    let roundTrips: Int?
    let qualified: Bool
    let tier: String?
    let isYou: Bool

    var shownName: String { displayName.flatMap { $0.isEmpty ? nil : $0 } ?? username }
}

struct LeagueResponse: Decodable {
    let league: League
}

/// `GET /paper/leagues/:id`.
struct LeagueDetailResponse: Decodable {
    let league: League
    let standings: [LeagueStanding]
}

/// `GET /paper/leagues`.
struct LeagueListResponse: Decodable {
    let leagues: [League]
}

/// `POST /paper/leagues` and `PATCH /paper/leagues/:id`.
struct LeagueNameBody: Encodable {
    let name: String
}

/// `POST /paper/leagues/join`.
struct JoinLeagueBody: Encodable {
    let inviteCode: String
}

enum LeagueRules {
    static let maxNameLength = 32

    /// Trimmed, inner runs of whitespace collapsed — what the server keeps.
    static func sanitizedName(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    static func isValidName(_ raw: String) -> Bool {
        let name = sanitizedName(raw)
        return !name.isEmpty && name.count <= maxNameLength
    }

    /// An invite code from whatever was pasted: a bare code, or a
    /// `https://cooked.trade/l/<code>` / `cookedpaper://league/<code>` link.
    static func inviteCode(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil,
           let last = url.pathComponents.last(where: { $0 != "/" }), !last.isEmpty {
            return last
        }
        return trimmed
    }
}

// MARK: - Dates

/// The API's ISO-8601 timestamps, with or without fractional seconds.
enum CompeteDate {
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func parse(_ string: String) -> Date? {
        fractional.date(from: string) ?? plain.date(from: string)
    }

    /// "2d 4h", "5h 12m", "12:04" — the time left until `end`, or nil once past.
    static func remaining(until end: Date, from now: Date = Date()) -> String? {
        let seconds = Int(end.timeIntervalSince(now))
        guard seconds > 0 else { return nil }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let secs = seconds % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Daily Call

/// `higher` / `lower`. Raw strings on the wire; anything else is ignored.
enum DailyCallSide: String, Codable, CaseIterable {
    case higher, lower

    var title: String {
        switch self {
        case .higher: "Higher"
        case .lower: "Lower"
        }
    }

    var symbol: String {
        switch self {
        case .higher: "arrow.up"
        case .lower: "arrow.down"
        }
    }
}

struct DailyCallToken: Decodable, Hashable {
    let chain: String
    let mint: String
    let symbol: String?
    let name: String?
    let logoUri: String?

    var displaySymbol: String { symbol.map { "$" + $0 } ?? String(mint.prefix(6)) }
    var logoURL: URL? { logoUri.flatMap(URL.init(string:)) }
}

/// Your call on a day. `outcome` is `correct` / `incorrect` / `push` / `void`,
/// nil until the day settles.
struct DailyCallPick: Decodable, Hashable {
    let side: String
    let calledAt: String
    let outcome: String?

    var sideKind: DailyCallSide? { DailyCallSide(rawValue: side) }
}

/// How everyone called it; the server sends it only once you've called or the
/// day has locked.
struct DailyCallCommunity: Decodable, Hashable {
    let higher: Int
    let lower: Int
    let sampleSize: Int
    @OptionalDecimalString var higherPct: Decimal?
    @OptionalDecimalString var lowerPct: Decimal?

    /// 0...1, the share that called higher (0.5 when nobody has called).
    var higherShare: Double {
        guard sampleSize > 0 else { return 0.5 }
        return Double(higher) / Double(sampleSize)
    }
}

/// One UTC day's call. `status` is `open` / `locked` / `settled`; `result` is
/// `higher` / `lower` / `push` / `void` once settled.
struct DailyCall: Decodable, Hashable, Identifiable {
    /// `"2026-10-04"`.
    let id: String
    let token: DailyCallToken
    let status: String
    @DecimalString var openPriceUsd: Decimal
    let openedAt: String
    let locksAt: String
    let endsAt: String
    @OptionalDecimalString var closePriceUsd: Decimal?
    let settledAt: String?
    let result: String?
    let community: DailyCallCommunity?
    let me: DailyCallPick?

    var lockDate: Date? { CompeteDate.parse(locksAt) }
    var endDate: Date? { CompeteDate.parse(endsAt) }
    var isOpen: Bool { status == "open" }
    var isSettled: Bool { status == "settled" }
}

struct DailyCallStreak: Decodable, Hashable {
    let current: Int
    let best: Int
}

/// `GET /paper/daily-call` and `POST /paper/daily-call`.
struct DailyCallTodayResponse: Decodable {
    /// Nil only when the server couldn't price a token to open the day.
    let call: DailyCall?
    @OptionalDecimalString var livePriceUsd: Decimal?
    let livePriceAt: String?
    /// Yesterday's call, for the result state.
    let previous: DailyCall?
    let streak: DailyCallStreak
    let disclaimer: String?
}

struct DailyCallHistoryItem: Decodable, Identifiable, Hashable {
    let id: String
    let token: DailyCallToken
    let result: String?
    @DecimalString var openPriceUsd: Decimal
    @OptionalDecimalString var closePriceUsd: Decimal?
    let side: String?
    let outcome: String?
}

/// `GET /paper/daily-call/stats`.
struct DailyCallStats: Decodable {
    let played: Int
    let correct: Int
    let incorrect: Int
    let pushes: Int
    let currentStreak: Int
    let bestStreak: Int
    let history: [DailyCallHistoryItem]
}

/// One settled day in the crowd record.
struct DailyCallCrowdDay: Decodable, Identifiable, Hashable {
    let id: String
    let symbol: String?
    let result: String
    let crowdSide: String
    @DecimalString var crowdPct: Decimal
    let sampleSize: Int
    let crowdRight: Bool
}

/// `GET /paper/daily-call/crowd-record`: how often the majority called it right.
/// Push, void and tied days are left out by the server.
struct DailyCallCrowdRecord: Decodable {
    let windowDays: Int
    let sampleSize: Int
    let crowdRight: Int
    let crowdWrong: Int
    @OptionalDecimalString var crowdRightPct: Decimal?
    /// Days in a row the crowd has been right (positive) or wrong (negative).
    let currentRun: Int
    /// Newest first.
    let days: [DailyCallCrowdDay]
    let disclaimer: String?
}

struct DailyCallBody: Encodable {
    let side: String
}
