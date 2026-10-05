import Foundation

/// "How cooked is your portfolio?" — a playful 0–100 risk score worked out on the
/// device from the snapshot the Portfolio screen already has. Paper money, just for
/// fun: it is a nudge, not advice.
///
/// The score is the sum of four capped parts (max 100):
/// - Liquidation (0–35): the open leveraged position nearest liquidation. 40% or
///   more away scores 0, 5% or closer scores 35, linear between.
/// - Leverage exposure (0–15): total leveraged notional over equity. 0x scores 0,
///   1x or more scores 15, linear between.
/// - Concentration (0–25): the largest single position's value over equity. 20% or
///   less scores 0, 80% or more scores 25, linear between.
/// - Drawdown (0–15): net unrealized P&L over cost basis (spot cost plus leveraged
///   margin). Flat or up scores 0, down 50% or more scores 15, linear between.
/// - Thin liquidity (0–10): the share of equity in spot tokens whose pool is under
///   $250K. 0% scores 0, 50% or more scores 10, linear between.
///
/// No positions at all is always 0 ("Raw") with no reasons. Equity at or below
/// zero with positions still open is 100.
///
/// Pure value types and pure functions; no SwiftUI, no formatting beyond the
/// reason copy, so it is tested without the UI in the loop.
enum CookedMeter {
    // MARK: - Inputs

    /// A spot holding.
    struct Holding: Equatable {
        var symbol: String
        var valueUsd: Double
        var costUsd: Double
        /// Nil when the position is unpriced; it then adds nothing to drawdown.
        var unrealizedPnlUsd: Double?
        /// Nil when unknown; it then never counts as thin.
        var liquidityUsd: Double?
    }

    /// An open leveraged position.
    struct LeveragedHolding: Equatable {
        var symbol: String
        var isLong: Bool
        var leverage: Int
        var notionalUsd: Double
        var marginUsd: Double
        /// What it adds to equity (margin plus unrealized, floored at zero).
        var valueUsd: Double
        var unrealizedPnlUsd: Double?
        /// Signed % the price must move to liquidate; only its size matters here.
        var distanceToLiquidationPct: Double?
    }

    struct Input: Equatable {
        var equityUsd: Double
        var holdings: [Holding] = []
        var leveraged: [LeveragedHolding] = []

        var isEmpty: Bool { holdings.isEmpty && leveraged.isEmpty }
    }

    // MARK: - Output

    enum Tier: Int, CaseIterable, Equatable {
        case raw, lightlyToasted, medium, wellDone, fullyCooked

        init(score: Int) {
            switch score {
            case ...20: self = .raw
            case 21...40: self = .lightlyToasted
            case 41...60: self = .medium
            case 61...80: self = .wellDone
            default: self = .fullyCooked
            }
        }

        var title: String {
            switch self {
            case .raw: "Raw"
            case .lightlyToasted: "Lightly toasted"
            case .medium: "Medium"
            case .wellDone: "Well done"
            case .fullyCooked: "Fully cooked"
            }
        }

        /// One line of flavor under the tier name.
        var copy: String {
            switch self {
            case .raw: "Cold pan. Nothing's sizzling."
            case .lightlyToasted: "A little heat. Keep an eye on it."
            case .medium: "Things are getting crispy."
            case .wellDone: "Smoke's coming off this one."
            case .fullyCooked: "Call the fire department."
            }
        }

        /// SF Symbol for the tier: the pan when cold, flames as it heats up.
        var symbol: String {
            switch self {
            case .raw: "frying.pan"
            case .lightlyToasted, .medium: "flame"
            case .wellDone, .fullyCooked: "flame.fill"
            }
        }
    }

    /// What pushed the score up, used for the reasons and the tip.
    enum DriverKind: Equatable {
        case liquidation, exposure, concentration, drawdown, thinLiquidity, wipedOut
    }

    struct Driver: Equatable {
        var kind: DriverKind
        var points: Double
        var reason: String
    }

    /// Everything the card and sheet show.
    struct Reading: Equatable {
        var score: Int
        var tier: Tier
        var reasons: [String]
        var tip: String
    }

    // MARK: - Tunables

    static let maxLiquidationPoints = 35.0
    static let maxExposurePoints = 15.0
    static let maxConcentrationPoints = 25.0
    static let maxDrawdownPoints = 15.0
    static let maxThinLiquidityPoints = 10.0

    /// Liquidation distance (%) that scores nothing, and the one that scores in full.
    static let safeLiquidationPct = 40.0
    static let dangerLiquidationPct = 5.0
    /// Notional / equity that scores in full.
    static let fullExposureRatio = 1.0
    /// Largest-position share that starts scoring, and the one that scores in full.
    static let concentrationFloor = 0.2
    static let concentrationCeiling = 0.8
    /// Loss on cost basis that scores in full.
    static let fullDrawdown = 0.5
    /// Pools under this are "thin"; this share of equity in them scores in full.
    static let thinLiquidityUsd = 250_000.0
    static let fullThinShare = 0.5
    /// A driver must add at least this many points to be given as a reason.
    static let reasonThreshold = 3.0

    // MARK: - Scoring

    static func score(_ input: Input) -> (score: Int, tier: Tier, reasons: [String]) {
        if input.isEmpty { return (0, .raw, []) }
        let all = drivers(input)
        let total = all.reduce(0.0) { $0 + $1.points }
        let score = min(100, max(0, Int(total.rounded())))
        let reasons = all
            .filter { $0.points >= reasonThreshold }
            .sorted { $0.points > $1.points }
            .prefix(2)
            .map(\.reason)
        return (score, Tier(score: score), Array(reasons))
    }

    /// The score plus a "what lowers it" tip aimed at the biggest driver.
    static func reading(_ input: Input) -> Reading {
        let result = score(input)
        return Reading(score: result.score, tier: result.tier, reasons: result.reasons, tip: tip(input))
    }

    /// Every part of the score, in no particular order. Parts that score zero are
    /// left out.
    static func drivers(_ input: Input) -> [Driver] {
        if input.isEmpty { return [] }
        let equity = input.equityUsd
        guard equity > 0 else {
            return [Driver(kind: .wipedOut, points: 100, reason: "Your equity is gone. The pan is empty.")]
        }

        var result: [Driver] = []

        // Liquidation: the open position nearest its liquidation price.
        let measured = input.leveraged.compactMap { position -> (LeveragedHolding, Double)? in
            guard let distance = position.distanceToLiquidationPct else { return nil }
            return (position, abs(distance))
        }
        if let nearest = measured.min(by: { $0.1 < $1.1 }) {
            let closeness = ramp(nearest.1, from: safeLiquidationPct, to: dangerLiquidationPct)
            let points = maxLiquidationPoints * closeness
            if points > 0 {
                let position = nearest.0
                let side = position.isLong ? "long" : "short"
                let away = nearest.1 < 1 ? "under 1%" : "\(Int(nearest.1.rounded()))%"
                result.append(Driver(
                    kind: .liquidation,
                    points: points,
                    reason: "\(position.leverage)x \(side) \(position.symbol) is \(away) from liquidation"
                ))
            }
        }

        // Exposure: how much notional the leverage controls versus equity.
        let notional = input.leveraged.reduce(0.0) { $0 + max(0, $1.notionalUsd) }
        if notional > 0 {
            let ratio = notional / equity
            let points = maxExposurePoints * ramp(ratio, from: 0, to: fullExposureRatio)
            if points > 0 {
                result.append(Driver(
                    kind: .exposure,
                    points: points,
                    reason: "Leverage controls \(multiple(ratio)) your equity"
                ))
            }
        }

        // Concentration: the single biggest position's share of equity.
        var largestSymbol = ""
        var largestValue = 0.0
        for holding in input.holdings where holding.valueUsd > largestValue {
            largestSymbol = holding.symbol
            largestValue = holding.valueUsd
        }
        for position in input.leveraged where position.valueUsd > largestValue {
            largestSymbol = position.symbol
            largestValue = position.valueUsd
        }
        if largestValue > 0 {
            let share = min(1, largestValue / equity)
            let points = maxConcentrationPoints * ramp(share, from: concentrationFloor, to: concentrationCeiling)
            if points > 0 {
                result.append(Driver(
                    kind: .concentration,
                    points: points,
                    reason: "\(percent(share)) of your portfolio is in \(largestSymbol)"
                ))
            }
        }

        // Drawdown: net unrealized P&L against what was put in.
        let pnl = input.holdings.compactMap(\.unrealizedPnlUsd).reduce(0.0, +)
            + input.leveraged.compactMap(\.unrealizedPnlUsd).reduce(0.0, +)
        let basis = input.holdings.reduce(0.0) { $0 + max(0, $1.costUsd) }
            + input.leveraged.reduce(0.0) { $0 + max(0, $1.marginUsd) }
        if pnl < 0, basis > 0 {
            let loss = -pnl / basis
            let points = maxDrawdownPoints * ramp(loss, from: 0, to: fullDrawdown)
            if points > 0 {
                result.append(Driver(
                    kind: .drawdown,
                    points: points,
                    reason: "Your open positions are down \(percent(loss)) on cost"
                ))
            }
        }

        // Thin liquidity: spot value in tokens with small pools.
        let thinValue = input.holdings.reduce(0.0) { total, holding in
            guard let liquidity = holding.liquidityUsd, liquidity < thinLiquidityUsd else { return total }
            return total + max(0, holding.valueUsd)
        }
        if thinValue > 0 {
            let share = min(1, thinValue / equity)
            let points = maxThinLiquidityPoints * ramp(share, from: 0, to: fullThinShare)
            if points > 0 {
                result.append(Driver(
                    kind: .thinLiquidity,
                    points: points,
                    reason: "\(percent(share)) of your portfolio is in thin-liquidity tokens"
                ))
            }
        }

        return result
    }

    /// One "what lowers it" line, aimed at the biggest driver.
    static func tip(_ input: Input) -> String {
        let top = drivers(input).max { $0.points < $1.points }
        switch top?.kind {
        case .liquidation: return "Add margin, cut the size, or close the position closest to liquidation."
        case .exposure: return "Lower your leverage or close a leveraged position to take some heat off."
        case .concentration: return "Spread out: trim your biggest bag and keep more in cash."
        case .drawdown: return "Cut the losers you wouldn't buy again today."
        case .thinLiquidity: return "Move some size into tokens with deeper pools."
        case .wipedOut: return "Reset your paper portfolio and start a fresh pan."
        case nil: return "Keep it that way: modest size, low leverage, a cash cushion."
        }
    }

    // MARK: - Helpers

    /// 0 at `from`, 1 at `to`, linear between and clamped outside. Works in either
    /// direction (`from` may be greater than `to`).
    static func ramp(_ value: Double, from: Double, to: Double) -> Double {
        guard from != to, value.isFinite else { return 0 }
        let t = (value - from) / (to - from)
        return min(1, max(0, t))
    }

    private static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private static func multiple(_ ratio: Double) -> String {
        if ratio >= 1 {
            return ratio.formatted(.number.precision(.fractionLength(0...1))) + "x"
        }
        return percent(ratio) + " of"
    }
}

// MARK: - From the portfolio snapshot

extension CookedMeter.Input {
    /// Builds the meter's input from the Portfolio screen's snapshot. Only open
    /// leveraged positions count.
    init(snapshot: PaperSnapshotResponse) {
        func double(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
        func optionalDouble(_ value: Decimal?) -> Double? { value.map { NSDecimalNumber(decimal: $0).doubleValue } }

        let holdings = snapshot.positions.map { position in
            CookedMeter.Holding(
                symbol: position.token?.symbol ?? "?",
                valueUsd: double(position.valueUsd),
                costUsd: double(position.costUsd),
                unrealizedPnlUsd: optionalDouble(position.unrealizedPnlUsd),
                liquidityUsd: optionalDouble(position.liquidityUsd)
            )
        }
        let leveraged = (snapshot.leveragedPositions ?? [])
            .filter { $0.status == .open }
            .map { position in
                CookedMeter.LeveragedHolding(
                    symbol: position.symbol,
                    isLong: position.direction == .long,
                    leverage: position.leverage,
                    notionalUsd: double(position.notionalUsd),
                    marginUsd: double(position.initialMarginUsd),
                    valueUsd: double(position.valueUsd),
                    unrealizedPnlUsd: optionalDouble(position.unrealizedPnlUsd),
                    distanceToLiquidationPct: optionalDouble(position.distanceToLiquidationPct)
                )
            }
        self.init(equityUsd: double(snapshot.equityUsd), holdings: holdings, leveraged: leveraged)
    }
}
