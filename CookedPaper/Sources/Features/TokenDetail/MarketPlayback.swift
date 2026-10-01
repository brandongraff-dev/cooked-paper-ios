import Foundation

/// The LIVE chart's bookkeeping as pure functions over a time-sorted tape, so it can
/// be unit tested without a view: merging batches, slicing what a frame shows, gap
/// detection, and 5-second candles.
///
/// Why playback at all: trades reach the phone in batches (a socket message up to 10×
/// a second, or a 1 s poll), but each one happened at its own moment. Drawing a batch
/// the instant it lands makes the line jump in steps. Instead the chart's playhead
/// runs `displayDelayMs` behind the server clock and reveals each trade when the
/// playhead reaches its own timestamp — the same tape, played back as the continuous
/// stream it was. Fills never use this delayed price; the server fills at its newest.
enum MarketPlayback {
    static let defaultDelayMs = 1500
    static let delayRangeMs = 500...5000

    /// How long a feed keeps trades: longer than any window the chart shows, short
    /// enough that a busy token's tape stays small.
    static let retentionMs: Int64 = 600_000

    /// The server's `displayDelayMs`, clamped so a bad value can't park the chart
    /// minutes in the past or run it ahead of the batches.
    static func clampDelay(_ ms: Int?) -> Int {
        guard let ms else { return defaultDelayMs }
        return min(max(ms, delayRangeMs.lowerBound), delayRangeMs.upperBound)
    }

    // MARK: - Searching

    /// Index of the first point at or after `t` (`count` if none).
    static func lowerBound(_ tape: [TapePoint], t: Int64) -> Int {
        var low = 0, high = tape.count
        while low < high {
            let mid = (low + high) / 2
            if tape[mid].t < t { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Index of the first point strictly after `t` (`count` if none).
    static func upperBound(_ tape: [TapePoint], t: Int64) -> Int {
        var low = 0, high = tape.count
        while low < high {
            let mid = (low + high) / 2
            if tape[mid].t <= t { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// The newest point the playhead has reached, or nil if it hasn't reached any.
    static func playheadIndex(_ tape: [TapePoint], at playhead: Int64) -> Int? {
        let index = upperBound(tape, t: playhead) - 1
        return index >= 0 ? index : nil
    }

    /// What a frame draws: every point from `start` to the playhead, plus the one
    /// before `start` so the line enters from the left edge instead of mid-air.
    static func visibleRange(_ tape: [TapePoint], from start: Int64, to playhead: Int64) -> ClosedRange<Int>? {
        guard let last = playheadIndex(tape, at: playhead) else { return nil }
        let first = max(0, min(lowerBound(tape, t: start) - 1, last))
        return first...last
    }

    // MARK: - Maintaining the tape

    /// Adds `incoming` to `tape`, skipping ids already seen and keeping the tape
    /// sorted by time. Equal timestamps keep arrival order (a transaction's inner
    /// swaps share a block time). Returns how many points were added.
    @discardableResult
    static func merge(_ incoming: [TapePoint], into tape: inout [TapePoint], ids: inout Set<String>) -> Int {
        guard !incoming.isEmpty else { return 0 }
        let sorted = incoming.enumerated()
            .sorted { $0.element.t != $1.element.t ? $0.element.t < $1.element.t : $0.offset < $1.offset }
            .map(\.element)
        var added = 0
        for point in sorted {
            guard ids.insert(point.id).inserted else { continue }
            // Almost always newer than everything held: append without searching.
            if let last = tape.last, point.t < last.t {
                tape.insert(point, at: upperBound(tape, t: point.t))
            } else {
                tape.append(point)
            }
            added += 1
        }
        return added
    }

    /// Drops points older than `cutoff`, forgetting their ids too.
    static func trim(_ tape: inout [TapePoint], ids: inout Set<String>, before cutoff: Int64) {
        let count = lowerBound(tape, t: cutoff)
        guard count > 0 else { return }
        for point in tape[..<count] { ids.remove(point.id) }
        tape.removeFirst(count)
    }

    /// A server restart's fresh snapshot is the authority for the span it covers:
    /// anything held from inside that span is dropped (it may be from the old
    /// server's view), older history is kept so the line doesn't vanish.
    static func dropOverlap(of snapshot: [TapePoint], from tape: inout [TapePoint], ids: inout Set<String>) {
        guard let oldest = snapshot.map(\.t).min() else { return }
        let keep = lowerBound(tape, t: oldest)
        for point in tape[keep...] { ids.remove(point.id) }
        tape.removeSubrange(keep...)
    }

    /// True when a socket batch doesn't follow on from the last seq seen — i.e.
    /// trades were missed and must be fetched with `?sinceSeq=`. A batch of n
    /// trades ending at `batchSeq` starts at `batchSeq - n + 1`.
    static func hasGap(lastSeq: Int?, batchSeq: Int, batchCount: Int) -> Bool {
        guard let lastSeq else { return false }
        return batchSeq - batchCount > lastSeq
    }

    // MARK: - Candles

    /// Buckets of `bucketMs` from `start` through `playhead`: the snapshot's 1 s
    /// candles folded up, overlaid with buckets built from the tape itself (which is
    /// newer and trade-exact). The last bucket is the one still growing. Empty
    /// buckets are left out — a quiet stretch is a gap, not a flat candle.
    static func candles(
        tape: [TapePoint],
        oneSecond: [LiveCandle],
        from start: Int64,
        through playhead: Int64,
        bucketMs: Int64
    ) -> [LiveCandle] {
        func bucket(_ t: Int64) -> Int64 {
            // Floor division that also holds for (theoretical) negative times.
            let q = t / bucketMs
            return (t % bucketMs < 0 ? q - 1 : q) * bucketMs
        }
        let firstBucket = bucket(start)
        var byBucket: [Int64: LiveCandle] = [:]

        for candle in oneSecond where candle.t >= firstBucket && candle.t <= playhead {
            let key = bucket(candle.t)
            if var existing = byBucket[key] {
                existing.high = max(existing.high, candle.high)
                existing.low = min(existing.low, candle.low)
                if candle.t >= existing.t { existing.close = candle.close } else { existing.open = candle.open }
                existing.volume += candle.volume
                existing.t = min(existing.t, candle.t)
                byBucket[key] = existing
            } else {
                byBucket[key] = candle
            }
        }

        var fromTape: [Int64: LiveCandle] = [:]
        if let range = visibleRange(tape, from: firstBucket, to: playhead) {
            for point in tape[range] where point.t >= firstBucket {
                let key = bucket(point.t)
                if var existing = fromTape[key] {
                    existing.high = max(existing.high, point.price)
                    existing.low = min(existing.low, point.price)
                    existing.close = point.price
                    existing.volume += point.amountUsd
                    fromTape[key] = existing
                } else {
                    fromTape[key] = LiveCandle(t: key, open: point.price, high: point.price, low: point.price, close: point.price, volume: point.amountUsd)
                }
            }
        }
        for (key, candle) in fromTape { byBucket[key] = candle }

        return byBucket
            .map { key, candle in
                var normalized = candle
                normalized.t = key
                return normalized
            }
            .sorted { $0.t < $1.t }
    }

    // MARK: - Dots

    /// Trade-dot radius: area grows with dollars (√amount), $5 → 2 pt up to $5,000
    /// and beyond → 7 pt, so whales read at a glance and dust stays out of the way.
    static func dotRadius(amountUsd: Double) -> Double {
        let low = 5.0.squareRoot(), high = 5000.0.squareRoot()
        let fraction = (max(amountUsd, 0).squareRoot() - low) / (high - low)
        return min(max(2 + 5 * fraction, 2), 7)
    }
}
