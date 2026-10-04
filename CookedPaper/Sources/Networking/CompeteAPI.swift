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
    static func message(for error: Error) -> String {
        guard let apiError = error as? APIError else { return error.localizedDescription }
        for key in [apiError.code, apiError.reason].compactMap({ $0 }) {
            if let known = sentence(for: key) { return known }
        }
        if case .server(let status, _) = apiError {
            if status == 429 { return "That's a lot of duels at once. Try again in a minute." }
            if status == 404 { return "Duels aren't available yet. Check back soon." }
        }
        return apiError.errorDescription ?? "Something went wrong. Try again."
    }

    static func sentence(for code: String) -> String? {
        switch code {
        case "duel_limit": return "You already have 5 duels going. Finish or cancel one first."
        case "duel_not_found": return "That duel doesn't exist anymore."
        case "duel_not_active": return "This duel isn't live. Trading opens when it starts and closes when it ends."
        case "duel_self": return "You can't duel yourself. Pick someone else."
        case "duel_exists": return "You already have an invite waiting with this player."
        case "user_not_found": return "No one goes by that username. Check the spelling."
        case "invite_invalid": return "This invite has expired or someone already took it."
        default: return nil
        }
    }
}
