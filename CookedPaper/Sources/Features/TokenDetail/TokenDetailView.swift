import Foundation
import SwiftUI
import UIKit

struct TokenDetailView: View {
    let mint: String

    @State private var profile: TokenProfileResponse?
    @State private var candles: TokenCandlesResponse?
    @State private var interval: CandleInterval = .oneHour
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var tradeSide: TradeSide?
    @State private var isWatched = false
    @State private var showGuestWatchAlert = false
    @State private var isContentVisible = false
    @State private var chartAlertLevels: [ChartAlertLevel] = []

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    private var palette: TokenPalette { TokenPalette(seed: mint) }

    var body: some View {
        ZStack {
            AmbientBackground(colors: [palette.primary, palette.secondary, CookedColor.Prism.indigo])

            if isLoading {
                ProgressView().tint(CookedColor.Brand.fill)
            } else if let errorMessage {
                EmptyStateView(symbol: "wifi.slash", title: "Couldn't load this token", detail: errorMessage)
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: CookedSpacing.lg) {
                            header
                                .entrance(isContentVisible, reduceMotion: reduceMotion)
                            chartSection
                                .entrance(isContentVisible, reduceMotion: reduceMotion, delay: 0.06)
                            statsGrid
                                .entrance(isContentVisible, reduceMotion: reduceMotion, delay: 0.12)
                        }
                        .padding(CookedSpacing.md)
                        .padding(.bottom, 96)
                    }
                    .scrollIndicators(.hidden)
                }
                .overlay(alignment: .bottom) {
                    tradeBar
                }
                .onAppear { isContentVisible = true }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: toggleWatch) {
                    Image(systemName: isWatched ? "star.fill" : "star")
                        .foregroundStyle(isWatched ? CookedColor.Brand.fill : CookedColor.Terminal.textMuted)
                        .animation(CookedMotion.standard, value: isWatched)
                }
            }
            ToolbarItem(placement: .principal) {
                Text(profile?.token.symbol ?? "")
                    .font(CookedFont.headline())
                    .foregroundStyle(CookedColor.Terminal.textPrimary)
            }
        }
        .sheet(item: $tradeSide) { side in
            TradeSheetView(mint: mint, side: side, tokenSymbol: profile?.token.symbol ?? "token")
        }
        .alert("Sign in to save a watchlist", isPresented: $showGuestWatchAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Sign in from Settings to save tokens.")
        }
        .task { await load() }
        .onChange(of: interval) { _, _ in Task { await loadCandles() } }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: CookedSpacing.md) {
            TokenLogo(mint: mint, symbol: profile?.token.symbol, size: 60)
                .glow(palette.primary, radius: 26, opacity: 0.55)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: CookedSpacing.xxs) {
                    Text(profile?.token.name ?? mint)
                        .font(CookedFont.body())
                        .foregroundStyle(CookedColor.Terminal.textSecondary)
                        .lineLimit(1)
                    if profile?.token.isVerified ?? false {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: CookedIconSize.xs))
                            .foregroundStyle(CookedColor.Verification.mark)
                    }
                }
                if let price = profile?.market.priceUsd.value {
                    RollingNumber(
                        value: NSDecimalNumber(decimal: price).doubleValue,
                        format: { $0.formatted(.currency(code: "USD").precision(.fractionLength(price < 1 ? 6 : 2))) },
                        font: CookedFont.priceDisplay(32)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                } else {
                    Text("—").font(CookedFont.priceDisplay(32)).foregroundStyle(CookedColor.Terminal.textMuted)
                }
                HStack(spacing: CookedSpacing.xs) {
                    ChangePill(value: profile?.market.change24h.value)
                    Text("24h")
                        .font(CookedFont.caption(12))
                        .foregroundStyle(CookedColor.Terminal.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: CookedSpacing.sm) {
            CandleChartView(
                candles: candles?.candles ?? [],
                isRelayed: candles?.isRelayed ?? false,
                interval: interval,
                alertLevels: chartAlertLevels
            )
            .frame(height: 260)

            HStack(spacing: CookedSpacing.xs) {
                CookedGlassContainer(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(CandleInterval.allCases) { option in
                            CookedChip(title: option.label, isSelected: option == interval) {
                                interval = option
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if candles?.isRelayed ?? false {
                Label("Relayed data · GeckoTerminal", systemImage: "antenna.radiowaves.left.and.right")
                    .font(CookedFont.caption(11))
                    .foregroundStyle(CookedColor.Terminal.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(CookedSpacing.sm)
        .glassPanel(cornerRadius: CookedRadius.lg)
    }

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: CookedSpacing.sm), GridItem(.flexible(), spacing: CookedSpacing.sm)],
            spacing: CookedSpacing.sm
        ) {
            statTile("Market cap", symbol: "building.columns.fill", color: CookedColor.Prism.indigo, value: profile?.market.marketCapUsd.value)
            statTile("Liquidity", symbol: "drop.fill", color: CookedColor.Prism.sky, value: profile?.market.liquidityUsd.value)
            statTile("24h volume", symbol: "chart.bar.fill", color: CookedColor.Prism.teal, value: profile?.market.volume24hUsd.value)
            statTile("Your position", symbol: "briefcase.fill", color: CookedColor.Prism.amber, value: heldValue)
        }
    }

    private var heldValue: Decimal? {
        PortfolioStore.shared.snapshot?.positions.first { $0.tokenMint == mint }?.valueUsd
    }

    private func statTile(_ title: String, symbol: String, color: Color, value: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: CookedSpacing.xs) {
            IconTile(symbol: symbol, color: color, size: 26)
            Text(value?.compactUSD() ?? "—")
                .font(CookedFont.priceLarge(19))
                .foregroundStyle(CookedColor.Terminal.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(CookedFont.caption(11))
                .foregroundStyle(CookedColor.Terminal.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CookedSpacing.sm)
        .glassPanel(cornerRadius: CookedRadius.md, tint: color)
    }

    private var holdsPosition: Bool {
        PortfolioStore.shared.snapshot?.positions.contains { $0.tokenMint == mint } ?? false
    }

    private var tradeBar: some View {
        CookedGlassContainer(spacing: CookedSpacing.sm) {
            HStack(spacing: CookedSpacing.sm) {
                if holdsPosition {
                    Button {
                        Haptics.tap()
                        tradeSide = .sell
                    } label: {
                        Label("Sell", systemImage: "arrow.down.right")
                    }
                    .buttonStyle(.cookedPrimary(destructive: true))
                }

                Button {
                    Haptics.tap()
                    tradeSide = .buy
                } label: {
                    Label("Buy", systemImage: "arrow.up.right")
                }
                .buttonStyle(.cookedPrimary)
                .accessibilityIdentifier("tokenDetail.buy")
            }
            .padding(CookedSpacing.sm)
            .glassPanel(cornerRadius: CookedRadius.xl)
            .padding(.horizontal, CookedSpacing.md)
            .padding(.bottom, CookedSpacing.xs)
        }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let profileFetch = TokenAPI.profile(mint: mint)
            async let candlesFetch = TokenAPI.candles(mint: mint, interval: interval)
            async let watchFetch = loadIsWatched()
            async let alertsFetch = loadAlertLevels()
            profile = try await profileFetch
            candles = try await candlesFetch
            isWatched = await watchFetch
            chartAlertLevels = await alertsFetch
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// The caller's own active `price_crossed` alerts on this mint, drawn as levels on
    /// the chart. `/social/alerts` has no per-mint filter, so this fetches the whole
    /// list and filters client-side — the same "never for a guest, never fails the
    /// screen" shape as `loadIsWatched`, since a chart is still useful with no alerts
    /// drawn on it.
    private func loadAlertLevels() async -> [ChartAlertLevel] {
        guard !SessionStore.shared.isGuest else { return [] }
        guard let alerts = try? await AlertsAPI.list() else { return [] }
        return alerts.compactMap { alert in
            guard case .priceCrossed(let alertMint, let direction, let priceUsd) = alert.rule, alertMint == mint else {
                return nil
            }
            return ChartAlertLevel(id: alert.id, price: priceUsd, direction: direction)
        }
    }

    /// Hydrates the star from the server so a token already on the caller's watchlist
    /// doesn't render unstarred on arrival. Never called for a guest (`/watchlist` is
    /// `auth: 'bearer'`) and never fails the screen — see `DiscoverView`'s twin of
    /// this.
    private func loadIsWatched() async -> Bool {
        guard !SessionStore.shared.isGuest else { return false }
        guard let list = try? await WatchlistAPI.list() else { return false }
        return list.items.contains { $0.mint == mint }
    }

    private func loadCandles() async {
        candles = try? await TokenAPI.candles(mint: mint, interval: interval)
    }

    /// `/watchlist/*` is `auth: 'bearer'` — a guest token is rejected server-side, so
    /// a guest never reaches the API here; they see the sign-in prompt instead.
    private func toggleWatch() {
        guard !SessionStore.shared.isGuest else {
            showGuestWatchAlert = true
            return
        }

        Haptics.tap()
        let wasWatching = isWatched
        isWatched.toggle()

        Task {
            do {
                if wasWatching {
                    _ = try await WatchlistAPI.remove(mint: mint)
                } else {
                    _ = try await WatchlistAPI.add(mint: mint)
                }
            } catch {
                isWatched = wasWatching
            }
        }
    }
}

extension TradeSide: Identifiable {
    var id: String { rawValue }
}
