import Foundation
import SwiftUI

struct TokenDetailView: View {
    let mint: String

    @State private var profile: TokenProfileResponse?
    @State private var candles: TokenCandlesResponse?
    @State private var range: ChartRange = .day
    @State private var showsCandles = false
    @State private var scrubIndex: Int?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var tradeSide: TradeSide?

    private var position: PaperPosition? {
        PortfolioStore.shared.snapshot?.positions.first { $0.tokenMint == mint }
    }

    /// Closes in order, gaps dropped — the line chart's series.
    private var closes: [Double] {
        (candles?.candles ?? []).compactMap { $0.map { NSDecimalNumber(decimal: $0.close).doubleValue } }
    }

    var body: some View {
        Group {
            if isLoading {
                loadingState
            } else if let errorMessage {
                EmptyStateView(symbol: "wifi.slash", title: "Couldn't load this token", detail: errorMessage)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground)
        .reservesTabBarSpace()
        .navigationTitle(profile?.token.symbol ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $tradeSide) { side in
            TradeSheetView(
                mint: mint,
                side: side,
                tokenSymbol: profile?.token.symbol ?? "token",
                priceUsd: profile?.market.priceUsd.value
            )
        }
        .task { await load() }
        .onChange(of: range) { _, _ in
            scrubIndex = nil
            Task { await loadCandles() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                VStack(alignment: .leading, spacing: Space.s24) {
                    header
                    chart
                    rangePicker
                }

                VStack(alignment: .leading, spacing: Space.headerGap) {
                    SectionHeader(title: "Stats")
                    StatGrid(items: marketStats)
                }

                if let position {
                    VStack(alignment: .leading, spacing: Space.headerGap) {
                        SectionHeader(title: "Your position")
                        StatGrid(items: positionStats(position))
                    }
                }

                Text(candles?.isRelayed ?? false ? "Data · GeckoTerminal" : "Data · Cooked")
                    .font(.caption13)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s8)
            .padding(.bottom, Space.s24)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
    }

    // MARK: - Header

    /// Price and change for what's on screen: the scrubbed point while dragging,
    /// otherwise the live price with the period's change.
    private var displayed: (price: Decimal?, change: Decimal?, percent: Decimal?, caption: String) {
        let series = closes
        if let scrubIndex, series.indices.contains(scrubIndex), let first = series.first, first > 0 {
            let value = series[scrubIndex]
            return (
                Decimal(value),
                Decimal(value - first),
                Decimal((value - first) / first * 100),
                scrubCaption(at: scrubIndex)
            )
        }

        let price = profile?.market.priceUsd.value
        let percent: Decimal?
        if range == .day {
            percent = profile?.market.change24h.value
        } else if let first = series.first, let last = series.last, first > 0 {
            percent = Decimal((last - first) / first * 100)
        } else {
            percent = nil
        }
        // Amount moved = price − price / (1 + pct/100), i.e. relative to the period
        // start, so "−$0.08 (−4.12%)" agree with each other.
        var change: Decimal?
        if let price, let percent {
            let divisor = 1 + percent / 100
            if divisor != 0 { change = price - price / divisor }
        }
        return (price, change, percent, range.changeCaption)
    }

    private func scrubCaption(at index: Int) -> String {
        let present = (candles?.candles ?? []).compactMap { $0 }
        guard present.indices.contains(index), let date = Self.parseDate(present[index].bucketStart) else { return "" }
        return range == .all || range == .month
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private var header: some View {
        let shown = displayed
        return VStack(alignment: .leading, spacing: Space.s8) {
            HStack(spacing: Space.s12) {
                TokenAvatar(mint: mint, symbol: profile?.token.symbol, logoURL: profile?.token.logoUri.flatMap(URL.init(string:)), size: 48)
                Text(profile?.token.name ?? profile?.token.symbol ?? "")
                    .font(.rowTitle)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .padding(.bottom, Space.s4)

            PriceText(value: shown.price, font: .heroPrice)
                .tracking(-0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(spacing: Space.s4) {
                if let change = shown.change, let percent = shown.percent {
                    Text("\(PriceFormat.signedPrice(change, reference: shown.price)) (\(PriceFormat.change(percent)))")
                        .foregroundStyle(Color.direction(percent))
                        .contentTransition(.numericText())
                } else {
                    Text("—").foregroundStyle(Color.textSecondary)
                }
                Text(shown.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .font(.rowSubvalue)
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chart: some View {
        Group {
            if showsCandles {
                CandleChartView(
                    candles: candles?.candles ?? [],
                    isRelayed: candles?.isRelayed ?? false,
                    interval: range.interval
                )
            } else if closes.count > 1 {
                PriceLineChart(values: closes, selectedIndex: $scrubIndex)
            } else {
                EmptyStateView(symbol: "chart.xyaxis.line", title: "No chart yet", detail: "There's no trading history for this window.")
            }
        }
        .frame(height: 220)
        .padding(.horizontal, -Space.margin)
    }

    private var rangePicker: some View {
        HStack(spacing: Space.s4) {
            ForEach(ChartRange.allCases) { option in
                Segment(title: option.rawValue, isSelected: option == range) {
                    range = option
                }
            }
            Button {
                Haptics.selection()
                withAnimation(Motion.standard) { showsCandles.toggle() }
            } label: {
                Image(systemName: showsCandles ? "chart.xyaxis.line" : "chart.bar.xaxis")
                    .font(.caption13)
                    .foregroundStyle(showsCandles ? Color.textPrimary : Color.textSecondary)
                    .frame(width: 44, height: Metrics.chipHeight)
                    .background(showsCandles ? Color.appSurfaceElevated : Color.clear, in: Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(showsCandles ? "Show line chart" : "Show candles")
        }
    }

    // MARK: - Stats

    private var marketStats: [StatItem] {
        let market = profile?.market
        return [
            StatItem(label: "Market cap", value: market?.marketCapUsd.value.map(PriceFormat.compact) ?? "—"),
            StatItem(label: "Liquidity", value: market?.liquidityUsd.value.map(PriceFormat.compact) ?? "—"),
            StatItem(label: "24h volume", value: market?.volume24hUsd.value.map(PriceFormat.compact) ?? "—"),
            StatItem(
                label: "24h change",
                value: PriceFormat.change(market?.change24h.value),
                color: Color.direction(market?.change24h.value)
            ),
        ]
    }

    private func positionStats(_ position: PaperPosition) -> [StatItem] {
        [
            StatItem(label: "Value", value: PriceFormat.usd(position.valueUsd)),
            StatItem(label: "Quantity", value: PriceFormat.quantity(position.qty)),
            StatItem(label: "Average cost", value: PriceFormat.price(position.avgCostUsd)),
            StatItem(
                label: "Return",
                value: PriceFormat.change(position.unrealizedReturnPct),
                color: Color.direction(position.unrealizedReturnPct)
            ),
        ]
    }

    // MARK: - Actions

    /// Pinned to the bottom; content scrolling beneath fades out into black above
    /// it so nothing visibly collides with the buttons.
    private var actionBar: some View {
        HStack(spacing: Space.s12) {
            if position != nil {
                Button("Sell") {
                    Haptics.tap()
                    tradeSide = .sell
                }
                .buttonStyle(.secondary)
            }
            Button("Buy") {
                Haptics.tap()
                tradeSide = .buy
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("tokenDetail.buy")
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s24)
        .padding(.bottom, Space.s8)
        .background(
            // The fade the spec asks for: transparent at the top edge to solid black
            // behind the buttons.
            LinearGradient(
                stops: [.init(color: Color.appBackground.opacity(0), location: 0), .init(color: Color.appBackground, location: 0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            SkeletonBlock(width: 48, height: 48, cornerRadius: 24)
            SkeletonBlock(width: 180, height: 44)
            SkeletonBlock(width: 140, height: 16)
            SkeletonBlock(height: 220, cornerRadius: Radius.card)
                .padding(.top, Space.s12)
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s8)
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let profileFetch = TokenAPI.profile(mint: mint)
            async let candlesFetch = TokenAPI.candles(mint: mint, interval: range.interval, limit: range.limit)
            profile = try await profileFetch
            candles = try await candlesFetch
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func parseDate(_ raw: String) -> Date? {
        isoFormatter.date(from: raw) ?? isoFormatterFractional.date(from: raw)
    }

    private func loadCandles() async {
        candles = try? await TokenAPI.candles(mint: mint, interval: range.interval, limit: range.limit)
    }
}

extension TradeSide: Identifiable {
    var id: String { rawValue }
}
