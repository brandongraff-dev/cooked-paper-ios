#if DEBUG
import Foundation

/// DEBUG stand-in for `GET /market/tokens/:mint/live` (see `MockAPI`): a realistic
/// trade tape per demo token — bursts and quiet gaps, a mix of buy/sell sizes from
/// $5 to $5,000, a trade every ~150–700 ms while busy — generated as a pure
/// function of time, so every request (full or `?sinceSeq=`) agrees with every
/// other one without any shared state. Prices follow `MockAPI.livePriceValue`, the
/// same path the mock's fills and 1-minute candles use, so the chart, the trade
/// sheet and the candles all tell one story.
///
/// Seq numbers are dense (+1 per print) from a fixed "server boot", as the contract
/// says, by counting every second's prints since then — cheap at a handful of hash
/// calls per second of uptime.
nonisolated enum MockMarket {
    /// The mock server "booted" a few minutes before the app did, so the first
    /// snapshot already carries a full 120 s of tape.
    private static let bootSecond = Int64(Date().timeIntervalSince1970) - 240
    static let displayDelayMs = 1500
    private static let snapshotSpanMs: Int64 = 120_000
    private static let pageLimit = 500

    private struct Event {
        let ms: Int64
        let observation: Bool
        let salt: UInt64
    }

    private struct Print {
        let seq: Int
        let t: Int64
        let price: Double
        let side: String
        let amountUsd: Double
        let source: String
        let id: String
    }

    static func live(mint: String, sinceSeq: Int?, now: Date = Date()) -> [String: Any] {
        let token = MockAPI.token(for: mint)
        let tokenIndex = MockAPI.tokens.firstIndex { $0.mint == token.mint } ?? 0
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let windowStart = nowMs - snapshotSpanMs

        // Walk every second since boot, numbering prints densely; keep the last 120 s.
        var seq = 0
        var firstSeqInWindow: Int?
        var window: [Print] = []
        var second = bootSecond
        while second <= nowMs / 1000 {
            for event in events(second: second, token: token, tokenIndex: tokenIndex) {
                let t = second * 1000 + event.ms
                guard t <= nowMs else { break }
                seq += 1
                guard t > windowStart else { continue }
                if firstSeqInWindow == nil { firstSeqInWindow = seq }
                window.append(makePrint(seq: seq, t: t, second: second, event: event, token: token))
            }
            second += 1
        }

        // A seq from the future (a "restarted" server) or from before the window
        // can't be resumed: answer with a full snapshot marked `reset`.
        var reset = false
        let trades: [Print]
        if let sinceSeq {
            if sinceSeq > seq || sinceSeq < (firstSeqInWindow ?? seq + 1) - 1 {
                reset = true
                trades = Array(window.suffix(pageLimit))
            } else {
                trades = Array(window.filter { $0.seq > sinceSeq }.prefix(pageLimit))
            }
        } else {
            trades = Array(window.suffix(pageLimit))
        }
        let isFull = sinceSeq == nil || reset
        let price: Any
        if let last = window.last {
            price = ["value": dec(last.price), "t": last.t, "source": last.source] as [String: Any]
        } else {
            price = NSNull()
        }

        var body: [String: Any] = [
            "mint": mint,
            "seq": seq,
            "serverTime": nowMs,
            "displayDelayMs": displayDelayMs,
            "status": [
                "state": "live", "source": "chain", "lagMs": 400,
                "poolAddress": NSNull(), "dex": "raydium",
            ] as [String: Any],
            "price": price,
            "trades": trades.map { json($0) },
        ]
        if isFull {
            body["candles1s"] = oneSecondCandles(window)
        }
        if reset {
            body["reset"] = true
        }
        return body
    }

    // MARK: - The tape

    /// This second's prints, as millisecond offsets. An envelope of slow waves makes
    /// bursts and lulls; each demo token has its own busyness and phase.
    private static func events(second: Int64, token: MockAPI.DemoToken, tokenIndex: Int) -> [Event] {
        let seed = symbolSeed(token)
        let x = Double(second)
        let phase = Double(seed)
        let envelope = 0.5 + 0.5 * sin(x / 13 + phase) * cos(x / 37 + phase * 0.3)
        let rate: Double = switch envelope {
        case 0.62...: 5.5
        case 0.4..<0.62: 2.2
        case 0.22..<0.4: 0.7
        default: 0.08
        }
        let busyness: [Double] = [1.0, 0.95, 0.8, 0.75, 0.55, 0.6, 0.6, 0.85]
        let expected = rate * busyness[tokenIndex % busyness.count]
        var count = Int(expected)
        if unit(second, seed, salt: 1) < expected - Double(count) { count += 1 }
        count = min(count, 12)

        var events = (0..<count).map { index in
            Event(ms: Int64(unit(second, seed, salt: 10 + UInt64(index)) * 1000), observation: false, salt: 100 + UInt64(index) * 8)
        }
        // A Jupiter quote every seven seconds: part of the line, never a dot.
        if (second + Int64(tokenIndex)) % 7 == 0 {
            events.append(Event(ms: 500, observation: true, salt: 90))
        }
        return events.sorted { $0.ms < $1.ms }
    }

    private static func makePrint(seq: Int, t: Int64, second: Int64, event: Event, token: MockAPI.DemoToken) -> Print {
        let seed = symbolSeed(token)
        let date = Date(timeIntervalSince1970: Double(t) / 1000)
        let mid = MockAPI.livePriceValue(token, at: date)
        if event.observation {
            return Print(seq: seq, t: t, price: mid, side: "buy", amountUsd: 0, source: "jupiter", id: "jup-\(token.symbol)-\(second)")
        }
        // Flow leans with the trend; buys print a hair above mid, sells below.
        let trend = mid - MockAPI.livePriceValue(token, at: date.addingTimeInterval(-1.5))
        let isBuy = unit(second, seed, salt: event.salt) < (trend >= 0 ? 0.68 : 0.32)
        let spread = 0.0006 * unit(second, seed, salt: event.salt + 1)
        let price = mid * (isBuy ? 1 + spread : 1 - spread)
        // Mostly small tickets with the occasional whale: $5 × 1000^(u²).
        let size = unit(second, seed, salt: event.salt + 2)
        let amount = min(5 * pow(1000, size * size), 5000)
        return Print(
            seq: seq, t: t, price: price, side: isBuy ? "buy" : "sell", amountUsd: amount,
            source: "chain", id: "mock\(token.symbol)\(second)x\(event.salt):0"
        )
    }

    private static func json(_ trade: Print) -> [String: Any] {
        [
            "id": trade.id, "t": trade.t, "slot": trade.t / 400,
            "price": dec(trade.price), "side": trade.side,
            "amountUsd": String(format: "%.2f", trade.amountUsd), "source": trade.source,
        ] as [String: Any]
    }

    private static func oneSecondCandles(_ prints: [Print]) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        var index = 0
        while index < prints.count {
            let bucket = prints[index].t / 1000 * 1000
            let open = prints[index].price
            var high = open
            var low = open
            var close = open
            var volume = 0.0
            while index < prints.count, prints[index].t / 1000 * 1000 == bucket {
                let price = prints[index].price
                high = max(high, price)
                low = min(low, price)
                close = price
                volume += prints[index].amountUsd
                index += 1
            }
            rows.append([
                "t": bucket, "o": dec(open), "h": dec(high), "l": dec(low), "c": dec(close),
                "v": String(format: "%.2f", volume),
            ] as [String: Any])
        }
        return rows
    }

    // MARK: - Helpers

    private static func symbolSeed(_ token: MockAPI.DemoToken) -> UInt64 {
        UInt64(token.symbol.unicodeScalars.reduce(0) { $0 + Int($1.value) })
    }

    /// A deterministic uniform [0, 1) from (second, token, salt) — SplitMix64.
    private static func unit(_ second: Int64, _ seed: UInt64, salt: UInt64) -> Double {
        let a: UInt64 = UInt64(bitPattern: second) &* 0x9E37_79B9_7F4A_7C15
        let b: UInt64 = seed &* 0xBF58_476D_1CE4_E5B9
        let c: UInt64 = salt &* 0x94D0_49BB_1331_11EB
        var z: UInt64 = (a ^ b ^ c) &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / 9_007_199_254_740_992
    }

    private static func dec(_ value: Double) -> String {
        String(format: "%.10g", value)
    }
}
#endif
