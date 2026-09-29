import Foundation
import SwiftUI

/// One real price observation.
struct LivePoint: Equatable {
    let time: Date
    let price: Double
}

/// Real prices for one token, newest last. Polls the server's live quote (the same
/// one trades fill against) and appends each answer; the chart animates between
/// them. Nothing here invents a price — easing only moves between two real ones.
@Observable
@MainActor
final class LivePriceFeed {
    let mint: String
    private(set) var points: [LivePoint] = []
    private var task: Task<Void, Never>?

    /// Seconds between polls. The server caches quotes for a few seconds, so polling
    /// faster than this buys nothing until prices are streamed.
    static var interval: TimeInterval {
        #if DEBUG
        if MockAPI.isEnabled { return 0.4 } // the mock stands in for a streaming feed
        #endif
        return 2
    }

    init(mint: String) { self.mint = mint }

    var latest: Double? { points.last?.price }

    /// Seeds with recent 1-minute closes (so the chart isn't empty) and starts polling.
    func start(seed: [LivePoint]) {
        if points.isEmpty { points = seed.sorted { $0.time < $1.time } }
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func poll() async {
        guard let quote = try? await TokenAPI.priceability(mint: mint), let price = quote.priceUsd else { return }
        let value = NSDecimalNumber(decimal: price).doubleValue
        guard value > 0 else { return }
        points.append(LivePoint(time: Date(), price: value))
        if points.count > 900 { points.removeFirst(points.count - 900) }
    }
}

/// A chart that never sits still: the time axis follows the clock every frame, the
/// newest price eases in over a quarter second instead of jumping, the y-range
/// glides to fit, and a pulsing dot and price tag ride the latest price. Drawn with
/// `Canvas` in a `TimelineView(.animation)`, so it redraws at the display's refresh
/// rate (up to 120 Hz on ProMotion).
struct LiveChartView: View {
    let feed: LivePriceFeed
    /// Seconds of history across the width.
    var window: TimeInterval = 90
    /// Line color. Callers pass the day's direction so the chart agrees with the
    /// header's change; nil colors by the visible window's own direction.
    var color: Color? = nil

    @State private var renderer = LiveChartRenderer()

    private static let stillFrames = ProcessInfo.processInfo.environment["UITEST_STILL_FRAMES"] == "1"

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: Self.stillFrames)) { context in
            let now = Self.stillFrames ? Date() : context.date
            Canvas { graphics, size in
                renderer.draw(in: &graphics, size: size, points: feed.points, now: now, window: window, color: color, animated: !Self.stillFrames)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Live price chart")
        .accessibilityValue(feed.latest.map { PriceFormat.price(Decimal($0)) } ?? "Loading")
    }
}

/// Per-frame drawing plus the little bit of state that makes motion continuous
/// (eased head, smoothed y-range). A plain class so writing to it while drawing
/// doesn't invalidate the view.
final class LiveChartRenderer {
    private var headFrom: Double?
    private var headTo: Double?
    private var headStart = Date.distantPast
    private var lastCount = 0
    private var yLow: Double?
    private var yHigh: Double?
    private var lastFrame: Date?

    private static let easeDuration: TimeInterval = 0.25
    private static let tagWidth: CGFloat = 76

    func draw(
        in graphics: inout GraphicsContext,
        size: CGSize,
        points: [LivePoint],
        now: Date,
        window: TimeInterval,
        color fixedColor: Color?,
        animated: Bool
    ) {
        guard let newest = points.last else { return }

        // Ease the head from where it was drawn toward each new real price.
        if points.count != lastCount || headTo == nil {
            headFrom = animated ? currentHead(now: now) ?? newest.price : newest.price
            headTo = newest.price
            headStart = now
            lastCount = points.count
        }
        let head = currentHead(now: now) ?? newest.price

        // The visible slice, plus one point before the window so the line enters
        // from the left edge instead of starting mid-air.
        let start = now.addingTimeInterval(-window)
        let firstVisible = points.firstIndex { $0.time >= start } ?? points.count - 1
        var visible = Array(points[max(0, firstVisible - 1)...])
        visible[visible.count - 1] = LivePoint(time: newest.time, price: head)

        // Y-range: fit what's visible, with a floor so a flat price isn't magnified
        // into noise, then glide there rather than snap.
        let values = visible.map(\.price)
        var low = values.min() ?? head
        var high = values.max() ?? head
        let minSpan = max(head * 0.004, 1e-12)
        if high - low < minSpan {
            let mid = (high + low) / 2
            low = mid - minSpan / 2
            high = mid + minSpan / 2
        }
        let pad = (high - low) * 0.18
        low -= pad
        high += pad
        let dt = lastFrame.map { min(max(now.timeIntervalSince($0), 0), 0.1) } ?? 1
        lastFrame = now
        let blend = animated ? 1 - exp(-dt * 7) : 1
        yLow = (yLow ?? low) + (low - (yLow ?? low)) * blend
        yHigh = (yHigh ?? high) + (high - (yHigh ?? high)) * blend
        let lo = yLow ?? low, hi = max(yHigh ?? high, lo + 1e-12)

        let plotWidth = size.width - Self.tagWidth
        let top: CGFloat = 12, bottom: CGFloat = 12
        let plotHeight = size.height - top - bottom
        func x(_ time: Date) -> CGFloat {
            plotWidth * CGFloat(1 - now.timeIntervalSince(time) / window)
        }
        func y(_ price: Double) -> CGFloat {
            top + plotHeight * CGFloat(1 - (price - lo) / (hi - lo))
        }

        // The line: real points, then flat from the newest to "now" at the right edge.
        var coords = visible.map { CGPoint(x: x($0.time), y: y($0.price)) }
        coords.append(CGPoint(x: plotWidth, y: y(head)))
        let line = Self.smoothPath(through: coords)

        let isUp = head >= (visible.first?.price ?? head)
        let color: Color = fixedColor ?? (isUp ? .positive : .negative)

        var fill = line
        fill.addLine(to: CGPoint(x: plotWidth, y: size.height))
        fill.addLine(to: CGPoint(x: coords.first?.x ?? 0, y: size.height))
        fill.closeSubpath()
        graphics.fill(
            fill,
            with: .linearGradient(
                Gradient(colors: [color.opacity(0.28), color.opacity(0)]),
                startPoint: CGPoint(x: 0, y: top),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )
        graphics.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // Dashed guide at the current price, across the plot to the tag.
        let headPoint = CGPoint(x: plotWidth, y: y(head))
        var guide = Path()
        guide.move(to: CGPoint(x: 0, y: headPoint.y))
        guide.addLine(to: CGPoint(x: size.width, y: headPoint.y))
        graphics.stroke(guide, with: .color(Color.textTertiary.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

        // Pulsing dot on the newest price.
        let phase = animated ? now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6 : 0.35
        let ring = 4 + 10 * phase
        graphics.fill(
            Path(ellipseIn: CGRect(x: headPoint.x - ring, y: headPoint.y - ring, width: ring * 2, height: ring * 2)),
            with: .color(color.opacity(0.35 * (1 - phase)))
        )
        graphics.fill(
            Path(ellipseIn: CGRect(x: headPoint.x - 4, y: headPoint.y - 4, width: 8, height: 8)),
            with: .color(color)
        )

        // Price tag riding the right edge.
        let label = Text(PriceFormat.price(Decimal(head)))
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundColor(.black)
        let resolved = graphics.resolve(label)
        let textSize = resolved.measure(in: CGSize(width: Self.tagWidth, height: 20))
        let tagHeight: CGFloat = 22
        let tagY = min(max(headPoint.y - tagHeight / 2, 0), size.height - tagHeight)
        let tagRect = CGRect(x: plotWidth + 8, y: tagY, width: min(textSize.width + 12, Self.tagWidth - 8), height: tagHeight)
        graphics.fill(Path(roundedRect: tagRect, cornerRadius: 6), with: .color(color))
        graphics.draw(resolved, at: CGPoint(x: tagRect.midX, y: tagRect.midY), anchor: .center)
    }

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
