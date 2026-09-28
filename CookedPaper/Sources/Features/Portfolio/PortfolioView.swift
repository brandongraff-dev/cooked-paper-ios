import Charts
import Foundation
import SwiftUI

struct PortfolioView: View {
    private let portfolioStore = PortfolioStore.shared
    private let live = LiveSocket.shared
    @State private var animatedRowIDs: Set<String> = []

    var body: some View {
        ZStack {
            AmbientBackground(colors: [CookedColor.Prism.teal, CookedColor.Brand.fill, CookedColor.Prism.indigo])

            if portfolioStore.isBootstrapping {
                skeleton
            } else if let snapshot = portfolioStore.snapshot {
                content(snapshot)
            } else if let error = portfolioStore.error {
                EmptyStateView(symbol: "wifi.slash", title: "Couldn't load your portfolio", detail: error)
                    .glassPanel()
                    .padding(CookedSpacing.md)
            }
        }
        .navigationTitle(portfolioStore.snapshot?.portfolio.name ?? "Portfolio")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SimulatedBadge() }
        }
        .navigationDestination(for: String.self) { mint in
            TokenDetailView(mint: mint)
        }
    }

    private func content(_ snapshot: PaperSnapshotResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CookedSpacing.lg) {
                heroCard(snapshot)
                statTiles(snapshot)

                if snapshot.positions.isEmpty {
                    EmptyStateView(
                        symbol: "chart.pie",
                        title: "No open positions",
                        detail: "Head to Discover and make your first trade — it's instant, and it's not real money."
                    )
                    .frame(maxWidth: .infinity)
                    .glassPanel()
                } else {
                    allocationCard(snapshot)

                    VStack(alignment: .leading, spacing: CookedSpacing.sm) {
                        SectionHeader(symbol: "square.stack.3d.up.fill", title: "Positions", tint: CookedColor.Prism.teal)
                        VStack(spacing: 0) {
                            ForEach(Array(snapshot.positions.enumerated()), id: \.element.id) { index, position in
                                NavigationLink(value: position.tokenMint) {
                                    PositionRow(
                                        position: position,
                                        live: livePosition(for: position.tokenMint),
                                        share: share(of: position.valueUsd, in: snapshot)
                                    )
                                }
                                .buttonStyle(RowPressStyle())
                                .staggeredEntrance(index: index, id: position.id, animatedIDs: $animatedRowIDs)

                                if index < snapshot.positions.count - 1 {
                                    Divider().overlay(CookedColor.Terminal.border).padding(.leading, 68)
                                }
                            }
                        }
                        .padding(.vertical, CookedSpacing.xxs)
                        .glassPanel()
                    }
                }

                if !snapshot.roundTrips.isEmpty {
                    VStack(alignment: .leading, spacing: CookedSpacing.sm) {
                        SectionHeader(symbol: "checkmark.circle.fill", title: "Recently closed", tint: CookedColor.Terminal.buy)
                        VStack(spacing: 0) {
                            ForEach(Array(snapshot.roundTrips.prefix(10).enumerated()), id: \.element.id) { offset, roundTrip in
                                RoundTripRow(roundTrip: roundTrip)
                                    .staggeredEntrance(
                                        index: snapshot.positions.count + offset,
                                        id: roundTrip.id,
                                        animatedIDs: $animatedRowIDs
                                    )
                                if offset < min(snapshot.roundTrips.count, 10) - 1 {
                                    Divider().overlay(CookedColor.Terminal.border).padding(.leading, 56)
                                }
                            }
                        }
                        .padding(.vertical, CookedSpacing.xxs)
                        .glassPanel()
                    }
                }
            }
            .padding(.horizontal, CookedSpacing.md)
            .padding(.bottom, CookedSpacing.xxxl)
        }
        .scrollIndicators(.hidden)
        .refreshable { try? await portfolioStore.refresh() }
    }

    // MARK: - Hero

    private func heroCard(_ snapshot: PaperSnapshotResponse) -> some View {
        let equity = live.latestTick?.equityUsd ?? snapshot.equityUsd
        let cash = live.latestTick?.cashUsd ?? snapshot.cashUsd
        let unrealized = snapshot.stats.unrealizedPnlUsd.usd
        let isUp = (snapshot.stats.returnPct.pct ?? 0) >= 0
        let mood = isUp ? CookedColor.Terminal.buy : CookedColor.Terminal.sell

        return VStack(alignment: .leading, spacing: CookedSpacing.sm) {
            HStack {
                Text("Total equity")
                    .font(CookedFont.label(13))
                    .foregroundStyle(CookedColor.Terminal.textSecondary)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(mood).frame(width: 6, height: 6)
                    Text("Live")
                        .font(CookedFont.caption(11))
                        .foregroundStyle(CookedColor.Terminal.textSecondary)
                }
                .padding(.horizontal, CookedSpacing.xs)
                .padding(.vertical, 3)
                .cookedGlass(in: Capsule())
            }

            RollingNumber(
                value: NSDecimalNumber(decimal: equity).doubleValue,
                format: { $0.formatted(.currency(code: "USD").precision(.fractionLength(2))) },
                font: CookedFont.priceDisplay(42)
            )
            .minimumScaleFactor(0.6)
            .lineLimit(1)

            HStack(spacing: CookedSpacing.xs) {
                PnLText(value: unrealized, isPercent: false, font: CookedFont.priceMedium())
                ChangePill(value: snapshot.stats.returnPct.pct)
                Text("all-time")
                    .font(CookedFont.caption(12))
                    .foregroundStyle(CookedColor.Terminal.textMuted)
            }

            if snapshot.equityCurve.points.count > 1 {
                EquityChart(points: snapshot.equityCurve.points, color: mood)
                    .frame(height: 120)
                    .padding(.top, CookedSpacing.xs)
            }

            HStack {
                Label {
                    Text("\(cash.usdString()) cash available")
                } icon: {
                    Image(systemName: "banknote.fill")
                }
                .font(CookedFont.caption(12))
                .foregroundStyle(CookedColor.Terminal.textSecondary)
                Spacer()
                Text("Peak \(snapshot.equityCurve.peakEquityUsd.usdString(fractionDigits: 0))")
                    .font(CookedFont.priceSmall(11))
                    .foregroundStyle(CookedColor.Terminal.textMuted)
            }
        }
        .padding(CookedSpacing.lg)
        .background(
            LinearGradient(colors: [mood.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: CookedRadius.xl, style: .continuous)
        )
        .glassPanel(cornerRadius: CookedRadius.xl, tint: mood)
        .shineSweep(cornerRadius: CookedRadius.xl)
    }

    private func statTiles(_ snapshot: PaperSnapshotResponse) -> some View {
        HStack(spacing: CookedSpacing.sm) {
            StatTile(
                symbol: "target",
                color: CookedColor.Prism.teal,
                title: "Win rate",
                value: snapshot.stats.winRatePct.pct.map { "\($0.formatted(.number.precision(.fractionLength(0))))%" } ?? "—",
                progress: snapshot.stats.winRatePct.pct.map { NSDecimalNumber(decimal: $0 / 100).doubleValue }
            )
            StatTile(
                symbol: "arrow.left.arrow.right",
                color: CookedColor.Prism.indigo,
                title: "Trades",
                value: "\(snapshot.stats.tradeCount)",
                progress: nil
            )
            StatTile(
                symbol: "arrow.down.right",
                color: CookedColor.Prism.amber,
                title: "Drawdown",
                value: snapshot.stats.maxDrawdownPct.pct.map { "\($0.formatted(.number.precision(.fractionLength(1))))%" } ?? "—",
                progress: nil
            )
        }
    }

    // MARK: - Allocation

    private func allocationSlices(_ snapshot: PaperSnapshotResponse) -> [AllocationSlice] {
        var slices = snapshot.positions.map { position in
            AllocationSlice(
                id: position.tokenMint,
                label: position.token?.symbol ?? "?",
                value: NSDecimalNumber(decimal: position.valueUsd).doubleValue,
                color: TokenPalette(seed: position.tokenMint).primary
            )
        }
        slices.append(AllocationSlice(
            id: "cash",
            label: "Cash",
            value: NSDecimalNumber(decimal: snapshot.cashUsd).doubleValue,
            color: Color.white.opacity(0.28)
        ))
        return slices
    }

    private func allocationCard(_ snapshot: PaperSnapshotResponse) -> some View {
        let slices = allocationSlices(snapshot)
        let total = max(slices.reduce(0) { $0 + $1.value }, 1)

        return VStack(alignment: .leading, spacing: CookedSpacing.md) {
            SectionHeader(symbol: "chart.pie.fill", title: "Allocation", tint: CookedColor.Prism.indigo)
            HStack(spacing: CookedSpacing.lg) {
                AllocationDonut(slices: slices)
                    .frame(width: 128, height: 128)
                    .overlay {
                        VStack(spacing: 0) {
                            Text("\(snapshot.positions.count)")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(CookedColor.Terminal.textPrimary)
                            Text(snapshot.positions.count == 1 ? "position" : "positions")
                                .font(CookedFont.caption(11))
                                .foregroundStyle(CookedColor.Terminal.textMuted)
                        }
                    }

                VStack(alignment: .leading, spacing: CookedSpacing.xs) {
                    ForEach(slices) { slice in
                        HStack(spacing: CookedSpacing.xs) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(slice.color)
                                .frame(width: 10, height: 10)
                            Text(slice.label)
                                .font(CookedFont.label(13))
                                .foregroundStyle(CookedColor.Terminal.textPrimary)
                            Spacer(minLength: 4)
                            Text("\((slice.value / total * 100).formatted(.number.precision(.fractionLength(0))))%")
                                .font(CookedFont.priceSmall(12))
                                .foregroundStyle(CookedColor.Terminal.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(CookedSpacing.lg)
        .glassPanel()
    }

    private func share(of value: Decimal, in snapshot: PaperSnapshotResponse) -> Double {
        let equity = NSDecimalNumber(decimal: snapshot.equityUsd).doubleValue
        guard equity > 0 else { return 0 }
        return min(1, NSDecimalNumber(decimal: value).doubleValue / equity)
    }

    /// Shaped like `content(_:)` — same hero card, same panels — so swapping in the
    /// real snapshot doesn't reflow or "pop" the screen.
    private var skeleton: some View {
        ScrollView {
            VStack(spacing: CookedSpacing.lg) {
                VStack(alignment: .leading, spacing: CookedSpacing.sm) {
                    SkeletonView().frame(width: 90, height: 12)
                    SkeletonView().frame(width: 210, height: 40)
                    SkeletonView().frame(width: 150, height: 14)
                    SkeletonView(cornerRadius: CookedRadius.md).frame(height: 120)
                }
                .padding(CookedSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassPanel(cornerRadius: CookedRadius.xl)

                VStack(spacing: CookedSpacing.sm) {
                    ForEach(0..<4, id: \.self) { _ in SkeletonRow() }
                }
                .padding(CookedSpacing.md)
                .glassPanel()
            }
            .padding(.horizontal, CookedSpacing.md)
        }
    }

    private func livePosition(for mint: String) -> LivePosition? {
        live.latestTick?.positions.first { $0.tokenMint == mint }
    }
}

private struct AllocationSlice: Identifiable {
    let id: String
    let label: String
    let value: Double
    let color: Color
}

private struct AllocationDonut: View {
    let slices: [AllocationSlice]
    @State private var revealed = false

    var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Value", revealed ? slice.value : (slice.id == "cash" ? 1 : 0.0001)),
                innerRadius: .ratio(0.64),
                angularInset: 2
            )
            .cornerRadius(4)
            .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
        .onAppear {
            if AmbientMotion.isEnabled {
                withAnimation(.smooth(duration: 1).delay(0.2)) { revealed = true }
            } else {
                revealed = true
            }
        }
    }
}

/// The equity curve, with its y-axis fitted to the curve's own range (not zero-based)
/// so a real 12% move reads as a real move instead of a flat line near the top.
private struct EquityChart: View {
    let points: [EquityPoint]
    let color: Color

    private var values: [Double] {
        points.map { NSDecimalNumber(decimal: $0.equityUsd).doubleValue }
    }

    var body: some View {
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.12, 1)

        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            AreaMark(
                x: .value("Point", index),
                yStart: .value("Base", low - pad),
                yEnd: .value("Equity", value)
            )
            .foregroundStyle(
                LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom)
            )
            .interpolationMethod(.catmullRom)

            LineMark(x: .value("Point", index), y: .value("Equity", value))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.catmullRom)

            if index == values.count - 1 {
                PointMark(x: .value("Point", index), y: .value("Equity", value))
                    .symbolSize(70)
                    .foregroundStyle(color)
            }
        }
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .shadow(color: color.opacity(0.5), radius: 8, y: 4)
    }
}

private struct StatTile: View {
    let symbol: String
    let color: Color
    let title: String
    let value: String
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: CookedSpacing.xs) {
            IconTile(symbol: symbol, color: color, size: 26)
            Text(value)
                .font(CookedFont.priceLarge(20))
                .foregroundStyle(CookedColor.Terminal.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(CookedFont.caption(11))
                .foregroundStyle(CookedColor.Terminal.textMuted)
            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(color).frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CookedSpacing.sm)
        .glassPanel(cornerRadius: CookedRadius.md, tint: color)
    }
}

private struct PositionRow: View {
    let position: PaperPosition
    let live: LivePosition?
    let share: Double

    private var unrealizedPct: Decimal? { live?.unrealizedPnlPct ?? position.unrealizedReturnPct }

    var body: some View {
        let palette = TokenPalette(seed: position.tokenMint)
        HStack(spacing: CookedSpacing.sm) {
            TokenLogo(mint: position.tokenMint, symbol: position.token?.symbol, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(position.token?.symbol ?? "?")
                    .font(CookedFont.headline())
                    .foregroundStyle(CookedColor.Terminal.textPrimary)
                Text("\(position.qty.formatted(.number.notation(.compactName))) @ \(position.avgCostUsd.priceString())")
                    .font(CookedFont.caption(12))
                    .foregroundStyle(CookedColor.Terminal.textMuted)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07))
                        Capsule()
                            .fill(LinearGradient(colors: [palette.primary, palette.secondary], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * share))
                    }
                }
                .frame(width: 90, height: 4)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(position.valueUsd.usdString())
                    .font(CookedFont.priceMedium())
                    .foregroundStyle(CookedColor.Terminal.textPrimary)
                ChangePill(value: unrealizedPct, font: CookedFont.priceSmall(11))
            }
        }
        .padding(.horizontal, CookedSpacing.md)
        .padding(.vertical, CookedSpacing.sm)
        .contentShape(Rectangle())
    }
}

private struct RoundTripRow: View {
    let roundTrip: PaperRoundTrip

    var body: some View {
        HStack(spacing: CookedSpacing.sm) {
            TokenLogo(mint: roundTrip.tokenMint, symbol: roundTrip.token?.symbol, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(roundTrip.token?.symbol ?? "?")
                    .font(CookedFont.body())
                    .foregroundStyle(CookedColor.Terminal.textPrimary)
                if let pct = roundTrip.returnPct {
                    Text("\(pct.signedPercentString()) return")
                        .font(CookedFont.caption(11))
                        .foregroundStyle(CookedColor.Terminal.textMuted)
                }
            }
            Spacer()
            PnLText(value: roundTrip.realizedPnlUsd, isPercent: false, font: CookedFont.priceSmall())
        }
        .padding(.horizontal, CookedSpacing.md)
        .padding(.vertical, CookedSpacing.sm)
    }
}
