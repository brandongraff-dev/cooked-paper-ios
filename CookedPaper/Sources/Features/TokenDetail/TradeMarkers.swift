import Foundation
import SwiftUI

/// One of the signed-in person's own trades on a token, placed on its chart: a solid
/// disc with a black "+" where they got in and "−" where they got out. Only their
/// trades; the market's tape stays a clean line. The marker sits ON the line at the
/// moment of the trade — the fill price (which includes slippage) is on the fill
/// screen, and pinning the marker to it would float it off a tightly-scaled chart.
struct ChartTradeMarker: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Bought, or opened a long / closed a short.
        case plus
        /// Sold, or closed a long / opened a short.
        case minus
    }

    let id: String
    /// Epoch milliseconds of the fill.
    let t: Int64
    /// The fill price.
    let price: Double
    let kind: Kind

    var color: Color { kind == .plus ? .positive : .negative }
}

enum ChartTradeMarkers {
    /// Spot fills plus leveraged opens and closes for `mint`, oldest first. Spot
    /// trades come from `/paper/portfolios/:id/trades`; leveraged ones from the
    /// snapshot's open positions and round trips, which already carry entry/exit
    /// prices and times.
    static func load(mint: String) async -> [ChartTradeMarker] {
        var markers: [ChartTradeMarker] = []
        if let portfolioId = SessionStore.shared.activePortfolioId,
           let trades = try? await PaperAPI.trades(portfolioId: portfolioId) {
            for trade in trades where trade.tokenMint == mint {
                guard let t = epochMs(trade.executedAt) else { continue }
                markers.append(ChartTradeMarker(
                    id: "spot-\(trade.id)",
                    t: t,
                    price: double(trade.priceUsd),
                    kind: trade.side == .buy ? .plus : .minus
                ))
            }
        }
        let snapshot = PortfolioStore.shared.snapshot
        for position in snapshot?.leveragedPositions ?? [] where position.tokenMint == mint {
            guard let t = epochMs(position.openedAt) else { continue }
            markers.append(ChartTradeMarker(
                id: "lev-open-\(position.id)",
                t: t,
                price: double(position.entryPriceUsd),
                kind: position.direction == .long ? .plus : .minus
            ))
        }
        for trip in snapshot?.leveragedRoundTrips ?? [] where trip.tokenMint == mint {
            if let opened = epochMs(trip.openedAt) {
                markers.append(ChartTradeMarker(
                    id: "lev-open-\(trip.positionId)",
                    t: opened,
                    price: double(trip.entryPriceUsd),
                    kind: trip.direction == .long ? .plus : .minus
                ))
            }
            if let closed = epochMs(trip.closedAt) {
                markers.append(ChartTradeMarker(
                    id: "lev-close-\(trip.positionId)",
                    t: closed,
                    price: double(trip.avgExitPriceUsd),
                    kind: trip.direction == .long ? .minus : .plus
                ))
            }
        }
        return markers.sorted { $0.t < $1.t }
    }

    static func epochMs(_ iso: String) -> Int64? {
        guard let date = isoFractional.date(from: iso) ?? isoPlain.date(from: iso) else { return nil }
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    private static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private static let isoPlain = ISO8601DateFormatter()
    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: - Drawing

    static let radius: CGFloat = 9

    /// Draws one marker into a `Canvas`: a solid green or red disc with a black "+"
    /// or "−", separated from the line by a thin ring in the background color.
    static func draw(_ kind: ChartTradeMarker.Kind, at center: CGPoint, in graphics: inout GraphicsContext, opacity: Double = 1) {
        let color: Color = kind == .plus ? .positive : .negative
        let r = radius
        let ring = Path(ellipseIn: CGRect(x: center.x - r - 2, y: center.y - r - 2, width: (r + 2) * 2, height: (r + 2) * 2))
        graphics.fill(ring, with: .color(Color.appBackground.opacity(opacity)))
        let disc = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        graphics.fill(disc, with: .color(color.opacity(opacity)))
        var glyph = Path()
        let arm: CGFloat = 4
        glyph.move(to: CGPoint(x: center.x - arm, y: center.y))
        glyph.addLine(to: CGPoint(x: center.x + arm, y: center.y))
        if kind == .plus {
            glyph.move(to: CGPoint(x: center.x, y: center.y - arm))
            glyph.addLine(to: CGPoint(x: center.x, y: center.y + arm))
        }
        graphics.stroke(glyph, with: .color(Color.black.opacity(opacity)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }
}

/// The same marker as a SwiftUI view, for Swift Charts symbols.
struct TradeMarkerSymbol: View {
    let kind: ChartTradeMarker.Kind

    var body: some View {
        Canvas { graphics, size in
            ChartTradeMarkers.draw(kind, at: CGPoint(x: size.width / 2, y: size.height / 2), in: &graphics)
        }
        .frame(width: ChartTradeMarkers.radius * 2 + 6, height: ChartTradeMarkers.radius * 2 + 6)
        .accessibilityHidden(true)
    }
}

extension CandleInterval {
    /// Length of one bucket, for placing markers on candle-indexed charts.
    var milliseconds: Int64 {
        switch self {
        case .oneMinute: 60_000
        case .fiveMinute: 300_000
        case .fifteenMinute: 900_000
        case .thirtyMinute: 1_800_000
        case .oneHour: 3_600_000
        case .fourHour: 14_400_000
        case .oneDay: 86_400_000
        }
    }
}
