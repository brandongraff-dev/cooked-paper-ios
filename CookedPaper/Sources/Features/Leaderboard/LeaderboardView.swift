import Foundation
import SwiftUI

struct LeaderboardView: View {
    @State private var window: LeaderboardWindow = .all
    @State private var response: PaperLeaderboardResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var animatedRowIDs: Set<String> = []

    var body: some View {
        ZStack {
            CookedColor.Terminal.bgBase.ignoresSafeArea()

            VStack(spacing: 0) {
                windowPicker
                content
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SimulatedBadge() }
        }
        .task { await load() }
        .onChange(of: window) { _, _ in
            Task { await load() }
        }
    }

    private var windowPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CookedSpacing.xs) {
                ForEach(LeaderboardWindow.allCases) { candidate in
                    CookedChip(title: candidate.label, isSelected: candidate == window) {
                        window = candidate
                    }
                }
            }
            .padding(.horizontal, CookedSpacing.md)
            .padding(.vertical, CookedSpacing.sm)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            Spacer()
            ProgressView().tint(CookedColor.Brand.fill)
            Spacer()
        } else if let errorMessage {
            Spacer()
            EmptyStateView(symbol: "wifi.slash", title: "Couldn't load the leaderboard", detail: errorMessage)
            Spacer()
        } else {
            let entries = response?.entries ?? []
            if entries.isEmpty {
                Spacer()
                EmptyStateView(
                    symbol: "trophy",
                    title: "No ranked traders yet",
                    detail: "Check back once more portfolios have a qualifying track record."
                )
                Spacer()
            } else {
                List {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        LeaderboardRow(entry: entry)
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

    private func load() async {
        isLoading = response == nil
        errorMessage = nil
        do {
            response = try await LeaderboardAPI.paperLeaderboard(window: window)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct LeaderboardRow: View {
    let entry: PaperLeaderboardEntry

    /// A stated `unavailable` reason means this trader has no qualifying sample yet —
    /// forcing the value to nil here (rather than trusting `pct` to already be null)
    /// keeps a malformed response from ever printing 0% for "no data".
    private var displayedReturnPct: Decimal? {
        entry.returnPct.unavailable == nil ? entry.returnPct.pct : nil
    }

    var body: some View {
        HStack(spacing: CookedSpacing.sm) {
            Text("\(entry.rank)")
                .font(CookedFont.priceMedium())
                .foregroundStyle(CookedColor.Terminal.textMuted)
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.username)
                    .font(CookedFont.headline())
                    .foregroundStyle(CookedColor.Terminal.textPrimary)
                Text("\(entry.roundTripCount) round trips")
                    .font(CookedFont.caption())
                    .foregroundStyle(CookedColor.Terminal.textMuted)
            }

            Spacer()

            PnLText(value: displayedReturnPct, isPercent: true)
        }
        .padding(.vertical, 4)
    }
}
