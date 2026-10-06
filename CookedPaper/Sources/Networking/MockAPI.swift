#if DEBUG
import Foundation

/// A DEBUG-only, in-process stand-in for `apps/api`, switched on by the
/// `UITEST_MOCK_API=1` launch environment variable (set only by the UI screenshot
/// walkthrough). CI has no backend to talk to (and screenshots shouldn't depend on
/// live markets), so without this every data-backed screen (Discover, Token Detail,
/// Portfolio, Leaderboard) would screenshot as an empty or error state. Every fixture below is shaped to decode through the exact same
/// `Decodable` models the real API feeds, so this exercises the real parsing and
/// rendering paths; only the transport is swapped.
nonisolated enum MockAPI {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["UITEST_MOCK_API"] == "1"
    }

    /// Call once at launch, before any view reads `SessionStore`. The onboarding
    /// walkthrough (`UITEST_MOCK_FRESH`) starts signed out and signs in with the
    /// Google button (which skips Google's own sheet under the mock); every other
    /// run starts signed in to the demo account.
    @MainActor
    static func prepareSessionIfNeeded() {
        guard isEnabled else { return }
        SessionStore.shared.clear()
        if !FreshAccount.isEnabled {
            SessionStore.shared.signIn(demoSession(), method: "apple")
        }
    }

    @MainActor
    private static func demoSession() -> SessionResponse {
        let data = (try? JSONSerialization.data(withJSONObject: session)) ?? Data()
        // Force-unwrap is fine: this is a fixed DEBUG fixture shaped like the real one.
        return try! JSONDecoder().decode(SessionResponse.self, from: data)
    }

    nonisolated static var session: [String: Any] {
        [
            "accessToken": "demo-access-token", "expiresIn": 900, "user": user,
            "refreshToken": "demo-refresh-token", "refreshExpiresAt": iso(daysFromNow: 30),
        ] as [String: Any]
    }

    // MARK: - Routing

    /// `authorization` is the request's `Authorization` header: a starter call
    /// without one mints a guest session, as the real server does with guests on.
    nonisolated static func response(method: String, path: String, query: [String: String], body: Data? = nil, authorization: String? = nil) -> (Int, Any) {
        let parts = path.split(separator: "/").map(String.init)

        /// Matches `parts` against a route template like `"tokens/:/profile"`, where
        /// each `:` segment is a wildcard; returns the wildcard values in order.
        func match(_ verb: String, _ template: String) -> [String]? {
            guard verb == method else { return nil }
            let segments = template.split(separator: "/").map(String.init)
            guard segments.count == parts.count else { return nil }
            var captures: [String] = []
            for (segment, part) in zip(segments, parts) {
                if segment == ":" { captures.append(part) } else if segment != part { return nil }
            }
            return captures
        }

        // A brand-new account for the onboarding walkthrough: $10,000 cash, no
        // positions, and buys/sells that actually change the book.
        if FreshAccount.isEnabled {
            if match("POST", "paper/portfolios/starter") != nil {
                // Onboarding runs as a guest: no token in, a guest token out.
                let mintsGuest = authorization == nil
                let guestToken: Any = mintsGuest ? "demo-guest-token" as Any : NSNull()
                let guestExpiry: Any = mintsGuest ? iso(daysFromNow: 7) as Any : NSNull()
                return (200, [
                    "portfolio": FreshAccount.portfolio(), "created": true,
                    "guestToken": guestToken, "guestTokenExpiresAt": guestExpiry,
                ] as [String: Any])
            }
            // Signing in after onboarding claims the guest's book, so its positions
            // carry over (the mock keeps one book for the whole run).
            if match("POST", "paper/portfolios/claim") != nil {
                return (200, ["claimed": [FreshAccount.portfolio()], "skipped": [] as [Any]] as [String: Any])
            }
            if match("GET", "paper/portfolios/:") != nil { return (200, FreshAccount.snapshot()) }
            if match("GET", "paper/portfolios/:/trades") != nil { return (200, ["trades": [] as [Any]] as [String: Any]) }
            if match("POST", "paper/portfolios/:/trades") != nil { return FreshAccount.execute(body) }
        }

        // Sign-in: any Apple or Google token is accepted.
        if match("POST", "auth/google/nonce") != nil || match("POST", "auth/apple/nonce") != nil {
            return (200, ["nonce": "demo-nonce-\(Int(Date().timeIntervalSince1970))", "expiresAt": iso(daysFromNow: 0.01)])
        }
        if match("POST", "auth/google") != nil || match("POST", "auth/apple") != nil { return (200, MockProfile.signInSession()) }
        if match("POST", "auth/refresh") != nil { return (200, session) }
        if match("DELETE", "auth/account") != nil { return (204, [:] as [String: Any]) }

        if let leverage = MockLeverage.route(method: method, parts: parts, body: body) { return leverage }
        if let compete = MockCompete.route(method: method, parts: parts, body: body) { return compete }

        if match("POST", "paper/portfolios/starter") != nil {
            return (200, [
                "portfolio": portfolio,
                "created": false,
                "guestToken": "demo-guest-token",
                "guestTokenExpiresAt": iso(daysFromNow: 30),
            ] as [String: Any])
        }
        if match("POST", "paper/portfolios/claim") != nil {
            return (200, ["claimed": [portfolio], "skipped": [] as [Any]] as [String: Any])
        }
        if match("GET", "paper/portfolios/:") != nil { return (200, snapshot) }
        if match("GET", "paper/portfolios/:/trades") != nil { return (200, ["trades": sessionTrades + trades]) }
        if match("POST", "paper/portfolios/:/quote") != nil { return (200, quote(body)) }
        if match("POST", "paper/portfolios/:/trades") != nil { return (200, executeResponse(body)) }
        if match("POST", "paper/portfolios/:/reset") != nil { return (200, [:] as [String: Any]) }
        if match("GET", "paper/discover") != nil { return (200, discover) }
        if let c = match("GET", "paper/leaderboard/portfolios/:/positions") {
            return (200, traderPositions(portfolioId: c[0]))
        }
        if match("GET", "paper/leaderboard/monkey") != nil {
            return (200, monkeyStanding(window: query["window"] ?? "all"))
        }
        if match("GET", "paper/leaderboard") != nil {
            return (200, leaderboard(window: query["window"] ?? "all"))
        }
        if let c = match("GET", "paper/tokens/:/priceable") {
            let t = token(for: c[0])
            return (200, ["tokenMint": c[0], "priceable": true, "reason": NSNull(), "priceUsd": livePrice(t)] as [String: Any])
        }
        if let c = match("GET", "market/tokens/:/live") {
            return (200, MockMarket.live(mint: c[0], sinceSeq: query["sinceSeq"].flatMap { Int($0) }))
        }
        if match("GET", "tokens/search") != nil {
            let q = (query["q"] ?? "").lowercased()
            let hits = tokens.filter { q.isEmpty || $0.symbol.lowercased().contains(q) || $0.name.lowercased().contains(q) }
            let results: [[String: Any]] = hits.map { ["mint": $0.mint, "symbol": $0.symbol, "name": $0.name, "isVerified": $0.verified] }
            return (200, ["results": results])
        }
        if let c = match("GET", "tokens/:/profile") { return (200, profile(for: token(for: c[0]))) }
        if let c = match("GET", "tokens/:/candles") {
            return (200, candles(for: token(for: c[0]), interval: query["interval"] ?? "1h", limit: Int(query["limit"] ?? "") ?? 200))
        }
        if match("GET", "watchlist") != nil {
            return (200, ["items": [["mint": tokens[0].mint, "addedAt": iso(daysFromNow: -3)]]])
        }
        if let c = match("POST", "watchlist/:") {
            return (200, ["mint": c[0], "watching": true, "addedAt": iso(daysFromNow: 0)] as [String: Any])
        }
        if let c = match("DELETE", "watchlist/:") {
            return (200, ["mint": c[0], "watching": false, "addedAt": NSNull()] as [String: Any])
        }
        if match("GET", "social/alerts") != nil { return (200, ["alerts": MockAlerts.list()]) }
        if match("POST", "social/alerts") != nil { return MockAlerts.create(body) }
        if let c = match("PATCH", "social/alerts/:") { return MockAlerts.update(id: c[0], body: body) }
        if let c = match("DELETE", "social/alerts/:") { return MockAlerts.delete(id: c[0]) }
        // Share cards: public metadata pointing at a web page that unfurls the PNG.
        if let c = match("GET", "cards/meta/paper/position/:/:/:") {
            return (200, cardMeta(path: "paper/position/\(c[0])/\(c[1])/\(c[2])", headline: token(for: c[1]).symbol, returnPct: 22.48))
        }
        if let c = match("GET", "cards/meta/paper/portfolio/:/:") {
            return (200, cardMeta(path: "paper/portfolio/\(c[0])/\(c[1])", headline: "Paper Portfolio", returnPct: 12.49))
        }
        // Push devices: accepted and forgotten (screenshot runs never register one).
        if match("POST", "social/apns-tokens") != nil { return (201, ["ok": true]) }
        if match("POST", "social/apns-tokens/revoke") != nil { return (200, ["ok": true]) }
        // Server-validated subscriptions: the demo account has no server-side
        // entitlement, so the paywall stays a StoreKit (or UITEST_BYPASS_PAYWALL)
        // decision exactly as before.
        if match("GET", "billing/apple/entitlement") != nil { return (200, ["entitlement": MockAlerts.inactiveEntitlement]) }
        if match("POST", "billing/apple/transactions") != nil { return (200, ["entitlement": MockAlerts.inactiveEntitlement]) }
        if match("GET", "auth/me") != nil { return (200, ["user": user]) }
        if match("PATCH", "auth/me") != nil { return MockProfile.update(body) }
        if match("GET", "auth/username-available") != nil {
            return (200, MockProfile.availability(query["username"] ?? ""))
        }
        if match("POST", "auth/logout") != nil { return (200, [:] as [String: Any]) }
        return (404, ["error": "not_found", "message": "No demo fixture for \(method) \(path)."])
    }

    // MARK: - Tokens

    nonisolated struct DemoToken: Sendable {
        let mint: String
        let symbol: String
        let name: String
        let price: String
        let change: String
        let volume: String
        let marketCap: String
        let liquidity: String
        let verified: Bool
    }

    static let tokens: [DemoToken] = [
        DemoToken(mint: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263", symbol: "BONK", name: "Bonk", price: "0.00002314", change: "12.48", volume: "48210334.12", marketCap: "1712004332.55", liquidity: "9120443.10", verified: true),
        DemoToken(mint: "EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm", symbol: "WIF", name: "dogwifhat", price: "1.8342", change: "-4.12", volume: "92133012.40", marketCap: "1831920004.00", liquidity: "22014330.00", verified: true),
        DemoToken(mint: "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN", symbol: "JUP", name: "Jupiter", price: "0.8121", change: "3.07", volume: "61230044.00", marketCap: "1096320000.00", liquidity: "18402200.00", verified: true),
        DemoToken(mint: "7GCihgDB8fe6KNjn2MYtkzZcRjQy3t9GHdC8uHYmW2hr", symbol: "POPCAT", name: "Popcat", price: "0.4412", change: "27.91", volume: "30921477.80", marketCap: "432380112.00", liquidity: "6120300.00", verified: false),
        DemoToken(mint: "HZ1JovNiVvGrGNiiYvEozEVgZ58xaU3RKwX8eACQBCt3", symbol: "PYTH", name: "Pyth Network", price: "0.3310", change: "-1.62", volume: "21044020.00", marketCap: "1204112000.00", liquidity: "9820100.00", verified: true),
        DemoToken(mint: "MEW1gQWJ3nEXg2qgERiKu7FAFj79PHvQVREQUzScPP5", symbol: "MEW", name: "cat in a dogs world", price: "0.004821", change: "8.33", volume: "12002011.00", marketCap: "428112000.00", liquidity: "3320100.00", verified: false),
        DemoToken(mint: "ukHH6c7mMyiWCf1b9pnWe25TSpkDDt3H5pQZgZ74J82", symbol: "BOME", name: "BOOK OF MEME", price: "0.006912", change: "-9.40", volume: "18422100.00", marketCap: "476330000.00", liquidity: "4410200.00", verified: false),
        DemoToken(mint: "A8C3xuqscfmyLrte3VmTqrAq8kgMASius9AFNANwpump", symbol: "FWOG", name: "Fwog", price: "0.1204", change: "41.20", volume: "8120330.00", marketCap: "117402000.00", liquidity: "1920300.00", verified: false),
    ]

    /// Real logos for the demo tokens (CoinGecko's CDN), keyed by mint.
    static let logos: [String: String] = [
        "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263": "https://coin-images.coingecko.com/coins/images/28600/large/bonk.jpg",
        "EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm": "https://coin-images.coingecko.com/coins/images/33566/large/dogwifhat.jpg",
        "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN": "https://coin-images.coingecko.com/coins/images/34188/large/jup.png",
        "7GCihgDB8fe6KNjn2MYtkzZcRjQy3t9GHdC8uHYmW2hr": "https://coin-images.coingecko.com/coins/images/33760/large/image.jpg",
        "HZ1JovNiVvGrGNiiYvEozEVgZ58xaU3RKwX8eACQBCt3": "https://coin-images.coingecko.com/coins/images/31924/large/pyth.png",
        "MEW1gQWJ3nEXg2qgERiKu7FAFj79PHvQVREQUzScPP5": "https://coin-images.coingecko.com/coins/images/36440/large/MEW.png",
        "ukHH6c7mMyiWCf1b9pnWe25TSpkDDt3H5pQZgZ74J82": "https://coin-images.coingecko.com/coins/images/36071/large/bome.png",
        "A8C3xuqscfmyLrte3VmTqrAq8kgMASius9AFNANwpump": "https://coin-images.coingecko.com/coins/images/39453/large/fwog.png",
    ]

    static func logoURL(mint: String) -> URL? {
        logos[mint].flatMap(URL.init(string:))
    }

    /// DEBUG stand-in for a streaming feed: the demo price wandering around its
    /// base, so the live chart has something to draw in screenshot runs.
    static func livePrice(_ t: DemoToken, at date: Date = Date()) -> String {
        dec(livePriceValue(t, at: date))
    }

    static func livePriceValue(_ t: DemoToken, at date: Date) -> Double {
        let base = Double(t.price) ?? 1
        let seed = Double(t.symbol.unicodeScalars.reduce(0) { $0 + Int($1.value) })
        let x = date.timeIntervalSince1970
        let wobble = 0.006 * sin(x / 4.3 + seed) + 0.004 * sin(x / 1.7 + seed * 2) + 0.0025 * sin(x * 1.9 + seed)
        return base * (1 + wobble)
    }

    static func token(for mint: String) -> DemoToken {
        tokens.first { $0.mint == mint } ?? tokens[0]
    }

    private static func identity(_ t: DemoToken) -> [String: Any] {
        ["mint": t.mint, "symbol": t.symbol, "name": t.name, "hasLogo": false, "isVerified": t.verified]
    }

    private static func profile(for t: DemoToken) -> [String: Any] {
        func fig(_ v: String) -> [String: Any] { ["value": v, "unavailable": NSNull()] }
        return [
            "token": ["mint": t.mint, "symbol": t.symbol, "name": t.name, "logoUri": NSNull(), "isVerified": t.verified] as [String: Any],
            "market": [
                "priceUsd": fig(t.price),
                "change24h": fig(t.change),
                "marketCapUsd": fig(t.marketCap),
                "volume24hUsd": fig(t.volume),
                "liquidityUsd": fig(t.liquidity),
            ],
        ]
    }

    private static func candles(for t: DemoToken, interval: String, limit: Int) -> [String: Any] {
        let step: TimeInterval = switch interval {
        case "1m": 60
        case "5m": 300
        case "15m": 900
        case "30m": 1800
        case "4h": 14400
        case "1d": 86400
        default: 3600
        }
        let count = min(max(limit, 20), 120)
        let last = Double(t.price) ?? 1
        let seed = Double(t.symbol.unicodeScalars.reduce(0) { $0 + Int($1.value) })
        let now = (Date().timeIntervalSince1970 / step).rounded(.down) * step
        var rows: [[String: Any]] = []
        // A deterministic wavy random-walk that ends exactly at the token's price.
        for i in 0..<count {
            if interval == "1m" {
                // The 1-minute series follows the same path as the live price, so the
                // LIVE chart's seed joins the live points without a jump.
                let start = Date(timeIntervalSince1970: now - Double(count - 1 - i) * step)
                let close = livePriceValue(t, at: start.addingTimeInterval(step))
                let open = livePriceValue(t, at: start)
                rows.append([
                    "bucketStart": isoFormatter.string(from: start),
                    "open": dec(open), "high": dec(max(open, close) * 1.001), "low": dec(min(open, close) * 0.999),
                    "close": dec(close), "volume": dec(50_000),
                ])
                continue
            }
            let x = Double(i) + seed
            let drift = 1 + 0.18 * (Double(i) - Double(count)) / Double(count)
            let wave = 1 + 0.05 * sin(x / 5) + 0.025 * sin(x / 1.7)
            let close = last * drift * wave
            let open = close * (1 + 0.012 * sin(x * 2.3))
            let high = max(open, close) * (1 + 0.008 + 0.006 * abs(sin(x * 3.1)))
            let low = min(open, close) * (1 - 0.008 - 0.006 * abs(cos(x * 2.7)))
            let start = Date(timeIntervalSince1970: now - Double(count - 1 - i) * step)
            rows.append([
                "bucketStart": isoFormatter.string(from: start),
                "open": dec(open), "high": dec(high), "low": dec(low), "close": dec(close),
                "volume": dec(50_000 + 40_000 * abs(sin(x * 0.9))),
            ])
        }
        return ["mint": t.mint, "interval": interval, "source": "relayed", "denomination": "usd", "candles": rows]
    }

    // MARK: - Discover

    private static var discover: [String: Any] {
        func entries(_ order: [Int]) -> [[String: Any]] {
            order.enumerated().map { rank, index -> [String: Any] in
                let t = tokens[index]
                return [
                    "mint": t.mint, "symbol": t.symbol, "name": t.name, "logoUri": NSNull(),
                    "isVerified": t.verified,
                    "paperTradeable": ["tradeable": true, "priceUsd": t.price, "liquidityUsd": t.liquidity] as [String: Any],
                    "metrics": ["volumeUsd": t.volume, "marketCapUsd": t.marketCap, "priceChangePct": t.change],
                    "rank": rank + 1,
                ]
            }
        }
        func block(_ feed: String, _ order: [Int]) -> [String: Any] {
            ["feed": feed, "entries": entries(order), "page": ["nextCursor": NSNull(), "hasMore": false] as [String: Any]]
        }
        return ["feeds": [
            block("most_active", [1, 2, 0, 3, 4, 6, 5, 7]),
            block("biggest_movers", [7, 3, 0, 5, 2, 4, 1, 6]),
            block("newest", [7, 5, 6, 3, 0, 1, 2, 4]),
            block("popular", [0, 1, 2, 3, 4, 5, 6, 7]),
            block("most_held", [0, 1, 3, 2, 4, 5, 6, 7]),
        ]]
    }

    // MARK: - Portfolio

    static let portfolioId = "demo-portfolio"

    private static var portfolio: [String: Any] {
        [
            "id": portfolioId, "name": "Paper Portfolio", "startingBalanceUsd": "10000",
            "cashUsd": "5612.37", "createdAt": iso(daysFromNow: -12), "resetAt": NSNull(),
            "resetCount": 0, "archivedAt": NSNull(), "isGuest": false,
        ]
    }

    private static var snapshot: [String: Any] {
        func position(_ t: DemoToken, qty: String, cost: String, avg: String, value: String, pnl: String, pct: String) -> [String: Any] {
            [
                "tokenMint": t.mint, "qty": qty, "costUsd": cost, "avgCostUsd": avg,
                "markPriceUsd": t.price, "markState": "fresh", "markFromLastFill": false,
                "valueUsd": value, "unrealizedPnlUsd": pnl, "unrealizedReturnPct": pct,
                "roundTripCount": 1, "token": identity(t),
                "marketCapUsd": t.marketCap, "liquidityUsd": t.liquidity,
            ]
        }
        func roundTrip(_ t: DemoToken, id: String, cost: String, proceeds: String, pnl: String, pct: String, daysAgo: Double) -> [String: Any] {
            [
                "tokenMint": t.mint, "qty": "1000", "costUsd": cost, "proceedsUsd": proceeds,
                "realizedPnlUsd": pnl, "returnPct": pct,
                "openedAt": iso(daysFromNow: -daysAgo - 1), "closedAt": iso(daysFromNow: -daysAgo),
                "closingTradeId": id, "token": identity(t),
            ]
        }
        func pct(_ v: String, n: Int) -> [String: Any] {
            ["pct": v, "sampleSize": n, "sampleOf": "round_trips", "unavailable": NSNull()]
        }
        func usd(_ v: String, n: Int) -> [String: Any] {
            ["usd": v, "sampleSize": n, "sampleOf": "positions", "unavailable": NSNull()]
        }
        var points: [[String: Any]] = []
        for i in 0..<30 {
            let equity = 10_000 + Double(i) * 42 + 180 * sin(Double(i) / 3)
            points.append(["at": iso(daysFromNow: Double(i - 29) * 0.4), "equityUsd": dec(equity), "kind": i == 0 ? "start" : "mark"])
        }
        // Cash already excludes the margin locked in leveraged positions.
        let lev = MockLeverage.totals
        let totalEquity = 5612.37 + 4836.54 + lev.value
        points.append(["at": iso(daysFromNow: 0), "equityUsd": String(format: "%.2f", totalEquity), "kind": "mark"])
        return [
            "portfolio": portfolio, "portfolioId": portfolioId,
            "cashUsd": "5612.37", "positionsValueUsd": "4836.54", "equityUsd": String(format: "%.2f", totalEquity),
            "leveragedPositions": MockLeverage.openPositions,
            "leveragedRoundTrips": MockLeverage.roundTrips,
            "leveragedValueUsd": String(format: "%.2f", lev.value),
            "lockedMarginUsd": String(format: "%.2f", lev.margin),
            "positions": [
                position(tokens[0], qty: "92000000", cost: "1650.00", avg: "0.00001793", value: "2128.88", pnl: "478.88", pct: "29.02"),
                position(tokens[1], qty: "820", cost: "1612.50", avg: "1.9665", value: "1504.04", pnl: "-108.46", pct: "-6.73"),
                position(tokens[3], qty: "2728", cost: "1010.00", avg: "0.3702", value: "1203.62", pnl: "193.62", pct: "19.17"),
            ],
            "roundTrips": [
                roundTrip(tokens[2], id: "rt-1", cost: "500.00", proceeds: "612.40", pnl: "112.40", pct: "22.48", daysAgo: 2),
                roundTrip(tokens[6], id: "rt-2", cost: "400.00", proceeds: "331.20", pnl: "-68.80", pct: "-17.20", daysAgo: 5),
                roundTrip(tokens[7], id: "rt-3", cost: "250.00", proceeds: "498.10", pnl: "248.10", pct: "99.24", daysAgo: 8),
            ],
            "stats": [
                "returnPct": pct("12.49", n: 3), "winRatePct": pct("66.67", n: 3),
                "maxDrawdownPct": pct("4.81", n: 3),
                "realizedPnlUsd": usd("291.70", n: 3), "unrealizedPnlUsd": usd(String(format: "%.2f", 564.04 + lev.unrealized), n: 5),
                "feesPaidUsd": "18.42", "tradeCount": 9, "roundTripCount": 3, "winCount": 2, "lossCount": 1,
            ] as [String: Any],
            "equityCurve": ["maxDrawdownPct": "4.81", "peakEquityUsd": "11302.10", "points": points] as [String: Any],
        ]
    }

    private static var trades: [[String: Any]] {
        [
            trade(id: "t-3", tokens[3], side: "buy", qty: "2728", price: "0.3702", value: "1010.00", daysAgo: 0.5),
            trade(id: "t-2", tokens[1], side: "buy", qty: "820", price: "1.9665", value: "1612.50", daysAgo: 1.5),
            trade(id: "t-1", tokens[0], side: "buy", qty: "92000000", price: "0.00001793", value: "1650.00", daysAgo: 3),
        ]
    }

    private static func trade(id: String, _ t: DemoToken, side: String, qty: String, price: String, value: String, daysAgo: Double) -> [String: Any] {
        [
            "id": id, "tokenMint": t.mint, "side": side, "qty": qty, "priceUsd": price, "valueUsd": value,
            "slippageBps": 42, "priceImpactBps": 11, "marketCapUsd": t.marketCap, "executedAt": iso(daysFromNow: -daysAgo),
        ]
    }

    /// Buys at the demo token's live price for the requested dollars; sells use the
    /// demo position. Enough for walkthroughs to show the right coin and amounts.
    private static func order(_ body: Data?) -> (t: DemoToken, side: String, price: Double, qty: Double, value: Double) {
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let t = token(for: json["tokenMint"] as? String ?? tokens[0].mint)
        let side = json["side"] as? String ?? "buy"
        let mid = livePriceValue(t, at: Date())
        let price = side == "buy" ? mid * 1.0042 : mid * 0.9958 // 30 bps slippage + a little impact
        let notional = Double(json["notionalUsd"] as? String ?? "") ?? 250
        let value = side == "buy" ? notional : 1504.04 * Double(json["sellPercent"] as? Int ?? 100) / 100
        return (t, side, price, value / price, value)
    }

    private static func quote(_ body: Data?) -> [String: Any] {
        let o = order(body)
        return [
            "tokenMint": o.t.mint, "side": o.side, "inAmount": dec(o.value), "outAmount": dec(o.qty),
            "minimumOut": dec(o.qty * 0.99), "priceImpactPct": "0.12", "priceUsd": dec(o.price),
            "guidance": [
                "isFirstTradeInPortfolio": false, "tradeCountInPortfolio": 9,
                "suggestedNotionalUsd": "561.24", "suggestedPctOfCash": 10, "warnings": [] as [Any],
            ] as [String: Any],
        ]
    }

    /// Fills made during this run, newest first, so the chart can mark them.
    private static let sessionLock = NSLock()
    nonisolated(unsafe) private static var sessionFills: [[String: Any]] = []
    private static var sessionTrades: [[String: Any]] {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return sessionFills
    }

    private static func executeResponse(_ body: Data?) -> [String: Any] {
        let o = order(body)
        let cashAfter = o.side == "buy" ? 5612.37 - o.value : 5612.37 + o.value
        let filled = trade(id: "t-new-\(Int(Date().timeIntervalSince1970 * 1000))", o.t, side: o.side, qty: dec(o.qty), price: dec(o.price), value: String(format: "%.2f", o.value), daysAgo: 0)
        sessionLock.lock()
        sessionFills.insert(filled, at: 0)
        sessionLock.unlock()
        return [
            "trade": filled,
            "cashUsd": String(format: "%.2f", cashAfter),
            "fill": ["fillPriceUsd": dec(o.price), "marketPriceUsd": dec(o.price / 1.0042)],
            "summary": [
                "side": o.side, "slippageCostUsd": String(format: "%.2f", o.value * 0.0042), "cashAfterUsd": String(format: "%.2f", cashAfter),
                "vsQuote": ["expectedPriceUsd": dec(o.price), "fillPriceUsd": dec(o.price), "deltaBps": 0, "direction": "flat"] as [String: Any],
            ] as [String: Any],
        ]
    }

    // MARK: - Leaderboard

    private static func leaderboard(window: String) -> [String: Any] {
        let names = ["degenwizard", "solsniper", "paperhands", "moonboi", "rugsurvivor", "chartooor", "the_monkey", "bagholder", "wenlambo", "gmgn", "cookedcat", "fomo_fren", "diamondpaws"]
        let returns = ["184.21", "122.40", "97.12", "74.55", "61.02", "48.90", "38.20", "33.14", "21.70", "12.49", "4.02", "-3.88", "-12.40"]
        let entries: [[String: Any]] = names.enumerated().map { i, name in
            leaderboardEntry(rank: i + 1, username: name, returnPct: returns[i], roundTrips: 24 - i)
        }
        return [
            "window": window, "season": "2026-09", "entries": entries,
            "rankedCount": entries.count, "emergingCount": 4, "computedAt": iso(daysFromNow: 0),
        ]
    }

    private static func leaderboardEntry(rank: Int, username: String, returnPct: String, roundTrips: Int) -> [String: Any] {
        [
            "rank": rank, "portfolioId": "lb-\(rank)", "username": username, "provenance": "PAPER · SIMULATED",
            "returnPct": ["pct": returnPct, "sampleSize": roundTrips, "sampleOf": "round_trips", "unavailable": NSNull()] as [String: Any],
            "roundTripCount": roundTrips, "resetCount": rank % 3 == 0 ? 1 : 0, "createdAt": iso(daysFromNow: -20),
            "isBot": username == "the_monkey",
        ]
    }

    private static func traderPositions(portfolioId: String) -> [String: Any] {
        let held = Array(tokens.prefix(3))
        let shares = ["41.5", "22.0", "9.5"]
        let returns = ["12.3", "-4.1", "31.0"]
        return [
            "entry": leaderboardEntry(rank: 1, username: "degenwizard", returnPct: "184.21", roundTrips: 24),
            "positions": held.enumerated().map { i, t in
                ["tokenMint": t.mint, "symbol": t.symbol, "name": t.name, "sharePct": shares[i], "unrealizedReturnPct": returns[i]] as [String: Any]
            },
            "cashSharePct": "27.0", "sampleSize": held.count, "computedAt": iso(daysFromNow: 0),
        ]
    }

    /// Six of the twelve demo traders are above the monkey's 38.2%.
    private static func monkeyStanding(window: String) -> [String: Any] {
        [
            "window": window, "season": "2026-10",
            "monkey": leaderboardEntry(rank: 7, username: "the_monkey", returnPct: "38.20", roundTrips: 18),
            "sampleSize": 12, "beatingMonkey": 6, "beatingPct": "50.0", "computedAt": iso(daysFromNow: 0),
        ]
    }

    // MARK: - Alerts & account

    /// The demo account's starting alert rules (see `MockAlerts`, which owns them
    /// once the run starts).
    static var seedAlerts: [[String: Any]] {
        [
            ["id": "a-1", "name": "BONK breakout", "rule": ["kind": "price_crossed", "mint": tokens[0].mint, "direction": "above", "priceUsd": "0.000025"],
             "channel": "push", "isActive": true, "cooldownSeconds": 300, "lastFiredAt": NSNull(), "createdAt": iso(daysFromNow: -2)],
            ["id": "a-2", "name": "WIF dip buy", "rule": ["kind": "price_crossed", "mint": tokens[1].mint, "direction": "below", "priceUsd": "1.60"],
             "channel": "push", "isActive": true, "cooldownSeconds": 300, "lastFiredAt": iso(daysFromNow: -1), "createdAt": iso(daysFromNow: -6)],
            ["id": "a-3", "name": "Whale watch", "rule": ["kind": "wallet_trades"],
             "channel": "in_app", "isActive": false, "cooldownSeconds": 600, "lastFiredAt": NSNull(), "createdAt": iso(daysFromNow: -9)],
        ]
    }

    private static func cardMeta(path: String, headline: String, returnPct: Double) -> [String: Any] {
        [
            "payload": ["returnPct": returnPct, "sampleSize": 3, "window": "all", "verifiedFrom": iso(daysFromNow: -12)] as [String: Any],
            "model": [
                "provenance": "paper", "username": MockProfile.current().0, "headline": headline,
                "headlineKind": path.hasPrefix("paper/position") ? "token" : "portfolio",
                "returnPct": returnPct, "sampleSize": 3, "sampleUnit": "round trips",
                "windowLabel": "All time", "coverageLabel": "Since \(iso(daysFromNow: -12))", "secondary": [] as [Any],
            ] as [String: Any],
            "imageUrl": "https://api.cooked.trade/cards/png/\(path)",
            "pageUrl": "https://cooked.trade/s/\(path)",
            "width": 1200, "height": 630,
        ]
    }

    static var user: [String: Any] {
        let (username, displayName) = MockProfile.current()
        return [
            "id": "demo-user", "username": username, "displayName": displayName.map { $0 as Any } ?? NSNull(),
            "walletAddress": NSNull(), "foundingMember": true, "avatarSeed": "demo-user-seed",
            "createdAt": iso(daysFromNow: -41), "verified": false, "referralCode": "PAPERHANDS",
        ] as [String: Any]
    }

    // MARK: - Helpers

    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()

    private static func iso(daysFromNow days: Double) -> String {
        isoFormatter.string(from: Date().addingTimeInterval(days * 86400))
    }

    /// Decimal-string formatting for generated numbers, enough significant digits for
    /// sub-cent memecoin prices.
    private static func dec(_ value: Double) -> String {
        String(format: "%.10g", value)
    }
}

/// Answers every request made through a session whose configuration lists it in
/// `protocolClasses`, from `MockAPI`'s fixtures. `nonisolated` for the same reason as
/// the UI test class: the project's default MainActor isolation would otherwise
/// clash with `URLProtocol`'s nonisolated overrides.
nonisolated final class MockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        var query: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            query[item.name] = item.value
        }
        let (status, body) = MockAPI.response(
            method: request.httpMethod ?? "GET",
            path: url.path,
            query: query,
            body: request.httpBody ?? request.httpBodyStream.map(Self.readAll),
            authorization: request.value(forHTTPHeaderField: "Authorization")
        )
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession hands a protocol its body as a stream, not `httpBody`.
    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// `UITEST_MOCK_FRESH=1`: a stateful brand-new paper account. Marks drift gently
/// with time so the walkthrough's position charts have a shape — this is the
/// DEBUG screenshot fixture only; the real app only ever shows server prices.
nonisolated enum FreshAccount {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["UITEST_MOCK_FRESH"] == "1"
    }

    private struct Holding {
        let mint: String
        var qty: Double
        var cost: Double
        let openedAt: Date
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cash: Double = 10_000
    nonisolated(unsafe) private static var holdings: [Holding] = []

    private static func mark(_ token: MockAPI.DemoToken) -> Double {
        let base = Double(token.price) ?? 1
        let seed = Double(token.symbol.unicodeScalars.reduce(0) { $0 + Int($1.value) })
        let t = Date().timeIntervalSince1970
        return base * (1 + 0.012 * sin(t / 4 + seed) + 0.006 * sin(t / 1.7 + seed))
    }

    private static func dec(_ value: Double) -> String { String(format: "%.10g", value) }

    static func portfolio() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return portfolioLocked()
    }

    private static func portfolioLocked() -> [String: Any] {
        [
            "id": MockAPI.portfolioId, "name": "Paper Portfolio", "startingBalanceUsd": "10000",
            "cashUsd": dec(cash), "createdAt": MockISO.string(Date()), "resetAt": NSNull(),
            "resetCount": 0, "archivedAt": NSNull(), "isGuest": false,
        ]
    }

    static func snapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        var positionsValue = 0.0
        var unrealized = 0.0
        let positions: [[String: Any]] = holdings.map { holding in
            let token = MockAPI.token(for: holding.mint)
            let price = mark(token)
            let value = holding.qty * price
            positionsValue += value
            unrealized += value - holding.cost
            let identity: [String: Any] = ["mint": token.mint, "symbol": token.symbol, "name": token.name, "hasLogo": false, "isVerified": token.verified]
            return [
                "tokenMint": holding.mint, "qty": dec(holding.qty), "costUsd": dec(holding.cost),
                "avgCostUsd": dec(holding.cost / holding.qty), "markPriceUsd": dec(price), "markState": "fresh",
                "markFromLastFill": false, "valueUsd": dec(value), "unrealizedPnlUsd": dec(value - holding.cost),
                "unrealizedReturnPct": dec((value - holding.cost) / holding.cost * 100), "roundTripCount": 0,
                "token": identity, "marketCapUsd": token.marketCap, "liquidityUsd": token.liquidity,
            ]
        }
        let equity = cash + positionsValue
        func measured(_ key: String, _ value: String?) -> [String: Any] {
            let reading: Any = value.map { $0 as Any } ?? NSNull()
            let unavailable: Any = value == nil ? "no_round_trips" as Any : NSNull()
            return [key: reading, "sampleSize": 0, "sampleOf": "round_trips", "unavailable": unavailable]
        }
        return [
            "portfolio": portfolioLocked(), "portfolioId": MockAPI.portfolioId,
            "cashUsd": dec(cash), "positionsValueUsd": dec(positionsValue), "equityUsd": dec(equity),
            "positions": positions, "roundTrips": [] as [Any],
            "stats": [
                "returnPct": measured("pct", dec((equity - 10_000) / 100)),
                "winRatePct": measured("pct", nil), "maxDrawdownPct": measured("pct", nil),
                "realizedPnlUsd": measured("usd", "0"), "unrealizedPnlUsd": measured("usd", dec(unrealized)),
                "feesPaidUsd": "0", "tradeCount": holdings.count, "roundTripCount": 0, "winCount": 0, "lossCount": 0,
            ] as [String: Any],
            "equityCurve": [
                "maxDrawdownPct": "0", "peakEquityUsd": dec(max(equity, 10_000)),
                "points": [
                    ["at": MockISO.string(Date().addingTimeInterval(-60)), "equityUsd": "10000", "kind": "start"],
                    ["at": MockISO.string(Date()), "equityUsd": dec(equity), "kind": "mark"],
                ],
            ] as [String: Any],
        ]
    }

    static func execute(_ body: Data?) -> (Int, Any) {
        guard let body,
              let request = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let mint = request["tokenMint"] as? String,
              let side = request["side"] as? String else {
            return (400, ["error": "bad_request", "message": "Malformed order."])
        }
        lock.lock(); defer { lock.unlock() }
        let token = MockAPI.token(for: mint)
        let price = mark(token)
        var qty = 0.0
        var value = 0.0

        if side == "buy" {
            let notional = Double(request["notionalUsd"] as? String ?? "") ?? 0
            guard notional > 0, notional <= cash else {
                return (422, ["error": "insufficient_cash", "message": "Not enough paper cash for that order."])
            }
            qty = notional / price
            value = notional
            cash -= notional
            if let index = holdings.firstIndex(where: { $0.mint == mint }) {
                holdings[index].qty += qty
                holdings[index].cost += notional
            } else {
                holdings.append(Holding(mint: mint, qty: qty, cost: notional, openedAt: Date()))
            }
        } else {
            guard let index = holdings.firstIndex(where: { $0.mint == mint }) else {
                return (422, ["error": "no_position", "message": "You don't hold this token."])
            }
            let percent = Double(request["sellPercent"] as? Int ?? 100) / 100
            qty = holdings[index].qty * percent
            value = qty * price
            cash += value
            holdings[index].cost *= (1 - percent)
            holdings[index].qty -= qty
            if holdings[index].qty <= 0.000_000_1 { holdings.remove(at: index) }
        }

        let trade: [String: Any] = [
            "id": UUID().uuidString, "tokenMint": mint, "side": side, "qty": dec(qty), "priceUsd": dec(price),
            "valueUsd": dec(value), "slippageBps": 0, "priceImpactBps": 0, "marketCapUsd": token.marketCap,
            "executedAt": MockISO.string(Date()),
        ]
        return (200, [
            "trade": trade, "cashUsd": dec(cash),
            "fill": ["fillPriceUsd": dec(price), "marketPriceUsd": dec(price)],
            "summary": ["side": side, "slippageCostUsd": "0", "cashAfterUsd": dec(cash), "vsQuote": NSNull()] as [String: Any],
        ] as [String: Any])
    }
}

/// The demo account's editable profile, for `GET`/`PATCH /auth/me` and the
/// username check. The onboarding walkthrough (`UITEST_MOCK_FRESH`) signs in as a
/// brand-new account with a generated handle, and its first sign-in of the run
/// says `isNewAccount: true` so the screenshots cover `ProfileSetupView`; every
/// other run starts signed in and never sees it.
nonisolated enum MockProfile {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var username = FreshAccount.isEnabled ? "trader_4f7c2a91" : "paperhands"
    nonisolated(unsafe) private static var displayName: String? = "Paper Hands"
    nonisolated(unsafe) private static var signInCount = 0

    /// Handles the mock server treats as someone else's, so the red state can be seen.
    private static let taken: Set<String> = ["satoshi", "paperhands", "diamondhands", "cooked"]
    private static let reserved: Set<String> = ["admin", "support", "cooked_team", "moderator"]

    static func current() -> (String, String?) {
        lock.lock(); defer { lock.unlock() }
        return (username, displayName)
    }

    static func signInSession() -> [String: Any] {
        lock.lock()
        signInCount += 1
        let isNew = signInCount == 1 && FreshAccount.isEnabled
        lock.unlock()
        var session = MockAPI.session
        session["isNewAccount"] = isNew
        return session
    }

    static func availability(_ candidate: String) -> [String: Any] {
        let lowered = candidate.lowercased()
        let (mine, _) = current()
        if let problem = UsernameRulesMock.problem(candidate) {
            return ["available": false, "reason": "invalid", "message": problem]
        }
        if reserved.contains(lowered) {
            return ["available": false, "reason": "reserved", "message": "That username is reserved."]
        }
        if taken.contains(lowered) && lowered != mine.lowercased() {
            return ["available": false, "reason": "taken", "message": "That username is taken."]
        }
        return ["available": true, "reason": NSNull(), "message": NSNull()] as [String: Any]
    }

    static func update(_ body: Data?) -> (Int, Any) {
        guard let body, let request = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return (400, ["error": "bad_request", "message": "Malformed profile update."])
        }
        if let candidate = request["username"] as? String {
            let check = availability(candidate)
            if check["available"] as? Bool != true {
                let reason = check["reason"] as? String == "taken" ? "username_taken" : "username_invalid"
                return (409, ["error": reason, "reason": reason, "message": check["message"] as? String ?? "That username isn't available."])
            }
            lock.lock(); username = candidate; lock.unlock()
        }
        if request.keys.contains("displayName") {
            let name = (request["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            lock.lock(); displayName = (name?.isEmpty ?? true) ? nil : name; lock.unlock()
        }
        return (200, ["user": MockAPI.user])
    }
}

/// The server's handle rules, restated for the mock (the app's `UsernameRules` is
/// MainActor-isolated by the project default; this runs on URLSession's queue).
nonisolated enum UsernameRulesMock {
    static func problem(_ candidate: String) -> String? {
        if candidate.count < 4 { return "Usernames need at least 4 characters." }
        if candidate.count > 24 { return "Usernames can be at most 24 characters." }
        let ok = candidate.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_") }
        return ok ? nil : "Usernames can only use letters, numbers and _."
    }
}

/// `/social/alerts` as a tiny stateful store, so creating, pausing and deleting an
/// alert in a screenshot run shows up in the lists afterwards.
nonisolated enum MockAlerts {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var alerts: [[String: Any]]?

    static var inactiveEntitlement: [String: Any] {
        ["active": false, "productId": NSNull(), "expiresAt": NSNull(), "willRenew": NSNull(), "environment": NSNull()] as [String: Any]
    }

    static func list() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return current()
    }

    static func create(_ body: Data?) -> (Int, Any) {
        guard let body,
              let request = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let name = request["name"] as? String,
              let rule = request["rule"] as? [String: Any] else {
            return (400, ["error": "bad_request", "message": "Malformed alert."])
        }
        let alert: [String: Any] = [
            "id": UUID().uuidString.lowercased(), "name": name, "rule": rule,
            "channel": request["channel"] as? String ?? "push", "isActive": true,
            "cooldownSeconds": request["cooldownSeconds"] as? Int ?? 300,
            "lastFiredAt": NSNull(), "createdAt": MockISO.string(Date()),
        ]
        lock.lock(); defer { lock.unlock() }
        var all = current()
        all.insert(alert, at: 0)
        alerts = all
        return (201, ["alert": alert])
    }

    static func update(id: String, body: Data?) -> (Int, Any) {
        let request = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        lock.lock(); defer { lock.unlock() }
        var all = current()
        guard let index = all.firstIndex(where: { $0["id"] as? String == id }) else {
            return (404, ["error": "not_found", "message": "No such alert."])
        }
        if let isActive = request["isActive"] as? Bool { all[index]["isActive"] = isActive }
        if let name = request["name"] as? String { all[index]["name"] = name }
        alerts = all
        return (200, ["alert": all[index]])
    }

    static func delete(id: String) -> (Int, Any) {
        lock.lock(); defer { lock.unlock() }
        var all = current()
        guard let index = all.firstIndex(where: { $0["id"] as? String == id }) else {
            return (404, ["error": "not_found", "message": "No such alert."])
        }
        let removed = all.remove(at: index)
        alerts = all
        return (200, ["alert": removed])
    }

    /// Call with `lock` held.
    private static func current() -> [[String: Any]] {
        if let alerts { return alerts }
        let seeded = MockAPI.seedAlerts
        alerts = seeded
        return seeded
    }
}

nonisolated enum MockISO {
    nonisolated(unsafe) private static let formatter = ISO8601DateFormatter()
    static func string(_ date: Date) -> String { formatter.string(from: date) }
}
#endif
