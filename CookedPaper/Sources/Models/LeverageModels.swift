import Foundation

// Leveraged paper positions: `packages/api-types/src/paper-leverage.ts`. Isolated
// margin, 2x/5x/10x, long or (synthetic) short, marked and liquidated on real live
// prices only. Every money field is a decimal string, as everywhere else.

enum LeverageDirection: String, Codable, CaseIterable, Identifiable {
    case long, short
    var id: String { rawValue }
    var title: String { self == .long ? "Long" : "Short" }
}

enum LeveragedStatus: String, Decodable {
    case open, closed, liquidated
}

struct PaperLeverageDisclosure: Decodable {
    let liquidationBasis: String
    let checkIntervalMs: Int
    let maintenanceMarginBps: Int
}

struct PaperLeverageConfigResponse: Decodable {
    let leverageOptions: [Int]
    let directions: [LeverageDirection]
    @DecimalString var minMarginUsd: Decimal
    let maxOpenPositions: Int
    let disclosure: PaperLeverageDisclosure
}

struct PaperLeveragedFill: Decodable, Identifiable {
    let id: String
    let kind: String
    @DecimalString var qty: Decimal
    @DecimalString var priceUsd: Decimal
    @DecimalString var midPriceUsd: Decimal
    @DecimalString var marginUsd: Decimal
    @DecimalString var realizedPnlUsd: Decimal
    @DecimalString var shortfallUsd: Decimal
    let priceSource: String
    let priceObservedAt: String
    let executedAt: String
}

struct PaperLeveragedPosition: Decodable, Identifiable {
    let id: String
    let tokenMint: String
    let token: PaperTokenIdentity?
    let direction: LeverageDirection
    let leverage: Int
    let status: LeveragedStatus
    @DecimalString var entryPriceUsd: Decimal
    @DecimalString var qty: Decimal
    @DecimalString var notionalUsd: Decimal
    @DecimalString var marginUsd: Decimal
    @DecimalString var initialMarginUsd: Decimal
    @DecimalString var liquidationPriceUsd: Decimal
    /// Null when nothing fresh priced it — shown as unmeasured, never a stale P&L.
    @OptionalDecimalString var markPriceUsd: Decimal?
    let markFromLastFill: Bool
    /// Margin plus unrealized, floored at zero: exactly what this adds to equity.
    @DecimalString var valueUsd: Decimal
    @OptionalDecimalString var unrealizedPnlUsd: Decimal?
    @OptionalDecimalString var unrealizedReturnOnMarginPct: Decimal?
    /// Signed % the price must move to reach liquidation.
    @OptionalDecimalString var distanceToLiquidationPct: Decimal?
    @DecimalString var realizedPnlUsd: Decimal
    let openedAt: String
    let closedAt: String?
    let fills: [PaperLeveragedFill]?

    var symbol: String { token?.symbol ?? "?" }
    /// "5x Long"
    var label: String { "\(leverage)x \(direction.title)" }
}

struct PaperLeveragedRoundTrip: Decodable, Identifiable {
    var id: String { positionId }
    let positionId: String
    let tokenMint: String
    let token: PaperTokenIdentity?
    let direction: LeverageDirection
    let leverage: Int
    /// "closed" or "liquidated"
    let outcome: String
    @DecimalString var initialMarginUsd: Decimal
    @DecimalString var entryPriceUsd: Decimal
    @DecimalString var avgExitPriceUsd: Decimal
    @DecimalString var realizedPnlUsd: Decimal
    @DecimalString var returnOnMarginPct: Decimal
    let openedAt: String
    let closedAt: String

    var isLiquidated: Bool { outcome == "liquidated" }
}

// MARK: - Quote / open / close

struct PaperLeverageQuoteBody: Encodable {
    let tokenMint: String
    let direction: LeverageDirection
    let leverage: Int
    let marginUsd: String
}

struct PaperLeverageQuoteResponse: Decodable {
    let tokenMint: String
    let direction: LeverageDirection
    let leverage: Int
    @DecimalString var marginUsd: Decimal
    @DecimalString var notionalUsd: Decimal
    @DecimalString var qty: Decimal
    @DecimalString var midPriceUsd: Decimal
    @DecimalString var estEntryPriceUsd: Decimal
    @DecimalString var priceImpactPct: Decimal
    @DecimalString var liquidationPriceUsd: Decimal
    @DecimalString var liquidationMovePct: Decimal
    @DecimalString var maxMarginUsd: Decimal
    let eligible: Bool
    let ineligibleReason: String?
}

struct OpenPaperLeveragedBody: Encodable {
    let tokenMint: String
    let direction: LeverageDirection
    let leverage: Int
    let marginUsd: String
    var expectedPriceUsd: String?
    var maxSlippageBps: Int?
    /// One per tap, reused on retry, so a retried request never locks margin twice.
    let clientOrderId: String
}

struct ClosePaperLeveragedBody: Encodable {
    let closePercent: Int
    var expectedPriceUsd: String?
}

struct PaperLeveragedMutationResponse: Decodable {
    let position: PaperLeveragedPosition
    let fill: PaperLeveragedFill
    @DecimalString var cashUsd: Decimal
    @DecimalString var equityUsd: Decimal
}

struct PaperLeveragedListResponse: Decodable {
    let positions: [PaperLeveragedPosition]
}

extension PaperLeverageQuoteResponse {
    /// Plain-language reason a quote can't be opened, from the server's `reason`.
    var ineligibleMessage: String? {
        guard !eligible else { return nil }
        return LeverageRefusal.message(for: ineligibleReason)
    }
}

enum LeverageRefusal {
    static func message(for reason: String?) -> String {
        switch reason {
        case "insufficient_cash": "Not enough paper cash for that margin."
        case "below_min_margin": "Margin is below the minimum."
        case "chain_not_supported": "Leverage is only available on Solana tokens."
        case "liquidity_unknown": "This token's liquidity isn't known, so leverage is off for it."
        case "liquidity_too_thin": "This token's pool is too thin for leverage."
        case "notional_exceeds_liquidity_cap": "That position is too large for this token's pool. Try less margin or lower leverage."
        case "entry_too_close_to_liquidation": "The entry would sit too close to liquidation. Try lower leverage."
        case "open_position_limit": "You've reached the limit of open leveraged positions."
        case "short_not_supported": "Shorts aren't available right now."
        case "price_moved": "The price moved. Review the new quote."
        case "position_not_open": "This position is already closed."
        default: "This position can't be opened right now."
        }
    }
}
