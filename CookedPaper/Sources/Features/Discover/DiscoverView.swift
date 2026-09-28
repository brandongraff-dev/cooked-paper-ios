import Foundation
import SwiftUI

struct DiscoverView: View {
    @State private var feed: PaperDiscoverFeed = .mostActive
    @State private var response: PaperDiscoverResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var searchResults: [TokenSearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var watchedMints: Set<String> = []
    @State private var showGuestWatchAlert = false
    @State private var animatedRowIDs: Set<String> = []

    var body: some View {
        ZStack {
            AmbientBackground.brand

            if isSearching {
                searchList
            } else {
                feedScroll
            }
        }
        .navigationDestination(for: String.self) { mint in
            TokenDetailView(mint: mint)
        }
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search a token")
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                searchResults = (try? await TokenAPI.search(newValue)) ?? []
            }
        }
        .task { await load() }
        .alert("Sign in to save a watchlist", isPresented: $showGuestWatchAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Sign in from Settings to save tokens.")
        }
    }

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    private var feedScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CookedSpacing.lg) {
                if isLoading {
                    loadingSkeleton
                } else if let errorMessage {
                    EmptyStateView(symbol: "wifi.slash", title: "Couldn't load the market", detail: errorMessage)
                        .frame(maxWidth: .infinity)
                        .glassPanel()
                        .padding(.horizontal, CookedSpacing.md)
                } else {
                    trendingSection
                    feedSection
                }
            }
            .padding(.top, CookedSpacing.xs)
            .padding(.bottom, CookedSpacing.xxxl)
        }
        .scrollIndicators(.hidden)
        .refreshable { await load() }
    }

    // MARK: - Trending carousel

    private var trendingEntries: [PaperDiscoverEntry] {
        Array((response?.entries(for: .biggestMovers) ?? []).prefix(6))
    }

    @ViewBuilder
    private var trendingSection: some View {
        if !trendingEntries.isEmpty {
            VStack(alignment: .leading, spacing: CookedSpacing.sm) {
                SectionHeader(symbol: "flame.fill", title: "Trending now", tint: CookedColor.Prism.amber)
                    .padding(.horizontal, CookedSpacing.md)

                ScrollView(.horizontal) {
                    HStack(spacing: CookedSpacing.sm) {
                        ForEach(Array(trendingEntries.enumerated()), id: \.element.id) { index, entry in
                            NavigationLink(value: entry.mint) {
                                TrendingCard(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.94)
                                    .opacity(phase.isIdentity ? 1 : 0.75)
                            }
                            .staggeredEntrance(index: index, id: "trend-" + entry.id, animatedIDs: $animatedRowIDs)
                        }
                    }
                    .padding(.horizontal, CookedSpacing.md)
                    .padding(.vertical, CookedSpacing.xs)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    // MARK: - Feed

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: CookedSpacing.sm) {
            feedPicker

            let entries = response?.entries(for: feed) ?? []
            if entries.isEmpty {
                EmptyStateView(symbol: "tray", title: "Nothing here yet", detail: "Check back in a bit — this feed refreshes about once a minute.")
                    .frame(maxWidth: .infinity)
                    .glassPanel()
                    .padding(.horizontal, CookedSpacing.md)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink(value: entry.mint) {
                            DiscoverRow(
                                rank: index + 1,
                                entry: entry,
                                isWatched: watchedMints.contains(entry.mint),
                                onToggleStar: { toggleWatch(mint: entry.mint) }
                            )
                        }
                        .buttonStyle(RowPressStyle())
                        .accessibilityIdentifier("discover.row.\(index)")
                        .staggeredEntrance(index: index, id: feed.rawValue + entry.id, animatedIDs: $animatedRowIDs)

                        if index < entries.count - 1 {
                            Divider()
                                .overlay(CookedColor.Terminal.border)
                                .padding(.leading, 76)
                        }
                    }
                }
                .padding(.vertical, CookedSpacing.xxs)
                .glassPanel(cornerRadius: CookedRadius.lg)
                .padding(.horizontal, CookedSpacing.md)
                .id(feed)
                .transition(.opacity)
            }
        }
        .animation(CookedMotion.calm, value: feed)
    }

    private var feedPicker: some View {
        ScrollView(.horizontal) {
            CookedGlassContainer(spacing: CookedSpacing.xs) {
                HStack(spacing: CookedSpacing.xs) {
                    ForEach(PaperDiscoverFeed.allCases) { candidate in
                        CookedChip(title: candidate.label, isSelected: candidate == feed) {
                            feed = candidate
                        }
                    }
                }
            }
            .padding(.horizontal, CookedSpacing.md)
            .padding(.vertical, CookedSpacing.xxs)
        }
        .scrollIndicators(.hidden)
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: CookedSpacing.lg) {
            HStack(spacing: CookedSpacing.sm) {
                ForEach(0..<2, id: \.self) { _ in
                    SkeletonView(cornerRadius: CookedRadius.lg).frame(width: 160, height: 180)
                }
            }
            VStack(spacing: CookedSpacing.sm) {
                ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
            }
            .padding(CookedSpacing.md)
            .glassPanel()
        }
        .padding(.horizontal, CookedSpacing.md)
    }

    private var searchList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { result in
                    NavigationLink(value: result.mint) {
                        HStack(spacing: CookedSpacing.sm) {
                            TokenLogo(mint: result.mint, symbol: result.symbol, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(result.symbol ?? "?")
                                        .font(CookedFont.headline())
                                        .foregroundStyle(CookedColor.Terminal.textPrimary)
                                    if result.isVerified {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.system(size: CookedIconSize.xs))
                                            .foregroundStyle(CookedColor.Verification.mark)
                                    }
                                }
                                Text(result.name ?? result.mint)
                                    .font(CookedFont.caption(12))
                                    .foregroundStyle(CookedColor.Terminal.textMuted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: CookedIconSize.xs, weight: .bold))
                                .foregroundStyle(CookedColor.Terminal.textMuted)
                        }
                        .padding(.horizontal, CookedSpacing.md)
                        .padding(.vertical, CookedSpacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
            .glassPanel()
            .padding(CookedSpacing.md)
        }
        .scrollIndicators(.hidden)
    }

    private func load() async {
        isLoading = response == nil
        errorMessage = nil
        do {
            async let discoverFetch = DiscoverAPI.paperDiscover()
            async let watchlistFetch = loadWatchedMints()
            response = try await discoverFetch
            watchedMints = await watchlistFetch
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Hydrates the star state from the server so a token already on the caller's
    /// watchlist doesn't render unstarred until the next toggle. Never called for a
    /// guest (`/watchlist` is `auth: 'bearer'`) and never fails the screen — a failed
    /// fetch here just means every star starts unfilled, the same as before this
    /// existed.
    private func loadWatchedMints() async -> Set<String> {
        guard !SessionStore.shared.isGuest else { return [] }
        guard let list = try? await WatchlistAPI.list() else { return [] }
        return Set(list.items.map(\.mint))
    }

    /// `/watchlist/*` is `auth: 'bearer'` — a guest token is rejected server-side, so
    /// a guest never reaches the API here; they see the sign-in prompt instead.
    private func toggleWatch(mint: String) {
        guard !SessionStore.shared.isGuest else {
            showGuestWatchAlert = true
            return
        }

        Haptics.tap()
        let wasWatching = watchedMints.contains(mint)
        if wasWatching {
            watchedMints.remove(mint)
        } else {
            watchedMints.insert(mint)
        }

        Task {
            do {
                if wasWatching {
                    _ = try await WatchlistAPI.remove(mint: mint)
                } else {
                    _ = try await WatchlistAPI.add(mint: mint)
                }
            } catch {
                if wasWatching {
                    watchedMints.insert(mint)
                } else {
                    watchedMints.remove(mint)
                }
            }
        }
    }
}

private struct DiscoverRow: View {
    let rank: Int
    let entry: PaperDiscoverEntry
    let isWatched: Bool
    let onToggleStar: () -> Void

    var body: some View {
        HStack(spacing: CookedSpacing.sm) {
            Text("\(rank)")
                .font(CookedFont.priceSmall(11))
                .foregroundStyle(CookedColor.Terminal.textMuted)
                .frame(width: 16)

            TokenLogo(mint: entry.mint, symbol: entry.symbol, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(entry.symbol ?? "?")
                        .font(CookedFont.headline())
                        .foregroundStyle(CookedColor.Terminal.textPrimary)
                    if entry.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: CookedIconSize.xs))
                            .foregroundStyle(CookedColor.Verification.mark)
                    }
                }
                Text(entry.metrics.volumeUsd.map { "Vol \($0.compactUSD())" } ?? (entry.name ?? ""))
                    .font(CookedFont.caption(12))
                    .foregroundStyle(CookedColor.Terminal.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: CookedSpacing.xs)

            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.paperTradeable.priceUsd.priceString())
                    .font(CookedFont.priceMedium())
                    .foregroundStyle(CookedColor.Terminal.textPrimary)
                ChangePill(value: entry.metrics.priceChangePct, font: CookedFont.priceSmall(11))
            }

            Button(action: onToggleStar) {
                Image(systemName: isWatched ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isWatched ? CookedColor.Prism.amber : CookedColor.Terminal.textMuted)
                    .symbolEffect(.bounce, value: isWatched)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, CookedSpacing.sm)
        .padding(.vertical, CookedSpacing.sm)
        .contentShape(Rectangle())
    }
}

/// A big glass card in the "Trending now" carousel — avatar with a colored halo, the
/// move front and center, and the two numbers that say whether it's real volume.
private struct TrendingCard: View {
    let entry: PaperDiscoverEntry

    var body: some View {
        let palette = TokenPalette(seed: entry.mint)
        VStack(alignment: .leading, spacing: CookedSpacing.sm) {
            HStack(alignment: .top) {
                TokenLogo(mint: entry.mint, symbol: entry.symbol, size: 46)
                    .glow(palette.primary, radius: 18, opacity: 0.5)
                Spacer()
                ChangePill(value: entry.metrics.priceChangePct)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.symbol ?? "?")
                    .font(CookedFont.title(20))
                    .foregroundStyle(CookedColor.Terminal.textPrimary)
                Text(entry.name ?? "")
                    .font(CookedFont.caption(12))
                    .foregroundStyle(CookedColor.Terminal.textSecondary)
                    .lineLimit(1)
            }
            Text(entry.paperTradeable.priceUsd.priceString())
                .font(CookedFont.priceMedium(16))
                .foregroundStyle(CookedColor.Terminal.textPrimary)
            HStack(spacing: CookedSpacing.xs) {
                MiniStat(title: "MCap", value: entry.metrics.marketCapUsd)
                MiniStat(title: "Vol", value: entry.metrics.volumeUsd)
            }
        }
        .padding(CookedSpacing.md)
        .frame(width: 176, height: 204)
        .background(
            LinearGradient(colors: [palette.primary.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: CookedRadius.lg, style: .continuous)
        )
        .glassPanel(cornerRadius: CookedRadius.lg, tint: palette.primary)
    }
}

private struct MiniStat: View {
    let title: String
    let value: Decimal?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(CookedFont.caption(10))
                .foregroundStyle(CookedColor.Terminal.textMuted)
            Text(value?.compactUSD() ?? "—")
                .font(CookedFont.priceSmall(11))
                .foregroundStyle(CookedColor.Terminal.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row-level press state: a soft highlight wash on touch-down instead of the
/// default opacity dip, so tapping a row feels like pressing into glass.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.06 : 0))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(CookedMotion.press, value: configuration.isPressed)
    }
}

/// A small icon + title header above a content group.
struct SectionHeader: View {
    let symbol: String
    let title: String
    var tint: Color = CookedColor.Brand.fill

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
            Text(title)
                .font(CookedFont.headline(17))
                .foregroundStyle(CookedColor.Terminal.textPrimary)
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: CookedSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: CookedIconSize.lg))
                .foregroundStyle(CookedColor.Terminal.textMuted)
            Text(title)
                .font(CookedFont.headline())
                .foregroundStyle(CookedColor.Terminal.textPrimary)
            Text(detail)
                .font(CookedFont.caption())
                .foregroundStyle(CookedColor.Terminal.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(CookedSpacing.xl)
    }
}
