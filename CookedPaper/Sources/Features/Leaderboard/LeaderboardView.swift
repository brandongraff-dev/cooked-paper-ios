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
            AmbientBackground(colors: [CookedColor.Prism.amber, CookedColor.Prism.indigo, CookedColor.Brand.dangerFill])

            ScrollView {
                VStack(spacing: CookedSpacing.lg) {
                    windowPicker
                    content
                }
                .padding(.bottom, CookedSpacing.xxxl)
            }
            .scrollIndicators(.hidden)
            .refreshable { await load() }
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
        ScrollView(.horizontal) {
            CookedGlassContainer(spacing: CookedSpacing.xs) {
                HStack(spacing: CookedSpacing.xs) {
                    ForEach(LeaderboardWindow.allCases) { candidate in
                        CookedChip(title: candidate.label, isSelected: candidate == window) {
                            window = candidate
                        }
                    }
                }
            }
            .padding(.horizontal, CookedSpacing.md)
            .padding(.vertical, CookedSpacing.xxs)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: CookedSpacing.sm) {
                ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
            }
            .padding(CookedSpacing.md)
            .glassPanel()
            .padding(.horizontal, CookedSpacing.md)
        } else if let errorMessage {
            EmptyStateView(symbol: "wifi.slash", title: "Couldn't load the leaderboard", detail: errorMessage)
                .frame(maxWidth: .infinity)
                .glassPanel()
                .padding(.horizontal, CookedSpacing.md)
        } else {
            let entries = response?.entries ?? []
            if entries.isEmpty {
                EmptyStateView(
                    symbol: "trophy",
                    title: "No ranked traders yet",
                    detail: "Check back once more portfolios have a qualifying track record."
                )
                .frame(maxWidth: .infinity)
                .glassPanel()
                .padding(.horizontal, CookedSpacing.md)
            } else {
                if entries.count >= 3 {
                    Podium(top: Array(entries.prefix(3)), currentUsername: SessionStore.shared.username)
                        .padding(.horizontal, CookedSpacing.md)
                        .id(window)
                }

                let rest = entries.count >= 3 ? Array(entries.dropFirst(3)) : entries
                if !rest.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(rest.enumerated()), id: \.element.id) { index, entry in
                            LeaderboardRow(entry: entry, isYou: entry.username == SessionStore.shared.username)
                                .staggeredEntrance(index: index, id: window.rawValue + entry.id, animatedIDs: $animatedRowIDs)
                            if index < rest.count - 1 {
                                Divider().overlay(CookedColor.Terminal.border).padding(.leading, 96)
                            }
                        }
                    }
                    .padding(.vertical, CookedSpacing.xxs)
                    .glassPanel()
                    .padding(.horizontal, CookedSpacing.md)
                }
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
    let isYou: Bool

    /// A stated `unavailable` reason means this trader has no qualifying sample yet —
    /// forcing the value to nil here (rather than trusting `pct` to already be null)
    /// keeps a malformed response from ever printing 0% for "no data".
    private var displayedReturnPct: Decimal? {
        entry.returnPct.unavailable == nil ? entry.returnPct.pct : nil
    }

    var body: some View {
        HStack(spacing: CookedSpacing.sm) {
            Text("\(entry.rank)")
                .font(CookedFont.priceMedium(14))
                .foregroundStyle(CookedColor.Terminal.textMuted)
                .frame(width: 28)

            TokenAvatar(seed: entry.username, label: entry.username, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.username)
                        .font(CookedFont.headline())
                        .foregroundStyle(CookedColor.Terminal.textPrimary)
                    if isYou {
                        Text("YOU")
                            .font(CookedFont.badge(9))
                            .foregroundStyle(CookedColor.Brand.onFill)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(CookedColor.Brand.fill, in: Capsule())
                    }
                }
                Text("\(entry.roundTripCount) round trips")
                    .font(CookedFont.caption(12))
                    .foregroundStyle(CookedColor.Terminal.textMuted)
            }

            Spacer()

            PnLText(value: displayedReturnPct, isPercent: true, font: CookedFont.priceMedium(15))
        }
        .padding(.horizontal, CookedSpacing.md)
        .padding(.vertical, CookedSpacing.sm)
        .background(isYou ? CookedColor.Brand.fill.opacity(0.1) : Color.clear)
    }
}

/// The top three as a podium — gold in the middle and tallest, with a crown, each
/// block rising into place when the board loads.
private struct Podium: View {
    let top: [PaperLeaderboardEntry]
    let currentUsername: String?
    @State private var risen = false

    private static let medal: [Color] = [Color(hex: 0xFFD166), Color(hex: 0xC9D3E0), Color(hex: 0xE3A36F)]
    private static let heights: [CGFloat] = [132, 100, 78]

    var body: some View {
        HStack(alignment: .bottom, spacing: CookedSpacing.sm) {
            column(1)
            column(0)
            column(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, CookedSpacing.lg)
        .onAppear {
            if AmbientMotion.isEnabled {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.1)) { risen = true }
            } else {
                risen = true
            }
        }
    }

    private func column(_ place: Int) -> some View {
        let entry = top[place]
        let color = Self.medal[place]
        let returnPct = entry.returnPct.unavailable == nil ? entry.returnPct.pct : nil

        return VStack(spacing: CookedSpacing.xs) {
            ZStack(alignment: .top) {
                TokenAvatar(seed: entry.username, label: entry.username, size: place == 0 ? 64 : 52)
                    .overlay(Circle().strokeBorder(color, lineWidth: 2.5))
                    .glow(color, radius: 20, opacity: 0.45)
                if place == 0 {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(hex: 0xFFE9A8), Color(hex: 0xF0A020)], startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: Color(hex: 0xF0A020).opacity(0.7), radius: 8)
                        .offset(y: -26)
                        .floating(amplitude: 3, period: 2.6)
                }
            }
            Text(entry.username)
                .font(CookedFont.label(13))
                .foregroundStyle(CookedColor.Terminal.textPrimary)
                .lineLimit(1)
            PnLText(value: returnPct, isPercent: true, font: CookedFont.priceSmall(12))

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: CookedRadius.md, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.5), color.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                Text("\(entry.rank)")
                    .font(.system(size: place == 0 ? 34 : 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: color.opacity(0.8), radius: 8)
                    .padding(.top, CookedSpacing.sm)
            }
            .frame(height: risen ? Self.heights[place] : 16)
            .glassPanel(cornerRadius: CookedRadius.md, tint: color)
        }
        .frame(maxWidth: .infinity)
    }
}
