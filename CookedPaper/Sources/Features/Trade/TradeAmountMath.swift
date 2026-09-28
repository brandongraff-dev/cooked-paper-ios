import Foundation

/// The trade ticket's quick-amount math, pulled out of `TradeSheetView` so it can be
/// tested without SwiftUI in the loop. No side effects, no formatting — callers decide
/// how to render or send what comes back.
enum TradeAmountMath {
    /// The buy-side chip's target: `percent`% of available cash, rounded to the cent
    /// (this is what the ticket ultimately sends as `notionalUsd`).
    static func quickBuyAmount(cashUsd: Decimal, percent: Int) -> Decimal {
        (cashUsd * Decimal(percent) / 100).rounded(2)
    }

    /// The sell-side row's display estimate for `percent`% of a position's current
    /// value — informational only. The trade itself goes by the server's own
    /// `sellPercent` primitive, never a client-computed quantity.
    static func quickSellEstimate(positionValueUsd: Decimal, percent: Int) -> Decimal {
        positionValueUsd * Decimal(percent) / 100
    }
}

private extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
