import Foundation
import SwiftUI

/// The paper leaderboard: where you stand as a headline, the top three on a podium,
/// how far it is to the next place, then everyone else with a bar for how close they
/// are to the leader. When you're below the podium, a card pinned above the tab bar
/// shows your spot and jumps to your row.
struct LeaderboardView: View {
    /// The navigation title; Compete shows this list under its own "Compete".
    var title = "Leaderboard"
    /// Inline under Compete: the headline below is the screen's big text, and a large
    /// title there only leaves an empty band above the segments.
    var titleDisplayMode: NavigationBarItem.TitleDisplayMode = .large

    @State private var window: LeaderboardWindow = .all
    @State private var response: PaperLeaderboardResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// The row tapped: opens what that trader holds.
    @State private var selectedEntry: PaperLeaderboardEntry?

    private var entries: [PaperLeaderboardEntry] { response?.entries ?? [] }
    private var podium: [PaperLeaderboardEntry] { entries.count >= 3 ? Array(entries.prefix(3)) : [] }
    private var rest: [PaperLeaderboardEntry] { Array(entries.dropFirst(podium.count)) }

    private var myEntry: PaperLeaderboardEntry? {
        guard let username = SessionStore.shared.username else { return nil }
        return entries.first { $0.username == username }
    }

    /// The trader one place above you, for "x% more to pass them".
    private var nextAbove: PaperLeaderboardEntry? {
        guard let myEntry, myEntry.rank > 1 else { return nil }
        return entries.last { $0.rank < myEntry.rank }
    }

    /// The best return on the board, which each row's bar is measured against.
    private var leaderValue: Decimal? {
        entries.compactMap { $0.rankValue }.max()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s20) {
                    header
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

                    content
                        .padding(.horizontal, Space.margin)
                }
                .padding(.top, Space.s8)
                .padding(.bottom, Space.s24)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isLoading && errorMessage == nil && !entries.isEmpty && (myEntry?.rank ?? .max) > podium.count {
                    YourSpotBar(entry: myEntry, nextAbove: nextAbove) {
                        Haptics.tap()
                        guard let myEntry else {
                            // Unranked: the way onto the board is a trade.
                            DeepLinkRouter.shared.openTab(.discover)
                            return
                        }
                        withAnimation(Motion.standard) { proxy.scrollTo(myEntry.id, anchor: .center) }
                    }
                    .padding(.horizontal, Space.margin)
                    .padding(.bottom, Space.s8)
                }
            }
        }
        .screenBackground()
        .refreshable { await load() }
        .reservesTabBarSpace()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(titleDisplayMode)
        .task { await load() }
        .onChange(of: window) { _, _ in
            Task { await load() }
        }
        .autoRefresh(every: 60) { await refreshSilently() }
        .sheet(item: $selectedEntry) { entry in
            TraderPositionsSheet(entry: entry)
        }
    }

    // MARK: - Header

    private var windowPhrase: String {
        switch window {
        case .day: "in the last 24 hours"
        case .week: "in the last 7 days"
        case .month: "in the last 30 days"
        case .all: "this month"
        }
    }

    @ViewBuilder
    private var header: some View {
        let ranked = response?.rankedCount ?? entries.count
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(myEntry.map { "You\u{2019}re \(Ordinal.string($0.rank))" } ?? "Top traders")
                    .font(.system(size: 40, weight: .heavy))
                    .tracking(-1.2)
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("leaderboard.headline")
                Text(isLoading && response == nil
                     ? "Paper money"
                     : "of \(ranked) traders \(windowPhrase), with paper money")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: Space.s8)
            if let myEntry {
                ShareLink(item: "I\u{2019}m \(Ordinal.string(myEntry.rank)) of \(ranked) traders on Cooked \(windowPhrase). Paper trading. cooked.trade") {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 40, height: 40)
                        .metalSurface(Circle())
                }
                .accessibilityLabel("Share your rank")
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
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
                symbol: "trophy.fill",
                title: "No one's ranked yet",
                action: EmptyStateAction(title: "Make a trade", identifier: "leaderboard.firstTrade") {
                    DeepLinkRouter.shared.openTab(.discover)
                }
            )
        } else {
            VStack(spacing: Space.s20) {
                if !podium.isEmpty {
                    Podium(entries: podium, me: myEntry?.username) { select($0) }
                }
                if let myEntry, myEntry.rank <= podium.count {
                    NextPlaceNudge(me: myEntry, above: nextAbove)
                }
                LazyVStack(spacing: Space.s4) {
                    ForEach(rest) { entry in
                        Button { select(entry) } label: {
                            LeaderboardRow(
                                entry: entry,
                                isMe: entry.username == myEntry?.username,
                                leaderValue: leaderValue
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityHint("Shows what this trader holds")
                        .accessibilityIdentifier("leaderboard.row.\(entry.rank - 1)")
                        .id(entry.id)
                    }
                }
            }
        }
    }

    private func select(_ entry: PaperLeaderboardEntry) {
        Haptics.tap()
        selectedEntry = entry
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

// MARK: - Pieces

extension PaperLeaderboardEntry {
    /// A stated `unavailable` reason means this trader has no qualifying sample yet —
    /// forcing the value to nil here (rather than trusting `pct` to already be null)
    /// keeps a malformed response from ever printing 0% for "no data".
    var shownPct: Decimal? {
        returnPct.unavailable == nil ? returnPct.pct : nil
    }

    /// The dollar move, when the server measured one.
    var shownUsd: Decimal? {
        guard let pnlUsd, pnlUsd.unavailable == nil else { return nil }
        return pnlUsd.usd
    }

    /// What the board shows and measures gaps in: dollars, or the percentage from a
    /// server that doesn't send dollars. Everyone ranked starts with the same $10K, so
    /// the two order the board the same way.
    var rankValue: Decimal? { shownUsd ?? shownPct }

    /// "+$18,421", or "+184.21%" without dollars.
    var pnlLabel: String {
        if let usd = shownUsd { return LeaderboardMoney.signed(usd) }
        return PriceFormat.change(shownPct)
    }
}

/// Whole dollars for the board: +$18,421 / −$412.
enum LeaderboardMoney {
    static func signed(_ value: Decimal) -> String {
        (value < 0 ? "\u{2212}" : "+") + whole(value.magnitude)
    }

    static func whole(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// The gap to the trader above, in the board's unit.
    static func gap(_ me: PaperLeaderboardEntry, _ above: PaperLeaderboardEntry) -> String? {
        if let mine = me.shownUsd, let theirs = above.shownUsd {
            return whole(max(theirs - mine, 1))
        }
        guard let mine = me.shownPct, let theirs = above.shownPct else { return nil }
        return NSDecimalNumber(decimal: max(theirs - mine, 0.01)).doubleValue
            .formatted(.number.precision(.fractionLength(2))) + "%"
    }
}

/// An entry's move, green or red: dollars when known.
struct PnlText: View {
    let entry: PaperLeaderboardEntry
    var font: Font = .rowSubvalue

    var body: some View {
        Text(entry.pnlLabel)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(Color.direction(entry.rankValue))
            .contentTransition(.numericText())
    }
}

/// 1st, 2nd, 3rd, 4th … 11th, 12th, 13th … 21st.
enum Ordinal {
    static func string(_ n: Int) -> String {
        let tens = n % 100
        let suffix: String
        if (11...13).contains(tens) {
            suffix = "th"
        } else {
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}

/// Gold, silver, bronze.
enum Medal {
    static func color(_ rank: Int) -> Color {
        switch rank {
        case 1: AchievementTier.gold.color
        case 2: AchievementTier.silver.color
        default: AchievementTier.bronze.color
        }
    }
}

/// A flat medal: a solid disc with a darker rim and the place on it.
struct MedalDisc: View {
    let rank: Int
    var size: CGFloat = 26

    var body: some View {
        let color = Medal.color(rank)
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(color.blended(with: .black, by: 0.3), lineWidth: max(1.5, size * 0.09)))
            .overlay(
                Text("\(rank)")
                    .font(.system(size: size * 0.48, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Color.black.opacity(0.7))
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 2nd, 1st, 3rd, left to right: rings in medal colors, a crown on the leader, and
/// the steps underneath.
private struct Podium: View {
    let entries: [PaperLeaderboardEntry]
    let me: String?
    let onSelect: (PaperLeaderboardEntry) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.s8) {
            ForEach([1, 0, 2], id: \.self) { index in
                if entries.indices.contains(index) {
                    column(entries[index])
                }
            }
        }
    }

    private func column(_ entry: PaperLeaderboardEntry) -> some View {
        let rank = entry.rank
        let color = Medal.color(rank)
        let avatar: CGFloat = rank == 1 ? 84 : 64
        let step: CGFloat = rank == 1 ? 110 : (rank == 2 ? 82 : 64)
        let isMe = entry.username == me
        return Button { onSelect(entry) } label: {
            VStack(spacing: Space.s8) {
                VStack(spacing: Space.s4) {
                    if rank == 1 {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(color)
                    }
                    ProfileAvatar(seed: entry.username, name: entry.username, size: avatar)
                        .padding(4)
                        .overlay(Circle().strokeBorder(isMe ? Color.accent : color, lineWidth: 3))
                        .shadow(color: color.opacity(rank == 1 ? 0.45 : 0), radius: 18)
                        .overlay(alignment: .bottom) {
                            MedalDisc(rank: rank, size: rank == 1 ? 30 : 26)
                                .offset(y: 12)
                        }
                        .padding(.bottom, 12)
                }
                VStack(spacing: 2) {
                    Text(isMe ? "You" : entry.username)
                        .font(.rowTitle)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    PnlText(entry: entry, font: .rowValue)
                }
                UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous)
                    .fill(color.opacity(0.14))
                    .overlay(alignment: .top) {
                        UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous)
                            .stroke(color.opacity(0.7), lineWidth: 2)
                            .frame(height: 24)
                            .mask(alignment: .top) { Rectangle().frame(height: 12) }
                    }
                    .overlay(alignment: .top) {
                        Text(Ordinal.string(rank))
                            .font(.system(size: rank == 1 ? 34 : 28, weight: .heavy))
                            .tracking(-1)
                            .foregroundStyle(color)
                            .padding(.top, Space.s12)
                    }
                    .frame(height: step)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Ordinal.string(rank)), \(isMe ? "you" : entry.username), \(entry.pnlLabel)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows what this trader holds")
        .accessibilityIdentifier("leaderboard.row.\(rank - 1)")
    }
}

/// "↑ 25.28% more to pass solsniper for 2nd", or a line for holding first.
private struct NextPlaceNudge: View {
    let me: PaperLeaderboardEntry
    let above: PaperLeaderboardEntry?

    var body: some View {
        HStack(spacing: Space.s12) {
            Image(systemName: above == nil ? "crown.fill" : "arrow.up")
                .font(.body.weight(.bold))
            Text(NextPlace.text(me: me, above: above))
                .font(.rowSubvalue)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.accentViolet)
        .padding(.horizontal, Space.s16)
        .padding(.vertical, Space.s16)
        .background(Color.accentViolet.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

enum NextPlace {
    /// The pinned bar's version: "$2,528 to pass #8".
    static func short(me: PaperLeaderboardEntry, above: PaperLeaderboardEntry?) -> String {
        guard let above else { return "You\u{2019}re in 1st" }
        guard let gap = LeaderboardMoney.gap(me, above) else { return "Next up: #\(above.rank)" }
        return "\(gap) to pass #\(above.rank)"
    }

    /// "$2,528 more to pass solsniper for 2nd".
    static func text(me: PaperLeaderboardEntry, above: PaperLeaderboardEntry?) -> String {
        guard let above else { return "You\u{2019}re in 1st. Hold it." }
        guard let gap = LeaderboardMoney.gap(me, above) else {
            return "Next up: \(above.username) in \(Ordinal.string(above.rank))"
        }
        return "\(gap) more to pass \(above.username) for \(Ordinal.string(above.rank))"
    }
}

/// rank | avatar | name and trips over a bar toward the leader | P&L.
private struct LeaderboardRow: View {
    let entry: PaperLeaderboardEntry
    let isMe: Bool
    let leaderValue: Decimal?

    private var fraction: Double {
        guard let value = entry.rankValue, let leaderValue, leaderValue > 0 else { return 0 }
        return min(1, max(0, NSDecimalNumber(decimal: value / leaderValue).doubleValue))
    }

    var body: some View {
        HStack(spacing: Space.s12) {
            Text("\(entry.rank)")
                .font(.rowValue.monospacedDigit())
                .foregroundStyle(isMe ? Color.accent : Color.textTertiary)
                .frame(width: 28, alignment: .leading)
            ProfileAvatar(seed: entry.username, name: entry.username)
            VStack(alignment: .leading, spacing: Space.s8) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s8) {
                    Text(isMe ? "You" : entry.username)
                        .font(.rowTitle)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(entry.roundTripCount) trips")
                        .font(.caption13)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: Space.s8)
                    PnlText(entry: entry, font: .rowValue)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(isMe ? Color.accent : Color.white.opacity(0.28))
                            .frame(width: max(4, geometry.size.width * fraction))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, isMe ? Space.s12 : 0)
        .padding(.vertical, Space.s12)
        .background {
            if isMe {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(Color.accent.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                            .strokeBorder(Color.accent.opacity(0.5), lineWidth: 1)
                    )
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Pinned above the tab bar while you're below the podium (or not ranked yet): your
/// place, the gap to the next one, and a tap that scrolls to your row — or, unranked,
/// opens Discover for the trade that gets you on the board.
private struct YourSpotBar: View {
    let entry: PaperLeaderboardEntry?
    let nextAbove: PaperLeaderboardEntry?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Space.s12) {
                if let entry {
                    Text("#\(entry.rank)")
                        .font(.system(size: 22, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Color.accent)
                        .frame(minWidth: 44, alignment: .leading)
                } else {
                    Text("—")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Color.textTertiary)
                        .frame(minWidth: 44, alignment: .leading)
                }
                ProfileAvatar(seed: SessionStore.shared.username ?? "you", name: SessionStore.shared.username ?? "You")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your spot")
                        .font(.rowTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text(entry.map { NextPlace.short(me: $0, above: nextAbove) } ?? "Close a trade to get ranked")
                        .font(.caption13)
                        .foregroundStyle(entry == nil ? Color.textSecondary : Color.accentViolet)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: Space.s8)
                if let entry {
                    PnlText(entry: entry, font: .rowValue)
                } else {
                    Text("Trade")
                        .font(.caption13.weight(.semibold))
                        .foregroundStyle(Color.accentInk)
                        .padding(.horizontal, Space.s12)
                        .frame(height: Metrics.chipHeight)
                        .background(Color.accent, in: Capsule())
                }
            }
            .padding(.horizontal, Space.s16)
            .padding(.vertical, Space.s12)
            .background(Color.appSurfaceElevated, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.accent.opacity(0.6), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
        }
        .buttonStyle(.pressable)
        .accessibilityHint(entry == nil ? "Opens Discover to make a trade" : "Scrolls to your row")
        .accessibilityIdentifier("leaderboard.yourSpot")
    }
}
