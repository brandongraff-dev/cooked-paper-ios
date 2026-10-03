import Foundation
import SwiftUI
import UIKit

struct DiscoverView: View {
    @State private var feed: PaperDiscoverFeed = .mostActive
    @State private var response: PaperDiscoverResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var searchResults: [TokenSearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    /// The last search failed (as opposed to finding nothing).
    @State private var searchError: String?
    /// The query `searchResults`/`searchError` answer, so "no results" only shows
    /// once a search for what's typed has actually come back.
    @State private var answeredQuery: String?

    var body: some View {
        ScrollView {
            if isSearching {
                searchResultsList
            } else {
                content
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background(Color.appBackground)
        .refreshable { await load() }
        .navigationDestination(for: String.self) { mint in
            TokenDetailView(mint: mint)
        }
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BrandMark(height: 22)
            }
        }
        .reservesTabBarSpace()
        // Pinned under the title: with no system tab bar, iOS 26 would otherwise
        // move the field to the bottom edge, where the floating bar lives.
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search tokens")
        .onSubmit(of: .search) {
            // Search is live as you type; the Search key just puts the keyboard away.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await runSearch(newValue)
            }
        }
        .task { await load() }
        // The server caches the feeds for ~60 s; every 30 s catches each update
        // within half a cache window, without a skeleton or a scroll jump.
        .autoRefresh(every: 30) { await refreshSilently() }
    }

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in SkeletonRow() }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s16)
        } else if let errorMessage {
            EmptyStateView(symbol: "wifi.slash", title: "Couldn't load the market", detail: errorMessage) {
                Task { await load() }
            }
        } else {
            VStack(alignment: .leading, spacing: Space.section) {
                trendingSection
                feedSection
            }
            .padding(.top, Space.s8)
            .padding(.bottom, Space.section)
        }
    }

    // MARK: - Trending

    private var trendingEntries: [PaperDiscoverEntry] {
        Array((response?.entries(for: .biggestMovers) ?? []).prefix(8))
    }

    @ViewBuilder
    private var trendingSection: some View {
        if !trendingEntries.isEmpty {
            VStack(alignment: .leading, spacing: Space.headerGap) {
                SectionHeader(title: "Trending")
                    .padding(.horizontal, Space.margin)

                ScrollView(.horizontal) {
                    HStack(spacing: Space.s12) {
                        ForEach(trendingEntries) { entry in
                            NavigationLink(value: entry.mint) {
                                TrendingCard(entry: entry)
                            }
                            .buttonStyle(.pressable)
                            .prefetchesLiveMarket(entry.mint)
                        }
                    }
                    .padding(.horizontal, Space.margin)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    // MARK: - Feed

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            ScrollView(.horizontal) {
                HStack(spacing: Space.s8) {
                    ForEach(PaperDiscoverFeed.allCases) { candidate in
                        Chip(title: candidate.label, isSelected: candidate == feed) {
                            feed = candidate
                        }
                    }
                }
                .padding(.horizontal, Space.margin)
            }
            .scrollIndicators(.hidden)

            let entries = response?.entries(for: feed) ?? []
            if entries.isEmpty {
                EmptyStateView(
                    symbol: "tray",
                    title: "Nothing here yet",
                    detail: "This feed refreshes about once a minute."
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink(value: entry.mint) {
                            TokenRow(entry: entry)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityIdentifier("discover.row.\(index)")
                        .prefetchesLiveMarket(entry.mint)

                        if index < entries.count - 1 {
                            RowSeparator()
                        }
                    }
                }
                .padding(.horizontal, Space.margin)
                .id(feed)
                .transition(.opacity)
            }
        }
        .animation(Motion.standard, value: feed)
    }

    // MARK: - Search

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespaces) }

    private var searchResultsList: some View {
        LazyVStack(spacing: 0) {
            if let searchError, answeredQuery == trimmedSearch {
                SearchMessageRow(symbol: "wifi.slash", title: "Couldn't search right now", detail: searchError) {
                    Task { await runSearch(searchText) }
                }
            } else if searchResults.isEmpty, answeredQuery == trimmedSearch {
                SearchMessageRow(symbol: "magnifyingglass", title: "No tokens found", detail: "Nothing matches “\(trimmedSearch)”.")
            }

            ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, result in
                NavigationLink(value: result.mint) {
                    ListRow(title: result.symbol ?? "?", subtitle: result.name) {
                        TokenAvatar(mint: result.mint, symbol: result.symbol)
                    } trailing: {
                        EmptyView()
                    }
                }
                .buttonStyle(.pressable)

                if index < searchResults.count - 1 {
                    RowSeparator()
                }
            }
        }
        .padding(.horizontal, Space.margin)
    }

    /// One search round. A failure shows as an error row with a retry, never as an
    /// empty "no results" list; a search superseded by more typing is dropped.
    private func runSearch(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        do {
            let results = try await TokenAPI.search(query)
            guard !Task.isCancelled else { return }
            searchResults = results
            searchError = nil
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            searchError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        answeredQuery = trimmed
    }

    private func load() async {
        isLoading = response == nil
        errorMessage = nil
        do {
            response = try await DiscoverAPI.paperDiscover()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// The auto-refresh: swaps in fresh feeds in place (same row ids, so the list
    /// keeps its scroll position) and leaves whatever is shown alone on failure.
    private func refreshSilently() async {
        guard !isLoading, let fresh = try? await DiscoverAPI.paperDiscover() else { return }
        response = fresh
        errorMessage = nil
    }
}

/// A search outcome that isn't a result: an error (with retry) or no matches.
private struct SearchMessageRow: View {
    let symbol: String
    let title: String
    let detail: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.avatarGap) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(Color.textTertiary)
                .frame(width: Metrics.avatar, height: Metrics.avatar)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Space.s8)
            if let retry {
                Button("Retry") {
                    Haptics.tap()
                    retry()
                }
                .buttonStyle(.compact)
                .accessibilityIdentifier("discover.search.retry")
            }
        }
        .frame(minHeight: Metrics.rowHeight)
    }
}

/// Avatar | symbol over volume | price over change. Nothing else.
private struct TokenRow: View {
    let entry: PaperDiscoverEntry

    var body: some View {
        ListRow(
            title: entry.symbol ?? "?",
            subtitle: entry.metrics.volumeUsd.map { "Vol \(PriceFormat.compact($0))" } ?? entry.name
        ) {
            TokenAvatar(mint: entry.mint, symbol: entry.symbol, logoURL: entry.logoUri.flatMap(URL.init(string:)))
        } trailing: {
            PriceText(value: entry.paperTradeable.priceUsd)
            ChangeText(percent: entry.metrics.priceChangePct)
        }
    }
}

/// Compact neutral card: avatar, symbol, price, change.
private struct TrendingCard: View {
    let entry: PaperDiscoverEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            TokenAvatar(mint: entry.mint, symbol: entry.symbol, logoURL: entry.logoUri.flatMap(URL.init(string:)), size: 32)
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(entry.symbol ?? "?")
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                PriceText(value: entry.paperTradeable.priceUsd, font: .rowSubvalue, color: .textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                ChangeText(percent: entry.metrics.priceChangePct, font: .caption13Digits)
            }
        }
        .padding(Space.s16)
        .frame(width: 136, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

private extension View {
    /// Warms this token's live chart while its row is on screen, so opening it
    /// shows a drawn chart rather than an empty one (see `MarketFeedStore`).
    func prefetchesLiveMarket(_ mint: String) -> some View {
        onAppear { MarketFeedStore.shared.prefetch(mint) }
            .onDisappear { MarketFeedStore.shared.cancelPrefetch(mint) }
    }
}
