import Foundation

// The live-market contract (v1), shared with the backend: `GET /market/tokens/:mint/live`
// and the `/market` Socket.IO namespace. Prices are decimal strings like every other
// money field; times are integer epoch milliseconds. The chart converts to `Double`
// only for drawing (see `TapePoint`), never for anything that is shown as money
// without the original `Decimal` beside it.

/// One swap on the token's pool — or, for `jupiter`/`dexscreener`, one price
/// observation that isn't a swap (side "buy", amountUsd "0"): drawn as a line point,
/// never as a trade dot.
struct MarketTrade: Decodable, Hashable {
    enum Side: String, Decodable {
        case buy, sell
    }

    /// Where the print came from. Unknown future sources decode as `.other` (and are
    /// treated like observations) rather than failing a whole batch.
    enum Source: String, Decodable {
        case chain, geckoterminal, dexscreener, jupiter, other

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Source(rawValue: raw) ?? .other
        }

        /// A real swap (dot-worthy), as opposed to a quote someone observed.
        var isSwap: Bool { self == .chain || self == .geckoterminal }
    }

    /// `<txSignature>:<innerIndex>` — unique per swap, so it's the dedupe key.
    let id: String
    /// Epoch milliseconds of the swap (block time for chain trades).
    let t: Int64
    let slot: Int64?
    /// USD per one token, from this swap's own transferred amounts.
    @DecimalString var price: Decimal
    let side: Side
    @DecimalString var amountUsd: Decimal
    let source: Source

    var isSwap: Bool { source.isSwap }
}

/// The feed's health, which drives the header's LIVE dot.
struct MarketStatus: Decodable, Equatable {
    enum State: String, Decodable {
        /// Watching the chain; trades are real-time.
        case live
        /// Running on a fallback source (Jupiter/DexScreener/GeckoTerminal) — e.g.
        /// the first seconds while the chain watcher attaches.
        case degraded
        /// Nothing fresh; the price shown may be old.
        case stale

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            // An unknown state is shown as the cautious middle, not as "live".
            self = State(rawValue: raw) ?? .degraded
        }
    }

    let state: State
    let source: MarketTrade.Source?
    let lagMs: Int?
    let poolAddress: String?
    let dex: String?
}

/// The server's newest accepted price, present even when there are no trades yet.
struct MarketPrice: Decodable, Equatable {
    @DecimalString var value: Decimal
    let t: Int64
    let source: MarketTrade.Source?
}

/// A one-second OHLCV bucket (full snapshots only, last 120 s).
struct Candle1s: Decodable, Equatable {
    /// Bucket start, epoch milliseconds.
    let t: Int64
    @DecimalString var o: Decimal
    @DecimalString var h: Decimal
    @DecimalString var l: Decimal
    @DecimalString var c: Decimal
    /// USD volume.
    @DecimalString var v: Decimal
}

/// `GET /market/tokens/:mint/live[?sinceSeq=N]`, and the `/market` socket's
/// `subscribe` ack. Without `sinceSeq` it's the last 120 s (trades + 1 s candles);
/// with it, only trades newer than N. `reset: true` means the client's seq was too
/// old or from a restarted server and this is a fresh full snapshot instead.
struct LiveMarketSnapshot: Decodable {
    let mint: String
    let seq: Int
    let serverTime: Int64
    let displayDelayMs: Int?
    let status: MarketStatus
    let price: MarketPrice?
    let trades: [MarketTrade]
    let candles1s: [Candle1s]
    let reset: Bool

    private enum CodingKeys: String, CodingKey {
        case mint, seq, serverTime, displayDelayMs, status, price, trades, candles1s, reset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mint = try container.decode(String.self, forKey: .mint)
        seq = try container.decode(Int.self, forKey: .seq)
        serverTime = try container.decode(Int64.self, forKey: .serverTime)
        displayDelayMs = try container.decodeIfPresent(Int.self, forKey: .displayDelayMs)
        status = try container.decode(MarketStatus.self, forKey: .status)
        price = try container.decodeIfPresent(MarketPrice.self, forKey: .price)
        // Incremental responses may leave these out entirely rather than send [].
        trades = try container.decodeIfPresent([MarketTrade].self, forKey: .trades) ?? []
        candles1s = try container.decodeIfPresent([Candle1s].self, forKey: .candles1s) ?? []
        reset = try container.decodeIfPresent(Bool.self, forKey: .reset) ?? false
    }
}

/// Socket `trades`: a batch (≤ 10/s per mint). `seq` is the seq of the batch's last
/// trade, so a batch of n covers `seq - n + 1 ... seq`.
struct MarketTradesMessage: Decodable {
    let mint: String
    let seq: Int
    let trades: [MarketTrade]
}

/// Socket `status`: sent when the feed's state changes.
struct MarketStatusMessage: Decodable {
    let mint: String
    let status: MarketStatus
}

// MARK: - Drawing-side values

/// A trade as the chart consumes it: time and price as plain numbers so a frame can
/// walk hundreds of them without touching `Decimal`, with the exact `Decimal` kept
/// for the header and price tag.
struct TapePoint: Equatable {
    enum Kind: Equatable {
        case buy, sell
        /// A quote (Jupiter/DexScreener) — part of the line, no dot.
        case observation
    }

    let id: String
    /// Epoch milliseconds.
    let t: Int64
    let price: Double
    let priceDecimal: Decimal
    let amountUsd: Double
    let kind: Kind

    init(id: String, t: Int64, price: Decimal, amountUsd: Double = 0, kind: Kind) {
        self.id = id
        self.t = t
        self.priceDecimal = price
        self.price = NSDecimalNumber(decimal: price).doubleValue
        self.amountUsd = amountUsd
        self.kind = kind
    }

    init(_ trade: MarketTrade) {
        let kind: Kind = trade.isSwap ? (trade.side == .buy ? .buy : .sell) : .observation
        self.init(
            id: trade.id,
            t: trade.t,
            price: trade.price,
            amountUsd: NSDecimalNumber(decimal: trade.amountUsd).doubleValue,
            kind: kind
        )
    }

    var isSwap: Bool { kind != .observation }
}

/// An OHLCV bucket in drawing units (the LIVE candle view's 1 s and 5 s candles).
struct LiveCandle: Equatable {
    /// Bucket start, epoch milliseconds.
    var t: Int64
    var open: Double
    var high: Double
    var low: Double
    var close: Double
    var volume: Double

    init(t: Int64, open: Double, high: Double, low: Double, close: Double, volume: Double) {
        self.t = t
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }

    init(_ candle: Candle1s) {
        func double(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
        self.init(t: candle.t, open: double(candle.o), high: double(candle.h), low: double(candle.l), close: double(candle.c), volume: double(candle.v))
    }
}
