import Foundation
import Testing

@testable import CookedPaper

struct PaperModelDecodingTests {
    @Test func decodesPortfolioSnapshotWithAnUnpricedPosition() throws {
        let json = Data(
            """
            {
              "portfolio": {
                "id": "pf_1",
                "name": "Main",
                "startingBalanceUsd": "1000.00",
                "cashUsd": "812.34",
                "createdAt": "2026-08-01T00:00:00.000Z",
                "resetAt": null,
                "resetCount": 0,
                "archivedAt": null,
                "isGuest": false
              },
              "portfolioId": "pf_1",
              "cashUsd": "812.34",
              "positionsValueUsd": "300.00",
              "equityUsd": "1112.34",
              "positions": [
                {
                  "tokenMint": "So11111111111111111111111111111111111111112",
                  "qty": "12.5",
                  "costUsd": "300.00",
                  "avgCostUsd": "24.00",
                  "markPriceUsd": "24.00",
                  "markState": "fresh",
                  "markFromLastFill": true,
                  "valueUsd": "300.00",
                  "unrealizedPnlUsd": null,
                  "unrealizedReturnPct": null,
                  "roundTripCount": 0,
                  "token": {
                    "mint": "So11111111111111111111111111111111111111112",
                    "symbol": "SOL",
                    "name": "Wrapped SOL",
                    "hasLogo": true,
                    "isVerified": true
                  },
                  "marketCapUsd": null,
                  "liquidityUsd": null
                }
              ],
              "roundTrips": [
                {
                  "tokenMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                  "qty": "40",
                  "costUsd": "80.00",
                  "proceedsUsd": "95.50",
                  "realizedPnlUsd": "15.50",
                  "returnPct": "19.375",
                  "openedAt": "2026-08-02T00:00:00.000Z",
                  "closedAt": "2026-08-03T00:00:00.000Z",
                  "closingTradeId": "trd_9",
                  "token": null
                }
              ],
              "stats": {
                "returnPct": { "pct": "11.34", "sampleSize": 4, "sampleOf": "trades", "unavailable": null },
                "winRatePct": { "pct": "75.00", "sampleSize": 4, "sampleOf": "roundTrips", "unavailable": null },
                "maxDrawdownPct": { "pct": null, "sampleSize": 0, "sampleOf": "equityCurve", "unavailable": "insufficient_history" },
                "realizedPnlUsd": { "usd": "15.50", "sampleSize": 1, "sampleOf": "roundTrips", "unavailable": null },
                "unrealizedPnlUsd": { "usd": null, "sampleSize": 0, "sampleOf": "positions", "unavailable": "unpriced" },
                "feesPaidUsd": "0.00",
                "tradeCount": 5,
                "roundTripCount": 1,
                "winCount": 1,
                "lossCount": 0
              },
              "equityCurve": {
                "maxDrawdownPct": "0.00",
                "peakEquityUsd": "1112.34",
                "points": [
                  { "at": "2026-08-01T00:00:00.000Z", "equityUsd": "1000.00", "kind": "open" },
                  { "at": "2026-08-03T00:00:00.000Z", "equityUsd": "1112.34", "kind": "trade" }
                ]
              }
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(PaperSnapshotResponse.self, from: json)

        #expect(decoded.portfolio.id == "pf_1")
        #expect(decoded.portfolio.isGuest == false)
        #expect(decoded.positions.count == 1)

        let position = try #require(decoded.positions.first)
        #expect(position.markFromLastFill == true)
        // Null exactly because markFromLastFill is true — must decode to nil,
        // never coerce to 0, per PaperModels.swift's own comment.
        #expect(position.unrealizedPnlUsd == nil)
        #expect(position.qty == Decimal(string: "12.5"))
        #expect(position.token?.symbol == "SOL")
        #expect(position.marketCapUsd == nil)

        let roundTrip = try #require(decoded.roundTrips.first)
        #expect(roundTrip.closingTradeId == "trd_9")
        #expect(roundTrip.realizedPnlUsd == Decimal(string: "15.50"))
        #expect(roundTrip.returnPct == Decimal(string: "19.375"))
        #expect(roundTrip.token == nil)

        #expect(decoded.stats.maxDrawdownPct.unavailable == "insufficient_history")
        #expect(decoded.stats.maxDrawdownPct.pct == nil)
        #expect(decoded.stats.tradeCount == 5)
        #expect(decoded.equityCurve.points.count == 2)
        // A server without leverage omits these keys entirely; that must still decode.
        #expect(decoded.leveragedPositions == nil)
        #expect(decoded.leveragedValueUsd == nil)
    }

    @Test(arguments: ["buy", "sell"])
    func decodesTradeSideForBothDirections(_ raw: String) throws {
        let json = Data(
            """
            {
              "id": "trd_1",
              "tokenMint": "So11111111111111111111111111111111111111112",
              "side": "\(raw)",
              "qty": "2.5",
              "priceUsd": "24.10",
              "valueUsd": "60.25",
              "slippageBps": 12,
              "priceImpactBps": 4,
              "marketCapUsd": null,
              "executedAt": "2026-08-02T00:00:00.000Z"
            }
            """.utf8
        )

        let trade = try JSONDecoder().decode(PaperTrade.self, from: json)
        #expect(trade.qty == Decimal(string: "2.5"))
        #expect(trade.marketCapUsd == nil)

        switch raw {
        case "buy": #expect(trade.side == .buy)
        case "sell": #expect(trade.side == .sell)
        default: Issue.record("unexpected trade side fixture: \(raw)")
        }
    }

    @Test func decodesATradesResponseListWithMixedSides() throws {
        let json = Data(
            """
            {
              "trades": [
                {
                  "id": "trd_1",
                  "tokenMint": "So11111111111111111111111111111111111111112",
                  "side": "buy",
                  "qty": "2.5",
                  "priceUsd": "24.10",
                  "valueUsd": "60.25",
                  "slippageBps": 12,
                  "priceImpactBps": 4,
                  "marketCapUsd": "125000000.50",
                  "executedAt": "2026-08-02T00:00:00.000Z"
                },
                {
                  "id": "trd_2",
                  "tokenMint": "So11111111111111111111111111111111111111112",
                  "side": "sell",
                  "qty": "1.0",
                  "priceUsd": "25.00",
                  "valueUsd": "25.00",
                  "slippageBps": 8,
                  "priceImpactBps": 2,
                  "marketCapUsd": null,
                  "executedAt": "2026-08-03T00:00:00.000Z"
                }
              ]
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(PaperTradesResponse.self, from: json)
        #expect(decoded.trades.count == 2)
        #expect(decoded.trades[0].side == .buy)
        #expect(decoded.trades[1].side == .sell)
        #expect(decoded.trades[0].marketCapUsd == Decimal(string: "125000000.50"))
    }

    @Test func decodesALiquidatableLongAndAnUnmeasuredShort() throws {
        let json = Data(
            """
            {
              "positions": [
                {
                  "id": "lev_1", "tokenMint": "Mint1", "chain": "solana",
                  "token": {"mint": "Mint1", "symbol": "WIF", "name": "dogwifhat", "hasLogo": true, "isVerified": true},
                  "direction": "long", "leverage": 5, "status": "open", "source": "manual",
                  "entryPriceUsd": "1.745", "entryMidPriceUsd": "1.74", "qtyOpened": "1432.66", "qty": "1432.66",
                  "notionalUsd": "2500.00", "marginUsd": "500.00", "initialMarginUsd": "500.00",
                  "maintenanceMarginBps": 100, "liquidationPriceUsd": "1.41010101", "bankruptcyPriceUsd": "1.396",
                  "markPriceUsd": "1.8342", "markState": "fresh", "markAgeMs": 900, "markFromLastFill": false,
                  "valueUsd": "627.79", "unrealizedPnlUsd": "127.79", "unrealizedReturnOnMarginPct": "25.56",
                  "unrealizedUnavailable": null, "distanceToLiquidationPct": "-23.12",
                  "realizedPnlUsd": "0", "shortfallUsd": "0", "liquidityUsd": "22014330",
                  "openedAt": "2026-09-28T10:00:00Z", "closedAt": null, "fills": []
                },
                {
                  "id": "lev_2", "tokenMint": "Mint2", "chain": "solana", "token": null,
                  "direction": "short", "leverage": 10, "status": "open", "source": "manual",
                  "entryPriceUsd": "0.0000225", "entryMidPriceUsd": "0.0000225", "qtyOpened": "133333333", "qty": "133333333",
                  "notionalUsd": "3000.00", "marginUsd": "300.00", "initialMarginUsd": "300.00",
                  "maintenanceMarginBps": 100, "liquidationPriceUsd": "0.0000245", "bankruptcyPriceUsd": "0.00002475",
                  "markPriceUsd": null, "markState": null, "markAgeMs": null, "markFromLastFill": true,
                  "valueUsd": "300.00", "unrealizedPnlUsd": null, "unrealizedReturnOnMarginPct": null,
                  "unrealizedUnavailable": "unmeasured", "distanceToLiquidationPct": null,
                  "realizedPnlUsd": "0", "shortfallUsd": "0", "liquidityUsd": null,
                  "openedAt": "2026-09-28T10:00:00Z", "closedAt": null, "fills": []
                }
              ]
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(PaperLeveragedListResponse.self, from: json)
        #expect(decoded.positions.count == 2)

        let long = decoded.positions[0]
        #expect(long.direction == .long)
        #expect(long.label == "5x Long")
        #expect(long.liquidationPriceUsd == Decimal(string: "1.41010101"))
        #expect(long.unrealizedPnlUsd == Decimal(string: "127.79"))

        // Unmeasured is nil, never zero.
        let short = decoded.positions[1]
        #expect(short.direction == .short)
        #expect(short.markPriceUsd == nil)
        #expect(short.unrealizedPnlUsd == nil)
        #expect(short.distanceToLiquidationPct == nil)
    }
}
