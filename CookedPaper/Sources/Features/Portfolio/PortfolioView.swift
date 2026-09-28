import Foundation
import SwiftUI

struct PortfolioView: View {
    private let portfolioStore = PortfolioStore.shared
    private let live = LiveSocket.shared
    @State private var scrubIndex: Int?

    var body: some View {
        Group {
            if portfolioStore.isBootstrapping {
                skeleton
            } else if let snapshot = portfolioStore.snapshot {
                content(snapshot)
            } else if let error = portfolioStore.error {
                EmptyStateView(symbol: "wifi.slash", title: "Couldn't load your portfolio", detail: error)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground)
        .navigationTitle("Portfolio")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: String.self) { mint in
            TokenDetailView(mint: mint)
        }
    }

    private func content(_ snapshot: PaperSnapshotResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                header(snapshot)

                VStack(alignment: .leading, spacing: Space.headerGap) {
                    SectionHeader(title: "Stats")
                    StatGrid(items: stats(snapshot))
                }

                VStack(alignment: .leading, spacing: Space.headerGap) {
                    SectionHeader(title: "Positions")
                    if snapshot.positions.isEmpty {
                        EmptyStateView(
                            symbol: "chart.pie",
                            title: "No open positions",
                            detail: "Find a token in Discover and make your first trade."
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(snapshot.positions.enumerated()), id: \.element.id) { index, position in
                                NavigationLink(value: position.tokenMint) {
                                    PositionRow(position: position, live: livePosition(for: position.tokenMint))
                                }
                                .buttonStyle(.pressable)
                                if index < snapshot.positions.count - 1 { RowSeparator() }
                            }
                        }
                    }
                }

                if !snapshot.roundTrips.isEmpty {
                    let closed = Array(snapshot.roundTrips.prefix(10))
                    VStack(alignment: .leading, spacing: Space.headerGap) {
                        SectionHeader(title: "Recently closed")
                        VStack(spacing: 0) {
                            ForEach(Array(closed.enumerated()), id: \.element.id) { index, roundTrip in
                                RoundTripRow(roundTrip: roundTrip)
                                if index < closed.count - 1 { RowSeparator() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s8)
            .padding(.bottom, Space.section)
        }
        .scrollIndicators(.hidden)
        .refreshable { try? await portfolioStore.refresh() }
    }

    // MARK: - Header

    private func header(_ snapshot: PaperSnapshotResponse) -> some View {
        let equity = live.latestTick?.equityUsd ?? snapshot.equityUsd
        let values = snapshot.equityCurve.points.map { NSDecimalNumber(decimal: $0.equityUsd).doubleValue }
        let scrubbed: Double? = scrubIndex.flatMap { values.indices.contains($0) ? values[$0] : nil }
        let shownEquity = scrubbed.map { Decimal($0) } ?? equity
        let start = snapshot.portfolio.startingBalanceUsd
        let change = shownEquity - start
        let percent: Decimal? = start > 0 ? change / start * 100 : nil

        return VStack(alignment: .leading, spacing: Space.s24) {
            VStack(alignment: .leading, spacing: Space.s8) {
                SimulatedCaption()
                Text(PriceFormat.usd(shownEquity))
                    .heroPriceStyle()
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: Space.s4) {
                    Text("\(PriceFormat.signedUSD(change)) (\(PriceFormat.change(percent)))")
                        .foregroundStyle(Color.direction(percent))
                        .contentTransition(.numericText())
                    Text(scrubIndex == nil ? "All time" : "At this point")
                        .foregroundStyle(Color.textSecondary)
                }
                .font(.rowSubvalue)
            }

            if values.count > 1 {
                PriceLineChart(values: values, selectedIndex: $scrubIndex)
                    .frame(height: 160)
                    .padding(.horizontal, -Space.margin)
            }
        }
    }

    private func stats(_ snapshot: PaperSnapshotResponse) -> [StatItem] {
        let cash = live.latestTick?.cashUsd ?? snapshot.cashUsd
        let stats = snapshot.stats
        return [
            StatItem(label: "Cash", value: PriceFormat.usd(cash)),
            StatItem(
                label: "Unrealized P&L",
                value: stats.unrealizedPnlUsd.usd.map(PriceFormat.signedUSD) ?? "—",
                color: Color.direction(stats.unrealizedPnlUsd.usd)
            ),
            StatItem(label: "Win rate", value: stats.winRatePct.pct.map { "\($0.formatted(.number.precision(.fractionLength(0))))%" } ?? "—"),
            StatItem(label: "Trades", value: "\(stats.tradeCount)"),
        ]
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            SkeletonBlock(width: 120, height: 14)
            SkeletonBlock(width: 220, height: 44)
            SkeletonBlock(width: 160, height: 16)
            SkeletonBlock(height: 160, cornerRadius: Radius.card)
                .padding(.bottom, Space.s24)
            ForEach(0..<4, id: \.self) { _ in SkeletonRow() }
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s8)
    }

    private func livePosition(for mint: String) -> LivePosition? {
        live.latestTick?.positions.first { $0.tokenMint == mint }
    }
}

/// Avatar | symbol over quantity | value over return.
private struct PositionRow: View {
    let position: PaperPosition
    let live: LivePosition?

    private var unrealizedPct: Decimal? { live?.unrealizedPnlPct ?? position.unrealizedReturnPct }

    var body: some View {
        ListRow(
            title: position.token?.symbol ?? "?",
            subtitle: "\(PriceFormat.quantity(position.qty)) tokens"
        ) {
            TokenAvatar(mint: position.tokenMint, symbol: position.token?.symbol)
        } trailing: {
            Text(PriceFormat.usd(position.valueUsd))
                .font(.rowValue)
                .foregroundStyle(Color.textPrimary)
                .contentTransition(.numericText())
            ChangeText(percent: unrealizedPct)
        }
    }
}

private struct RoundTripRow: View {
    let roundTrip: PaperRoundTrip

    var body: some View {
        ListRow(
            title: roundTrip.token?.symbol ?? "?",
            subtitle: roundTrip.returnPct.map { "\(PriceFormat.change($0)) return" }
        ) {
            TokenAvatar(mint: roundTrip.tokenMint, symbol: roundTrip.token?.symbol)
        } trailing: {
            Text(PriceFormat.signedUSD(roundTrip.realizedPnlUsd))
                .font(.rowValue)
                .foregroundStyle(Color.direction(roundTrip.realizedPnlUsd))
        }
    }
}
