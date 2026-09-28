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
}
