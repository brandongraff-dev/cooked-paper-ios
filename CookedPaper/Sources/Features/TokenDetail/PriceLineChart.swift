import Charts
import SwiftUI

/// The time windows the detail screen offers. Each maps onto the existing candles
/// endpoint's interval + limit — a presentation choice, not a new query.
enum ChartRange: String, CaseIterable, Identifiable {
    /// A few minutes of real prices scrolling with the clock (`LiveChartView`).
    case live = "LIVE"
    case hour = "1H"
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case all = "ALL"

    var id: String { rawValue }

    var interval: CandleInterval {
        switch self {
        case .live, .hour: .oneMinute
        case .day: .fifteenMinute
        case .week: .oneHour
        case .month: .fourHour
        case .all: .oneDay
        }
    }

    var limit: Int {
        switch self {
        case .live: 5
        case .hour: 60
        case .day: 96
        case .week: 168
        case .month: 180
        case .all: 200
        }
    }

    /// Trailing label on the header's change line.
    var changeCaption: String {
        switch self {
        case .live, .day: "Today"
        case .hour: "Past hour"
        case .week: "Past week"
        case .month: "Past month"
        case .all: "All time"
        }
    }
}

/// A clean line chart: no grid, no axes, no volume. The line is green or red by
/// the period's direction with a faint fill beneath. Dragging scrubs: a vertical
/// rule follows the finger, `selectedIndex` updates (the header reads it to show the
/// scrubbed price live), and each new point ticks a selection haptic.
struct PriceLineChart: View {
    let values: [Double]
    @Binding var selectedIndex: Int?
    /// The person's own trades, placed on the line at the bucket they fell in.
    var markers: [(index: Int, marker: ChartTradeMarker)] = []

    private var isUp: Bool { (values.last ?? 0) >= (values.first ?? 0) }
    private var lineColor: Color { isUp ? .positive : .negative }

    var body: some View {
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = high > low ? (high - low) * 0.08 : max(high * 0.01, 0.000_000_1)

        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                AreaMark(
                    x: .value("Time", index),
                    yStart: .value("Floor", low - pad),
                    yEnd: .value("Price", value)
                )
                // A wash under the line in the period's direction, so the shape reads
                // at a glance.
                .foregroundStyle(
                    LinearGradient(colors: [lineColor.opacity(0.32), lineColor.opacity(0)], startPoint: .top, endPoint: .bottom)
                )

                LineMark(x: .value("Time", index), y: .value("Price", value))
                    .foregroundStyle(lineColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            // The latest value, lit, while nothing is being scrubbed.
            if selectedIndex == nil, let last = values.last {
                PointMark(x: .value("Time", values.count - 1), y: .value("Price", last))
                    .foregroundStyle(lineColor.opacity(0.25))
                    .symbolSize(220)
                PointMark(x: .value("Time", values.count - 1), y: .value("Price", last))
                    .foregroundStyle(lineColor)
                    .symbolSize(50)
            }

            // Pinned to the line at the trade's bucket.
            ForEach(markers.filter { values.indices.contains($0.index) }, id: \.marker.id) { item in
                PointMark(x: .value("Time", item.index), y: .value("Price", values[item.index]))
                    .symbol { TradeMarkerSymbol(kind: item.marker.kind) }
            }

            if let selectedIndex, values.indices.contains(selectedIndex) {
                RuleMark(x: .value("Time", selectedIndex))
                    .foregroundStyle(Color.textTertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Time", selectedIndex), y: .value("Price", values[selectedIndex]))
                    .foregroundStyle(lineColor)
                    .symbolSize(64)
            }
        }
        .chartXScale(domain: 0...max(values.count - 1, 1))
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .shadow(color: lineColor.opacity(0.35), radius: 10, y: 4)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                guard !values.isEmpty, let plotFrame = proxy.plotFrame else { return }
                                let x = drag.location.x - geometry[plotFrame].origin.x
                                guard let position = proxy.value(atX: x, as: Double.self) else { return }
                                let index = min(max(Int(position.rounded()), 0), values.count - 1)
                                if index != selectedIndex {
                                    Haptics.selection()
                                    selectedIndex = index
                                }
                            }
                            .onEnded { _ in selectedIndex = nil }
                    )
            }
        }
        .accessibilityLabel("Price chart")
        .accessibilityValue(isUp ? "Up over this period" : "Down over this period")
    }
}
