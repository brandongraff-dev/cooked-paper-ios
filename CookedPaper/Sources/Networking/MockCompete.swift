#if DEBUG
import Foundation

/// DEBUG-only fixtures for seasons, achievements and duels (see `MockAPI` for why
/// the mock exists). The demo account sits at #42 of 1,310 (Head Chef) this
/// season, has 8 of 20 achievements with one not yet seen (so the unlock toast
/// plays at launch), and has one active duel, one incoming invite, one open invite
/// link and two finished duels. Duel actions (accept, decline, cancel, create,
/// join, rematch) change that state for the rest of the run.
nonisolated enum MockCompete {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var duels: [[String: Any]]?
    nonisolated(unsafe) private static var seen: Set<String> = []
    nonisolated(unsafe) private static var counter = 0

    static let names = ["degenwizard", "solsniper", "paperhands_og", "moonboi", "rugsurvivor", "chartooor", "bagholder", "wenlambo", "gmgn", "cookedcat", "fomo_fren", "diamondpaws"]

    // MARK: - Routing

    static func route(method: String, parts: [String], body: Data?) -> (Int, Any)? {
        guard parts.first == "paper", parts.count >= 2 else { return nil }
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]

        switch (method, Array(parts.dropFirst())) {
        // Seasons
        case ("GET", ["seasons", "current"]): return (200, currentSeason())
        case ("GET", ["seasons", "history"]): return (200, ["seasons": history()])
        case ("GET", let rest) where rest.count == 3 && rest[0] == "seasons" && rest[2] == "results":
            if rest[1] == seasonId(monthsAgo: 0) {
                return (404, ["error": "not_found", "message": "This season isn't finished yet."])
            }
            return (200, results(seasonId: rest[1]))

        // Achievements
        case ("GET", ["achievements"]): return (200, achievements())
        case ("POST", ["achievements", "seen"]):
            let ids = json["ids"] as? [String] ?? []
            lock.lock(); seen.formUnion(ids); lock.unlock()
            return (200, ["ok": true])

        // Duels
        case ("GET", ["duels"]): return (200, list())
        case ("GET", ["duels", "stats"]):
            return (200, ["wins": 3, "losses": 1, "draws": 0, "currentStreak": 2, "bestStreak": 3])
        case ("POST", ["duels"]): return create(json)
        case ("POST", ["duels", "join"]): return join(json["inviteCode"] as? String ?? "")
        case ("GET", let rest) where rest.count == 2 && rest[0] == "duels":
            guard let duel = find(rest[1]) else { return notFound() }
            return (200, ["duel": duel])
        case ("POST", let rest) where rest.count == 3 && rest[0] == "duels":
            return act(id: rest[1], verb: rest[2])

        // A duel's own portfolio (the main one is `MockAPI`'s).
        case ("GET", let rest) where rest.count == 2 && rest[0] == "portfolios" && rest[1].hasPrefix("duel-pf-"):
            return (200, duelSnapshot(portfolioId: rest[1]))

        default:
            return nil
        }
    }

    // MARK: - Seasons

    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private static func monthStart(monthsAgo: Int) -> Date {
        let calendar = utcCalendar()
        let now = calendar.dateComponents([.year, .month], from: Date())
        let start = calendar.date(from: now) ?? Date()
        return calendar.date(byAdding: .month, value: -monthsAgo, to: start) ?? start
    }

    private static func seasonId(monthsAgo: Int) -> String {
        let parts = utcCalendar().dateComponents([.year, .month], from: monthStart(monthsAgo: monthsAgo))
        return String(format: "%04d-%02d", parts.year ?? 2026, parts.month ?? 1)
    }

    private static func season(monthsAgo: Int) -> [String: Any] {
        let calendar = utcCalendar()
        let start = monthStart(monthsAgo: monthsAgo)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        let parts = calendar.dateComponents([.year, .month], from: start)
        let year = parts.year ?? 2026
        let month = parts.month ?? 1
        let number = max(1, (year - 2026) * 12 + month)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "LLLL yyyy"
        return [
            "id": String(format: "%04d-%02d", year, month), "number": number,
            "label": "Season \(number) · \(formatter.string(from: start))",
            "startsAt": MockISO.string(start), "endsAt": MockISO.string(end),
        ]
    }

    private static var tiers: [[String: Any]] {
        [
            ["id": "michelin", "name": "Michelin", "topPercent": 1],
            ["id": "head_chef", "name": "Head Chef", "topPercent": 10],
            ["id": "sous_chef", "name": "Sous Chef", "topPercent": 25],
            ["id": "line_cook", "name": "Line Cook", "topPercent": 50],
            ["id": "prep_cook", "name": "Prep Cook", "topPercent": 100],
        ]
    }

    private static func currentSeason() -> [String: Any] {
        let returns = ["184.21", "122.40", "97.12", "74.55", "61.02", "48.90", "41.37", "36.80", "33.14", "29.95"]
        let top: [[String: Any]] = returns.enumerated().map { index, value in
            [
                "rank": index + 1, "username": names[index], "displayName": NSNull(),
                "avatarSeed": "seed-\(names[index])", "returnPct": value, "tier": "michelin",
            ] as [String: Any]
        }
        return [
            "season": season(monthsAgo: 0),
            "tiers": tiers,
            "me": [
                "qualified": true, "rank": 42, "of": 1310, "percentile": "3.2",
                "tier": "head_chef", "returnPct": "18.45", "roundTrips": 7, "minRoundTrips": 2,
                "nextTier": ["id": "michelin", "rankNeeded": 13] as [String: Any],
            ] as [String: Any],
            "top": top,
        ]
    }

    private static func history() -> [[String: Any]] {
        [
            ["season": season(monthsAgo: 1), "rank": 12, "of": 900, "tier": "head_chef", "returnPct": "44.10"],
            ["season": season(monthsAgo: 2), "rank": 160, "of": 820, "tier": "sous_chef", "returnPct": "12.80"],
            ["season": season(monthsAgo: 3), "rank": 402, "of": 640, "tier": "prep_cook", "returnPct": "-4.20"],
        ]
    }

    private static func results(seasonId: String) -> [String: Any] {
        let monthsAgo = (1...3).first { self.seasonId(monthsAgo: $0) == seasonId } ?? 1
        let field = 900
        let rows: [[String: Any]] = (0..<50).map { index in
            let rank = index + 1
            let percent = Double(rank) / Double(field) * 100
            let tier = percent <= 1 ? "michelin" : percent <= 10 ? "head_chef" : percent <= 25 ? "sous_chef" : "line_cook"
            let name = rank == 12 ? MockProfile.current().0 : "\(names[index % names.count])\(index >= names.count ? String(index) : "")"
            return [
                "rank": rank, "username": name, "displayName": NSNull(), "avatarSeed": "seed-\(name)",
                "returnPct": String(format: "%.2f", 210 * pow(0.93, Double(index))), "tier": tier,
            ] as [String: Any]
        }
        return ["season": season(monthsAgo: monthsAgo), "results": rows]
    }

    // MARK: - Achievements

    nonisolated private struct Entry: Sendable {
        let id: String
        let title: String
        let description: String
        let tier: String
        let icon: String
    }

    private static let catalog: [Entry] = [
        Entry(id: "first_trade", title: "First Bite", description: "Make your first trade", tier: "bronze", icon: "fork.knife"),
        Entry(id: "first_profit", title: "In the Green", description: "Close a trade in profit", tier: "bronze", icon: "arrow.up.right"),
        Entry(id: "first_leverage", title: "Turn Up the Heat", description: "Open your first leveraged position", tier: "bronze", icon: "flame"),
        Entry(id: "max_leverage", title: "Full Send", description: "Open a position at the maximum leverage", tier: "silver", icon: "bolt.fill"),
        Entry(id: "got_cooked", title: "Got Cooked", description: "Get liquidated (it happens)", tier: "bronze", icon: "frying.pan"),
        Entry(id: "double_up", title: "Double Up", description: "Close a position at +100% or more", tier: "gold", icon: "chart.line.uptrend.xyaxis"),
        Entry(id: "ten_bagger", title: "Ten Bagger", description: "Close a position at +900% or more", tier: "legendary", icon: "star.fill"),
        Entry(id: "hot_streak", title: "Hot Streak", description: "5 profitable closes in a row", tier: "silver", icon: "flame.fill"),
        Entry(id: "diamond_hands", title: "Diamond Hands", description: "Close in profit after holding 7+ days", tier: "silver", icon: "diamond"),
        Entry(id: "comeback", title: "Comeback Kid", description: "Get your portfolio from −30% back to positive", tier: "gold", icon: "arrow.uturn.up"),
        Entry(id: "diversified", title: "Full Menu", description: "Hold 5 different coins at once", tier: "bronze", icon: "square.grid.2x2"),
        Entry(id: "high_roller", title: "High Roller", description: "Put $5,000 into one position", tier: "silver", icon: "dollarsign.circle"),
        Entry(id: "duel_first_win", title: "First Blood", description: "Win a duel", tier: "bronze", icon: "figure.fencing"),
        Entry(id: "duel_streak_3", title: "Undefeated", description: "Win 3 duels in a row", tier: "gold", icon: "crown"),
        Entry(id: "duel_10_wins", title: "Duelist", description: "Win 10 duels", tier: "silver", icon: "shield.lefthalf.filled"),
        Entry(id: "season_finisher", title: "Season Finisher", description: "Qualify on a season leaderboard", tier: "bronze", icon: "flag.checkered"),
        Entry(id: "season_line_cook", title: "Line Cook", description: "Finish a season in the top 50%", tier: "bronze", icon: "medal"),
        Entry(id: "season_sous_chef", title: "Sous Chef", description: "Finish a season in the top 25%", tier: "silver", icon: "medal.fill"),
        Entry(id: "season_head_chef", title: "Head Chef", description: "Finish a season in the top 10%", tier: "gold", icon: "trophy"),
        Entry(id: "season_michelin", title: "Michelin Star", description: "Finish a season in the top 1%", tier: "legendary", icon: "trophy.fill"),
    ]

    /// Unlocked ids, newest first, with how many days ago. `hot_streak` is the
    /// one the demo account hasn't seen yet.
    private static let unlocked: [(id: String, daysAgo: Double)] = [
        ("hot_streak", 0.02), ("duel_first_win", 1.5), ("season_head_chef", 3), ("season_finisher", 3.1),
        ("high_roller", 6), ("first_leverage", 9), ("first_profit", 11), ("first_trade", 12),
    ]

    private static let progress: [String: (Int, Int)] = [
        "duel_streak_3": (2, 3), "duel_10_wins": (3, 10), "diversified": (3, 5), "double_up": (0, 1),
    ]

    private static func achievements() -> [String: Any] {
        lock.lock()
        let seenIds = seen
        lock.unlock()
        let unlockedIds = Set(unlocked.map(\.id))
        func item(_ entry: Entry, unlockedAt: Date?) -> [String: Any] {
            let isUnlocked = unlockedAt != nil
            let progressValue: Any = progress[entry.id].map { ["current": $0.0, "target": $0.1] as Any } ?? NSNull()
            return [
                "id": entry.id, "title": entry.title, "description": entry.description,
                "tier": entry.tier, "icon": entry.icon, "unlocked": isUnlocked,
                "unlockedAt": unlockedAt.map { MockISO.string($0) as Any } ?? NSNull(),
                "seen": isUnlocked ? (entry.id != "hot_streak" || seenIds.contains(entry.id)) : false,
                "progress": isUnlocked ? NSNull() as Any : progressValue,
            ]
        }
        var rows: [[String: Any]] = []
        for (id, daysAgo) in unlocked {
            guard let entry = catalog.first(where: { $0.id == id }) else { continue }
            rows.append(item(entry, unlockedAt: Date().addingTimeInterval(-daysAgo * 86_400)))
        }
        for entry in catalog where !unlockedIds.contains(entry.id) {
            rows.append(item(entry, unlockedAt: nil))
        }
        return ["achievements": rows, "unlockedCount": unlocked.count, "total": catalog.count]
    }

    // MARK: - Duels

    private static func me(portfolioId: Any = NSNull(), returnPct: Any = NSNull(), equity: Any = NSNull()) -> [String: Any] {
        let (username, displayName) = MockProfile.current()
        return [
            "userId": "demo-user", "username": username,
            "displayName": displayName.map { $0 as Any } ?? NSNull(),
            "avatarSeed": "demo-user-seed", "portfolioId": portfolioId,
            "returnPct": returnPct, "equityUsd": equity,
        ]
    }

    private static func player(_ name: String, portfolioId: Any = NSNull(), returnPct: Any = NSNull(), equity: Any = NSNull()) -> [String: Any] {
        [
            "userId": "user-\(name)", "username": name, "displayName": NSNull(),
            "avatarSeed": "seed-\(name)", "portfolioId": portfolioId,
            "returnPct": returnPct, "equityUsd": equity,
        ]
    }

    private static func iso(hoursFromNow hours: Double) -> String {
        MockISO.string(Date().addingTimeInterval(hours * 3600))
    }

    private static func duel(
        id: String, status: String, hours: Int, createdHoursAgo: Double,
        startsIn: Double?, inviteCode: String? = nil,
        challenger: [String: Any], opponent: [String: Any]?, you: String, winner: String? = nil
    ) -> [String: Any] {
        let starts: Any = startsIn.map { iso(hoursFromNow: $0) as Any } ?? NSNull()
        let ends: Any = startsIn.map { iso(hoursFromNow: $0 + Double(hours)) as Any } ?? NSNull()
        let finished: Any = status == "finished" ? ends : NSNull()
        return [
            "id": id, "status": status, "durationHours": hours,
            "createdAt": iso(hoursFromNow: -createdHoursAgo), "startsAt": starts, "endsAt": ends,
            "finishedAt": finished, "inviteCode": inviteCode.map { $0 as Any } ?? NSNull(),
            "challenger": challenger, "opponent": opponent.map { $0 as Any } ?? NSNull(),
            "you": you, "winner": winner.map { $0 as Any } ?? NSNull(), "startingBalanceUsd": "1000",
        ]
    }

    private static func seed() -> [[String: Any]] {
        [
            duel(id: "duel-active-1", status: "active", hours: 24, createdHoursAgo: 7, startsIn: -6.2,
                 challenger: me(portfolioId: "duel-pf-1", returnPct: "4.21", equity: "1042.10"),
                 opponent: player("degenwizard", portfolioId: "duel-pf-opp-1", returnPct: "2.87", equity: "1028.70"),
                 you: "challenger"),
            duel(id: "duel-incoming-1", status: "pending", hours: 1, createdHoursAgo: 0.4, startsIn: nil,
                 challenger: player("solsniper"), opponent: me(), you: "opponent"),
            duel(id: "duel-outgoing-1", status: "pending", hours: 168, createdHoursAgo: 2, startsIn: nil,
                 inviteCode: "k3J9xQ2a", challenger: me(), opponent: nil, you: "challenger"),
            duel(id: "duel-finished-1", status: "finished", hours: 1, createdHoursAgo: 30, startsIn: -29,
                 challenger: player("moonboi", portfolioId: "duel-pf-opp-2", returnPct: "3.10", equity: "1031.00"),
                 opponent: me(portfolioId: "duel-pf-2", returnPct: "12.40", equity: "1124.00"),
                 you: "opponent", winner: "opponent"),
            duel(id: "duel-finished-2", status: "finished", hours: 24, createdHoursAgo: 80, startsIn: -78,
                 challenger: me(portfolioId: "duel-pf-3", returnPct: "-5.20", equity: "948.00"),
                 opponent: player("chartooor", portfolioId: "duel-pf-opp-3", returnPct: "8.75", equity: "1087.50"),
                 you: "challenger", winner: "opponent"),
        ]
    }

    /// Call with `lock` held.
    private static func current() -> [[String: Any]] {
        if let duels { return duels }
        let seeded = seed()
        duels = seeded
        return seeded
    }

    private static func list() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        let all = current()
        func bucket(_ test: ([String: Any]) -> Bool) -> [[String: Any]] { all.filter(test) }
        return [
            "active": bucket { $0["status"] as? String == "active" },
            "incoming": bucket { $0["status"] as? String == "pending" && $0["you"] as? String == "opponent" },
            "outgoing": bucket { $0["status"] as? String == "pending" && $0["you"] as? String == "challenger" },
            "finished": bucket { $0["status"] as? String == "finished" },
        ]
    }

    private static func find(_ id: String) -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        return current().first { $0["id"] as? String == id }
    }

    private static func notFound() -> (Int, Any) {
        (404, ["error": "duel_not_found", "message": "No such duel."])
    }

    private static func nextId(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)-\(counter)"
    }

    private static func create(_ json: [String: Any]) -> (Int, Any) {
        let hours = json["durationHours"] as? Int ?? 24
        guard [1, 24, 168].contains(hours) else {
            return (400, ["error": "bad_request", "message": "Duration must be 1, 24 or 168 hours."])
        }
        let username = (json["opponentUsername"] as? String)?.trimmingCharacters(in: .whitespaces)
        lock.lock(); defer { lock.unlock() }
        var all = current()
        let open = all.filter { ["pending", "active"].contains($0["status"] as? String ?? "") }
        guard open.count < 5 else {
            return (409, ["error": "duel_limit", "message": "Too many open duels."])
        }
        let created: [String: Any]
        if let username, !username.isEmpty {
            let lowered = username.lowercased()
            if lowered == MockProfile.current().0.lowercased() {
                return (409, ["error": "duel_self", "message": "You can't duel yourself."])
            }
            guard names.contains(lowered) || lowered == "satoshi" else {
                return (404, ["error": "user_not_found", "message": "No such user."])
            }
            created = duel(id: nextId("duel-new"), status: "pending", hours: hours, createdHoursAgo: 0, startsIn: nil,
                           challenger: me(), opponent: player(lowered), you: "challenger")
        } else {
            let code = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
            created = duel(id: nextId("duel-new"), status: "pending", hours: hours, createdHoursAgo: 0, startsIn: nil,
                           inviteCode: code, challenger: me(), opponent: nil, you: "challenger")
        }
        all.insert(created, at: 0)
        duels = all
        return (201, ["duel": created])
    }

    private static func join(_ code: String) -> (Int, Any) {
        guard code.count == 8 else {
            return (404, ["error": "invite_invalid", "message": "That invite isn't valid."])
        }
        lock.lock(); defer { lock.unlock() }
        var all = current()
        let joined = duel(id: nextId("duel-joined"), status: "active", hours: 24, createdHoursAgo: 1, startsIn: 0,
                          challenger: player("wenlambo", portfolioId: "duel-pf-opp-9", returnPct: "0", equity: "1000"),
                          opponent: me(portfolioId: "duel-pf-9", returnPct: "0", equity: "1000"), you: "opponent")
        all.insert(joined, at: 0)
        duels = all
        return (200, ["duel": joined])
    }

    private static func act(id: String, verb: String) -> (Int, Any) {
        lock.lock(); defer { lock.unlock() }
        var all = current()
        guard let index = all.firstIndex(where: { $0["id"] as? String == id }) else { return notFound() }
        var target = all[index]
        let status = target["status"] as? String ?? ""
        switch verb {
        case "accept":
            guard status == "pending", target["you"] as? String == "opponent" else {
                return (409, ["error": "duel_not_active", "message": "This invite can't be accepted."])
            }
            let hours = target["durationHours"] as? Int ?? 24
            target["status"] = "active"
            target["startsAt"] = iso(hoursFromNow: 0)
            target["endsAt"] = iso(hoursFromNow: Double(hours))
            if var challenger = target["challenger"] as? [String: Any] {
                challenger["portfolioId"] = "duel-pf-opp-\(id)"
                challenger["returnPct"] = "0"
                challenger["equityUsd"] = "1000"
                target["challenger"] = challenger
            }
            target["opponent"] = me(portfolioId: "duel-pf-\(id)", returnPct: "0", equity: "1000")
            all[index] = target
        case "decline", "cancel":
            guard status == "pending" else {
                return (409, ["error": "duel_not_active", "message": "Only a pending invite can be \(verb)d."])
            }
            target["status"] = verb == "decline" ? "declined" : "cancelled"
            target["inviteCode"] = NSNull()
            all.remove(at: index)
        case "rematch":
            let isChallenger = target["you"] as? String == "challenger"
            let them = (isChallenger ? target["opponent"] : target["challenger"]) as? [String: Any]
            let name = them?["username"] as? String ?? "degenwizard"
            let created = duel(id: nextId("duel-rematch"), status: "pending", hours: target["durationHours"] as? Int ?? 24,
                               createdHoursAgo: 0, startsIn: nil, challenger: me(), opponent: player(name), you: "challenger")
            all.insert(created, at: 0)
            duels = all
            return (201, ["duel": created])
        default:
            return (404, ["error": "not_found", "message": "No such action."])
        }
        duels = all
        return (200, ["duel": target])
    }

    // MARK: - Duel portfolio

    private static func duelSnapshot(portfolioId: String) -> [String: Any] {
        let bonk = MockAPI.tokens[0]
        let popcat = MockAPI.tokens[3]
        func identity(_ t: MockAPI.DemoToken) -> [String: Any] {
            ["mint": t.mint, "symbol": t.symbol, "name": t.name, "hasLogo": false, "isVerified": t.verified]
        }
        func position(_ t: MockAPI.DemoToken, qty: String, cost: String, value: String, pnl: String, pct: String) -> [String: Any] {
            let avg = (Double(cost) ?? 0) / max(1e-12, Double(qty) ?? 1)
            return [
                "tokenMint": t.mint, "qty": qty, "costUsd": cost, "avgCostUsd": String(format: "%.10g", avg),
                "markPriceUsd": t.price, "markState": "fresh", "markFromLastFill": false,
                "valueUsd": value, "unrealizedPnlUsd": pnl, "unrealizedReturnPct": pct,
                "roundTripCount": 0, "token": identity(t),
                "marketCapUsd": t.marketCap, "liquidityUsd": t.liquidity,
            ]
        }
        func measured(_ key: String, _ value: String) -> [String: Any] {
            [key: value, "sampleSize": 1, "sampleOf": key == "pct" ? "round_trips" : "positions", "unavailable": NSNull()]
        }
        let created = MockISO.string(Date().addingTimeInterval(-6.2 * 3600))
        return [
            "portfolio": [
                "id": portfolioId, "name": "Duel", "startingBalanceUsd": "1000", "cashUsd": "420.40",
                "createdAt": created, "resetAt": NSNull(), "resetCount": 0, "archivedAt": NSNull(), "isGuest": false,
            ] as [String: Any],
            "portfolioId": portfolioId,
            "cashUsd": "420.40", "positionsValueUsd": "621.70", "equityUsd": "1042.10",
            "positions": [
                position(bonk, qty: "17500000", cost: "380.00", value: "404.95", pnl: "24.95", pct: "6.57"),
                position(popcat, qty: "492", cost: "199.60", value: "216.75", pnl: "17.15", pct: "8.59"),
            ],
            "roundTrips": [] as [Any],
            "stats": [
                "returnPct": measured("pct", "4.21"), "winRatePct": measured("pct", "100"),
                "maxDrawdownPct": measured("pct", "1.20"),
                "realizedPnlUsd": measured("usd", "0"), "unrealizedPnlUsd": measured("usd", "42.10"),
                "feesPaidUsd": "1.74", "tradeCount": 2, "roundTripCount": 0, "winCount": 0, "lossCount": 0,
            ] as [String: Any],
            "equityCurve": [
                "maxDrawdownPct": "1.20", "peakEquityUsd": "1046.30",
                "points": [
                    ["at": created, "equityUsd": "1000", "kind": "start"],
                    ["at": MockISO.string(Date()), "equityUsd": "1042.10", "kind": "mark"],
                ],
            ] as [String: Any],
            "leveragedPositions": [] as [Any],
            "leveragedRoundTrips": [] as [Any],
            "leveragedValueUsd": "0", "lockedMarginUsd": "0",
        ]
    }
}
#endif
