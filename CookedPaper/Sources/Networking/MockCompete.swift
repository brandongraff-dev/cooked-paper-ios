#if DEBUG
import Foundation

/// DEBUG-only fixtures for seasons, achievements and duels (see `MockAPI` for why
/// the mock exists). The demo account sits at #42 of 1,310 (Head Chef) this
/// season, has 10 of 26 achievements with one not yet seen (so the unlock toast
/// plays at launch), has one active duel, one incoming invite, one open invite
/// link and two finished duels, and is in two friend leagues (owns one with 7
/// members, 2 not yet qualified; joined another). Duel and league actions change
/// that state for the rest of the run. Today's Daily Call is open on WIF (no call
/// yet, a 3-day streak); yesterday's BONK call settled correct. Making a call
/// sticks for the rest of the run.
nonisolated enum MockCompete {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var duels: [[String: Any]]?
    nonisolated(unsafe) private static var seen: Set<String> = []
    nonisolated(unsafe) private static var counter = 0
    nonisolated(unsafe) private static var dailyPick: (side: String, at: Date)?

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

        // Daily Call
        case ("GET", ["daily-call"]): return (200, dailyToday())
        case ("POST", ["daily-call"]): return makeDailyCall(json["side"] as? String ?? "")
        case ("GET", ["daily-call", "stats"]): return (200, dailyStats())

        // Leagues
        case ("GET", ["leagues"]): return (200, ["leagues": leagueList()])
        case ("POST", ["leagues"]): return createLeague(json["name"] as? String ?? "")
        case ("POST", ["leagues", "join"]): return joinLeague(json["inviteCode"] as? String ?? "")
        case ("GET", let rest) where rest.count == 2 && rest[0] == "leagues":
            return leagueDetail(rest[1])
        case ("PATCH", let rest) where rest.count == 2 && rest[0] == "leagues":
            return renameLeague(rest[1], name: json["name"] as? String ?? "")
        case ("DELETE", let rest) where rest.count == 2 && rest[0] == "leagues":
            return deleteLeague(rest[1])
        case ("POST", let rest) where rest.count == 3 && rest[0] == "leagues" && rest[2] == "leave":
            return leaveLeague(rest[1])
        case ("POST", let rest) where rest.count == 3 && rest[0] == "leagues" && rest[2] == "rotate-code":
            return rotateLeagueCode(rest[1])
        case ("POST", let rest) where rest.count == 5 && rest[0] == "leagues" && rest[2] == "members" && rest[4] == "remove":
            return removeLeagueMember(rest[1], userId: rest[3])

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
        Entry(id: "league_founder", title: "Host", description: "Start a league that reaches 3 members", tier: "bronze", icon: "person.3.fill"),
        Entry(id: "league_champion", title: "League Champion", description: "Finish a season #1 in a league of 5+", tier: "gold", icon: "crown.fill"),
        Entry(id: "daily_first_call", title: "Make the Call", description: "Make your first Daily Call", tier: "bronze", icon: "megaphone"),
        Entry(id: "daily_streak_3", title: "Reading the Room", description: "3 correct Daily Calls in a row", tier: "bronze", icon: "calendar.badge.checkmark"),
        Entry(id: "daily_streak_7", title: "Seven Straight", description: "7 correct Daily Calls in a row", tier: "silver", icon: "flame.circle"),
        Entry(id: "daily_streak_30", title: "Oracle", description: "30 correct Daily Calls in a row", tier: "legendary", icon: "eye.circle.fill"),
    ]

    /// Unlocked ids, newest first, with how many days ago. `hot_streak` is the
    /// one the demo account hasn't seen yet.
    private static let unlocked: [(id: String, daysAgo: Double)] = [
        ("hot_streak", 0.02), ("daily_streak_3", 0.9), ("duel_first_win", 1.5), ("season_head_chef", 3), ("season_finisher", 3.1),
        ("league_founder", 5), ("high_roller", 6), ("first_leverage", 9), ("first_profit", 11), ("first_trade", 12),
    ]

    private static let progress: [String: (Int, Int)] = [
        "duel_streak_3": (2, 3), "duel_10_wins": (3, 10), "daily_streak_7": (3, 7), "daily_streak_30": (3, 30), "diversified": (3, 5), "double_up": (0, 1),
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

    // MARK: - Daily Call

    private static func dailyDec(_ value: Double) -> String { String(format: "%.10g", value) }

    private static func dayStart(daysAgo: Int) -> Date {
        let calendar = utcCalendar()
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
    }

    private static func dayId(daysAgo: Int) -> String {
        let parts = utcCalendar().dateComponents([.year, .month, .day], from: dayStart(daysAgo: daysAgo))
        return String(format: "%04d-%02d-%02d", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
    }

    private static func dailyToken(_ t: MockAPI.DemoToken) -> [String: Any] {
        [
            "chain": "solana", "mint": t.mint, "symbol": t.symbol, "name": t.name,
            "logoUri": MockAPI.logos[t.mint].map { $0 as Any } ?? NSNull(),
            "safety": [
                "state": "unevaluated", "reason": "never_scored", "checks": [] as [Any],
                "missingCritical": ["mint_authority_revoked", "freeze_authority_revoked", "lp_locked_or_burned"],
                "score": NSNull(), "scoreVersion": NSNull(), "computedAt": NSNull(),
            ] as [String: Any],
        ]
    }

    /// The day's token cycles through the demo list so it changes daily.
    private static func dailyDemoToken(daysAgo: Int) -> MockAPI.DemoToken {
        let day = Int(dayStart(daysAgo: daysAgo).timeIntervalSince1970 / 86_400)
        let pool = Array(MockAPI.tokens.prefix(4))
        return pool[((day % pool.count) + pool.count) % pool.count]
    }

    private static func community(higher: Int, lower: Int) -> [String: Any] {
        let total = higher + lower
        func pct(_ n: Int) -> Any {
            total == 0 ? NSNull() as Any : String(format: "%.1f", Double(n) * 100 / Double(total))
        }
        return ["higher": higher, "lower": lower, "sampleSize": total, "higherPct": pct(higher), "lowerPct": pct(lower)]
    }

    private static func dailyCallObject(daysAgo: Int, pick: (side: String, at: Date)?) -> [String: Any] {
        let start = dayStart(daysAgo: daysAgo)
        let locks = start.addingTimeInterval(20 * 3_600)
        let ends = start.addingTimeInterval(86_400)
        let token = dailyDemoToken(daysAgo: daysAgo)
        let open = MockAPI.livePrice(token, at: start)
        let settled = daysAgo > 0
        let now = Date()
        let status = settled ? "settled" : (now >= locks ? "locked" : "open")
        let close: Any = settled ? dailyDec((Double(open) ?? 1) * 1.042) as Any : NSNull()
        let result: Any = settled ? "higher" as Any : NSNull()
        var higher = 1_284
        var lower = 911
        if let pick, !settled {
            if pick.side == "higher" { higher += 1 } else { lower += 1 }
        }
        let revealed = pick != nil || status != "open"
        let me: Any = pick.map { made -> Any in
            [
                "side": made.side, "calledAt": MockISO.string(made.at),
                "outcome": settled ? (made.side == "higher" ? "correct" : "incorrect") as Any : NSNull(),
            ] as [String: Any]
        } ?? NSNull()
        return [
            "id": dayId(daysAgo: daysAgo), "token": dailyToken(token), "status": status,
            "openPriceUsd": open, "openedAt": MockISO.string(start.addingTimeInterval(4)),
            "locksAt": MockISO.string(locks), "endsAt": MockISO.string(ends),
            "closePriceUsd": close,
            "settledAt": settled ? MockISO.string(ends.addingTimeInterval(31)) as Any : NSNull(),
            "result": result,
            "community": revealed ? community(higher: higher, lower: lower) as Any : NSNull(),
            "me": me,
        ]
    }

    private static func dailyToday() -> [String: Any] {
        lock.lock()
        let pick = dailyPick
        lock.unlock()
        let token = dailyDemoToken(daysAgo: 0)
        let yesterday = (side: "higher", at: dayStart(daysAgo: 1).addingTimeInterval(9 * 3_600))
        return [
            "call": dailyCallObject(daysAgo: 0, pick: pick),
            "livePriceUsd": MockAPI.livePrice(token),
            "livePriceAt": MockISO.string(Date()),
            "previous": dailyCallObject(daysAgo: 1, pick: yesterday),
            "streak": ["current": 3, "best": 5],
            "disclaimer": "Paper game: simulated prices, no stakes, no prizes.",
        ]
    }

    private static func makeDailyCall(_ side: String) -> (Int, Any) {
        guard side == "higher" || side == "lower" else {
            return (400, ["error": "bad_request", "message": "side must be higher or lower."])
        }
        let locks = dayStart(daysAgo: 0).addingTimeInterval(20 * 3_600)
        if Date() >= locks {
            return (409, ["error": "daily_call_locked", "message": "Calls for today have locked."])
        }
        lock.lock()
        if dailyPick != nil {
            lock.unlock()
            return (409, ["error": "daily_call_exists", "message": "You already made today's call."])
        }
        dailyPick = (side, Date())
        lock.unlock()
        return (201, dailyToday())
    }

    private static func dailyStats() -> [String: Any] {
        let sides = ["higher", "higher", "higher", "higher", NSNull(), "higher", "lower"] as [Any]
        let history: [[String: Any]] = (1...7).map { (daysAgo: Int) -> [String: Any] in
            let token = dailyDemoToken(daysAgo: daysAgo)
            let open = MockAPI.livePrice(token, at: dayStart(daysAgo: daysAgo))
            let up = daysAgo != 4
            let side = sides[daysAgo - 1]
            let outcome: Any = (side as? String).map { s -> Any in (s == "higher") == up ? "correct" : "incorrect" } ?? NSNull()
            return [
                "id": dayId(daysAgo: daysAgo), "token": dailyToken(token),
                "result": up ? "higher" : "lower",
                "openPriceUsd": open,
                "closePriceUsd": dailyDec((Double(open) ?? 1) * (up ? 1.042 : 0.97)),
                "side": side, "outcome": outcome,
            ]
        }
        return [
            "played": 6, "correct": 4, "incorrect": 2, "pushes": 0,
            "currentStreak": 3, "bestStreak": 5, "history": history,
        ]
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

    // MARK: - Leagues

    nonisolated(unsafe) private static var leagues: [[String: Any]]?

    private static func member(_ name: String, returnPct: String?, roundTrips: Int, tier: String) -> [String: Any] {
        [
            "userId": "user-\(name)", "username": name, "displayName": NSNull(), "avatarSeed": "seed-\(name)",
            "returnPct": returnPct.map { $0 as Any } ?? NSNull(), "roundTrips": roundTrips, "tier": tier,
        ]
    }

    private static func meMember() -> [String: Any] {
        let (username, displayName) = MockProfile.current()
        return [
            "userId": "demo-user", "username": username,
            "displayName": displayName.map { $0 as Any } ?? NSNull(), "avatarSeed": "demo-user-seed",
            "returnPct": "18.45", "roundTrips": 7, "tier": "head_chef",
        ]
    }

    private static func seedLeagues() -> [[String: Any]] {
        [
            [
                "id": "league-1", "name": "Group chat degens", "ownerUsername": MockProfile.current().0,
                "inviteCode": "Q7m2Lx9a", "createdAt": iso(hoursFromNow: -24 * 9),
                "members": [
                    member("degenwizard", returnPct: "34.10", roundTrips: 9, tier: "head_chef"),
                    meMember(),
                    member("moonboi", returnPct: "11.62", roundTrips: 5, tier: "sous_chef"),
                    member("bagholder", returnPct: "2.04", roundTrips: 3, tier: "line_cook"),
                    member("fomo_fren", returnPct: "-6.80", roundTrips: 4, tier: "prep_cook"),
                    member("wenlambo", returnPct: nil, roundTrips: 1, tier: "unranked"),
                    member("gmgn", returnPct: nil, roundTrips: 0, tier: "unranked"),
                ],
            ],
            [
                "id": "league-2", "name": "Desk 4 traders", "ownerUsername": "solsniper",
                "inviteCode": "Hb3kPq7z", "createdAt": iso(hoursFromNow: -24 * 20),
                "members": [
                    member("solsniper", returnPct: "52.30", roundTrips: 12, tier: "head_chef"),
                    member("chartooor", returnPct: "21.75", roundTrips: 8, tier: "sous_chef"),
                    meMember(),
                    member("rugsurvivor", returnPct: "-3.10", roundTrips: 6, tier: "prep_cook"),
                ],
            ],
        ]
    }

    /// Call with `lock` held.
    private static func currentLeagues() -> [[String: Any]] {
        if let leagues { return leagues }
        let seeded = seedLeagues()
        leagues = seeded
        return seeded
    }

    private static func isQualified(_ member: [String: Any]) -> Bool {
        (member["roundTrips"] as? Int ?? 0) >= 2 && member["returnPct"] is String
    }

    /// Ranked members (best return first) with ranks, then the unqualified.
    private static func standings(_ league: [String: Any]) -> [[String: Any]] {
        let members = league["members"] as? [[String: Any]] ?? []
        let ranked = members.filter(isQualified).sorted {
            (Double($0["returnPct"] as? String ?? "") ?? 0) > (Double($1["returnPct"] as? String ?? "") ?? 0)
        }
        let rest = members.filter { !isQualified($0) }
        var rows: [[String: Any]] = []
        for (index, var row) in ranked.enumerated() {
            row["rank"] = index + 1
            row["qualified"] = true
            row["isYou"] = row["userId"] as? String == "demo-user"
            rows.append(row)
        }
        for var row in rest {
            row["rank"] = NSNull()
            row["qualified"] = false
            row["isYou"] = row["userId"] as? String == "demo-user"
            rows.append(row)
        }
        return rows
    }

    private static func leagueObject(_ league: [String: Any]) -> [String: Any] {
        let rows = standings(league)
        let mine = rows.first { $0["isYou"] as? Bool == true }
        let owner = league["ownerUsername"] as? String ?? ""
        return [
            "id": league["id"] ?? "", "name": league["name"] ?? "", "ownerUsername": owner,
            "isOwner": owner.lowercased() == MockProfile.current().0.lowercased(),
            "inviteCode": league["inviteCode"] ?? NSNull(),
            "memberCount": rows.count, "maxMembers": 50,
            "createdAt": league["createdAt"] ?? MockISO.string(Date()),
            "season": season(monthsAgo: 0),
            "yourRank": mine?["rank"] ?? NSNull(),
        ]
    }

    private static func isOwner(_ league: [String: Any]) -> Bool {
        (league["ownerUsername"] as? String ?? "").lowercased() == MockProfile.current().0.lowercased()
    }

    private static func leagueNotFound() -> (Int, Any) {
        (404, ["error": "league_not_found", "message": "No such league."])
    }

    private static func notOwner() -> (Int, Any) {
        (403, ["error": "not_owner", "message": "Only the owner can do that."])
    }

    private static func newInviteCode() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
    }

    private static func sanitized(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    private static func leagueList() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return currentLeagues().map(leagueObject)
    }

    private static func leagueDetail(_ id: String) -> (Int, Any) {
        lock.lock(); defer { lock.unlock() }
        guard let league = currentLeagues().first(where: { $0["id"] as? String == id }) else { return leagueNotFound() }
        return (200, ["league": leagueObject(league), "standings": standings(league)])
    }

    private static func createLeague(_ rawName: String) -> (Int, Any) {
        let name = sanitized(rawName)
        guard !name.isEmpty, name.count <= 32 else {
            return (400, ["error": "bad_request", "message": "League names are 1–32 characters."])
        }
        lock.lock(); defer { lock.unlock() }
        var all = currentLeagues()
        guard all.count < 10, all.filter(isOwner).count < 5 else {
            return (409, ["error": "league_limit", "message": "Too many leagues."])
        }
        let created: [String: Any] = [
            "id": nextId("league-new"), "name": name, "ownerUsername": MockProfile.current().0,
            "inviteCode": newInviteCode(), "createdAt": MockISO.string(Date()), "members": [meMember()],
        ]
        all.insert(created, at: 0)
        leagues = all
        return (201, ["league": leagueObject(created)])
    }

    private static func joinLeague(_ code: String) -> (Int, Any) {
        lock.lock(); defer { lock.unlock() }
        var all = currentLeagues()
        if all.contains(where: { $0["inviteCode"] as? String == code }) {
            return (409, ["error": "already_member", "message": "Already a member."])
        }
        guard code.count == 8 else {
            return (404, ["error": "invite_invalid", "message": "That invite isn't valid."])
        }
        guard all.count < 10 else {
            return (409, ["error": "league_limit", "message": "Too many leagues."])
        }
        let joined: [String: Any] = [
            "id": nextId("league-joined"), "name": "Friday night fills", "ownerUsername": "cookedcat",
            "inviteCode": code, "createdAt": iso(hoursFromNow: -24 * 3),
            "members": [
                member("cookedcat", returnPct: "27.40", roundTrips: 6, tier: "sous_chef"),
                member("diamondpaws", returnPct: "9.15", roundTrips: 4, tier: "line_cook"),
                member("paperhands_og", returnPct: nil, roundTrips: 1, tier: "unranked"),
                meMember(),
            ],
        ]
        all.insert(joined, at: 0)
        leagues = all
        return (200, ["league": leagueObject(joined)])
    }

    private static func renameLeague(_ id: String, name rawName: String) -> (Int, Any) {
        let name = sanitized(rawName)
        guard !name.isEmpty, name.count <= 32 else {
            return (400, ["error": "bad_request", "message": "League names are 1–32 characters."])
        }
        lock.lock(); defer { lock.unlock() }
        var all = currentLeagues()
        guard let index = all.firstIndex(where: { $0["id"] as? String == id }) else { return leagueNotFound() }
        guard isOwner(all[index]) else { return notOwner() }
        all[index]["name"] = name
        leagues = all
        return (200, ["league": leagueObject(all[index])])
    }

    private static func rotateLeagueCode(_ id: String) -> (Int, Any) {
        lock.lock(); defer { lock.unlock() }
        var all = currentLeagues()
        guard let index = all.firstIndex(where: { $0["id"] as? String == id }) else { return leagueNotFound() }
        guard isOwner(all[index]) else { return notOwner() }
        all[index]["inviteCode"] = newInviteCode()
        leagues = all
        return (200, ["league": leagueObject(all[index])])
    }

    private static func removeLeagueMember(_ id: String, userId: String) -> (Int, Any) {
        lock.lock(); defer { lock.unlock() }
        var all = currentLeagues()
        guard let index = all.firstIndex(where: { $0["id"] as? String == id }) else { return leagueNotFound() }
        guard isOwner(all[index]) else { return notOwner() }
        guard userId != "demo-user" else {
            return (400, ["error": "bad_request", "message": "Leave the league instead."])
        }
        var members = all[index]["members"] as? [[String: Any]] ?? []
        members.removeAll { $0["userId"] as? String == userId }
        all[index]["members"] = members
        leagues = all
        return (200, ["ok": true])
    }

    private static func deleteLeague(_ id: String) -> (Int, Any) {
        lock.lock(); defer { lock.unlock() }
        var all = currentLeagues()
        guard let index = all.firstIndex(where: { $0["id"] as? String == id }) else { return leagueNotFound() }
        guard isOwner(all[index]) else { return notOwner() }
        all.remove(at: index)
        leagues = all
        return (200, ["ok": true])
    }

    /// Leaving drops the league from your list; server-side, ownership passes to
    /// the longest-standing member (or the league goes if you were the last).
    private static func leaveLeague(_ id: String) -> (Int, Any) {
        lock.lock(); defer { lock.unlock() }
        var all = currentLeagues()
        guard let index = all.firstIndex(where: { $0["id"] as? String == id }) else { return leagueNotFound() }
        all.remove(at: index)
        leagues = all
        return (200, ["ok": true])
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
