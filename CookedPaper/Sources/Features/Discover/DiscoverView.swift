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
                searchResults = (try? await TokenAPI.search(newValue)) ?? []
            }
        }
        .task {
            // The server feed rebuilds about once a minute; checking every 30 s
            // keeps market caps (and their tick flashes) current while on screen.
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await load()
            }
        }
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
            EmptyStateView(symbol: "wifi.slash", title: "Couldn't load the market", detail: errorMessage)
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

    private var searchResultsList: some View {
        LazyVStack(spacing: 0) {
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

    private func load() async {
        isLoading = response == nil
        do {
            response = try await DiscoverAPI.paperDiscover()
            errorMessage = nil
        } catch is CancellationError {
            // Left the screen mid-refresh; keep whatever is showing.
        } catch {
            // A failed background refresh keeps the last good feed on screen
            // rather than swapping it for an error.
            if response == nil { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }
}

/// Avatar | symbol over volume | market cap over change. Nothing else. Memecoin
/// prices like $0.0₄2314 don't compare across rows; market cap does.
private struct TokenRow: View {
    let entry: PaperDiscoverEntry

    var body: some View {
        ListRow(
            title: entry.symbol ?? "?",
            subtitle: entry.metrics.volumeUsd.map { "Vol \(PriceFormat.compact($0))" } ?? entry.name
        ) {
            TokenAvatar(mint: entry.mint, symbol: entry.symbol, logoURL: entry.logoUri.flatMap(URL.init(string:)))
        } trailing: {
            HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                Text("MC")
                    .font(.caption13)
                    .foregroundStyle(Color.textTertiary)
                MarketCapText(value: entry.metrics.marketCapUsd)
            }
            .accessibilityElement(children: .combine)
            ChangeText(percent: entry.metrics.priceChangePct)
        }
    }
}

/// Compact neutral card: avatar, symbol, market cap, change.
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
                HStack(alignment: .firstTextBaseline, spacing: Space.s4) {
                    Text("MC")
                        .font(.caption13)
                        .foregroundStyle(Color.textTertiary)
                    MarketCapText(value: entry.metrics.marketCapUsd, font: .rowSubvalue, color: .textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityElement(children: .combine)
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
