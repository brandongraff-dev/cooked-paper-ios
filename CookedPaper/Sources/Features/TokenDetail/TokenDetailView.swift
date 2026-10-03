import Foundation
import SwiftUI

struct TokenDetailView: View {
    let mint: String

    @State private var profile: TokenProfileResponse?
    @State private var candles: TokenCandlesResponse?
    @State private var range: ChartRange = .live
    @State private var feed: MarketFeed
    @State private var showsCandles = false
    @State private var scrubIndex: Int?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var tradeSide: TradeSide?
    @State private var showsLeverage = false
    /// The person's own buys and sells on this token, drawn on the chart.
    @State private var myTrades: [ChartTradeMarker] = []
    @Environment(\.scenePhase) private var scenePhase

    init(mint: String) {
        self.mint = mint
        // Shared with Discover's prefetch, so a token opened from a row it already
        // fetched draws its chart on the first frame.
        _feed = State(initialValue: MarketFeedStore.shared.feed(for: mint))
    }

    private static let stillFrames = ProcessInfo.processInfo.environment["UITEST_STILL_FRAMES"] == "1"

    private var position: PaperPosition? {
        PortfolioStore.shared.snapshot?.positions.first { $0.tokenMint == mint }
    }

    /// Closes in order, gaps dropped — the line chart's series.
    /// Changes whenever a trade lands, so the markers reload.
    private var tradesKey: String {
        let snapshot = PortfolioStore.shared.snapshot
        return "\(snapshot?.stats.tradeCount ?? 0)-\(snapshot?.leveragedPositions?.count ?? 0)-\(snapshot?.leveragedRoundTrips?.count ?? 0)"
    }

    /// Each of the person's trades placed on the candle bucket it fell in; trades
    /// outside the shown range are left off.
    private var indexedMarkers: [(index: Int, marker: ChartTradeMarker)] {
        let starts = (candles?.candles ?? []).compactMap { $0 }.compactMap { Self.parseDate($0.bucketStart) }
        guard let first = starts.first, let last = starts.last else { return [] }
        let startMs = starts.map { Int64($0.timeIntervalSince1970 * 1000) }
        let firstMs = Int64(first.timeIntervalSince1970 * 1000)
        let endMs = Int64(last.timeIntervalSince1970 * 1000) + range.interval.milliseconds
        return myTrades.compactMap { marker -> (index: Int, marker: ChartTradeMarker)? in
            guard marker.t >= firstMs, marker.t < endMs else { return nil }
            return (index: startMs.lastIndex { $0 <= marker.t } ?? 0, marker: marker)
        }
    }

    private var closes: [Double] {
        displayedCandles.compactMap { $0.map { NSDecimalNumber(decimal: $0.close).doubleValue } }
    }

    /// The fetched candles with the live price folded into the newest bucket, so a
    /// non-LIVE chart moves between its periodic refetches. Only when that bucket is
    /// the one happening now (a relayed series whose last candle is hours old is left
    /// alone) and only for a USD series — the tape is in dollars, and a
    /// quote-denominated candle must never be overwritten with one.
    private var displayedCandles: [Candle?] {
        let fetched = candles?.candles ?? []
        guard range != .live,
              candles?.denomination == "usd",
              let live = feed.latestPrice, live > 0,
              let lastIndex = fetched.lastIndex(where: { $0 != nil }),
              var last = fetched[lastIndex],
              let start = Self.parseDate(last.bucketStart)
        else { return fetched }
        let elapsed = Date().timeIntervalSince(start)
        let bucketSeconds = TimeInterval(range.interval.milliseconds) / 1000
        guard elapsed >= 0, elapsed < bucketSeconds else { return fetched }
        last.close = live
        if live > last.high { last.high = live }
        if live < last.low { last.low = live }
        var folded = fetched
        folded[lastIndex] = last
        return folded
    }

    /// Restarts the periodic candle refetch whenever the range changes or the app
    /// comes and goes from the foreground.
    private var chartRefreshKey: String {
        "\(range.rawValue)|\(scenePhase == .active)"
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
        .sheet(isPresented: $showsLeverage) {
            LeverageSheetView(mint: mint, tokenSymbol: profile?.token.symbol ?? "token")
        }
        .task {
            // The live tape starts alongside the profile, not after it.
            syncFeed()
            await load()
        }
        .onChange(of: range) { _, _ in
            scrubIndex = nil
            syncFeed()
            Task { await loadCandles() }
        }
        .onChange(of: scenePhase) { _, _ in syncFeed() }
        .onDisappear { feed.stop() }
        // Cancelled on disappear and whenever the key changes, so it only ever runs
        // while this range is on screen with the app active.
        .task(id: chartRefreshKey) { await refreshCandlesPeriodically() }
        .task(id: tradesKey) { myTrades = await ChartTradeMarkers.load(mint: mint) }
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
    /// otherwise the live price with the period's change. On LIVE that's the price at
    /// the chart's playhead, so the header never runs ahead of the line.
    private func displayed(livePrice: Decimal?) -> (price: Decimal?, change: Decimal?, percent: Decimal?, caption: String) {
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

        let price = livePrice ?? profile?.market.priceUsd.value
        let percent: Decimal?
        if range == .day || range == .live {
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
        VStack(alignment: .leading, spacing: Space.s8) {
            HStack(spacing: Space.s12) {
                TokenAvatar(mint: mint, symbol: profile?.token.symbol, logoURL: profile?.token.logoUri.flatMap(URL.init(string:)), size: 48)
                Text(profile?.token.name ?? profile?.token.symbol ?? "")
                    .font(.rowTitle)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: Space.s8)
                if range == .live {
                    // Once a second is plenty to notice the feed going quiet.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        LiveStatusBadge(state: feed.effectiveState(at: context.date))
                    }
                }
            }
            .padding(.bottom, Space.s4)

            // Re-reads the playhead price ten times a second on LIVE (each trade
            // lands at its own moment, not when its batch arrived). Other ranges show
            // the newest price held, which redraws as the feed delivers.
            TimelineView(.animation(minimumInterval: 0.1, paused: range != .live || Self.stillFrames)) { context in
                priceLines(livePrice: range == .live
                    ? feed.displayPrice(at: Self.stillFrames ? Date() : context.date)
                    : feed.latestPrice)
            }
        }
    }

    private func priceLines(livePrice: Decimal?) -> some View {
        let shown = displayed(livePrice: livePrice)
        return VStack(alignment: .leading, spacing: Space.s8) {
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
            if range == .live {
                LiveChartView(
                    feed: feed,
                    color: (profile?.market.change24h.value ?? 0) < 0 ? .negative : .positive,
                    style: showsCandles ? .candles : .line,
                    markers: myTrades
                )
            } else if showsCandles {
                CandleChartView(
                    candles: displayedCandles,
                    isRelayed: candles?.isRelayed ?? false,
                    interval: range.interval
                )
            } else if closes.count > 1 {
                PriceLineChart(values: closes, selectedIndex: $scrubIndex, markers: indexedMarkers)
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
            Button {
                Haptics.tap()
                showsLeverage = true
            } label: {
                Label("Leverage", systemImage: "bolt.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("tokenDetail.leverage")
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
        syncFeed()
    }

    /// Runs the live feed while this screen is up and the app is in the
    /// foreground — on every range, since the header price and the newest candle
    /// follow it too; it resumes from the last seq it saw when the app comes back.
    private func syncFeed() {
        if scenePhase != .background {
            feed.start()
        } else {
            feed.stop()
        }
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

    /// Refetches the range's candles in place while it's on screen — often enough
    /// that a candle closing shows up without leaving the screen, rarely enough
    /// that a month-long view doesn't hammer the API. Silent: a failed refetch
    /// keeps the chart that's already drawn.
    private func refreshCandlesPeriodically() async {
        guard scenePhase == .active, let interval = range.refreshInterval else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            let requested = range
            guard !isLoading,
                  let fresh = try? await TokenAPI.candles(mint: mint, interval: requested.interval, limit: requested.limit),
                  !Task.isCancelled, requested == range
            else { continue }
            candles = fresh
        }
    }

    private func loadCandles() async {
        candles = try? await TokenAPI.candles(mint: mint, interval: range.interval, limit: range.limit)
    }
}

extension ChartRange {
    /// How often a non-LIVE range refetches its candles while on screen; nil for
    /// LIVE, which streams. Roughly a quarter of a bucket for the short ranges.
    var refreshInterval: Duration? {
        switch self {
        case .live: nil
        case .hour: .seconds(15)
        case .day: .seconds(30)
        case .week: .seconds(60)
        case .month, .all: .seconds(120)
        }
    }
}

extension TradeSide: Identifiable {
    var id: String { rawValue }
}
