import Foundation
import SwiftUI

struct LeaderboardView: View {
    /// The navigation title; Compete shows this list under its own "Compete".
    var title = "Leaderboard"

    @State private var window: LeaderboardWindow = .all
    @State private var response: PaperLeaderboardResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// The row tapped: opens what that trader holds.
    @State private var selectedEntry: PaperLeaderboardEntry?

    private var entries: [PaperLeaderboardEntry] { response?.entries ?? [] }

    private var myEntry: PaperLeaderboardEntry? {
        guard let username = SessionStore.shared.username else { return nil }
        return entries.first { $0.username == username }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.headerGap) {
                SimulatedCaption()
                    .padding(.horizontal, Space.margin)

                ScrollView(.horizontal) {
                    HStack(spacing: Space.s8) {
                        ForEach(LeaderboardWindow.allCases) { candidate in
                            Chip(title: candidate.label, isSelected: candidate == window) {
                                window = candidate
                            }
                        }
                    }
                    .padding(.horizontal, Space.margin)
                }
                .scrollIndicators(.hidden)

                BeatTheMonkeyCard(window: window, myEntry: myEntry)
                    .padding(.horizontal, Space.margin)

                list
                    .padding(.horizontal, Space.margin)
            }
            .padding(.bottom, Space.s24)
        }
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .refreshable { await load() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isLoading && errorMessage == nil && !entries.isEmpty {
                myRankBar
            }
        }
        .reservesTabBarSpace()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .onChange(of: window) { _, _ in
            Task { await load() }
        }
        .autoRefresh(every: 60) { await refreshSilently() }
        .sheet(item: $selectedEntry) { entry in
            TraderPositionsSheet(entry: entry)
        }
    }

    @ViewBuilder
    private var list: some View {
        if isLoading {
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in SkeletonRow() }
            }
        } else if let errorMessage {
            EmptyStateView(symbol: "wifi.slash", title: "Couldn't load the leaderboard", detail: errorMessage) {
                Task { await load() }
            }
        } else if entries.isEmpty {
            EmptyStateView(
                symbol: "trophy",
                title: "No ranked traders yet",
                detail: "Check back once more portfolios have a qualifying track record."
            )
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        Haptics.tap()
                        selectedEntry = entry
                    } label: {
                        LeaderboardRow(entry: entry)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows what this trader holds")
                    if index < entries.count - 1 {
                        RowSeparator(leadingInset: LeaderboardRow.textInset)
                    }
                }
            }
        }
    }

    /// Pinned above the tab bar: where the current user stands.
    private var myRankBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.appSeparator).frame(height: 1)
            Group {
                if let myEntry {
                    LeaderboardRow(entry: myEntry, titleOverride: "You")
                } else {
                    HStack(spacing: Space.s12) {
                        Text("—")
                            .font(.rowSubvalue)
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: LeaderboardRow.rankWidth, alignment: .leading)
                        MonogramAvatar(text: SessionStore.shared.username ?? "You")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You")
                                .font(.rowTitle)
                                .foregroundStyle(Color.textPrimary)
                            Text("Close a trade to get ranked")
                                .font(.rowSubtitle)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                    }
                    .frame(height: Metrics.rowHeight)
                }
            }
            .padding(.horizontal, Space.margin)
        }
        .background(Color.appSurface)
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

    /// The auto-refresh: replaces the ranks in place, never shows the skeleton, and
    /// keeps the current list if the request fails or the window changed meanwhile.
    private func refreshSilently() async {
        let requested = window
        guard !isLoading,
              let fresh = try? await LeaderboardAPI.paperLeaderboard(window: requested),
              requested == window
        else { return }
        response = fresh
        errorMessage = nil
    }
}

/// rank | avatar | username over round trips | return %.
private struct LeaderboardRow: View {
    let entry: PaperLeaderboardEntry
    var titleOverride: String? = nil

    static let rankWidth: CGFloat = 24
    static let textInset: CGFloat = rankWidth + Space.s12 + Metrics.avatar + Metrics.avatarGap

    /// A stated `unavailable` reason means this trader has no qualifying sample yet —
    /// forcing the value to nil here (rather than trusting `pct` to already be null)
    /// keeps a malformed response from ever printing 0% for "no data".
    private var displayedReturnPct: Decimal? {
        entry.returnPct.unavailable == nil ? entry.returnPct.pct : nil
    }

    private var isTopThree: Bool { entry.rank <= 3 }

    var body: some View {
        HStack(spacing: Space.s12) {
            Text("\(entry.rank)")
                .font(.rowSubvalue)
                .foregroundStyle(isTopThree ? Color.textPrimary : Color.textTertiary)
                .frame(width: Self.rankWidth, alignment: .leading)

            ListRow(
                title: titleOverride ?? (entry.isHouseBot ? "The Monkey 🐒" : entry.username),
                subtitle: entry.isHouseBot
                    ? "Bot · trades at random · \(entry.roundTripCount) round trips"
                    : "\(entry.roundTripCount) round trips"
            ) {
                MonogramAvatar(text: entry.username)
                    .overlay(alignment: .bottomTrailing) {
                        if isTopThree {
                            Image(systemName: "medal.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                                .padding(Space.s4)
                                .background(Color.appBackground, in: Circle())
                                .offset(x: Space.s4, y: Space.s4)
                        }
                    }
            } trailing: {
                ChangeText(percent: displayedReturnPct, font: .rowValue)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
