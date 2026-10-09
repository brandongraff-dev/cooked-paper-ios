import Foundation
import SwiftUI

struct PortfolioView: View {
    private let portfolioStore = PortfolioStore.shared
    private let live = LiveSocket.shared
    @State private var scrubIndex: Int?
    @State private var selectedLeveraged: LeveragedSelection?
    @State private var showsCookedMeter = false

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
        .screenBackground()
        .reservesTabBarSpace()
        .navigationTitle("Portfolio")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: String.self) { mint in
            TokenDetailView(mint: mint)
        }
        .sheet(item: $selectedLeveraged) { selection in
            LeveragedPositionSheet(positionId: selection.id)
        }
        .sheet(isPresented: $showsCookedMeter) {
            CookedMeterSheet(reading: cookedMeterReading(portfolioStore.snapshot))
        }
    }

    private func content(_ snapshot: PaperSnapshotResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                header(snapshot)

                VStack(alignment: .leading, spacing: Space.headerGap) {
                    StatGrid(items: stats(snapshot))
                    CookedMeterCard(reading: cookedMeterReading(snapshot)) {
                        showsCookedMeter = true
                    }
                }

                VStack(alignment: .leading, spacing: Space.headerGap) {
                    SectionHeader(
                        title: "Positions",
                        caption: snapshot.positions.isEmpty ? nil : "\(snapshot.positions.count)"
                    )
                    if snapshot.positions.isEmpty {
                        EmptyStateView(
                            symbol: "chart.pie.fill",
                            title: "No open positions",
                            action: EmptyStateAction(
                                title: "Make your first trade",
                                identifier: "portfolio.firstTrade"
                            ) {
                                DeepLinkRouter.shared.openTab(.discover)
                            },
                            compact: true
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
                        .glassList()
                    }
                }

                let leveraged = snapshot.leveragedPositions ?? []
                if !leveraged.isEmpty {
                    VStack(alignment: .leading, spacing: Space.headerGap) {
                        SectionHeader(
                            title: "Leverage",
                            caption: snapshot.lockedMarginUsd.map { "\(PriceFormat.usd($0)) margin" }
                        )
                        VStack(spacing: 0) {
                            ForEach(Array(leveraged.enumerated()), id: \.element.id) { index, position in
                                Button {
                                    Haptics.tap()
                                    selectedLeveraged = LeveragedSelection(id: position.id)
                                } label: {
                                    LeveragedPositionRow(position: position)
                                }
                                .buttonStyle(.pressable)
                                .accessibilityIdentifier("portfolio.leveraged.\(index)")
                                if index < leveraged.count - 1 { RowSeparator() }
                            }
                        }
                        .glassList()
                    }
                }

                let closedLeveraged = Array((snapshot.leveragedRoundTrips ?? []).prefix(5))
                if !snapshot.roundTrips.isEmpty || !closedLeveraged.isEmpty {
                    let closed = Array(snapshot.roundTrips.prefix(10))
                    VStack(alignment: .leading, spacing: Space.headerGap) {
                        SectionHeader(title: "Recently closed")
                        VStack(spacing: 0) {
                            ForEach(Array(closedLeveraged.enumerated()), id: \.element.id) { index, roundTrip in
                                LeveragedRoundTripRow(roundTrip: roundTrip)
                                if index < closedLeveraged.count - 1 || !closed.isEmpty { RowSeparator() }
                            }
                            ForEach(Array(closed.enumerated()), id: \.element.id) { index, roundTrip in
                                RoundTripRow(roundTrip: roundTrip)
                                if index < closed.count - 1 { RowSeparator() }
                            }
                        }
                        .glassList()
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
                Kicker(text: "Paper · Simulated")
                Text(PriceFormat.usd(shownEquity))
                    .heroPriceStyle()
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: Space.s8) {
                    ChangePill(percent: percent)
                    Text(PriceFormat.signedUSD(change))
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
            StatItem(label: "Cash", value: PriceFormat.usd(cash), symbol: "dollarsign", tint: .tileBlue),
            StatItem(
                label: "Unrealized P&L",
                value: stats.unrealizedPnlUsd.usd.map(PriceFormat.signedUSD) ?? "—",
                color: Color.direction(stats.unrealizedPnlUsd.usd),
                symbol: "chart.line.uptrend.xyaxis",
                tint: .tilePurple
            ),
            StatItem(label: "Win rate", value: stats.winRatePct.pct.map { "\($0.formatted(.number.precision(.fractionLength(0))))%" } ?? "—", symbol: "target", tint: .tileOrange),
            StatItem(label: "Trades", value: "\(stats.tradeCount)", symbol: "arrow.left.arrow.right", tint: .tileTeal),
        ]
    }

    /// The Cooked meter, worked out on the device from the snapshot alone.
    private func cookedMeterReading(_ snapshot: PaperSnapshotResponse?) -> CookedMeter.Reading {
        guard let snapshot else { return CookedMeter.reading(CookedMeter.Input(equityUsd: 0)) }
        return CookedMeter.reading(CookedMeter.Input(snapshot: snapshot))
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

private struct LeveragedSelection: Identifiable {
    let id: String
}

/// Avatar | symbol + "5x Long" over liquidation distance | value over return on margin.
private struct LeveragedPositionRow: View {
    let position: PaperLeveragedPosition

    private var subtitle: String {
        guard let distance = position.distanceToLiquidationPct else {
            return "Liq. \(PriceFormat.price(position.liquidationPriceUsd))"
        }
        let away = abs(distance).formatted(.number.precision(.fractionLength(1)))
        return "Liq. \(PriceFormat.price(position.liquidationPriceUsd)) · \(away)% away"
    }

    var body: some View {
        HStack(spacing: Metrics.avatarGap) {
            TokenAvatar(mint: position.tokenMint, symbol: position.token?.symbol)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s8) {
                    Text(position.symbol)
                        .font(.rowTitle)
                        .foregroundStyle(Color.textPrimary)
                    LeverageBadge(position: position)
                }
                Text(subtitle)
                    .font(.rowSubvalue)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(PriceFormat.usd(position.valueUsd))
                    .font(.rowValue)
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                if position.unrealizedPnlUsd == nil {
                    Text("Unmeasured")
                        .font(.rowSubvalue)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    ChangeText(percent: position.unrealizedReturnOnMarginPct)
                }
            }
        }
        .frame(minHeight: Metrics.rowHeight)
        .contentShape(Rectangle())
    }
}

private struct LeveragedRoundTripRow: View {
    let roundTrip: PaperLeveragedRoundTrip

    var body: some View {
        ListRow(
            title: roundTrip.token?.symbol ?? "?",
            subtitle: roundTrip.isLiquidated
                ? "\(roundTrip.leverage)x \(roundTrip.direction.title) · Liquidated"
                : "\(roundTrip.leverage)x \(roundTrip.direction.title) · \(PriceFormat.change(roundTrip.returnOnMarginPct)) on margin"
        ) {
            TokenAvatar(mint: roundTrip.tokenMint, symbol: roundTrip.token?.symbol)
        } trailing: {
            Text(PriceFormat.signedUSD(roundTrip.realizedPnlUsd))
                .font(.rowValue)
                .foregroundStyle(Color.direction(roundTrip.realizedPnlUsd))
        }
    }
}
