import Foundation
import Testing

@testable import CookedPaper

/// The live-market contract's JSON (v1) and the LIVE chart's playback bookkeeping.
struct MarketLiveDecodingTests {
    private func decode(_ json: String) throws -> LiveMarketSnapshot {
        try JSONDecoder().decode(LiveMarketSnapshot.self, from: Data(json.utf8))
    }

    @Test func decodesAFullSnapshot() throws {
        let snapshot = try decode(
            """
            {
              "mint": "EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm",
              "seq": 1234,
              "serverTime": 1759110001000,
              "displayDelayMs": 1500,
              "status": { "state": "live", "source": "chain", "lagMs": 900, "poolAddress": "Pool111", "dex": "raydium" },
              "price": { "value": "1.8342", "t": 1759110000123, "source": "chain" },
              "trades": [
                { "id": "sigA:0", "t": 1759110000000, "slot": 312345677, "price": "1.8301", "side": "sell", "amountUsd": "4999.99", "source": "chain" },
                { "id": "sigB:1", "t": 1759110000123, "slot": 312345678, "price": "1.8342", "side": "buy", "amountUsd": "123.45", "source": "geckoterminal" },
                { "id": "jup:1", "t": 1759110000200, "slot": null, "price": "1.8340", "side": "buy", "amountUsd": "0", "source": "jupiter" }
              ],
              "candles1s": [
                { "t": 1759110000000, "o": "1.8301", "h": "1.8342", "l": "1.8301", "c": "1.8342", "v": "5123.44" }
              ]
            }
            """
        )
        #expect(snapshot.seq == 1234)
        #expect(snapshot.serverTime == 1_759_110_001_000)
        #expect(snapshot.displayDelayMs == 1500)
        #expect(snapshot.status.state == .live)
        #expect(snapshot.status.source == .chain)
        #expect(snapshot.status.dex == "raydium")
        #expect(snapshot.price?.value == Decimal(string: "1.8342"))
        #expect(snapshot.reset == false)
        #expect(snapshot.trades.count == 3)
        #expect(snapshot.trades[0].price == Decimal(string: "1.8301"))
        #expect(snapshot.trades[0].amountUsd == Decimal(string: "4999.99"))
        #expect(snapshot.trades[0].side == .sell)
        #expect(snapshot.trades[1].slot == 312_345_678)
        #expect(snapshot.trades[2].slot == nil)
        #expect(snapshot.candles1s.first?.c == Decimal(string: "1.8342"))
        #expect(snapshot.candles1s.first?.v == Decimal(string: "5123.44"))

        // Swaps become dots; a Jupiter quote is a line point only.
        let points = snapshot.trades.map(TapePoint.init)
        #expect(points.map(\.kind) == [.sell, .buy, .observation])
        #expect(points[1].priceDecimal == Decimal(string: "1.8342"))
        #expect(abs(points[1].price - 1.8342) < 1e-12)
    }

    @Test func decodesAnIncrementalResponseWithoutCandles() throws {
        let snapshot = try decode(
            """
            {
              "mint": "m", "seq": 1236, "serverTime": 1759110002000, "displayDelayMs": 1500,
              "status": { "state": "live", "source": "chain", "lagMs": 400, "poolAddress": null, "dex": null },
              "price": { "value": "0.00002314", "t": 1759110001900, "source": "chain" },
              "trades": [
                { "id": "sigC:0", "t": 1759110001900, "slot": 1, "price": "0.00002314", "side": "buy", "amountUsd": "12.00", "source": "chain" }
              ]
            }
            """
        )
        #expect(snapshot.candles1s.isEmpty)
        #expect(snapshot.reset == false)
        #expect(snapshot.status.poolAddress == nil)
        #expect(snapshot.status.dex == nil)
        #expect(snapshot.trades.first?.price == Decimal(string: "0.00002314"))
    }

    @Test func decodesAReset() throws {
        let snapshot = try decode(
            """
            {
              "mint": "m", "seq": 7, "serverTime": 1759110002000, "displayDelayMs": 2500, "reset": true,
              "status": { "state": "live", "source": "chain", "lagMs": 400, "poolAddress": null, "dex": "pumpswap" },
              "price": null, "trades": [], "candles1s": []
            }
            """
        )
        #expect(snapshot.reset)
        #expect(snapshot.seq == 7)
        #expect(snapshot.price == nil)
        #expect(MarketPlayback.clampDelay(snapshot.displayDelayMs) == 2500)
    }

    @Test func decodesADegradedFirstResponse() throws {
        let snapshot = try decode(
            """
            {
              "mint": "m", "seq": 0, "serverTime": 1759110002000, "displayDelayMs": 9000,
              "status": { "state": "degraded", "source": "dexscreener", "lagMs": null, "poolAddress": null, "dex": null },
              "price": { "value": "0.4412", "t": 1759110001000, "source": "dexscreener" },
              "trades": [], "candles1s": []
            }
            """
        )
        #expect(snapshot.status.state == .degraded)
        #expect(snapshot.status.source == .dexscreener)
        #expect(snapshot.status.lagMs == nil)
        #expect(snapshot.price?.value == Decimal(string: "0.4412"))
        // A server asking for more than 5 s is clamped.
        #expect(MarketPlayback.clampDelay(snapshot.displayDelayMs) == 5000)
    }

    @Test func unknownSourcesAndStatesDecodeCautiously() throws {
        let status = try JSONDecoder().decode(
            MarketStatus.self,
            from: Data(#"{ "state": "warming", "source": "birdeye", "lagMs": 1, "poolAddress": null, "dex": null }"#.utf8)
        )
        #expect(status.state == .degraded)
        #expect(status.source == .other)
    }

    @Test func decodesSocketMessages() throws {
        let trades = try JSONDecoder().decode(
            MarketTradesMessage.self,
            from: Data(#"{ "mint": "m", "seq": 12, "trades": [ { "id": "s:0", "t": 5, "slot": 1, "price": "2", "side": "sell", "amountUsd": "9", "source": "chain" } ] }"#.utf8)
        )
        #expect(trades.seq == 12)
        #expect(trades.trades.first?.side == .sell)

        let status = try JSONDecoder().decode(
            MarketStatusMessage.self,
            from: Data(#"{ "mint": "m", "status": { "state": "stale", "source": "jupiter", "lagMs": 30000, "poolAddress": null, "dex": null } }"#.utf8)
        )
        #expect(status.status.state == .stale)
    }

    @Test func rejectsANumericPrice() {
        // Money is always a decimal string; a JSON number is a contract break.
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                MarketTrade.self,
                from: Data(#"{ "id": "s:0", "t": 5, "slot": 1, "price": 2.5, "side": "buy", "amountUsd": "9", "source": "chain" }"#.utf8)
            )
        }
    }
}

struct MarketPlaybackTests {
    /// Whole-number prices, so the Decimal → Double conversion is exact.
    private func point(_ id: String, _ t: Int64, _ price: Int = 1, kind: TapePoint.Kind = .buy) -> TapePoint {
        TapePoint(id: id, t: t, price: Decimal(price), amountUsd: 10, kind: kind)
    }

    @Test func mergeDedupesAndKeepsTimeOrder() {
        var tape: [TapePoint] = []
        var ids = Set<String>()
        #expect(MarketPlayback.merge([point("b", 200), point("a", 100)], into: &tape, ids: &ids) == 2)
        // A late-arriving older trade slots into place; a repeat is ignored.
        #expect(MarketPlayback.merge([point("c", 150), point("a", 100), point("d", 300)], into: &tape, ids: &ids) == 2)
        #expect(tape.map(\.id) == ["a", "c", "b", "d"])
        #expect(ids == ["a", "b", "c", "d"])
    }

    @Test func equalTimestampsKeepArrivalOrder() {
        var tape: [TapePoint] = []
        var ids = Set<String>()
        MarketPlayback.merge([point("x:0", 100), point("x:1", 100), point("x:2", 100)], into: &tape, ids: &ids)
        MarketPlayback.merge([point("y:0", 100)], into: &tape, ids: &ids)
        #expect(tape.map(\.id) == ["x:0", "x:1", "x:2", "y:0"])
    }

    @Test func playheadRevealsTradesAtTheirOwnTimes() {
        let tape = [point("a", 100), point("b", 200), point("c", 300)]
        #expect(MarketPlayback.playheadIndex(tape, at: 99) == nil)
        #expect(MarketPlayback.playheadIndex(tape, at: 100) == 0)
        #expect(MarketPlayback.playheadIndex(tape, at: 299) == 1)
        #expect(MarketPlayback.playheadIndex(tape, at: 300) == 2)
        #expect(MarketPlayback.playheadIndex(tape, at: 10_000) == 2)
        #expect(MarketPlayback.playheadIndex([], at: 10_000) == nil)
    }

    @Test func visibleRangeIncludesOnePointBeforeTheWindow() {
        let tape = (0..<10).map { point("p\($0)", Int64($0) * 100) }
        // Window 350...720: points 4...7 are inside, 3 is the lead-in, 8+ not yet played.
        #expect(MarketPlayback.visibleRange(tape, from: 350, to: 720) == 3...7)
        // Window starting before the tape: nothing to lead in with.
        #expect(MarketPlayback.visibleRange(tape, from: -50, to: 250) == 0...2)
        // Only the lead-in has been played: it alone is drawn.
        #expect(MarketPlayback.visibleRange(tape, from: 950, to: 960) == 9...9)
        #expect(MarketPlayback.visibleRange(tape, from: 0, to: -1) == nil)
    }

    @Test func trimForgetsOldIds() {
        var tape = [point("a", 100), point("b", 200), point("c", 300)]
        var ids: Set<String> = ["a", "b", "c"]
        MarketPlayback.trim(&tape, ids: &ids, before: 250)
        #expect(tape.map(\.id) == ["c"])
        #expect(ids == ["c"])
        // A trimmed trade that shows up again is accepted as new.
        #expect(MarketPlayback.merge([point("a", 100)], into: &tape, ids: &ids) == 1)
    }

    @Test func resetDropsTheOverlappedSpanOnly() {
        var tape = [point("old", 100), point("mid", 200), point("stale", 300)]
        var ids: Set<String> = ["old", "mid", "stale"]
        let fresh = [point("n1", 200), point("n2", 400)]
        MarketPlayback.dropOverlap(of: fresh, from: &tape, ids: &ids)
        MarketPlayback.merge(fresh, into: &tape, ids: &ids)
        #expect(tape.map(\.id) == ["old", "n1", "n2"])
    }

    @Test func detectsSeqGaps() {
        #expect(!MarketPlayback.hasGap(lastSeq: nil, batchSeq: 50, batchCount: 1))
        #expect(!MarketPlayback.hasGap(lastSeq: 10, batchSeq: 13, batchCount: 3)) // 11...13
        #expect(MarketPlayback.hasGap(lastSeq: 10, batchSeq: 14, batchCount: 3)) // 12...14, missed 11
        #expect(!MarketPlayback.hasGap(lastSeq: 10, batchSeq: 9, batchCount: 2)) // old, dedupe handles it
    }

    @Test func clampsTheDisplayDelay() {
        #expect(MarketPlayback.clampDelay(nil) == 1500)
        #expect(MarketPlayback.clampDelay(100) == 500)
        #expect(MarketPlayback.clampDelay(2000) == 2000)
        #expect(MarketPlayback.clampDelay(60_000) == 5000)
    }

    @Test func buildsFiveSecondCandlesUpToThePlayhead() {
        let tape = [
            point("a", 10_000, 10), point("b", 11_000, 14), point("c", 12_000, 8), point("d", 14_999, 11),
            point("e", 15_000, 12), point("f", 16_000, 13),
            point("future", 21_000, 90),
        ]
        let oneSecond = [LiveCandle(t: 5_000, open: 9, high: 10, low: 8.5, close: 9.5, volume: 3)]
        let candles = MarketPlayback.candles(tape: tape, oneSecond: oneSecond, from: 5_000, through: 16_500, bucketMs: 5_000)
        #expect(candles.map(\.t) == [5_000, 10_000, 15_000])
        #expect(candles[0] == oneSecond[0])
        #expect(candles[1].open == 10)
        #expect(candles[1].high == 14)
        #expect(candles[1].low == 8)
        #expect(candles[1].close == 11)
        #expect(candles[1].volume == 40)
        // The growing candle stops at the playhead: the future trade isn't in it.
        #expect(candles[2].close == 13)
        #expect(candles[2].high == 13)
    }

    @Test func dotRadiusScalesWithDollarsWithinBounds() {
        #expect(MarketPlayback.dotRadius(amountUsd: 0) == 2)
        #expect(MarketPlayback.dotRadius(amountUsd: 5) == 2)
        #expect(abs(MarketPlayback.dotRadius(amountUsd: 5000) - 7) < 1e-9)
        #expect(MarketPlayback.dotRadius(amountUsd: 1_000_000) == 7)
        #expect(MarketPlayback.dotRadius(amountUsd: 1000) > MarketPlayback.dotRadius(amountUsd: 100))
    }
}
