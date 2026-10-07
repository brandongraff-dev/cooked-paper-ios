import SwiftUI

/// Compete → Season: today's Daily Call card on top, then this month's standing (tier, rank, return, how far to the
/// next tier, or what it takes to qualify), the tier ladder, the top 10, and links
/// to achievements and past seasons. A season is a UTC calendar month ranked on the
/// main portfolio's return; duels never count toward it.
struct SeasonView: View {
    @State private var response: SeasonCurrentResponse?
    @State private var isLoading = true
    @State private var isUnavailable = false
    @State private var errorMessage: String?
    private let achievements = AchievementCenter.shared

    var body: some View {
        ScrollView {
            // The Daily Call leads the Compete tab; it hides itself if the server
            // doesn't have it yet.
            DailyCallCard()
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.s8)
            CrowdRecordCard()
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.s16)
            SectionHeader(title: "Play")
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.s24)
            PlayGrid()
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.headerGap)
            Group {
                if isLoading {
                    skeleton
                } else if isUnavailable {
                    EmptyStateView(
                        symbol: "flag.checkered",
                        title: "Seasons start soon",
                        detail: "Monthly seasons with tiers are on their way. The leaderboard is live in the meantime."
                    )
                } else if let response {
                    content(response)
                } else {
                    EmptyStateView(
                        symbol: "wifi.slash",
                        title: "Couldn't load the season",
                        detail: errorMessage ?? "Check your connection and try again."
                    ) {
                        Task { await load() }
                    }
                }
            }
            .padding(.top, Space.s24)
            .padding(.bottom, Space.section)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .refreshable { await load() }
        .reservesTabBarSpace()
        .task { await load() }
        .autoRefresh(every: 60) { await refreshSilently() }
    }

    private func content(_ response: SeasonCurrentResponse) -> some View {
        VStack(alignment: .leading, spacing: Space.section) {
            SeasonHeaderCard(response: response)

            VStack(alignment: .leading, spacing: Space.headerGap) {
                SectionHeader(title: "Tiers")
                TierLadder(tiers: ladderTiers(response), current: SeasonTier(id: response.me?.tier))
            }

            if !response.top.isEmpty {
                VStack(alignment: .leading, spacing: Space.headerGap) {
                    SectionHeader(title: "Top 10", caption: "Simulated")
                    VStack(spacing: 0) {
                        let top = Array(response.top.prefix(10))
                        ForEach(Array(top.enumerated()), id: \.element.id) { index, entry in
                            SeasonEntryRow(entry: entry, tierName: tierName(entry.tier, in: response))
                            if index < top.count - 1 {
                                RowSeparator(leadingInset: SeasonEntryRow.textInset)
                            }
                        }
                    }
                }
            }

            VStack(spacing: 0) {
                if !achievements.isUnavailable {
                    NavigationLink(value: CompeteRoute.achievements) {
                        LinkRow(
                            symbol: "rosette",
                            title: "Achievements",
                            detail: achievements.response.map { "\($0.unlockedCount) of \($0.total)" },
                            tint: .tileYellow
                        )
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("season.achievements")
                    RowSeparator(leadingInset: 30 + Space.s12)
                }
                NavigationLink(value: CompeteRoute.recap) {
                    LinkRow(symbol: "sparkles.rectangle.stack", title: "Your monthly recap", detail: nil, tint: .tilePink)
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("season.recap")
                RowSeparator(leadingInset: 30 + Space.s12)
                NavigationLink(value: CompeteRoute.seasonHistory) {
                    LinkRow(symbol: "clock.arrow.circlepath", title: "Past seasons", detail: nil, tint: .tileGray)
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("season.history")
            }
            .padding(.horizontal, Space.s16)
            .glassCard()

            CompeteLegalCaption()
        }
        .padding(.horizontal, Space.margin)
        .task { if achievements.response == nil { await achievements.load() } }
    }

    /// The five ranked tiers, best first — the server's list, or the spec's
    /// defaults if it sent none.
    private func ladderTiers(_ response: SeasonCurrentResponse) -> [SeasonTierInfo] {
        let ranked = response.tiers.filter { $0.tier != .unranked }
        if !ranked.isEmpty { return ranked }
        return [
            SeasonTierInfo(id: SeasonTier.michelin.rawValue, name: "Michelin", topPercent: 1),
            SeasonTierInfo(id: SeasonTier.headChef.rawValue, name: "Head Chef", topPercent: 10),
            SeasonTierInfo(id: SeasonTier.sousChef.rawValue, name: "Sous Chef", topPercent: 25),
            SeasonTierInfo(id: SeasonTier.lineCook.rawValue, name: "Line Cook", topPercent: 50),
            SeasonTierInfo(id: SeasonTier.prepCook.rawValue, name: "Prep Cook", topPercent: nil),
        ]
    }

    private func tierName(_ id: String, in response: SeasonCurrentResponse) -> String {
        response.tiers.first { $0.id == id }?.name ?? SeasonTier(id: id).defaultName
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            SkeletonBlock(height: 220, cornerRadius: Radius.card)
                .padding(.bottom, Space.s16)
            SkeletonBlock(width: 80, height: 18)
            ForEach(0..<5, id: \.self) { _ in SkeletonRow() }
        }
        .padding(.horizontal, Space.margin)
    }

    private func load() async {
        isLoading = response == nil && !isUnavailable
        errorMessage = nil
        do {
            response = try await SeasonsAPI.current()
            isUnavailable = false
        } catch let error where error.isNotFound {
            isUnavailable = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func refreshSilently() async {
        guard !isLoading, !isUnavailable, let fresh = try? await SeasonsAPI.current() else { return }
        response = fresh
    }
}

// MARK: - Header

private struct SeasonHeaderCard: View {
    let response: SeasonCurrentResponse

    private var me: SeasonStanding? { response.me }
    private var tier: SeasonTier { SeasonTier(id: me?.tier) }

    private var tierName: String {
        guard let me else { return SeasonTier.unranked.defaultName }
        return response.tiers.first { $0.id == me.tier }?.name ?? tier.defaultName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s20) {
            HStack(alignment: .firstTextBaseline) {
                Text(response.season.label)
                    .font(.caption13)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: Space.s8)
                if let end = response.season.endDate {
                    CountdownText(end: end)
                        .accessibilityLabel("Time left in the season")
                }
            }

            if let me, me.qualified {
                qualified(me)
            } else {
                unranked(me)
            }

            SimulatedCaption()
        }
        .padding(Space.s20)
        .glassCard()
        .accessibilityIdentifier("season.header")
    }

    @ViewBuilder
    private func qualified(_ me: SeasonStanding) -> some View {
        HStack(alignment: .center, spacing: Space.s16) {
            TierBadge(tier: tier, size: 56)
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(tierName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                if let rank = me.rank {
                    Text(CompeteFormat.rank(rank, of: me.of))
                        .font(.rowSubvalue)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: Space.s8)
            VStack(alignment: .trailing, spacing: Space.s4) {
                ChangeText(percent: me.returnPct, font: .title3.weight(.semibold))
                Text("Return")
                    .font(.caption13)
                    .foregroundStyle(Color.textTertiary)
            }
        }

        if let next = me.nextTier, let rank = me.rank {
            let places = max(1, rank - next.rankNeeded)
            let nextName = response.tiers.first { $0.id == next.id }?.name ?? SeasonTier(id: next.id).defaultName
            VStack(alignment: .leading, spacing: Space.s8) {
                ProgressTrack(fraction: progressToNext(me, nextId: next.id), tint: SeasonTier(id: next.id).color)
                Text("\(CompeteFormat.count(places)) \(places == 1 ? "place" : "places") to \(nextName)")
                    .font(.caption13Digits)
                    .foregroundStyle(Color.textSecondary)
            }
        } else if tier == .michelin {
            Text("Top tier. Hold it to the end of the month.")
                .font(.caption13)
                .foregroundStyle(Color.textSecondary)
        }
    }

    @ViewBuilder
    private func unranked(_ me: SeasonStanding?) -> some View {
        let needed = me?.minRoundTrips ?? 2
        let done = min(me?.roundTrips ?? 0, needed)
        let left = max(0, needed - done)
        HStack(alignment: .center, spacing: Space.s16) {
            TierBadge(tier: .unranked, size: 56)
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Unranked")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(left == 0
                     ? "Qualifying at the next update"
                     : "Close \(left) \(left == 1 ? "trade" : "trades") to qualify")
                    .font(.rowSubvalue)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        VStack(alignment: .leading, spacing: Space.s8) {
            ProgressTrack(fraction: needed > 0 ? Double(done) / Double(needed) : 0)
            Text("\(done) of \(needed) closed trades")
                .font(.caption13Digits)
                .foregroundStyle(Color.textSecondary)
        }
    }

    /// How far through the current tier's band toward the next one, by percentile
    /// (e.g. at 3.2% between Head Chef's 10% and Michelin's 1% → 76%).
    private func progressToNext(_ me: SeasonStanding, nextId: String) -> Double {
        guard let percentile = me.percentile.map({ NSDecimalNumber(decimal: $0).doubleValue }),
              let nextTop = response.tiers.first(where: { $0.id == nextId })?.topPercent
        else { return 0 }
        let currentTop = response.tiers.first(where: { $0.id == me.tier })?.topPercent ?? 100
        let band = currentTop - nextTop
        guard band > 0 else { return 0 }
        return min(1, max(0, (currentTop - percentile) / band))
    }
}

// MARK: - Ladder

private struct TierLadder: View {
    let tiers: [SeasonTierInfo]
    let current: SeasonTier

    var body: some View {
        VStack(spacing: Space.s4) {
            ForEach(tiers) { info in
                let isMine = info.tier == current
                HStack(spacing: Space.s12) {
                    TierBadge(tier: info.tier, size: 32)
                    Text(info.name)
                        .font(.rowTitle)
                        .foregroundStyle(isMine ? Color.textPrimary : Color.textSecondary)
                    if isMine {
                        Text("You")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.inverseText)
                            .padding(.horizontal, Space.s8)
                            .padding(.vertical, 2)
                            .background(Color.inverseFill, in: Capsule())
                    }
                    Spacer(minLength: Space.s8)
                    Text(rule(info))
                        .font(.caption13Digits)
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, Space.s12)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(isMine ? Color.appSurfaceElevated : Color.appSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .strokeBorder(isMine ? info.tier.color.opacity(0.45) : Color.clear, lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isMine ? .isSelected : [])
            }
        }
    }

    private func rule(_ info: SeasonTierInfo) -> String {
        guard let top = info.topPercent, top < 100 else { return "Qualified" }
        return "Top \(top.formatted(.number.precision(.fractionLength(0...1))))%"
    }
}

// MARK: - Rows

/// rank | avatar | name over tier | return %.
struct SeasonEntryRow: View {
    let entry: SeasonTopEntry
    let tierName: String

    static let rankWidth: CGFloat = 24
    static let textInset: CGFloat = rankWidth + Space.s12 + Metrics.avatar + Metrics.avatarGap

    var body: some View {
        HStack(spacing: Space.s12) {
            Text("\(entry.rank)")
                .font(.rowSubvalue)
                .foregroundStyle(entry.rank <= 3 ? Color.textPrimary : Color.textTertiary)
                .frame(width: Self.rankWidth, alignment: .leading)
            ListRow(title: entry.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? entry.username, subtitle: tierName) {
                ProfileAvatar(seed: entry.avatarSeed ?? entry.username, name: entry.displayName ?? entry.username)
                    .overlay(alignment: .bottomTrailing) {
                        TierBadge(tier: SeasonTier(id: entry.tier), size: 18)
                            .background(Color.appBackground, in: Circle())
                            .offset(x: Space.s4, y: Space.s4)
                    }
            } trailing: {
                ChangeText(percent: entry.returnPct, font: .rowValue)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The four game modes as tiles: a big colored icon, a name, and a few words.
private struct PlayGrid: View {
    private struct Mode: Identifiable {
        let id: String
        let route: CompeteRoute
        let symbol: String
        let color: Color
        let title: String
        let caption: String
        /// The full sentence, for VoiceOver.
        let detail: String
    }

    private let modes: [Mode] = [
        Mode(id: "season.challenges", route: .challenges, symbol: "flag.checkered", color: .tileOrange,
             title: "Challenges", caption: "+8% to pass",
             detail: "Hit plus 8 percent before you lose 5 percent."),
        Mode(id: "season.rooms", route: .rooms, symbol: "dot.radiowaves.left.and.right", color: .tilePink,
             title: "Live Rooms", caption: "CPI & Fed days",
             detail: "Trade market events with everyone, or host a room for your stream."),
        Mode(id: "season.squads", route: .squads, symbol: "person.3.fill", color: .tileIndigo,
             title: "Squads", caption: "Trade by vote",
             detail: "Share one portfolio with friends. Every trade is a vote."),
        Mode(id: "season.replay", route: .replays, symbol: "chart.line.downtrend.xyaxis", color: .tileTeal,
             title: "Crash Replay", caption: "Survive the crash",
             detail: "Trade a real historical crash blind."),
    ]

    var body: some View {
        // A plain Grid, not LazyVGrid: the tiles sit below the fold, and a lazy grid
        // wouldn't build them (or expose them to VoiceOver and UI tests) until scrolled to.
        Grid(horizontalSpacing: Space.s12, verticalSpacing: Space.s12) {
            ForEach([0, 2], id: \.self) { start in
                GridRow {
                    ForEach(modes[start..<start + 2]) { mode in
                        tile(mode)
                    }
                }
            }
        }
    }

    private func tile(_ mode: Mode) -> some View {
        NavigationLink(value: mode.route) {
            VStack(alignment: .leading, spacing: Space.s4) {
                ModeIcon(mode: mode.id)
                    .frame(height: 56, alignment: .bottomLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, Space.s16)
                Text(mode.title)
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(mode.caption)
                    .font(.caption13)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s16)
            .overlay(alignment: .topTrailing) {
                if mode.id == "season.rooms" { LiveTag().padding(Space.s12) }
            }
            .glassCard()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(mode.title)
        .accessibilityHint(mode.detail)
        .accessibilityIdentifier(mode.id)
    }
}

/// Each mode's drawn icon: a coin stack, a live beacon, a squad's faces, a crash.
private struct ModeIcon: View {
    let mode: String

    var body: some View {
        Group {
            switch mode {
            case "season.challenges":
                // A rank badge and the rail, two thirds of the way to the pass line.
                HStack(spacing: Space.s12) {
                    TierEmblem(level: 2, size: 40)
                    ChallengeRail(marker: 0.66, fill: true)
                }
            case "season.rooms": LiveBeaconIcon(height: 46)
            case "season.squads": squadFaces
            default: CrashScreenIcon(height: 50)
            }
        }
        .accessibilityHidden(true)
    }

    /// Three friends' avatars, overlapping, and a +2.
    private var squadFaces: some View {
        HStack(spacing: -12) {
            ForEach(["ada", "kai", "zoe"], id: \.self) { seed in
                ProfileAvatar(seed: seed, name: seed, size: 40)
                    .overlay(Circle().strokeBorder(Color.appSurface, lineWidth: 2.5))
            }
            Text("+2")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 40, height: 40)
                .metalSurface(Circle())
                .padding(.leading, 16)
        }
    }
}

/// "● LIVE" on a red-tinted pill.
private struct LiveTag: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Color.negative).frame(width: 6, height: 6)
            Text("LIVE")
                .font(.caption2.weight(.heavy))
                .tracking(1)
        }
        .foregroundStyle(Color.negative)
        .padding(.horizontal, Space.s8)
        .padding(.vertical, 4)
        .background(Color.negative.opacity(0.16), in: Capsule())
        .accessibilityHidden(true)
    }
}

/// An icon, a title and an optional detail, with a chevron — a row inside a card.
struct LinkRow: View {
    let symbol: String
    let title: String
    let detail: String?
    var tint: Color = .tileBlue

    var body: some View {
        HStack(spacing: Space.s12) {
            IconTile(symbol: symbol, color: tint, size: 30)
            Text(title)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.rowSubvalue)
                    .foregroundStyle(Color.textTertiary)
            }
            Image(systemName: "chevron.right")
                .font(.caption13)
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

// MARK: - Past seasons

/// Every finished season the account qualified in, newest first.
struct SeasonHistoryView: View {
    @State private var seasons: [SeasonHistoryEntry]?
    @State private var isUnavailable = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            Group {
                if let seasons {
                    if seasons.isEmpty {
                        EmptyStateView(
                            symbol: "flag.checkered",
                            title: "No finished seasons yet",
                            detail: "Close a couple of trades in a month to place on its leaderboard. Your results land here when it ends."
                        )
                    } else {
                        list(seasons)
                    }
                } else if isUnavailable {
                    EmptyStateView(symbol: "flag.checkered", title: "Seasons start soon", detail: "Past seasons will show up here once the first one ends.")
                } else if let errorMessage {
                    EmptyStateView(symbol: "wifi.slash", title: "Couldn't load past seasons", detail: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { _ in SkeletonRow() }
                    }
                    .padding(.horizontal, Space.margin)
                }
            }
            .padding(.top, Space.s8)
            .padding(.bottom, Space.section)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .refreshable { await load() }
        .reservesTabBarSpace()
        .navigationTitle("Past seasons")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func list(_ seasons: [SeasonHistoryEntry]) -> some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SimulatedCaption()
            VStack(spacing: 0) {
                ForEach(Array(seasons.enumerated()), id: \.element.id) { index, entry in
                    NavigationLink(value: CompeteRoute.seasonResults(id: entry.season.id, label: entry.season.label)) {
                        ListRow(title: entry.season.label, subtitle: CompeteFormat.rank(entry.rank, of: entry.of)) {
                            TierBadge(tier: SeasonTier(id: entry.tier), size: Metrics.avatar)
                        } trailing: {
                            ChangeText(percent: entry.returnPct, font: .rowValue)
                            Text(SeasonTier(id: entry.tier).defaultName)
                                .font(.rowSubvalue)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .buttonStyle(.pressable)
                    if index < seasons.count - 1 { RowSeparator() }
                }
            }
            CompeteLegalCaption()
                .padding(.top, Space.s16)
        }
        .padding(.horizontal, Space.margin)
    }

    private func load() async {
        errorMessage = nil
        do {
            seasons = try await SeasonsAPI.history()
        } catch let error where error.isNotFound {
            isUnavailable = true
        } catch {
            if seasons == nil { errorMessage = error.localizedDescription }
        }
    }
}

/// A finished season's final standings.
struct SeasonResultsView: View {
    let seasonId: String
    let label: String

    @State private var results: [SeasonTopEntry]?
    @State private var isUnavailable = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            Group {
                if let results {
                    if results.isEmpty {
                        EmptyStateView(symbol: "trophy", title: "No results", detail: "Nobody qualified this season.")
                    } else {
                        VStack(alignment: .leading, spacing: Space.headerGap) {
                            SimulatedCaption()
                            LazyVStack(spacing: 0) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                                    SeasonEntryRow(entry: entry, tierName: SeasonTier(id: entry.tier).defaultName)
                                    if index < results.count - 1 {
                                        RowSeparator(leadingInset: SeasonEntryRow.textInset)
                                    }
                                }
                            }
                            CompeteLegalCaption()
                                .padding(.top, Space.s16)
                        }
                        .padding(.horizontal, Space.margin)
                    }
                } else if isUnavailable {
                    EmptyStateView(symbol: "hourglass", title: "Results aren't final yet", detail: "Final standings appear here once the season is archived.")
                } else if let errorMessage {
                    EmptyStateView(symbol: "wifi.slash", title: "Couldn't load results", detail: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { _ in SkeletonRow() }
                    }
                    .padding(.horizontal, Space.margin)
                }
            }
            .padding(.top, Space.s8)
            .padding(.bottom, Space.section)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .refreshable { await load() }
        .reservesTabBarSpace()
        .navigationTitle(label)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        errorMessage = nil
        do {
            results = try await SeasonsAPI.results(seasonId: seasonId).results
        } catch let error where error.isNotFound {
            isUnavailable = true
        } catch {
            if results == nil { errorMessage = error.localizedDescription }
        }
    }
}
