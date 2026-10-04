import Foundation
import Testing

@testable import CookedPaper

/// The compete spec's example payloads, decoded through the app's models.
struct CompeteModelDecodingTests {
    @Test func decodesTheCurrentSeason() throws {
        let json = Data(
            """
            {
              "season": { "id": "2026-10", "number": 10, "label": "Season 10 · October 2026",
                          "startsAt": "2026-10-01T00:00:00.000Z", "endsAt": "2026-11-01T00:00:00.000Z" },
              "tiers": [ { "id": "michelin", "name": "Michelin", "topPercent": 1 },
                         { "id": "head_chef", "name": "Head Chef", "topPercent": 10 } ],
              "me": { "qualified": true, "rank": 42, "of": 1310, "percentile": "3.2",
                      "tier": "head_chef", "returnPct": "18.45", "roundTrips": 7, "minRoundTrips": 2,
                      "nextTier": { "id": "michelin", "rankNeeded": 13 } },
              "top": [ { "rank": 1, "username": "degenwizard", "displayName": null,
                         "avatarSeed": "abc", "returnPct": "184.21", "tier": "michelin" } ]
            }
            """.utf8
        )
        let decoded = try JSONDecoder().decode(SeasonCurrentResponse.self, from: json)
        #expect(decoded.season.number == 10)
        #expect(decoded.season.endDate != nil)
        #expect(decoded.tiers.first?.topPercent == 1)
        #expect(decoded.me?.rank == 42)
        #expect(decoded.me?.returnPct == Decimal(string: "18.45"))
        #expect(SeasonTier(id: decoded.me?.tier) == .headChef)
        #expect(decoded.me?.nextTier?.rankNeeded == 13)
        #expect(decoded.top.first?.returnPct == Decimal(string: "184.21"))
    }

    @Test func decodesAnUnqualifiedStanding() throws {
        let json = Data(
            """
            { "qualified": false, "rank": null, "of": 1310, "percentile": null, "tier": "unranked",
              "returnPct": null, "roundTrips": 1, "minRoundTrips": 2, "nextTier": null }
            """.utf8
        )
        let decoded = try JSONDecoder().decode(SeasonStanding.self, from: json)
        #expect(decoded.qualified == false)
        #expect(decoded.rank == nil)
        #expect(decoded.percentile == nil)
        #expect(SeasonTier(id: decoded.tier) == .unranked)
    }

    @Test func decodesAchievementsWithAndWithoutProgress() throws {
        let json = Data(
            """
            { "achievements": [
                { "id": "first_trade", "title": "First Bite", "description": "Make your first trade",
                  "tier": "bronze", "icon": "fork.knife", "unlocked": true,
                  "unlockedAt": "2026-10-02T10:00:00Z", "seen": false, "progress": null },
                { "id": "hot_streak", "title": "Hot Streak", "description": "5 profitable closes in a row",
                  "tier": "silver", "icon": "flame.fill", "unlocked": false,
                  "unlockedAt": null, "seen": false, "progress": { "current": 3, "target": 5 } }
              ], "unlockedCount": 1, "total": 20 }
            """.utf8
        )
        let decoded = try JSONDecoder().decode(AchievementsResponse.self, from: json)
        #expect(decoded.total == 20)
        #expect(decoded.achievements[0].seen == false)
        #expect(decoded.achievements[0].tierKind == .bronze)
        #expect(decoded.achievements[1].progress?.fraction == 0.6)
    }

    @Test func decodesADuelListAndWorksOutTheResult() throws {
        let json = Data(
            """
            { "active": [],
              "incoming": [],
              "outgoing": [],
              "finished": [ {
                "id": "d1", "status": "finished", "durationHours": 24,
                "createdAt": "2026-10-01T00:00:00Z", "startsAt": "2026-10-01T01:00:00Z",
                "endsAt": "2026-10-02T01:00:00Z", "finishedAt": "2026-10-02T01:00:30Z",
                "inviteCode": null,
                "challenger": { "userId": "u1", "username": "wifmaxi", "displayName": null, "avatarSeed": "s1",
                                "portfolioId": "p1", "returnPct": "12.40", "equityUsd": "1124.00" },
                "opponent": { "userId": "u2", "username": "moonboi", "displayName": null, "avatarSeed": null,
                              "portfolioId": "p2", "returnPct": "3.10", "equityUsd": "1031.00" },
                "you": "challenger", "winner": "challenger", "startingBalanceUsd": "1000"
              } ] }
            """.utf8
        )
        let decoded = try JSONDecoder().decode(DuelListResponse.self, from: json)
        let duel = try #require(decoded.finished.first)
        #expect(duel.state == .finished)
        #expect(duel.outcome == .won)
        #expect(duel.leader == .me)
        #expect(duel.me?.username == "wifmaxi")
        #expect(duel.them?.equityUsd == Decimal(string: "1031.00"))
        #expect(duel.startingBalanceUsd == 1000)
    }

    @Test func decodesAnOpenInviteWithNoOpponent() throws {
        let json = Data(
            """
            { "duel": {
                "id": "d2", "status": "pending", "durationHours": 1,
                "createdAt": "2026-10-01T00:00:00Z", "startsAt": null, "endsAt": null, "finishedAt": null,
                "inviteCode": "k3J9xQ2a",
                "challenger": { "userId": "u1", "username": "wifmaxi", "displayName": null, "avatarSeed": null,
                                "portfolioId": null, "returnPct": null, "equityUsd": null },
                "opponent": null, "you": "challenger", "winner": null, "startingBalanceUsd": "1000"
            } }
            """.utf8
        )
        let duel = try JSONDecoder().decode(DuelResponse.self, from: json).duel
        #expect(duel.opponent == nil)
        #expect(duel.outcome == nil)
        #expect(duel.inviteURL?.absoluteString == "https://cooked.trade/d/k3J9xQ2a")
        #expect(duel.durationLabel == "1h")
    }

    @Test func encodesAnOpenInviteWithAnExplicitNull() throws {
        let data = try JSONEncoder().encode(CreateDuelBody(opponentUsername: nil, durationHours: 24))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["opponentUsername"] is NSNull)
        #expect(object["durationHours"] as? Int == 24)
    }

    @Test func decodesALeagueWithRankedAndUnqualifiedMembers() throws {
        let json = Data(
            """
            { "league": { "id": "l1", "name": "Group chat degens", "ownerUsername": "wifmaxi", "isOwner": true,
                          "inviteCode": "Q7m2Lx9a", "memberCount": 2, "maxMembers": 50,
                          "createdAt": "2026-10-01T00:00:00Z",
                          "season": { "id": "2026-10", "number": 10, "label": "Season 10 · October 2026",
                                      "startsAt": "2026-10-01T00:00:00Z", "endsAt": "2026-11-01T00:00:00Z" },
                          "yourRank": null },
              "standings": [
                { "rank": 1, "userId": "u2", "username": "degenwizard", "displayName": null, "avatarSeed": "s",
                  "returnPct": "34.10", "roundTrips": 9, "qualified": true, "tier": "head_chef", "isYou": false },
                { "rank": null, "userId": "u1", "username": "wifmaxi", "displayName": "Wif Maxi", "avatarSeed": null,
                  "returnPct": null, "roundTrips": 1, "qualified": false, "tier": "unranked", "isYou": true }
              ] }
            """.utf8
        )
        let decoded = try JSONDecoder().decode(LeagueDetailResponse.self, from: json)
        #expect(decoded.league.isOwner)
        #expect(decoded.league.yourRank == nil)
        #expect(decoded.league.inviteURL?.absoluteString == "https://cooked.trade/l/Q7m2Lx9a")
        #expect(decoded.standings[0].returnPct == Decimal(string: "34.10"))
        #expect(decoded.standings[1].rank == nil)
        #expect(decoded.standings[1].shownName == "Wif Maxi")
    }

    @Test func cleansLeagueNamesAndInviteCodes() {
        #expect(LeagueRules.sanitizedName("  Group   chat\n degens ") == "Group chat degens")
        #expect(!LeagueRules.isValidName("   "))
        #expect(!LeagueRules.isValidName(String(repeating: "a", count: 33)))
        #expect(LeagueRules.inviteCode(from: " Q7m2Lx9a ") == "Q7m2Lx9a")
        #expect(LeagueRules.inviteCode(from: "https://cooked.trade/l/Q7m2Lx9a") == "Q7m2Lx9a")
        #expect(LeagueRules.inviteCode(from: "cookedpaper://league/Q7m2Lx9a") == "Q7m2Lx9a")
    }
}
