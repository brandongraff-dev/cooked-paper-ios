import Foundation

// MARK: - Shared shapes

struct PaperTokenIdentity: Decodable, Hashable {
    let mint: String
    let symbol: String?
    let name: String?
    let hasLogo: Bool
    let isVerified: Bool
}

enum MarkState: String, Decodable {
    case fresh, stale, dead
}

/// `{ pct|usd, sampleSize, sampleOf, unavailable }` — every aggregate stat on the
/// portfolio snapshot carries this wrapper. `unavailable == nil` iff the value is
/// non-null; check it before rendering rather than treating null as zero.
struct MeasuredPct: Decodable {
    @OptionalDecimalString var pct: Decimal?
    let sampleSize: Int
    let sampleOf: String
    let unavailable: String?
}

struct MeasuredUsd: Decodable {
    @OptionalDecimalString var usd: Decimal?
    let sampleSize: Int
    let sampleOf: String
    let unavailable: String?
}

// MARK: - Portfolio

struct PaperPortfolio: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    @DecimalString var startingBalanceUsd: Decimal
    @DecimalString var cashUsd: Decimal
    let createdAt: String
    let resetAt: String?
    let resetCount: Int
    let archivedAt: String?
    let isGuest: Bool

    static func == (lhs: PaperPortfolio, rhs: PaperPortfolio) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct StarterPaperPortfolioResponse: Decodable {
    let portfolio: PaperPortfolio
    let created: Bool
    let guestToken: String?
    let guestTokenExpiresAt: String?
}

// MARK: - Positions & round trips

struct PaperPosition: Decodable, Identifiable {
    var id: String { tokenMint }
    let tokenMint: String
    @DecimalString var qty: Decimal
    @DecimalString var costUsd: Decimal
    @DecimalString var avgCostUsd: Decimal
    @DecimalString var markPriceUsd: Decimal
    let markState: MarkState
    let markFromLastFill: Bool
    @DecimalString var valueUsd: Decimal
    /// Null exactly when `markFromLastFill` is true — render "unpriced", never $0.
    @OptionalDecimalString var unrealizedPnlUsd: Decimal?
    @OptionalDecimalString var unrealizedReturnPct: Decimal?
    let roundTripCount: Int
    let token: PaperTokenIdentity?
    @OptionalDecimalString var marketCapUsd: Decimal?
    @OptionalDecimalString var liquidityUsd: Decimal?
}

struct PaperRoundTrip: Decodable, Identifiable {
    var id: String { closingTradeId }
    let tokenMint: String
    @DecimalString var qty: Decimal
    @DecimalString var costUsd: Decimal
    @DecimalString var proceedsUsd: Decimal
    @DecimalString var realizedPnlUsd: Decimal
    @OptionalDecimalString var returnPct: Decimal?
    let openedAt: String
    let closedAt: String
    let closingTradeId: String
    let token: PaperTokenIdentity?
}

// MARK: - Stats & equity curve

struct PaperStats: Decodable {
    let returnPct: MeasuredPct
    let winRatePct: MeasuredPct
    let maxDrawdownPct: MeasuredPct
    let realizedPnlUsd: MeasuredUsd
    let unrealizedPnlUsd: MeasuredUsd
    @DecimalString var feesPaidUsd: Decimal
    let tradeCount: Int
    let roundTripCount: Int
    let winCount: Int
    let lossCount: Int
}

struct EquityPoint: Decodable, Identifiable {
    var id: String { at }
    let at: String
    @DecimalString var equityUsd: Decimal
    let kind: String
}

struct EquityCurve: Decodable {
    @DecimalString var maxDrawdownPct: Decimal
    @DecimalString var peakEquityUsd: Decimal
    let points: [EquityPoint]
}

// MARK: - Snapshot (the main portfolio/positions screen)

struct PaperSnapshotResponse: Decodable {
    let portfolio: PaperPortfolio
    let portfolioId: String
    @DecimalString var cashUsd: Decimal
    @DecimalString var positionsValueUsd: Decimal
    @DecimalString var equityUsd: Decimal
    let positions: [PaperPosition]
    let roundTrips: [PaperRoundTrip]
    let stats: PaperStats
    let equityCurve: EquityCurve
}

// MARK: - Trades (fill history)

enum TradeSide: String, Codable {
    case buy, sell
}

struct PaperTrade: Decodable, Identifiable {
    let id: String
    let tokenMint: String
    let side: TradeSide
    @DecimalString var qty: Decimal
    @DecimalString var priceUsd: Decimal
    @DecimalString var valueUsd: Decimal
    let slippageBps: Int
    let priceImpactBps: Int
    @OptionalDecimalString var marketCapUsd: Decimal?
    let executedAt: String
}

struct PaperTradesResponse: Decodable {
    let trades: [PaperTrade]
}

// MARK: - Quote (preview) & execute

struct TradeGuidanceWarning: Decodable, Identifiable {
    var id: String { self.warningId }
    let warningId: String
    let severity: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case warningId = "id"
        case severity, message
    }
}

struct FirstTradeGuidance: Decodable {
    let isFirstTradeInPortfolio: Bool
    let tradeCountInPortfolio: Int
    @OptionalDecimalString var suggestedNotionalUsd: Decimal?
    let suggestedPctOfCash: Int
    let warnings: [TradeGuidanceWarning]
}

struct PaperQuoteResponse: Decodable {
    let tokenMint: String
    let side: TradeSide
    @DecimalString var inAmount: Decimal
    @DecimalString var outAmount: Decimal
    @DecimalString var minimumOut: Decimal
    @DecimalString var priceImpactPct: Decimal
    @DecimalString var priceUsd: Decimal
    let guidance: FirstTradeGuidance
}

struct VsQuote: Decodable {
    @DecimalString var expectedPriceUsd: Decimal
    @DecimalString var fillPriceUsd: Decimal
    let deltaBps: Int
    let direction: String
}

struct FillSummary: Decodable {
    let side: TradeSide
    @DecimalString var slippageCostUsd: Decimal
    @DecimalString var cashAfterUsd: Decimal
    let vsQuote: VsQuote?
}

struct FillInfo: Decodable {
    @DecimalString var fillPriceUsd: Decimal
    @DecimalString var marketPriceUsd: Decimal
}

struct ExecutePaperTradeResponse: Decodable {
    let trade: PaperTrade
    @DecimalString var cashUsd: Decimal
    let fill: FillInfo
    let summary: FillSummary
}

// MARK: - Request bodies

/// Exactly one of `qty` / `notionalUsd` / `sellPercent` is set — enforced by the call
/// site (`TradeAmount`), not by this type, since Swift has no sum-type-of-optionals
/// the way the server's Zod refinement does.
struct ExecutePaperTradeBody: Encodable {
    let tokenMint: String
    let side: TradeSide
    var qty: String?
    var notionalUsd: String?
    var sellPercent: Int?
    var expectedPriceUsd: String?
}

typealias PaperQuoteBody = ExecutePaperTradeBody
