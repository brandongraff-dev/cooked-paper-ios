import Foundation

/// Seasons, achievements and duels (`auth: 'bearer'` server-side: a signed-in
/// account; guests get 401, so nothing here is called before sign-in). The backend
/// may not have these routes deployed yet, so callers treat a 404 as "not here
/// yet" (`Error.isNotFound`) and hide the feature instead of showing an error.
enum SeasonsAPI {
    static func current() async throws -> SeasonCurrentResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/seasons/current"),
            as: SeasonCurrentResponse.self
        )
    }

    static func history() async throws -> [SeasonHistoryEntry] {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/seasons/history"),
            as: SeasonHistoryResponse.self
        ).seasons
    }

    /// Archived seasons only; the current one answers 404.
    static func results(seasonId: String, limit: Int = 50) async throws -> SeasonResultsResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/seasons/\(seasonId)/results", query: ["limit": String(limit)]),
            as: SeasonResultsResponse.self
        )
    }
}

enum AchievementsAPI {
    static func list() async throws -> AchievementsResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/achievements"),
            as: AchievementsResponse.self
        )
    }

    static func markSeen(ids: [String]) async throws {
        try await APIClient.shared.send(
            Endpoint(
                path: "/paper/achievements/seen",
                method: "POST",
                body: APIClient.shared.encode(AchievementsSeenBody(ids: ids))
            ),
            as: OKResponse.self
        )
    }
}

enum DuelsAPI {
    static func list() async throws -> DuelListResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/duels"),
            as: DuelListResponse.self
        )
    }

    static func stats() async throws -> DuelStats {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/duels/stats"),
            as: DuelStats.self
        )
    }

    static func duel(id: String) async throws -> Duel {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/duels/\(id)"),
            as: DuelResponse.self
        ).duel
    }

    /// `opponentUsername` nil creates an open invite link.
    static func create(opponentUsername: String?, durationHours: Int) async throws -> Duel {
        try await APIClient.shared.send(
            Endpoint(
                path: "/paper/duels",
                method: "POST",
                body: APIClient.shared.encode(CreateDuelBody(opponentUsername: opponentUsername, durationHours: durationHours))
            ),
            as: DuelResponse.self
        ).duel
    }

    static func join(inviteCode: String) async throws -> Duel {
        try await APIClient.shared.send(
            Endpoint(
                path: "/paper/duels/join",
                method: "POST",
                body: APIClient.shared.encode(JoinDuelBody(inviteCode: inviteCode))
            ),
            as: DuelResponse.self
        ).duel
    }

    static func accept(id: String) async throws -> Duel {
        try await action(id: id, "accept")
    }

    static func decline(id: String) async throws -> Duel {
        try await action(id: id, "decline")
    }

    static func cancel(id: String) async throws -> Duel {
        try await action(id: id, "cancel")
    }

    static func rematch(id: String) async throws -> Duel {
        try await action(id: id, "rematch")
    }

    private static func action(id: String, _ verb: String) async throws -> Duel {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/duels/\(id)/\(verb)", method: "POST"),
            as: DuelResponse.self
        ).duel
    }
}

enum LeaguesAPI {
    static func list() async throws -> [League] {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/leagues"),
            as: LeagueListResponse.self
        ).leagues
    }

    static func detail(id: String) async throws -> LeagueDetailResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/leagues/\(id)"),
            as: LeagueDetailResponse.self
        )
    }

    static func create(name: String) async throws -> League {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/leagues", method: "POST", body: APIClient.shared.encode(LeagueNameBody(name: name))),
            as: LeagueResponse.self
        ).league
    }

    static func join(inviteCode: String) async throws -> League {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/leagues/join", method: "POST", body: APIClient.shared.encode(JoinLeagueBody(inviteCode: inviteCode))),
            as: LeagueResponse.self
        ).league
    }

    static func leave(id: String) async throws {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/leagues/\(id)/leave", method: "POST"),
            as: OKResponse.self
        )
    }

    static func rename(id: String, name: String) async throws -> League {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/leagues/\(id)", method: "PATCH", body: APIClient.shared.encode(LeagueNameBody(name: name))),
            as: LeagueResponse.self
        ).league
    }

    static func rotateCode(id: String) async throws -> League {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/leagues/\(id)/rotate-code", method: "POST"),
            as: LeagueResponse.self
        ).league
    }

    static func removeMember(leagueId: String, userId: String) async throws {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/leagues/\(leagueId)/members/\(userId)/remove", method: "POST"),
            as: OKResponse.self
        )
    }

    static func delete(id: String) async throws {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/leagues/\(id)", method: "DELETE"),
            as: OKResponse.self
        )
    }
}

/// The Daily Call: one featured token per UTC day, called higher or lower than
/// its open. Bearer like the rest of Compete; a 404 means the server doesn't have
/// it yet and the card hides itself.
enum DailyCallAPI {
    static func today() async throws -> DailyCallTodayResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/daily-call"),
            as: DailyCallTodayResponse.self
        )
    }

    /// One call per day, final once made.
    static func call(_ side: DailyCallSide) async throws -> DailyCallTodayResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/daily-call", method: "POST", body: APIClient.shared.encode(DailyCallBody(side: side.rawValue))),
            as: DailyCallTodayResponse.self
        )
    }

    static func stats() async throws -> DailyCallStats {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/daily-call/stats"),
            as: DailyCallStats.self
        )
    }

    /// Public: the same record for everyone.
    static func crowdRecord() async throws -> DailyCallCrowdRecord {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/daily-call/crowd-record"),
            as: DailyCallCrowdRecord.self
        )
    }
}

/// Prop-firm style challenges. Bearer.
enum ChallengeAPI {
    static func list() async throws -> ChallengeListResponse {
        try await APIClient.shared.send(Endpoint(path: "/paper/challenges"), as: ChallengeListResponse.self)
    }

    static func start(tier: String) async throws -> Challenge {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/challenges", method: "POST", body: APIClient.shared.encode(CreateChallengeBody(tier: tier))),
            as: ChallengeResponse.self
        ).challenge
    }

    static func abandon(id: String) async throws -> Challenge {
        try await APIClient.shared.send(
            Endpoint(path: "/paper/challenges/\(id)/abandon", method: "POST"),
            as: ChallengeResponse.self
        ).challenge
    }
}

extension Error {
    /// The route answered 404 — for the compete endpoints, usually "this server
    /// doesn't have the feature yet".
    var isNotFound: Bool {
        guard let apiError = self as? APIError, case .server(let status, _) = apiError else { return false }
        return status == 404
    }
}

/// Friendly sentences for the compete error codes (spec §3), checked against both
/// the envelope's `error` and its `reason`.
enum CompeteErrorText {
    /// Which feature is asking: a few codes (`invite_invalid`, a bare 404) read
    /// differently for a league than for a duel.
    enum Context {
        case duel, league
    }

    static func message(for error: Error, in context: Context = .duel) -> String {
        guard let apiError = error as? APIError else { return error.localizedDescription }
        for key in [apiError.code, apiError.reason].compactMap({ $0 }) {
            if let known = sentence(for: key, in: context) { return known }
        }
        if case .server(let status, _) = apiError {
            if status == 429 { return "That's a lot at once. Try again in a minute." }
            if status == 404 {
                return context == .league
                    ? "Leagues aren't available yet. Check back soon."
                    : "Duels aren't available yet. Check back soon."
            }
        }
        return apiError.errorDescription ?? "Something went wrong. Try again."
    }

    static func sentence(for code: String, in context: Context = .duel) -> String? {
        if context == .league, code == "invite_invalid" {
            return "That invite code doesn't work. It may have been changed. Ask for a fresh link."
        }
        switch code {
        case "league_full": return "This league is full. Leagues hold up to 50 members."
        case "league_limit": return "You're at the limit: 10 leagues joined, 5 owned. Leave one first."
        case "league_not_found": return "That league doesn't exist anymore."
        case "already_member": return "You're already in this league."
        case "not_owner": return "Only the league's owner can do that."
        case "duel_limit": return "You already have 5 duels going. Finish or cancel one first."
        case "duel_not_found": return "That duel doesn't exist anymore."
        case "duel_not_active": return "This duel isn't live. Trading opens when it starts and closes when it ends."
        case "contest_not_active": return "This isn't running right now, so its portfolio can't trade."
        case "duel_self": return "You can't duel yourself. Pick someone else."
        case "duel_exists": return "You already have an invite waiting with this player."
        case "user_not_found": return "No one goes by that username. Check the spelling."
        case "invite_invalid": return "This invite has expired or someone already took it."
        case "daily_call_locked": return "Calls are locked for today. A new Daily Call opens at 00:00 UTC."
        case "daily_call_exists": return "You've already made today's call. Calls are final."
        case "daily_call_unavailable": return "Today's Daily Call isn't ready yet. Try again in a minute."
        default: return nil
        }
    }
}
