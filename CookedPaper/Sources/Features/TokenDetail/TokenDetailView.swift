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

    var body: some View {
        ZStack {
            CookedColor.Terminal.bgBase.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(CookedColor.Brand.fill)
            } else if let errorMessage {
                EmptyStateView(symbol: "wifi.slash", title: "Couldn't load this token", detail: errorMessage)
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: CookedSpacing.md) {
                            header
                                .entrance(isContentVisible, reduceMotion: reduceMotion)
                            chartSection
                                .entrance(isContentVisible, reduceMotion: reduceMotion, delay: 0.06)
                            statsGrid
                                .entrance(isContentVisible, reduceMotion: reduceMotion, delay: 0.12)
                        }
                        .padding(CookedSpacing.md)
                    }
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
        HStack(alignment: .top, spacing: CookedSpacing.sm) {
            TokenLogo(mint: mint, size: 44)
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
                HStack(alignment: .firstTextBaseline, spacing: CookedSpacing.xs) {
                    if let price = profile?.market.priceUsd.value {
                        Text(price.usdString(fractionDigits: price < 1 ? 6 : 2))
                            .font(CookedFont.priceDisplay(30))
                            .foregroundStyle(CookedColor.Terminal.textPrimary)
                    } else {
                        Text("—").font(CookedFont.priceDisplay(30)).foregroundStyle(CookedColor.Terminal.textMuted)
                    }
                    PnLText(value: profile?.market.change24h.value, isPercent: true, font: CookedFont.priceMedium())
                }
            }
            Spacer()
        }
    }

    private var chartSection: some View {
        VStack(spacing: CookedSpacing.xs) {
            CandleChartView(
                candles: candles?.candles ?? [],
                isRelayed: candles?.isRelayed ?? false,
                interval: interval,
                alertLevels: chartAlertLevels
            )
            .frame(height: 280)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CookedSpacing.xs) {
                    ForEach(CandleInterval.allCases) { option in
                        CookedChip(title: option.label, isSelected: option == interval) {
                            interval = option
                        }
                    }
                }
            }
        }
    }

    private var statsGrid: some View {
        CookedCard {
            VStack(spacing: CookedSpacing.sm) {
                statRow("Market cap", profile?.market.marketCapUsd.value)
                Divider().overlay(CookedColor.Terminal.border)
                statRow("Liquidity", profile?.market.liquidityUsd.value)
                Divider().overlay(CookedColor.Terminal.border)
                statRow("24h volume", profile?.market.volume24hUsd.value)
            }
        }
    }

    private func statRow(_ title: String, _ value: Decimal?) -> some View {
        HStack {
            Text(title)
                .font(CookedFont.body())
                .foregroundStyle(CookedColor.Terminal.textSecondary)
            Spacer()
            Text(value?.usdString() ?? "—")
                .font(CookedFont.priceMedium())
                .foregroundStyle(CookedColor.Terminal.textPrimary)
        }
    }

    private var holdsPosition: Bool {
        PortfolioStore.shared.snapshot?.positions.contains { $0.tokenMint == mint } ?? false
    }

    private var tradeBar: some View {
        CookedGlassContainer {
            HStack(spacing: CookedSpacing.sm) {
                if holdsPosition {
                    Button {
                        Haptics.tap()
                        tradeSide = .sell
                    } label: {
                        Text("Sell")
                    }
                    .buttonStyle(.cookedPrimary(destructive: true))
                }

                Button {
                    Haptics.tap()
                    tradeSide = .buy
                } label: {
                    Text("Buy")
                }
                .buttonStyle(.cookedPrimary)
            }
            .padding(CookedSpacing.md)
            .cookedGlass(in: Rectangle())
            .overlay(Rectangle().fill(CookedColor.Terminal.border).frame(height: 1), alignment: .top)
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
