import Foundation
import SwiftUI

/// A chart that plays the market back trade by trade: the playhead runs a moment
/// behind the server clock (`MarketFeed.playheadMs`), each trade appears when the
/// playhead reaches its own timestamp, the newest price eases in over a quarter
/// second instead of jumping, and the y-range glides to fit. The market's own trades
/// stay a clean line; only the person's buys and sells are marked (a "+" or "−" in a
/// circle). Drawn with one `Canvas` in a
/// `TimelineView(.animation)`, so it redraws at the display's refresh rate (up to
/// 120 Hz on ProMotion).
struct LiveChartView: View {
    enum Style {
        case line
        /// 5-second candles, the newest one growing live.
        case candles
    }

    let feed: MarketFeed
    /// Seconds of history across the width.
    var window: TimeInterval = 90
    /// Line color. Callers pass the day's direction so the chart agrees with the
    /// header's change; nil colors by the visible window's own direction.
    var color: Color? = nil
    var style: Style = .line
    /// The person's own buys and sells on this token.
    var markers: [ChartTradeMarker] = []

    @State private var renderer = LiveChartRenderer()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let stillFrames = ProcessInfo.processInfo.environment["UITEST_STILL_FRAMES"] == "1"

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: Self.stillFrames)) { context in
            let now = Self.stillFrames ? Date() : context.date
            let frame = LiveChartFrame(
                tape: feed.tape,
                oneSecond: feed.oneSecondCandles,
                playhead: feed.playheadMs(at: now),
                now: now,
                windowMs: Int64(window * 1000),
                color: color,
                style: style,
                markers: markers,
                animated: !Self.stillFrames,
                pulses: !Self.stillFrames && !reduceMotion
            )
            Canvas { graphics, size in
                renderer.draw(in: &graphics, size: size, frame: frame)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Live price chart")
        .accessibilityValue(feed.latestPrice.map { PriceFormat.price($0) } ?? "Loading")
    }
}

/// Everything one frame needs, gathered outside the `Canvas` closure.
struct LiveChartFrame {
    let tape: [TapePoint]
    let oneSecond: [LiveCandle]
    /// Epoch ms the chart is showing (server time minus the display delay).
    let playhead: Int64
    /// Wall-clock time of the frame; easing runs on this.
    let now: Date
    let windowMs: Int64
    let color: Color?
    let style: LiveChartView.Style
    let markers: [ChartTradeMarker]
    let animated: Bool
    /// The breathing ring on the head; off under Reduce Motion.
    let pulses: Bool
}

/// Per-frame drawing plus the state that makes motion continuous (eased head,
/// smoothed y-range) and a few buffers reused across frames so steady-state drawing
/// doesn't allocate. A plain class so writing to it while drawing doesn't
/// invalidate the view.
final class LiveChartRenderer {
    private var headFrom: Double?
    private var headTo: Double?
    private var headStart = Date.distantPast
    private var headId: String?
    private var yLow: Double?
    private var yHigh: Double?
    private var lastFrame: Date?
    private var coords: [CGPoint] = []
    private var tagText: (id: String, text: String)?
    private var candleCache: (key: CandleKey, candles: [LiveCandle])?

    private struct CandleKey: Equatable {
        let count: Int
        let lastId: String?
        let playIndex: Int
        let oneSecondCount: Int
        let firstBucket: Int64
    }

    private static let easeDuration: TimeInterval = 0.25
    private static let tagWidth: CGFloat = 76
    static let bucketMs: Int64 = 5000
    /// Beyond this many points in view, the line samples every nth one — more than
    /// the screen has pixels for.
    private static let maxLinePoints = 1200

    func draw(in graphics: inout GraphicsContext, size: CGSize, frame: LiveChartFrame) {
        let tape = frame.tape
        guard size.width > Self.tagWidth,
              let playIndex = MarketPlayback.playheadIndex(tape, at: frame.playhead)
        else { return }
        let current = tape[playIndex]

        // Ease from wherever the head was drawn toward each trade the playhead reaches.
        if current.id != headId || headTo == nil {
            headFrom = frame.animated ? currentHead(now: frame.now) ?? current.price : current.price
            headTo = current.price
            headStart = frame.now
            headId = current.id
        }
        let head = currentHead(now: frame.now) ?? current.price

        // Candles keep the right edge one bucket past the playhead so the growing
        // candle has room; the line ends exactly at the playhead.
        let rightEdge = frame.style == .candles ? frame.playhead + Self.bucketMs : frame.playhead
        let start = rightEdge - frame.windowMs
        let range = MarketPlayback.visibleRange(tape, from: start, to: frame.playhead) ?? playIndex...playIndex

        var candles: [LiveCandle] = []
        var low = head, high = head
        switch frame.style {
        case .line:
            for index in range {
                let price = tape[index].price
                low = min(low, price)
                high = max(high, price)
            }
        case .candles:
            candles = liveCandles(frame: frame, playIndex: playIndex, start: start, head: head)
            for candle in candles {
                low = min(low, candle.low)
                high = max(high, candle.high)
            }
        }

        // Y-range: fit what's visible, with a floor so a flat price isn't magnified
        // into noise, then glide there rather than snap.
        let minSpan = max(head * 0.004, 1e-12)
        if high - low < minSpan {
            let mid = (high + low) / 2
            low = mid - minSpan / 2
            high = mid + minSpan / 2
        }
        let pad = (high - low) * 0.18
        low -= pad
        high += pad
        let dt = lastFrame.map { min(max(frame.now.timeIntervalSince($0), 0), 0.1) } ?? 1
        lastFrame = frame.now
        let blend = frame.animated ? 1 - exp(-dt * 7) : 1
        yLow = (yLow ?? low) + (low - (yLow ?? low)) * blend
        yHigh = (yHigh ?? high) + (high - (yHigh ?? high)) * blend
        let lo = yLow ?? low, hi = max(yHigh ?? high, lo + 1e-12)

        let plotWidth = size.width - Self.tagWidth
        let top: CGFloat = 12, bottom: CGFloat = 12
        let plotHeight = size.height - top - bottom
        let windowMs = Double(frame.windowMs)
        func x(_ t: Int64) -> CGFloat {
            plotWidth * CGFloat(1 - Double(rightEdge - t) / windowMs)
        }
        func y(_ price: Double) -> CGFloat {
            top + plotHeight * CGFloat(1 - (price - lo) / (hi - lo))
        }

        let color: Color = frame.color ?? (head >= tape[range.lowerBound].price ? .positive : .negative)
        let headY = y(head)

        switch frame.style {
        case .line:
            drawLine(in: &graphics, size: size, tape: tape, range: range, head: head, x: x, y: y, plotWidth: plotWidth, top: top, color: color)
        case .candles:
            drawCandles(in: &graphics, candles: candles, x: x, y: y, plotWidth: plotWidth, windowMs: windowMs)
        }

        // The person's own trades, once the playhead has reached them, pinned to the
        // line at that moment (the newest one rides the eased head).
        for marker in frame.markers where marker.t <= frame.playhead {
            let px = x(marker.t)
            guard px >= 0, px <= plotWidth,
                  let index = MarketPlayback.playheadIndex(tape, at: marker.t) else { continue }
            let py = index == playIndex ? headY : y(tape[index].price)
            ChartTradeMarkers.draw(marker.kind, at: CGPoint(x: px, y: min(max(py, top), size.height - bottom)), in: &graphics)
        }

        // Dashed guide at the current price, across the plot to the tag.
        var guide = Path()
        guide.move(to: CGPoint(x: 0, y: headY))
        guide.addLine(to: CGPoint(x: size.width, y: headY))
        graphics.stroke(guide, with: .color(Color.textTertiary.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

        if frame.style == .line {
            // The head: a dot at the playhead, breathing unless motion is reduced.
            let headPoint = CGPoint(x: plotWidth, y: headY)
            if frame.pulses {
                let phase = frame.now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                let ring = 4 + 10 * phase
                graphics.fill(
                    Path(ellipseIn: CGRect(x: headPoint.x - ring, y: headPoint.y - ring, width: ring * 2, height: ring * 2)),
                    with: .color(color.opacity(0.35 * (1 - phase)))
                )
            }
            graphics.fill(
                Path(ellipseIn: CGRect(x: headPoint.x - 4, y: headPoint.y - 4, width: 8, height: 8)),
                with: .color(color)
            )
        }

        // Price tag riding the right edge: the playhead trade's exact price (what the
        // header shows), while its position eases.
        if tagText?.id != current.id {
            tagText = (current.id, PriceFormat.price(current.priceDecimal))
        }
        let label = Text(tagText?.text ?? "")
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundColor(.black)
        let resolved = graphics.resolve(label)
        let textSize = resolved.measure(in: CGSize(width: Self.tagWidth, height: 20))
        let tagHeight: CGFloat = 22
        let tagY = min(max(headY - tagHeight / 2, 0), size.height - tagHeight)
        let tagRect = CGRect(x: plotWidth + 8, y: tagY, width: min(textSize.width + 12, Self.tagWidth - 8), height: tagHeight)
        graphics.fill(Path(roundedRect: tagRect, cornerRadius: 6), with: .color(color))
        graphics.draw(resolved, at: CGPoint(x: tagRect.midX, y: tagRect.midY), anchor: .center)
    }

    // MARK: - Line

    private func drawLine(
        in graphics: inout GraphicsContext,
        size: CGSize,
        tape: [TapePoint],
        range: ClosedRange<Int>,
        head: Double,
        x: (Int64) -> CGFloat,
        y: (Double) -> CGFloat,
        plotWidth: CGFloat,
        top: CGFloat,
        color: Color
    ) {
        // Real points up to the playhead (the newest at the eased head), then flat
        // to the right edge.
        coords.removeAll(keepingCapacity: true)
        let step = max(1, range.count / Self.maxLinePoints)
        var index = range.lowerBound
        while index < range.upperBound {
            coords.append(CGPoint(x: x(tape[index].t), y: y(tape[index].price)))
            index += step
        }
        let headY = y(head)
        coords.append(CGPoint(x: x(tape[range.upperBound].t), y: headY))
        coords.append(CGPoint(x: plotWidth, y: headY))
        let line = Self.smoothPath(through: coords)

        var fill = line
        fill.addLine(to: CGPoint(x: plotWidth, y: size.height))
        fill.addLine(to: CGPoint(x: coords.first?.x ?? 0, y: size.height))
        fill.closeSubpath()
        graphics.fill(
            fill,
            with: .color(color.opacity(0.12))
        )
        graphics.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Candles

    /// 5 s candles through the playhead, recomputed only when the tape, the
    /// playhead's trade, or the first visible bucket changes; the growing candle's
    /// close follows the eased head every frame.
    private func liveCandles(frame: LiveChartFrame, playIndex: Int, start: Int64, head: Double) -> [LiveCandle] {
        let firstBucket = Self.floorBucket(start)
        let key = CandleKey(
            count: frame.tape.count,
            lastId: frame.tape.last?.id,
            playIndex: playIndex,
            oneSecondCount: frame.oneSecond.count,
            firstBucket: firstBucket
        )
        let candles: [LiveCandle]
        if let cached = candleCache, cached.key == key {
            candles = cached.candles
        } else {
            candles = MarketPlayback.candles(
                tape: frame.tape,
                oneSecond: frame.oneSecond,
                from: firstBucket,
                through: frame.playhead,
                bucketMs: Self.bucketMs
            )
            candleCache = (key, candles)
        }
        guard var last = candles.last, last.t == Self.floorBucket(frame.playhead) else { return candles }
        var patched = candles
        last.close = head
        last.high = max(last.high, head)
        last.low = min(last.low, head)
        patched[patched.count - 1] = last
        return patched
    }

    private func drawCandles(
        in graphics: inout GraphicsContext,
        candles: [LiveCandle],
        x: (Int64) -> CGFloat,
        y: (Double) -> CGFloat,
        plotWidth: CGFloat,
        windowMs: Double
    ) {
        let slot = plotWidth * CGFloat(Double(Self.bucketMs) / windowMs)
        let bodyWidth = max(slot * 0.62, 1)
        var upWicks = Path(), downWicks = Path(), upBodies = Path(), downBodies = Path()
        for candle in candles {
            let center = x(candle.t) + slot / 2
            guard center + bodyWidth >= 0 else { continue }
            let isUp = candle.close >= candle.open
            let openY = y(candle.open), closeY = y(candle.close)
            let body = CGRect(x: center - bodyWidth / 2, y: min(openY, closeY), width: bodyWidth, height: max(abs(openY - closeY), 1))
            if isUp {
                upWicks.move(to: CGPoint(x: center, y: y(candle.high)))
                upWicks.addLine(to: CGPoint(x: center, y: y(candle.low)))
                upBodies.addRoundedRect(in: body, cornerSize: CGSize(width: 1.5, height: 1.5))
            } else {
                downWicks.move(to: CGPoint(x: center, y: y(candle.high)))
                downWicks.addLine(to: CGPoint(x: center, y: y(candle.low)))
                downBodies.addRoundedRect(in: body, cornerSize: CGSize(width: 1.5, height: 1.5))
            }
        }
        graphics.stroke(upWicks, with: .color(.positive), lineWidth: 1)
        graphics.stroke(downWicks, with: .color(.negative), lineWidth: 1)
        graphics.fill(upBodies, with: .color(.positive))
        graphics.fill(downBodies, with: .color(.negative))
    }

    private static func floorBucket(_ t: Int64) -> Int64 {
        let q = t / bucketMs
        return (t % bucketMs < 0 ? q - 1 : q) * bucketMs
    }

    // MARK: - Helpers

    private func currentHead(now: Date) -> Double? {
        guard let headFrom, let headTo else { return nil }
        let t = min(max(now.timeIntervalSince(headStart) / Self.easeDuration, 0), 1)
        let eased = 1 - pow(1 - t, 3) // ease-out cubic
        return headFrom + (headTo - headFrom) * eased
    }

    /// Quadratic curves through midpoints: smooth corners, still passes near every
    /// real point, never overshoots into values that didn't happen.
    private static func smoothPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for index in 1..<points.count - 1 {
            let mid = CGPoint(x: (points[index].x + points[index + 1].x) / 2, y: (points[index].y + points[index + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[index])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}

/// The token header's live indicator. Green and breathing when the server is
/// watching the chain; a quiet gray dot while it's on a fallback source; "Delayed"
/// when nothing fresh is arriving — so a still chart is never mistaken for a quiet
/// market.
struct LiveStatusBadge: View {
    let state: MarketStatus.State?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    private static let stillFrames = ProcessInfo.processInfo.environment["UITEST_STILL_FRAMES"] == "1"

    var body: some View {
        if let state {
            HStack(spacing: Space.s4) {
                Circle()
                    .fill(dotColor(state))
                    .frame(width: 6, height: 6)
                    .background {
                        if state == .live {
                            Circle()
                                .fill(Color.positive.opacity(0.4))
                                .scaleEffect(breathing ? 2.6 : 1)
                                .opacity(breathing ? 0 : 1)
                        }
                    }
                Text(state == .stale ? "Delayed" : "Live")
                    .font(.caption13)
                    .foregroundStyle(state == .stale ? Color.textTertiary : Color.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText(state))
            .accessibilityIdentifier("tokenDetail.liveStatus")
            .onAppear {
                guard !reduceMotion, !Self.stillFrames else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { breathing = true }
            }
        }
    }

    private func dotColor(_ state: MarketStatus.State) -> Color {
        switch state {
        case .live: .positive
        case .degraded: .textSecondary
        case .stale: .textTertiary
        }
    }

    private func accessibilityText(_ state: MarketStatus.State) -> String {
        switch state {
        case .live: "Live prices"
        case .degraded: "Live prices from a backup source"
        case .stale: "Prices delayed"
        }
    }
}
