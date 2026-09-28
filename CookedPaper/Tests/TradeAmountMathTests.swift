import Foundation
import Testing

@testable import CookedPaper

struct TradeAmountMathTests {
    @Test(arguments: [
        (25, "250.00"),
        (50, "500.00"),
        (75, "750.00"),
        (100, "1000.00"),
    ])
    func quickBuyAmountTakesAPercentOfCash(percent: Int, expected: String) {
        let cashUsd = Decimal(string: "1000.00")!
        let result = TradeAmountMath.quickBuyAmount(cashUsd: cashUsd, percent: percent)
        #expect(result == Decimal(string: expected))
    }

    // 40.02 * 25 / 100 = 10.005 — exactly halfway between two cents, so this also
    // exercises the rounding mode (`.plain`: ties go to the greater absolute value).
    @Test func quickBuyAmountRoundsAFractionalCentResult() {
        let cashUsd = Decimal(string: "40.02")!
        let result = TradeAmountMath.quickBuyAmount(cashUsd: cashUsd, percent: 25)
        #expect(result == Decimal(string: "10.01"))
    }

    @Test(arguments: [25, 50, 75, 100])
    func quickBuyAmountWithZeroCashIsAlwaysZero(percent: Int) {
        let result = TradeAmountMath.quickBuyAmount(cashUsd: 0, percent: percent)
        #expect(result == 0)
    }

    @Test(arguments: [
        (25, "250"),
        (50, "500"),
        (75, "750"),
        (100, "1000"),
    ])
    func quickSellEstimateTakesAPercentOfPositionValue(percent: Int, expected: String) {
        let positionValueUsd = Decimal(string: "1000")!
        let result = TradeAmountMath.quickSellEstimate(positionValueUsd: positionValueUsd, percent: percent)
        #expect(result == Decimal(string: expected))
    }
}
