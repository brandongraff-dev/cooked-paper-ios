#if DEBUG
import Foundation

/// DEBUG-only leverage fixtures for `MockAPI` (see that file for why the mock exists).
/// Quotes, opens and closes use the same arithmetic as the server —
/// isolated margin, 1% maintenance, 30 bps base slippage plus impact sized on the
/// full notional — against the demo token's price.
nonisolated enum MockLeverage {
    static let maintenance = 0.01
    static let baseSlippageBps = 30.0

    static func route(method: String, parts: [String], body: Data?) -> (Int, Any)? {
        // paper/leverage/config
        if method == "GET", parts == ["paper", "leverage", "config"] { return (200, config) }
        // paper/portfolios/:id/leverage/...
        guard parts.count >= 4, parts[0] == "paper", parts[1] == "portfolios", parts[3] == "leverage" else { return nil }
        let rest = Array(parts.dropFirst(4))
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        switch (method, rest.count) {
        case ("POST", 1) where rest[0] == "quote": return (200, quote(json))
        case ("POST", 1) where rest[0] == "positions": return (201, open(json))
        case ("GET", 1) where rest[0] == "positions": return (200, ["positions": openPositions])
        case ("POST", 3) where rest[0] == "positions" && rest[2] == "close": return (200, close(rest[1], json))
        default: return nil
        }
    }

    static var config: [String: Any] {
        [
            "leverageOptions": [2, 5, 10], "directions": ["long", "short"], "chains": ["solana"],
            "minMarginUsd": "10", "minLiquidityUsd": "100000", "maxNotionalLiquidityPct": "2",
            "maxOpenPositions": 20, "disclosure": disclosure,
        ] as [String: Any]
    }

    static var disclosure: [String: Any] {
        [
            "liquidationBasis": "sampled", "checkIntervalMs": 5000, "markSource": "live_mid",
            "maintenanceMarginBps": 100, "fundingModelled": false, "borrowModelled": false, "feesModelled": false,
        ] as [String: Any]
    }

    // MARK: - Math

    static func liquidationPrice(entry: Double, leverage: Double, long: Bool) -> Double {
        long ? entry * (1 - 1 / leverage) / (1 - maintenance) : entry * (1 + 1 / leverage) / (1 + maintenance)
    }

    static func fillPrice(mid: Double, notional: Double, liquidity: Double, buying: Bool) -> (price: Double, impactBps: Double) {
        let impact = min(2000, liquidity > 0 ? notional / (2 * liquidity) * 10_000 : 0)
        let bps = baseSlippageBps + impact
        return (buying ? mid * (1 + bps / 10_000) : mid * (1 - bps / 10_000), impact)
    }

    private static func dec(_ value: Double) -> String { String(format: "%.10g", value) }
    private static func usd(_ value: Double) -> String { String(format: "%.2f", value) }

    private static func quote(_ body: [String: Any]) -> [String: Any] {
        let mint = body["tokenMint"] as? String ?? MockAPI.tokens[0].mint
        let t = MockAPI.token(for: mint)
        let long = (body["direction"] as? String ?? "long") == "long"
        let leverage = Double(body["leverage"] as? Int ?? 5)
        let margin = Double(body["marginUsd"] as? String ?? "0") ?? 0
        let mid = Double(t.price) ?? 1
        let notional = margin * leverage
        let fill = fillPrice(mid: mid, notional: notional, liquidity: Double(t.liquidity) ?? 0, buying: long)
        let liq = liquidationPrice(entry: fill.price, leverage: leverage, long: long)
        let cash = 5612.37
        let eligible = margin >= 10 && margin <= cash
        return [
            "mode": "paper", "tokenMint": mint, "direction": long ? "long" : "short", "leverage": Int(leverage),
            "marginUsd": usd(margin), "notionalUsd": usd(notional), "qty": dec(notional / fill.price),
            "midPriceUsd": t.price, "estEntryPriceUsd": dec(fill.price), "priceAgeMs": 900,
            "slippageBps": Int(baseSlippageBps + fill.impactBps), "priceImpactPct": dec(fill.impactBps / 100),
            "liquidationPriceUsd": dec(liq), "bankruptcyPriceUsd": dec(long ? fill.price * (1 - 1 / leverage) : fill.price * (1 + 1 / leverage)),
            "liquidationMovePct": dec((liq / mid - 1) * 100), "maintenanceMarginBps": 100,
            "maxMarginUsd": usd(cash), "eligible": eligible,
            "ineligibleReason": eligible ? NSNull() as Any : (margin < 10 ? "below_min_margin" : "insufficient_cash") as Any,
            "fee": ["feeUsd": "0"], "requiresSignature": false, "disclosure": disclosure,
        ] as [String: Any]
    }

    private static func open(_ body: [String: Any]) -> [String: Any] {
        let q = quote(body)
        let mint = q["tokenMint"] as? String ?? ""
        let t = MockAPI.token(for: mint)
        let long = (q["direction"] as? String) == "long"
        let margin = Double(q["marginUsd"] as? String ?? "0") ?? 0
        let entry = Double(q["estEntryPriceUsd"] as? String ?? "1") ?? 1
        let position = position(
            id: "lev-new", t, long: long, leverage: q["leverage"] as? Int ?? 5,
            entry: entry, margin: margin, daysAgo: 0
        )
        return [
            "position": position,
            "fill": fill(kind: "open", qty: position["qty"] as? String ?? "0", price: entry, mid: Double(t.price) ?? entry, margin: margin, pnl: 0),
            "cashUsd": usd(5612.37 - margin), "equityUsd": "11291.37",
            "context": ["marketPriceUsd": t.price, "priceObservedAt": now, "priceAgeMs": 900, "priceSource": "jupiter"] as [String: Any],
        ] as [String: Any]
    }

    private static func close(_ id: String, _ body: [String: Any]) -> [String: Any] {
        let percent = Double(body["closePercent"] as? Int ?? 100) / 100
        let seed = seeds.first { $0.id == id } ?? seeds[0]
        let t = MockAPI.tokens[seed.token]
        let mid = Double(t.price) ?? seed.entry
        let qty = seed.margin * Double(seed.leverage) / seed.entry * percent
        let exit = fillPrice(mid: mid, notional: qty * mid, liquidity: Double(t.liquidity) ?? 0, buying: !seed.long).price
        let released = seed.margin * percent
        let pnl = max(-released, (seed.long ? 1.0 : -1.0) * qty * (exit - seed.entry))
        var position = position(id: seed.id, t, long: seed.long, leverage: seed.leverage, entry: seed.entry, margin: seed.margin * (1 - percent), daysAgo: seed.daysAgo)
        if percent >= 1 {
            position["status"] = "closed"
            position["closedAt"] = now
        }
        return [
            "position": position,
            "fill": fill(kind: "close", qty: dec(qty), price: exit, mid: mid, margin: released, pnl: pnl),
            "cashUsd": usd(5612.37 + released + pnl), "equityUsd": "11291.37",
            "context": ["marketPriceUsd": t.price, "priceObservedAt": now, "priceAgeMs": 900, "priceSource": "jupiter"] as [String: Any],
        ] as [String: Any]
    }

    // MARK: - Fixtures

    struct Seed: Sendable {
        let id: String
        let token: Int
        let long: Bool
        let leverage: Int
        let entry: Double
        let margin: Double
        let daysAgo: Double
    }

    /// Open positions on the demo portfolio: a 5x WIF long in profit, a 10x BONK short under water.
    static let seeds: [Seed] = [
        Seed(id: "lev-1", token: 1, long: true, leverage: 5, entry: 1.7450, margin: 500, daysAgo: 0.3),
        Seed(id: "lev-2", token: 0, long: false, leverage: 10, entry: 0.00002250, margin: 300, daysAgo: 0.1),
    ]

    static var openPositions: [[String: Any]] {
        seeds.map { s in
            position(id: s.id, MockAPI.tokens[s.token], long: s.long, leverage: s.leverage, entry: s.entry, margin: s.margin, daysAgo: s.daysAgo)
        }
    }

    static var roundTrips: [[String: Any]] {
        func trip(_ id: String, _ token: Int, leverage: Int, entry: Double, exit: Double, margin: Double, liquidated: Bool, daysAgo: Double) -> [String: Any] {
            let t = MockAPI.tokens[token]
            let qty = margin * Double(leverage) / entry
            let pnl = max(-margin, qty * (exit - entry))
            return [
                "positionId": id, "tokenMint": t.mint, "token": identity(t), "direction": "long", "leverage": leverage,
                "outcome": liquidated ? "liquidated" : "closed", "initialMarginUsd": usd(margin),
                "entryPriceUsd": dec(entry), "avgExitPriceUsd": dec(exit), "realizedPnlUsd": usd(pnl),
                "returnOnMarginPct": String(format: "%.2f", pnl / margin * 100),
                "openedAt": iso(daysAgo: daysAgo + 0.2), "closedAt": iso(daysAgo: daysAgo),
            ]
        }
        return [
            trip("lev-rt-1", 2, leverage: 2, entry: 0.7410, exit: 0.8010, margin: 400, liquidated: false, daysAgo: 1),
            trip("lev-rt-2", 3, leverage: 10, entry: 0.4890, exit: 0.4432, margin: 200, liquidated: true, daysAgo: 3),
        ]
    }

    /// Leveraged value (floored margin + unrealized) and locked margin over `seeds`.
    static var totals: (value: Double, margin: Double, unrealized: Double) {
        var value = 0.0, margin = 0.0, unrealized = 0.0
        for s in seeds {
            let mark = Double(MockAPI.tokens[s.token].price) ?? s.entry
            let qty = s.margin * Double(s.leverage) / s.entry
            let pnl = (s.long ? 1.0 : -1.0) * qty * (mark - s.entry)
            value += max(0, s.margin + pnl)
            margin += s.margin
            unrealized += pnl
        }
        return (value, margin, unrealized)
    }

    private static func position(id: String, _ t: MockAPI.DemoToken, long: Bool, leverage: Int, entry: Double, margin: Double, daysAgo: Double) -> [String: Any] {
        let mark = Double(t.price) ?? entry
        let notional = margin * Double(leverage)
        let qty = notional / entry
        let pnl = (long ? 1.0 : -1.0) * qty * (mark - entry)
        let liq = liquidationPrice(entry: entry, leverage: Double(leverage), long: long)
        return [
            "id": id, "tokenMint": t.mint, "chain": "solana", "token": identity(t),
            "direction": long ? "long" : "short", "leverage": leverage, "status": "open", "source": "manual",
            "entryPriceUsd": dec(entry), "entryMidPriceUsd": dec(entry), "qtyOpened": dec(qty), "qty": dec(qty),
            "notionalUsd": usd(notional), "marginUsd": usd(margin), "initialMarginUsd": usd(margin),
            "maintenanceMarginBps": 100, "liquidationPriceUsd": dec(liq),
            "bankruptcyPriceUsd": dec(long ? entry * (1 - 1 / Double(leverage)) : entry * (1 + 1 / Double(leverage))),
            "markPriceUsd": t.price, "markState": "fresh", "markAgeMs": 900, "markFromLastFill": false,
            "valueUsd": usd(max(0, margin + pnl)), "unrealizedPnlUsd": usd(pnl),
            "unrealizedReturnOnMarginPct": margin > 0 ? String(format: "%.2f", pnl / margin * 100) : "0",
            "unrealizedUnavailable": NSNull(), "distanceToLiquidationPct": String(format: "%.2f", (liq / mark - 1) * 100),
            "realizedPnlUsd": "0", "shortfallUsd": "0", "liquidityUsd": t.liquidity,
            "openedAt": iso(daysAgo: daysAgo), "closedAt": NSNull(), "fills": [] as [Any],
        ] as [String: Any]
    }

    private static func fill(kind: String, qty: String, price: Double, mid: Double, margin: Double, pnl: Double) -> [String: Any] {
        [
            "id": "\(Int(Date().timeIntervalSince1970))", "kind": kind, "qty": qty,
            "priceUsd": dec(price), "midPriceUsd": dec(mid), "slippageBps": 30, "priceImpactBps": 1,
            "marginUsd": usd(margin), "realizedPnlUsd": usd(pnl), "shortfallUsd": "0", "feeUsd": "0",
            "priceSource": "jupiter", "priceObservedAt": now, "executedAt": now,
        ]
    }

    private static func identity(_ t: MockAPI.DemoToken) -> [String: Any] {
        ["mint": t.mint, "symbol": t.symbol, "name": t.name, "hasLogo": true, "isVerified": t.verified]
    }

    private static var now: String { ISO8601DateFormatter().string(from: Date()) }
    private static func iso(daysAgo: Double) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(-daysAgo * 86400))
    }
}
#endif
