#if DEBUG
import Foundation

/// Demo data for contests (challenges, rooms, squads) for UI tests and screenshots,
/// in the shape the API sends. Off unless `MockAPI` is enabled (DEBUG only).
nonisolated enum MockContests {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var challengeActive = true

    static func route(method: String, parts: [String], body: Data?) -> (Int, Any)? {
        guard parts.first == "paper", parts.count >= 2 else { return nil }
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]

        switch (method, Array(parts.dropFirst())) {
        case ("GET", ["challenges"]):
            return (200, challengeList())
        case ("POST", ["challenges"]):
            lock.lock(); challengeActive = true; lock.unlock()
            return (201, ["challenge": challenge(tier: json["tier"] as? String ?? "50k", status: "active", returnPct: "0.00")])
        case ("POST", let rest) where rest.count == 3 && rest[0] == "challenges" && rest[2] == "abandon":
            lock.lock(); challengeActive = false; lock.unlock()
            return (200, ["challenge": challenge(tier: "50k", status: "abandoned", returnPct: "2.48")])
        case ("GET", ["overlay", "key"]), ("POST", ["overlay", "key"]):
            return (200, ["key": "demoOverlayKey1234567890", "url": "https://cooked.trade/overlay/demoOverlayKey1234567890"])
        case ("GET", ["replays"]):
            return (200, [
                "scenarios": [(1, "medium", "covid"), (2, "medium", "may2021"), (3, "hard", "ftx"), (4, "brutal", "luna")].map { n, d, id -> [String: Any] in
                    ["id": id, "number": n, "difficulty": d, "candleCount": 97, "bestReturnPct": n == 1 ? "4.12" : NSNull(), "players": 120 * n,
                     "teaser": teaser(seed: n)] as [String: Any]
                },
                "startingBalanceUsd": "10000.00",
            ] as [String: Any])
        case ("GET", let rest) where rest.count == 2 && rest[0] == "replays":
            return (200, replayScenario(id: rest[1]))
        case ("POST", let rest) where rest.count == 3 && rest[0] == "replays":
            return (201, [
                "returnPct": "4.12", "holdReturnPct": "-31.26", "verdict": "survived",
                "reveal": ["name": "Bitcoin, COVID crash", "symbol": "BTC", "date": "March 10–14, 2020",
                           "story": "As COVID lockdowns hit, every market sold off at once."],
                "rank": 12, "sampleSize": 318,
            ] as [String: Any])
        case ("GET", ["squads"]):
            return (200, ["squads": [["id": "squad-1", "name": "Group chat", "memberCount": 4, "openProposals": 1] as [String: Any]]])
        case ("POST", ["squads"]), ("POST", ["squads", "join"]):
            return (200, ["squad": squad()])
        case ("GET", let rest) where rest.count == 2 && rest[0] == "squads":
            return (200, ["squad": squad()])
        case ("POST", let rest) where rest.count >= 3 && rest[0] == "squads" && rest[2] == "proposals":
            return (200, ["squad": squad()])
        case ("POST", let rest) where rest.count == 3 && rest[0] == "squads" && rest[2] == "leave":
            return (200, ["ok": true])
        case ("GET", ["rooms"]):
            return (200, ["live": [room(status: "live")], "upcoming": [room(status: "scheduled", title: "Fed decision day")], "mine": [] as [Any]])
        case ("POST", ["rooms"]):
            return (201, ["room": roomDetail(kind: "host", title: json["title"] as? String ?? "My stream")])
        case ("POST", ["rooms", "join"]):
            return (200, ["room": roomDetail(kind: "host", title: "Friday stream")])
        case ("GET", let rest) where rest.count == 2 && rest[0] == "rooms":
            return (200, ["room": roomDetail(kind: "event", title: "CPI day: the 8:30 print")])
        case ("POST", let rest) where rest.count == 3 && rest[0] == "rooms" && rest[2] == "join":
            return (200, ["room": roomDetail(kind: "event", title: "CPI day: the 8:30 print")])
        default:
            return nil
        }
    }

    /// A wobbly opening, different per scenario, for the list cards.
    private static func teaser(seed: Int) -> [Double] {
        (0..<24).map { i in
            let x = Double(i)
            return 100 + sin(x * 0.55 + Double(seed)) * 2.2 - x * 0.12 * Double(seed % 3 + 1) + cos(x * 1.7) * 0.8
        }
    }

    /// A made-up crash: a slow bleed, a capitulation candle, and a dead-cat bounce.
    private static func replayScenario(id: String) -> [String: Any] {
        var candles: [[Double]] = []
        var price = 100.0
        for i in 0..<97 {
            let drift = i == 50 ? -0.28 : (i > 50 && i < 60 ? 0.02 : -0.004)
            let open = price
            let close = max(1, open * (1 + drift + sin(Double(i)) * 0.006))
            candles.append([open, max(open, close) * 1.004, min(open, close) * 0.995, close])
            price = close
        }
        return ["id": id, "number": 1, "difficulty": "medium", "interval": "1h", "candles": candles, "startingBalanceUsd": "10000.00"]
    }

    private static func squad() -> [String: Any] {
        let wif = MockAPI.tokens[1]
        let proposal: [String: Any] = [
            "id": "proposal-1", "proposer": "moonboi", "side": "buy", "tokenMint": wif.mint, "symbol": wif.symbol,
            "notionalUsd": "1500.00", "sellPercent": NSNull(), "status": "open", "yes": 2, "no": 0, "needed": 3,
            "myVote": NSNull(), "createdAt": MockAPI.iso(daysFromNow: -0.005), "expiresAt": MockAPI.iso(daysFromNow: 0.015),
            "failure": NSNull(),
        ]
        return [
            "id": "squad-1", "name": "Group chat", "owner": "moonboi",
            "members": ["moonboi", "you", "solsniper", "cookedcat"].map { ["username": $0, "isOwner": $0 == "moonboi"] as [String: Any] },
            "inviteCode": "Sq8dCh4t", "portfolioId": "squad-portfolio", "returnPct": "7.25",
            "equityUsd": "10725.00", "cashUsd": "6200.00",
            "positions": [["tokenMint": wif.mint, "symbol": wif.symbol, "valueUsd": "4525.00", "unrealizedReturnPct": "13.10"] as [String: Any]],
            "open": [proposal], "recent": [] as [Any], "maxMembers": 5,
        ]
    }

    private static func room(status: String, title: String = "CPI day: the 8:30 print", kind: String = "event") -> [String: Any] {
        let live = status == "live"
        return [
            "id": "room-\(status)", "kind": kind, "title": title, "host": NSNull(),
            "startingBalanceUsd": "10000.00",
            "startsAt": MockAPI.iso(daysFromNow: live ? -0.01 : 2),
            "endsAt": MockAPI.iso(daysFromNow: live ? 0.03 : 2.04),
            "status": status, "participantCount": live ? 214 : 0, "joined": false, "inviteCode": NSNull(),
        ]
    }

    private static func roomDetail(kind: String, title: String) -> [String: Any] {
        let names = ["degenwizard", "you", "solsniper", "paperhands_og", "moonboi"]
        let returns = ["12.40", "6.10", "3.02", "-1.25", "-8.80"]
        var detail = room(status: "live", title: title, kind: kind)
        detail["joined"] = true
        if kind == "host" {
            detail["host"] = ["username": "degenwizard"]
            detail["inviteCode"] = "Fr1dAyS7"
        }
        detail["standings"] = names.enumerated().map { i, name in
            ["rank": i + 1, "username": name, "isHost": kind == "host" && i == 0, "isYou": name == "you", "returnPct": returns[i]] as [String: Any]
        }
        detail["me"] = ["rank": 2, "returnPct": "6.10", "portfolioId": "room-portfolio"] as [String: Any]
        detail["beatingHost"] = kind == "host" ? 0 : NSNull()
        detail["sampleSize"] = names.count
        detail["disclaimer"] = "Paper room: simulated prices, no stakes, no prizes."
        return detail
    }

    private static func challenge(tier: String, status: String, returnPct: String, daysAgo: Double = 6) -> [String: Any] {
        let balance: Double = ["10k": 10_000, "50k": 50_000, "100k": 100_000][tier] ?? 50_000
        let equity = balance * (1 + (Double(returnPct) ?? 0) / 100)
        let (target, loss): (Double, Double) = ["10k": (8, 5), "50k": (10, 5), "100k": (12, 4)][tier] ?? (8, 5)
        return [
            "id": "challenge-\(tier)-\(status)", "tier": tier, "status": status,
            "rules": ["profitTargetPct": String(format: "%g", target), "maxLossPct": String(format: "%g", loss), "days": 30] as [String: Any],
            "startingBalanceUsd": String(format: "%.2f", balance),
            "targetEquityUsd": String(format: "%.2f", balance * (1 + target / 100)),
            "floorEquityUsd": String(format: "%.2f", balance * (1 - loss / 100)),
            "equityUsd": String(format: "%.2f", equity), "returnPct": returnPct,
            "portfolioId": "challenge-portfolio",
            "startedAt": MockAPI.iso(daysFromNow: -daysAgo),
            "endsAt": MockAPI.iso(daysFromNow: 30 - daysAgo),
            "finishedAt": status == "active" ? NSNull() : MockAPI.iso(daysFromNow: -1),
        ]
    }

    private static func challengeList() -> [String: Any] {
        lock.lock(); let active = challengeActive; lock.unlock()
        return [
            "active": active ? challenge(tier: "50k", status: "active", returnPct: "2.48") : NSNull(),
            "history": [
                challenge(tier: "10k", status: "passed", returnPct: "8.31", daysAgo: 40),
                challenge(tier: "50k", status: "failed", returnPct: "-5.02", daysAgo: 75),
            ],
            "tiers": ["10k", "50k", "100k"].map { tier -> [String: Any] in
                let balance: Double = ["10k": 10_000, "50k": 50_000, "100k": 100_000][tier]!
                // The ladder: the demo account passed a $10K, so $50K is open and $100K is not.
                let rules: [String: (String, String)] = ["10k": ("8", "5"), "50k": ("10", "5"), "100k": ("12", "4")]
                let requires: [String: Any] = ["10k": NSNull(), "50k": "10k", "100k": "50k"]
                return [
                    "tier": tier, "startingBalanceUsd": String(format: "%.2f", balance),
                    "rules": ["profitTargetPct": rules[tier]!.0, "maxLossPct": rules[tier]!.1, "days": 30] as [String: Any],
                    "requires": requires[tier]!, "unlocked": tier != "100k",
                ]
            },
            "passed": 1, "attempts": 3,
            "disclaimer": "Paper challenge: simulated prices, no real money, no funding and no prizes.",
        ]
    }
}
#endif
