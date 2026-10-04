import SwiftUI

/// What the person chose to do in a duel: a coin and an order type. Carries the
/// duel's portfolio so the ticket it opens can only ever trade there.
struct DuelTradeIntent: Identifiable {
    enum Kind {
        case buy, sell, leverage
    }

    let id = UUID()
    let mint: String
    let symbol: String
    let priceUsd: Decimal?
    let kind: Kind
    let portfolio: DuelPortfolioStore
}

/// Pick a coin to trade in a duel: Discover's most-active list, or a search, then
/// Buy / Sell / Leverage. The choice is handed back through `onPick` and the
/// picker closes; the duel screen opens the matching ticket.
struct DuelCoinPicker: View {
    let portfolio: DuelPortfolioStore
    let onPick: (DuelTradeIntent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var feed: [PaperDiscoverEntry] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var searchResults: [TokenSearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var answeredQuery: String?
    @State private var choosing: Candidate?

    private struct Candidate: Identifiable {
        var id: String { mint }
        let mint: String
        let symbol: String
        let priceUsd: Decimal?
    }

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if trimmedSearch.isEmpty {
                    feedList
                } else {
                    searchList
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .background(Color.appSurfaceElevated)
            .navigationTitle("Trade in duel")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search tokens")
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await runSearch(newValue)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
            .confirmationDialog(
                choosing.map { "Trade \($0.symbol)" } ?? "",
                isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }),
                titleVisibility: .visible,
                presenting: choosing
            ) { candidate in
                Button("Buy") { pick(candidate, .buy) }
                if holds(candidate.mint) {
                    Button("Sell") { pick(candidate, .sell) }
                }
                Button("Leverage") { pick(candidate, .leverage) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Trades here use your duel portfolio only.")
            }
            .task { await load() }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(Color.appSurfaceElevated)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var feedList: some View {
        if isLoading {
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in SkeletonRow() }
            }
            .padding(.horizontal, Space.margin)
        } else if let loadError, feed.isEmpty {
            EmptyStateView(symbol: "wifi.slash", title: "Couldn't load coins", detail: loadError) {
                Task { await load() }
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(feed.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        Haptics.tap()
                        choosing = Candidate(mint: entry.mint, symbol: entry.symbol ?? "token", priceUsd: entry.paperTradeable.priceUsd)
                    } label: {
                        ListRow(
                            title: entry.symbol ?? "?",
                            subtitle: holds(entry.mint) ? "In your duel portfolio" : entry.name
                        ) {
                            TokenAvatar(mint: entry.mint, symbol: entry.symbol, logoURL: entry.logoUri.flatMap(URL.init(string:)))
                        } trailing: {
                            PriceText(value: entry.paperTradeable.priceUsd)
                            ChangeText(percent: entry.metrics.priceChangePct)
                        }
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("duelPicker.row.\(index)")
                    if index < feed.count - 1 { RowSeparator() }
                }
            }
            .padding(.horizontal, Space.margin)
        }
    }

    private var searchList: some View {
        LazyVStack(spacing: 0) {
            if searchResults.isEmpty, answeredQuery == trimmedSearch {
                EmptyStateView(symbol: "magnifyingglass", title: "No tokens found", detail: "Nothing matches “\(trimmedSearch)”.")
            }
            ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, result in
                Button {
                    Haptics.tap()
                    choosing = Candidate(mint: result.mint, symbol: result.symbol ?? "token", priceUsd: nil)
                } label: {
                    ListRow(title: result.symbol ?? "?", subtitle: result.name) {
                        TokenAvatar(mint: result.mint, symbol: result.symbol)
                    } trailing: {
                        EmptyView()
                    }
                }
                .buttonStyle(.pressable)
                if index < searchResults.count - 1 { RowSeparator() }
            }
        }
        .padding(.horizontal, Space.margin)
    }

    private func holds(_ mint: String) -> Bool {
        portfolio.snapshot?.positions.contains { $0.tokenMint == mint } ?? false
    }

    private func pick(_ candidate: Candidate, _ kind: DuelTradeIntent.Kind) {
        onPick(DuelTradeIntent(
            mint: candidate.mint,
            symbol: candidate.symbol,
            priceUsd: candidate.priceUsd,
            kind: kind,
            portfolio: portfolio
        ))
        dismiss()
    }

    private func load() async {
        isLoading = feed.isEmpty
        loadError = nil
        do {
            feed = try await DiscoverAPI.paperDiscover().entries(for: .mostActive)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func runSearch(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let results = (try? await TokenAPI.search(query)) ?? []
        guard !Task.isCancelled else { return }
        searchResults = results
        answeredQuery = trimmed
    }
}
