import Foundation

// MARK: - Candles (chart)

struct Candle: Decodable, Identifiable {
    var id: String { bucketStart }
    let bucketStart: String
    @DecimalString var open: Decimal
    @DecimalString var high: Decimal
    @DecimalString var low: Decimal
    @DecimalString var close: Decimal
    @DecimalString var volume: Decimal
}

enum CandleInterval: String, CaseIterable, Identifiable {
    case oneMinute = "1m"
    case fiveMinute = "5m"
    case fifteenMinute = "15m"
    case thirtyMinute = "30m"
    case oneHour = "1h"
    case fourHour = "4h"
    case oneDay = "1d"

    var id: String { rawValue }

    /// The label shown in the chart's timeframe picker.
    var label: String {
        switch self {
        case .oneMinute: "1m"
        case .fiveMinute: "5m"
        case .fifteenMinute: "15m"
        case .thirtyMinute: "30m"
        case .oneHour: "1H"
        case .fourHour: "4H"
        case .oneDay: "1D"
        }
    }
}

/// `getTokenCandles` self-heals: when our own trade-folded series is empty (true for
/// almost every token — the corpus is ~20 watched wallets) it falls back server-side
/// to relayed GeckoTerminal candles and sets `source: 'relayed'`. A gap (`null` in
/// `candles`) is a genuine no-trade window and must render as a gap, never a flat
/// interpolated line — that rule is repeated verbatim in the backend's own schema
/// comments, so it is repeated here rather than "simplified" away.
struct TokenCandlesResponse: Decodable {
    let mint: String
    let interval: String
    let source: String?
    /// 'quote' means prices are in the pool's quote-asset units (e.g. SOL); 'usd'
    /// means dollars. Read this BEFORE formatting a candle — never assume USD.
    let denomination: String
    let candles: [Candle?]

    var isRelayed: Bool { source == "relayed" }
}

// MARK: - Token facts (detail-screen header)

struct MarketFigure: Decodable {
    @OptionalDecimalString var value: Decimal?
    let unavailable: String?
}

struct TokenMetadata: Decodable {
    let mint: String
    let symbol: String?
    let name: String?
    let logoUri: String?
    let isVerified: Bool
}

struct TokenMarket: Decodable {
    let priceUsd: MarketFigure
    let change24h: MarketFigure
    let marketCapUsd: MarketFigure
    let volume24hUsd: MarketFigure
    let liquidityUsd: MarketFigure
}

struct TokenProfileResponse: Decodable {
    let token: TokenMetadata
    let market: TokenMarket
}

// MARK: - Paper-tradeable check (the trade sheet's buy-button gate)

struct PaperTokenPriceability: Decodable {
    let tokenMint: String
    let priceable: Bool
    let reason: String?
    @OptionalDecimalString var priceUsd: Decimal?
}
