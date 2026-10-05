import Foundation
import Testing

@testable import CookedPaper

struct CookedMeterTests {
    // MARK: - Tiers

    @Test(arguments: [
        (0, CookedMeter.Tier.raw),
        (20, CookedMeter.Tier.raw),
        (21, CookedMeter.Tier.lightlyToasted),
        (40, CookedMeter.Tier.lightlyToasted),
        (41, CookedMeter.Tier.medium),
        (60, CookedMeter.Tier.medium),
        (61, CookedMeter.Tier.wellDone),
        (80, CookedMeter.Tier.wellDone),
        (81, CookedMeter.Tier.fullyCooked),
        (100, CookedMeter.Tier.fullyCooked),
    ])
    func tierBoundaries(score: Int, expected: CookedMeter.Tier) {
        #expect(CookedMeter.Tier(score: score) == expected)
    }

    @Test func tierTitles() {
        #expect(CookedMeter.Tier.raw.title == "Raw")
        #expect(CookedMeter.Tier.lightlyToasted.title == "Lightly toasted")
        #expect(CookedMeter.Tier.medium.title == "Medium")
        #expect(CookedMeter.Tier.wellDone.title == "Well done")
        #expect(CookedMeter.Tier.fullyCooked.title == "Fully cooked")
    }

    // MARK: - Empty

    @Test func emptyPortfolioIsRawWithNoReasons() {
        let result = CookedMeter.score(CookedMeter.Input(equityUsd: 10_000))
        #expect(result.score == 0)
        #expect(result.tier == .raw)
        #expect(result.reasons.isEmpty)
    }

    @Test func emptyPortfolioWithNoEquityIsStillRaw() {
        let result = CookedMeter.score(CookedMeter.Input(equityUsd: 0))
        #expect(result.score == 0)
        #expect(result.tier == .raw)
        #expect(result.reasons.isEmpty)
    }

    @Test func smallDiversifiedSpotBookStaysRaw() {
        let holdings = ["BONK", "WIF", "JUP", "PYTH"].map { symbol in
            CookedMeter.Holding(symbol: symbol, valueUsd: 1_000, costUsd: 1_000, unrealizedPnlUsd: 0, liquidityUsd: 10_000_000)
        }
        let result = CookedMeter.score(CookedMeter.Input(equityUsd: 10_000, holdings: holdings))
        #expect(result.score == 0)
        #expect(result.tier == .raw)
        #expect(result.reasons.isEmpty)
    }

    // MARK: - Leverage near liquidation

    @Test func leverageNearLiquidationIsTheTopReason() {
        let input = CookedMeter.Input(
            equityUsd: 10_000,
            holdings: [
                CookedMeter.Holding(symbol: "JUP", valueUsd: 1_000, costUsd: 1_000, unrealizedPnlUsd: 0, liquidityUsd: 10_000_000),
            ],
            leveraged: [
                CookedMeter.LeveragedHolding(
                    symbol: "WIF", isLong: true, leverage: 5,
                    notionalUsd: 2_500, marginUsd: 500, valueUsd: 500,
                    unrealizedPnlUsd: 0, distanceToLiquidationPct: -9.2
                ),
                CookedMeter.LeveragedHolding(
                    symbol: "BONK", isLong: false, leverage: 2,
                    notionalUsd: 400, marginUsd: 200, valueUsd: 200,
                    unrealizedPnlUsd: 0, distanceToLiquidationPct: 45
                ),
            ]
        )
        let result = CookedMeter.score(input)
        #expect(result.reasons.first == "5x long WIF is 9% from liquidation")
        // (40 − 9.2) / 35 × 35 = 30.8 liquidation points, plus 2,900 / 10,000 × 15
        // = 4.35 exposure points.
        #expect(result.score == 35)
        #expect(result.tier == .lightlyToasted)
        #expect(CookedMeter.tip(input).contains("liquidation"))
    }

    @Test func positionAtOrInsideTheDangerDistanceTakesFullLiquidationPoints() {
        let input = CookedMeter.Input(
            equityUsd: 10_000,
            leveraged: [
                CookedMeter.LeveragedHolding(
                    symbol: "BONK", isLong: false, leverage: 10,
                    notionalUsd: 0, marginUsd: 100, valueUsd: 100,
                    unrealizedPnlUsd: 0, distanceToLiquidationPct: 0.4
                ),
            ]
        )
        let result = CookedMeter.score(input)
        #expect(result.score == 35)
        #expect(result.reasons == ["10x short BONK is under 1% from liquidation"])
    }

    @Test func farFromLiquidationGivesNoLiquidationReason() {
        let input = CookedMeter.Input(
            equityUsd: 10_000,
            leveraged: [
                CookedMeter.LeveragedHolding(
                    symbol: "WIF", isLong: true, leverage: 2,
                    notionalUsd: 200, marginUsd: 100, valueUsd: 100,
                    unrealizedPnlUsd: 0, distanceToLiquidationPct: -48
                ),
            ]
        )
        let result = CookedMeter.score(input)
        #expect(!result.reasons.contains { $0.contains("liquidation") })
    }

    // MARK: - Concentration

    @Test func concentrationIsTheReasonWhenOneBagDominates() {
        let input = CookedMeter.Input(
            equityUsd: 10_000,
            holdings: [
                CookedMeter.Holding(symbol: "BONK", valueUsd: 6_500, costUsd: 6_500, unrealizedPnlUsd: 0, liquidityUsd: 9_000_000),
                CookedMeter.Holding(symbol: "JUP", valueUsd: 800, costUsd: 800, unrealizedPnlUsd: 0, liquidityUsd: 18_000_000),
            ]
        )
        let result = CookedMeter.score(input)
        #expect(result.reasons == ["65% of your portfolio is in BONK"])
        // (0.65 − 0.2) / 0.6 × 25 = 18.75 → 19.
        #expect(result.score == 19)
        #expect(result.tier == .raw)
        #expect(CookedMeter.tip(input).contains("biggest bag"))
    }

    @Test func allInOnOneThinLosingTokenIsMedium() {
        let input = CookedMeter.Input(
            equityUsd: 1_000,
            holdings: [
                CookedMeter.Holding(symbol: "FWOG", valueUsd: 1_000, costUsd: 2_000, unrealizedPnlUsd: -1_000, liquidityUsd: 80_000),
            ]
        )
        let result = CookedMeter.score(input)
        // Concentration 25 + drawdown (50% down) 15 + thin liquidity 10.
        #expect(result.score == 50)
        #expect(result.tier == .medium)
        #expect(result.reasons == [
            "100% of your portfolio is in FWOG",
            "Your open positions are down 50% on cost",
        ])
    }

    // MARK: - Bounds

    @Test func wipedOutEquityWithOpenPositionsIsFullyCooked() {
        let input = CookedMeter.Input(
            equityUsd: 0,
            leveraged: [
                CookedMeter.LeveragedHolding(
                    symbol: "WIF", isLong: true, leverage: 10,
                    notionalUsd: 1_000, marginUsd: 100, valueUsd: 0,
                    unrealizedPnlUsd: -100, distanceToLiquidationPct: -1
                ),
            ]
        )
        let result = CookedMeter.score(input)
        #expect(result.score == 100)
        #expect(result.tier == .fullyCooked)
        #expect(result.reasons.count == 1)
    }

    @Test func scoreNeverExceedsOneHundredAndGivesAtMostTwoReasons() {
        let input = CookedMeter.Input(
            equityUsd: 1_000,
            holdings: [
                CookedMeter.Holding(symbol: "FWOG", valueUsd: 900, costUsd: 3_000, unrealizedPnlUsd: -2_100, liquidityUsd: 50_000),
            ],
            leveraged: [
                CookedMeter.LeveragedHolding(
                    symbol: "WIF", isLong: true, leverage: 10,
                    notionalUsd: 5_000, marginUsd: 500, valueUsd: 100,
                    unrealizedPnlUsd: -400, distanceToLiquidationPct: -2
                ),
            ]
        )
        let result = CookedMeter.score(input)
        #expect(result.score == 100)
        #expect(result.tier == .fullyCooked)
        #expect(result.reasons.count == 2)
    }

    @Test(arguments: [
        (40.0, 5.0, 40.0, 0.0),
        (40.0, 5.0, 5.0, 1.0),
        (40.0, 5.0, 22.5, 0.5),
        (40.0, 5.0, 100.0, 0.0),
        (40.0, 5.0, 1.0, 1.0),
        (0.0, 1.0, 0.25, 0.25),
    ])
    func rampIsClampedAndLinear(from: Double, to: Double, value: Double, expected: Double) {
        #expect(abs(CookedMeter.ramp(value, from: from, to: to) - expected) < 0.000_001)
    }
}
