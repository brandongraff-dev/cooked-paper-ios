import Foundation
import SwiftUI

/// One of the caller's own active price alerts on this mint, drawn as a level on the
/// chart. Deliberately not `PriceAlert` itself — the chart shouldn't need to know
/// about ids, names, or cooldowns to draw a line at a price.
struct ChartAlertLevel: Identifiable {
    let id: String
    let price: Decimal
    let direction: Direction

    enum Direction { case above, below }
}

/// A hand-rolled candlestick renderer rather than Swift Charts: a financial candle
/// (open/high/low/close as one mark, a genuine gap for a missing bucket rather than
/// an interpolated line, a scrub crosshair) doesn't map onto Swift Charts' mark
/// vocabulary without fighting it, and `Canvas` gives direct control over exactly
/// the two gestures that make a chart feel alive — apple-design §2/§3: 1:1 tracking
/// on the crosshair drag, and continuous feedback through a pinch, not just at the
/// gesture's end.
struct CandleChartView: View {
    let candles: [Candle?]
    let isRelayed: Bool
    let interval: CandleInterval
    var alertLevels: [ChartAlertLevel] = []

    @State private var visibleCount: CGFloat
    @GestureState private var pinchDelta: CGFloat = 1
    @State private var crosshairIndex: Int?
    @State private var lastHapticIndex: Int?
    @State private var hasAppeared = false

    init(candles: [Candle?], isRelayed: Bool, interval: CandleInterval, alertLevels: [ChartAlertLevel] = []) {
        self.candles = candles
        self.isRelayed = isRelayed
        self.interval = interval
        self.alertLevels = alertLevels
        _visibleCount = State(initialValue: CGFloat(min(candles.count, 80)))
    }

    /// `.calm`'s curve retimed to `.slow` — `.speed` is the only way to stretch an
    /// existing `Animation` without duplicating its curve literal outside Motion.swift.
    private var revealAnimation: Animation { Motion.standard }

    var body: some View {
        GeometryReader { geometry in
            let effectiveCount = max(8, min(CGFloat(candles.count), visibleCount * pinchDelta))
            let visible = Array(candles.suffix(Int(effectiveCount)))
            let priceRange = Self.priceRange(of: visible)
            // A level outside the visible prices would draw (and label) off the
            // chart, over the header; it simply isn't shown until price nears it.
            let visibleAlerts = alertLevels.filter { priceRange.contains($0.price) }
            let maPeriod = Self.movingAveragePeriod(for: visible.count)
            let maSeries = maPeriod.map { Self.movingAverageSeries(of: visible, period: $0) } ?? []
            let showMovingAverage = maSeries.contains { $0 != nil }
            let slot = visible.isEmpty ? 0 : geometry.size.width / CGFloat(visible.count)
            let lastCandle = visible.compactMap { $0 }.last
            let crosshairCandle: Candle? = crosshairIndex.flatMap { visible[safe: $0] ?? nil }
            let lastPriceY: CGFloat? = lastCandle.map { Self.yPosition(for: $0.close, priceRange: priceRange, height: geometry.size.height) }
            // An axis label within a pill's height of the live-price pill would print
            // underneath it (both are trailing-aligned), so it yields to the pill.
            let priceLabels = Self.priceAxisLabels(priceRange: priceRange, height: geometry.size.height)
                .filter { label in lastPriceY.map { abs($0 - label.y) > 16 } ?? true }
            let timeLabels = Self.timeLabels(for: visible, interval: interval)

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawGrid(context: context, size: size)
                    drawVolumeBars(visible, context: context, size: size)
                    drawCandles(visible, priceRange: priceRange, context: context, size: size)
                    if showMovingAverage {
                        drawMovingAverage(maSeries, priceRange: priceRange, context: context, size: size)
                    }
                    for level in visibleAlerts {
                        let y = Self.yPosition(for: level.price, priceRange: priceRange, height: size.height)
                        drawPriceLine(at: y, color: Color.textSecondary, context: context, size: size)
                    }
                    if let lastCandle {
                        let y = Self.yPosition(for: lastCandle.close, priceRange: priceRange, height: size.height)
                        drawPriceLine(at: y, color: Color.textSecondary, context: context, size: size)
                    }
                    if let crosshairIndex, visible.indices.contains(crosshairIndex) {
                        drawCrosshair(at: crosshairIndex, in: visible, priceRange: priceRange, context: context, size: size)
                    }
                }
                .opacity(hasAppeared ? 1 : 0)
                .onAppear {
                    guard !hasAppeared else { return } // a re-render (e.g. a timeframe switch) must not replay the reveal
                    withAnimation(revealAnimation) { hasAppeared = true }
                }
                .gesture(crosshairGesture(visibleCount: visible.count, width: geometry.size.width))
                .gesture(magnifyGesture)

                ForEach(priceLabels) { label in
                    Text(label.text)
                        .font(Font.caption2.monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: geometry.size.width - Space.s8 * 2, alignment: .trailing)
                        .position(x: geometry.size.width / 2, y: label.y)
                }

                ForEach(timeLabels) { label in
                    let rawX = slot * CGFloat(label.index) + slot / 2
                    // The price labels get a `.frame(width:alignment:)` to stay clear of
                    // the trailing edge; a time label has no such frame (its width isn't
                    // known up front), so without this clamp the first/last label — whose
                    // raw center sits half a candle-slot from the edge — renders roughly
                    // half off-canvas. 20pt is a safe half-width for "HH:mm"/"MMM d" at
                    // caption size.
                    let x = min(max(rawX, 20), geometry.size.width - 20)
                    Text(label.text)
                        .font(Font.caption2.monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                        .position(x: x, y: geometry.size.height - Space.s8)
                }

                if let lastCandle {
                    let y = Self.yPosition(for: lastCandle.close, priceRange: priceRange, height: geometry.size.height)
                    ChartPricePill(price: lastCandle.close, color: Color.textSecondary)
                        .frame(width: geometry.size.width - Space.s8 * 2, alignment: .trailing)
                        .position(x: geometry.size.width / 2, y: y)
                }

                // Leading edge, opposite the live-price pill — an alert's own line
                // already carries `warn` color on the canvas layer above; the label
                // only needs to say which price and which direction it's watching for.
                // Same near-full-width-frame-then-align trick as the price pills above,
                // mirrored to `.leading` so a long price string still clears the edge.
                ForEach(visibleAlerts) { level in
                    let y = Self.yPosition(for: level.price, priceRange: priceRange, height: geometry.size.height)
                    AlertLevelLabel(level: level)
                        .frame(width: geometry.size.width - Space.s8 * 2, alignment: .leading)
                        .position(x: geometry.size.width / 2, y: y)
                }

                if let crosshairCandle {
                    let y = Self.yPosition(for: crosshairCandle.close, priceRange: priceRange, height: geometry.size.height)
                    ChartPricePill(price: crosshairCandle.close, color: Color.textTertiary)
                        .frame(width: geometry.size.width - Space.s8 * 2, alignment: .trailing)
                        .position(x: geometry.size.width / 2, y: y)
                }

                if let crosshairIndex, let candle = visible[safe: crosshairIndex] ?? nil {
                    CrosshairLabel(candle: candle)
                        .padding(Space.s8)
                }

                if showMovingAverage, let maPeriod {
                    Text("MA \(maPeriod)")
                        .font(Font.caption2.monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                        .padding(Space.s8)
                        // Leading, not trailing: the trailing edge belongs to the price
                        // axis labels, and the top one would print underneath this.
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .opacity(crosshairIndex == nil ? 1 : 0)
                }
            }
        }
    }

    // MARK: - Gestures

    /// A plain drag on the chart must scroll the page it's embedded in — a trading
    /// app's chart lives inside a `ScrollView` (see `TokenDetailView`), and a bare
    /// `DragGesture` here would win that fight and trap every scroll attempt that
    /// happens to start over the chart. Requiring a brief press first is the
    /// documented fix for exactly this conflict: a quick swipe scrolls normally, a
    /// deliberate press-and-hold-then-drag is unambiguous crosshair intent.
    private func crosshairGesture(visibleCount: Int, width: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    // The press just resolved, before any drag — confirm crosshair
                    // mode engaged on the same frame, not on the first move.
                    Haptics.tap()
                case .second(true, let drag?):
                    guard visibleCount > 0 else { return }
                    let slot = width / CGFloat(visibleCount)
                    let index = min(visibleCount - 1, max(0, Int(drag.location.x / slot)))
                    crosshairIndex = index
                    if lastHapticIndex != index {
                        Haptics.tap()
                        lastHapticIndex = index
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                crosshairIndex = nil
                lastHapticIndex = nil
            }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchDelta) { value, state, _ in
                // Pinching OUT should show FEWER candles (zoom in on price action), so
                // invert: a magnification > 1 divides the visible count.
                state = 1 / value
            }
            .onEnded { value in
                visibleCount = max(8, min(CGFloat(candles.count), visibleCount / value))
            }
    }

    // MARK: - Drawing

    private static func priceRange(of visible: [Candle?]) -> ClosedRange<Decimal> {
        let present = visible.compactMap { $0 }
        guard let low = present.map(\.low).min(), let high = present.map(\.high).max(), low < high else {
            return 0...1
        }
        let padding = (high - low) * 0.08
        return (low - padding)...(high + padding)
    }

    private static func yPosition(for price: Decimal, priceRange: ClosedRange<Decimal>, height: CGFloat) -> CGFloat {
        let span = priceRange.upperBound - priceRange.lowerBound
        guard span > 0 else { return height / 2 }
        let fraction = (price - priceRange.lowerBound) / span
        return height - (CGFloat(NSDecimalNumber(decimal: fraction).doubleValue) * height)
    }

    // MARK: - Moving average

    /// A fixed window would misrepresent a chart scrubbed down to eight candles, so
    /// the period tracks how much is actually on screen — never more than 20, never
    /// enough to swallow most of a thin view.
    private static func movingAveragePeriod(for visibleCount: Int) -> Int? {
        let period = min(20, visibleCount / 3)
        return period >= 2 ? period : nil
    }

    /// One value per visible index, `nil` until a full, gap-free window of `period`
    /// candles sits behind it — a gap candle inside the window poisons the mean for
    /// every index that window covers, the same way it breaks the line when drawn.
    private static func movingAverageSeries(of visible: [Candle?], period: Int) -> [Decimal?] {
        guard period >= 2, !visible.isEmpty else { return [] }
        var series = [Decimal?](repeating: nil, count: visible.count)
        for index in visible.indices where index >= period - 1 {
            let window = visible[(index - period + 1)...index]
            guard window.allSatisfy({ $0 != nil }) else { continue }
            let sum = window.reduce(Decimal(0)) { $0 + $1!.close }
            series[index] = sum / Decimal(period)
        }
        return series
    }

    // MARK: - Axis labels

    private static let gridRowCount = 4

    private static func priceAxisLabels(priceRange: ClosedRange<Decimal>, height: CGFloat) -> [PriceAxisLabel] {
        guard height > 0 else { return [] }
        let span = priceRange.upperBound - priceRange.lowerBound
        return (0...gridRowCount).map { row in
            let rawY = height / CGFloat(gridRowCount) * CGFloat(row)
            let y = min(max(rawY, 7), height - 7) // keeps the top/bottom label from clipping at the canvas edge
            let price = priceRange.upperBound - (Decimal(row) / Decimal(gridRowCount)) * span
            return PriceAxisLabel(id: row, y: y, text: price.priceFormatted)
        }
    }

    /// Spaced across whatever is currently visible, not a fixed pixel interval — the
    /// same pinch-zoom that rescales the candles must rescale the timestamps too.
    private static func timeLabelIndices(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let labelCount = min(4, count)
        guard labelCount > 1 else { return [0] }
        return (0..<labelCount).map { step in
            let fraction = Double(step) / Double(labelCount - 1)
            return min(count - 1, Int((Double(count - 1) * fraction).rounded()))
        }
    }

    private static func timeLabels(for visible: [Candle?], interval: CandleInterval) -> [TimeAxisLabel] {
        let formatter = timeAxisFormatter(for: interval)
        return timeLabelIndices(count: visible.count).compactMap { index in
            guard let candle = visible[index] else { return nil } // a gap has no timestamp to show
            guard let date = parseBucketStart(candle.bucketStart) else { return nil }
            return TimeAxisLabel(index: index, text: formatter.string(from: date))
        }
    }

    private static func timeAxisFormatter(for interval: CandleInterval) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = interval == .oneDay ? "MMM d" : "HH:mm"
        return formatter
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Tried plain first, since that's the common case — a second formatter only for
    /// the backend occasionally emitting fractional seconds.
    private static func parseBucketStart(_ raw: String) -> Date? {
        isoFormatter.date(from: raw) ?? isoFormatterWithFractionalSeconds.date(from: raw)
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        for i in 0...Self.gridRowCount {
            let y = size.height / CGFloat(Self.gridRowCount) * CGFloat(i)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(Color.appSeparator), lineWidth: 1)
        }
    }

    private func drawPriceLine(at y: CGFloat, color: Color, context: GraphicsContext, size: CGSize) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    private func drawCandles(_ visible: [Candle?], priceRange: ClosedRange<Decimal>, context: GraphicsContext, size: CGSize) {
        guard !visible.isEmpty else { return }
        let slot = size.width / CGFloat(visible.count)
        let bodyWidth = max(1, slot * 0.6)

        func y(_ price: Decimal) -> CGFloat {
            Self.yPosition(for: price, priceRange: priceRange, height: size.height)
        }

        for (index, candle) in visible.enumerated() {
            guard let candle else { continue } // a genuine gap — draw nothing, never interpolate
            let x = slot * CGFloat(index) + slot / 2
            let isUp = candle.close >= candle.open
            let color = isUp ? Color.positive : Color.negative

            var wick = Path()
            wick.move(to: CGPoint(x: x, y: y(candle.high)))
            wick.addLine(to: CGPoint(x: x, y: y(candle.low)))
            context.stroke(wick, with: .color(color), lineWidth: 1)

            let openY = y(candle.open)
            let closeY = y(candle.close)
            let bodyRect = CGRect(
                x: x - bodyWidth / 2,
                y: min(openY, closeY),
                width: bodyWidth,
                height: max(1, abs(closeY - openY))
            )
            context.fill(Path(bodyRect), with: .color(color))
        }
    }

    /// A secondary layer, not a second chart — its own max keeps a single illiquid
    /// candle from flattening every other bar the way sharing the price scale would.
    private func drawVolumeBars(_ visible: [Candle?], context: GraphicsContext, size: CGSize) {
        guard !visible.isEmpty else { return }
        let maxVolume = visible.compactMap({ $0?.volume }).max() ?? 0
        guard maxVolume > 0 else { return }

        let slot = size.width / CGFloat(visible.count)
        let barWidth = max(1, slot * 0.6)
        let bandHeight = size.height * 0.15
        let bandTop = size.height - bandHeight

        for (index, candle) in visible.enumerated() {
            guard let candle else { continue } // a genuine gap — no bar, same as the price body
            let fraction = CGFloat(NSDecimalNumber(decimal: candle.volume / maxVolume).doubleValue)
            let barHeight = max(1, bandHeight * fraction)
            let x = slot * CGFloat(index) + slot / 2
            let isUp = candle.close >= candle.open
            let color = isUp ? Color.positive : Color.negative
            let rect = CGRect(x: x - barWidth / 2, y: bandTop + (bandHeight - barHeight), width: barWidth, height: barHeight)
            context.fill(Path(rect), with: .color(color.opacity(0.5)))
        }
    }

    private func drawMovingAverage(_ series: [Decimal?], priceRange: ClosedRange<Decimal>, context: GraphicsContext, size: CGSize) {
        guard !series.isEmpty else { return }
        let slot = size.width / CGFloat(series.count)
        var path = Path()
        var isDrawing = false

        for (index, value) in series.enumerated() {
            guard let value else { isDrawing = false; continue } // breaks the line, same as a gap candle
            let x = slot * CGFloat(index) + slot / 2
            let y = Self.yPosition(for: value, priceRange: priceRange, height: size.height)
            if isDrawing {
                path.addLine(to: CGPoint(x: x, y: y))
            } else {
                path.move(to: CGPoint(x: x, y: y))
                isDrawing = true
            }
        }

        context.stroke(path, with: .color(Color.textSecondary), lineWidth: 1.5)
    }

    private func drawCrosshair(at index: Int, in visible: [Candle?], priceRange: ClosedRange<Decimal>, context: GraphicsContext, size: CGSize) {
        let slot = size.width / CGFloat(visible.count)
        let x = slot * CGFloat(index) + slot / 2

        var vertical = Path()
        vertical.move(to: CGPoint(x: x, y: 0))
        vertical.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(vertical, with: .color(Color.textTertiary), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        if let candle = visible[index] { // a gap has no close price for the horizontal half of the crosshair
            let y = Self.yPosition(for: candle.close, priceRange: priceRange, height: size.height)
            drawPriceLine(at: y, color: Color.textTertiary, context: context, size: size)
        }
    }
}

private struct CrosshairLabel: View {
    let candle: Candle

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("O \(candle.open.priceFormatted)")
            Text("H \(candle.high.priceFormatted)")
            Text("L \(candle.low.priceFormatted)")
            Text("C \(candle.close.priceFormatted)")
            Text("V \(candle.volume.formatted(.number.precision(.fractionLength(0))))")
        }
        // Smaller and monospaced, not `Font.caption2.monospacedDigit()` — five stacked OHLCV rows
        // need tabular figures at a size that still leaves room for the volume row.
        .font(Font.caption2.monospacedDigit())
        .foregroundStyle(Color.textPrimary)
        .padding(Space.s8)
        .background(Color.appSurfaceElevated.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }
}

/// A price pill pinned to the chart's trailing edge — the live last-close price in
/// `Color.textSecondary`, or the scrubbed crosshair price in
/// `.chartCrosshair`, so which one is "live" vs. "what you're scrubbing" is never
/// ambiguous from color alone.
private struct ChartPricePill: View {
    let price: Decimal
    let color: Color

    var body: some View {
        Text(price.priceFormatted)
            .font(Font.caption2.monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, Space.s8)
            .padding(.vertical, Space.s8)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

/// A caller-owned price alert's level, labeled on the chart's leading edge. `warn`
/// text on a `warn`-tinted pill — same "fill echoes the line it labels" convention
/// `ChartPricePill` uses, just on the opposite side and in the alert color instead of
/// the live/crosshair ones.
private struct AlertLevelLabel: View {
    let level: ChartAlertLevel

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: level.direction == .above ? "arrow.up" : "arrow.down")
                .font(Font.caption2.weight(.semibold))
            Text(level.price.priceFormatted)
                .font(Font.caption2.monospacedDigit())
        }
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, Space.s8)
        .padding(.vertical, Space.s8)
        .background(Color.textSecondary.opacity(0.15))
        .clipShape(Capsule())
    }
}

private struct PriceAxisLabel: Identifiable {
    let id: Int
    let y: CGFloat
    let text: String
}

private struct TimeAxisLabel: Identifiable {
    let index: Int
    let text: String
    var id: Int { index }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Decimal {
    var priceFormatted: String { PriceFormat.price(self) }
}
