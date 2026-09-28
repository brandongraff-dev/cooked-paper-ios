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
            CookedColor.Terminal.bgBase.ignoresSafeArea()

            VStack(spacing: 0) {
                feedPicker

                if isSearching {
                    searchList
                } else {
                    feedList
                }
            }
            .navigationDestination(for: String.self) { mint in
                TokenDetailView(mint: mint)
            }
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

    private var feedPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CookedSpacing.xs) {
                ForEach(PaperDiscoverFeed.allCases) { candidate in
                    CookedChip(title: candidate.label, isSelected: candidate == feed) {
                        feed = candidate
                    }
                }
            }
            .padding(.horizontal, CookedSpacing.md)
            .padding(.vertical, CookedSpacing.sm)
        }
    }

    @ViewBuilder
    private var feedList: some View {
        if isLoading {
            Spacer()
            ProgressView().tint(CookedColor.Brand.fill)
            Spacer()
        } else if let errorMessage {
            Spacer()
            EmptyStateView(symbol: "wifi.slash", title: "Couldn't load the market", detail: errorMessage)
            Spacer()
        } else {
            let entries = response?.entries(for: feed) ?? []
            if entries.isEmpty {
                Spacer()
                EmptyStateView(symbol: "tray", title: "Nothing here yet", detail: "Check back in a bit — this feed refreshes about once a minute.")
                Spacer()
            } else {
                List {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink(value: entry.mint) {
                            DiscoverRow(
                                entry: entry,
                                isWatched: watchedMints.contains(entry.mint),
                                onToggleStar: { toggleWatch(mint: entry.mint) }
                            )
                        }
                        .listRowBackground(CookedColor.Terminal.bgBase)
                        .listRowSeparatorTint(CookedColor.Terminal.border)
                        .staggeredEntrance(index: index, id: entry.id, animatedIDs: $animatedRowIDs)
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
    }

    private var searchList: some View {
        List {
            ForEach(searchResults) { result in
                NavigationLink(value: result.mint) {
                    HStack(spacing: CookedSpacing.sm) {
                        TokenLogo(mint: result.mint, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.symbol ?? "?")
                                .font(CookedFont.headline())
                                .foregroundStyle(CookedColor.Terminal.textPrimary)
                            Text(result.name ?? result.mint)
                                .font(CookedFont.caption())
                                .foregroundStyle(CookedColor.Terminal.textMuted)
                                .lineLimit(1)
                        }
                    }
                }
                .listRowBackground(CookedColor.Terminal.bgBase)
            }
        }
        .listStyle(.plain)
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
    let entry: PaperDiscoverEntry
    let isWatched: Bool
    let onToggleStar: () -> Void

    var body: some View {
        HStack(spacing: CookedSpacing.sm) {
            TokenLogo(mint: entry.mint, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.symbol ?? "?")
                    .font(CookedFont.headline())
                    .foregroundStyle(CookedColor.Terminal.textPrimary)
                Text(entry.name ?? entry.mint)
                    .font(CookedFont.caption())
                    .foregroundStyle(CookedColor.Terminal.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.paperTradeable.priceUsd.usdString(fractionDigits: entry.paperTradeable.priceUsd < 1 ? 6 : 2))
                    .font(CookedFont.priceMedium())
                    .foregroundStyle(CookedColor.Terminal.textPrimary)
                PnLText(value: entry.metrics.priceChangePct, isPercent: true, font: CookedFont.caption())
            }

            Button(action: onToggleStar) {
                Image(systemName: isWatched ? "star.fill" : "star")
                    .foregroundStyle(isWatched ? CookedColor.Brand.fill : CookedColor.Terminal.textMuted)
                    .imageScale(.medium)
                    .frame(width: 32, height: 32)
                    .animation(CookedMotion.standard, value: isWatched)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
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
