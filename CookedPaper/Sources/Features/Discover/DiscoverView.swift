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

    var body: some View {
        ScrollView {
            if isSearching {
                searchResultsList
            } else {
                content
            }
        }
        .scrollIndicators(.hidden)
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
        .searchable(text: $searchText, prompt: "Search tokens")
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                searchResults = (try? await TokenAPI.search(newValue)) ?? []
            }
        }
        .task { await load() }
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
        errorMessage = nil
        do {
            response = try await DiscoverAPI.paperDiscover()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
