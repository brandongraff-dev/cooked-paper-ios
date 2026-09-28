import Charts
import Foundation
import SwiftUI

struct PortfolioView: View {
    private let portfolioStore = PortfolioStore.shared
    private let live = LiveSocket.shared
    @State private var animatedRowIDs: Set<String> = []

    var body: some View {
        ZStack {
            CookedColor.Terminal.bgBase.ignoresSafeArea()

            if portfolioStore.isBootstrapping {
                skeleton
            } else if let snapshot = portfolioStore.snapshot {
                content(snapshot)
            } else if let error = portfolioStore.error {
                EmptyStateView(symbol: "wifi.slash", title: "Couldn't load your portfolio", detail: error)
            }
        }
        .navigationTitle(portfolioStore.snapshot?.portfolio.name ?? "Portfolio")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SimulatedBadge() }
        }
    }

    private func content(_ snapshot: PaperSnapshotResponse) -> some View {
        List {
            Section {
                equityHeader(snapshot)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if snapshot.equityCurve.points.count > 1 {
                    EquitySparkline(points: snapshot.equityCurve.points)
                        .frame(height: 100)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            if snapshot.positions.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "chart.pie",
                        title: "No open positions",
                        detail: "Head to Discover and make your first trade — it's instant, and it's not real money."
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                Section("Positions") {
                    ForEach(Array(snapshot.positions.enumerated()), id: \.element.id) { index, position in
                        NavigationLink(value: position.tokenMint) {
                            PositionRow(position: position, live: livePosition(for: position.tokenMint))
                        }
                        .listRowBackground(CookedColor.Terminal.bgSurface)
                        .staggeredEntrance(index: index, id: position.id, animatedIDs: $animatedRowIDs)
                    }
                }
            }

            if !snapshot.roundTrips.isEmpty {
                Section("Recently closed") {
                    ForEach(Array(snapshot.roundTrips.prefix(10).enumerated()), id: \.element.id) { offset, roundTrip in
                        RoundTripRow(roundTrip: roundTrip)
                            .listRowBackground(CookedColor.Terminal.bgSurface)
                            .staggeredEntrance(
                                index: snapshot.positions.count + offset,
                                id: roundTrip.id,
                                animatedIDs: $animatedRowIDs
                            )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { try? await portfolioStore.refresh() }
        .navigationDestination(for: String.self) { mint in
            TokenDetailView(mint: mint)
        }
    }

    /// Shaped like `content(_:)`'s own `List` — same style, same section chrome — so
    /// swapping in the real snapshot doesn't reflow or "pop" the screen.
    private var skeleton: some View {
        List {
            Section {
                VStack(spacing: CookedSpacing.xs) {
                    SkeletonView().frame(width: 90, height: 12)
                    SkeletonView().frame(width: 170, height: 36)
                    SkeletonView().frame(width: 130, height: 14)
                    SkeletonView().frame(width: 150, height: 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, CookedSpacing.md)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section("Positions") {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonRow()
                        .listRowBackground(CookedColor.Terminal.bgSurface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func equityHeader(_ snapshot: PaperSnapshotResponse) -> some View {
        let equity = live.latestTick?.equityUsd ?? snapshot.equityUsd
        let cash = live.latestTick?.cashUsd ?? snapshot.cashUsd
        let unrealized = snapshot.stats.unrealizedPnlUsd.usd

        return VStack(spacing: CookedSpacing.xs) {
            Text("Total equity")
                .font(CookedFont.caption())
                .foregroundStyle(CookedColor.Terminal.textMuted)
            Text(equity.usdString())
                .font(CookedFont.priceDisplay(40))
                .foregroundStyle(CookedColor.Terminal.textPrimary)
            HStack(spacing: CookedSpacing.xs) {
                PnLText(value: unrealized, isPercent: false, font: CookedFont.priceMedium())
                if let pct = snapshot.stats.returnPct.pct {
                    Text("(\(pct.signedPercentString()) all-time)")
                        .font(CookedFont.caption())
                        .foregroundStyle(CookedColor.Terminal.textMuted)
                }
            }
            Text("\(cash.usdString()) cash available")
                .font(CookedFont.caption())
                .foregroundStyle(CookedColor.Terminal.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CookedSpacing.md)
    }

    private func livePosition(for mint: String) -> LivePosition? {
        live.latestTick?.positions.first { $0.tokenMint == mint }
    }
}

private struct EquitySparkline: View {
    let points: [EquityPoint]

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Time", point.at), y: .value("Equity", NSDecimalNumber(decimal: point.equityUsd).doubleValue))
                .foregroundStyle(CookedColor.Terminal.accent)
                .interpolationMethod(.monotone)
            AreaMark(x: .value("Time", point.at), y: .value("Equity", NSDecimalNumber(decimal: point.equityUsd).doubleValue))
                .foregroundStyle(
                    LinearGradient(colors: [CookedColor.Terminal.accent.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
                )
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

private struct PositionRow: View {
    let position: PaperPosition
    let live: LivePosition?

    private var unrealizedPct: Decimal? { live?.unrealizedPnlPct ?? position.unrealizedReturnPct }

    var body: some View {
        HStack(spacing: CookedSpacing.sm) {
            TokenLogo(mint: position.tokenMint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(position.token?.symbol ?? "?")
                    .font(CookedFont.headline())
                    .foregroundStyle(CookedColor.Terminal.textPrimary)
                Text("\(position.qty.formatted()) @ \(position.avgCostUsd.usdString(fractionDigits: position.avgCostUsd < 1 ? 6 : 2))")
                    .font(CookedFont.caption())
                    .foregroundStyle(CookedColor.Terminal.textMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(position.valueUsd.usdString())
                    .font(CookedFont.priceMedium())
                    .foregroundStyle(CookedColor.Terminal.textPrimary)
                PnLText(value: unrealizedPct, isPercent: true, font: CookedFont.caption())
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RoundTripRow: View {
    let roundTrip: PaperRoundTrip

    var body: some View {
        HStack(spacing: CookedSpacing.sm) {
            TokenLogo(mint: roundTrip.tokenMint, size: 28)
            Text(roundTrip.token?.symbol ?? "?")
                .font(CookedFont.body())
                .foregroundStyle(CookedColor.Terminal.textPrimary)
            Spacer()
            PnLText(value: roundTrip.realizedPnlUsd, isPercent: false, font: CookedFont.priceSmall())
        }
    }
}
