import SwiftUI

/// Compete → Duels: your record as the headline, then active duels (live head-to-head and the
/// clock), invites waiting on you, invites you sent, and finished duels with a
/// rematch. Two players, the same fresh $1,000 paper portfolio, best return wins.
struct DuelsView: View {
    private let store = DuelsStore.shared

    @State private var showsNewDuel = false
    @State private var busyDuelId: String?
    @State private var actionError: String?

    var body: some View {
        ScrollView {
            Group {
                if store.isLoading && store.lists == nil {
                    skeleton
                } else if store.isUnavailable {
                    EmptyStateView(
                        symbol: "figure.fencing",
                        title: "Duels are almost here",
                        detail: "Head-to-head paper duels with friends are on their way. Check back soon."
                    )
                } else if let lists = store.lists {
                    content(lists)
                } else {
                    EmptyStateView(
                        symbol: "wifi.slash",
                        title: "Couldn't load your duels",
                        detail: store.errorMessage ?? "Check your connection and try again."
                    ) {
                        Task { await store.load() }
                    }
                }
            }
            .padding(.top, Space.s8)
            .padding(.bottom, Space.section)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .refreshable { await store.load() }
        .reservesTabBarSpace()
        .task { await store.load() }
        .autoRefresh(every: 15) { await store.refreshSilently() }
        .sheet(isPresented: $showsNewDuel) {
            NewDuelSheet()
        }
        .alert(
            "Couldn't update the duel",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private func content(_ lists: DuelListResponse) -> some View {
        VStack(alignment: .leading, spacing: Space.section) {
            if lists.isEmpty {
                VStack(alignment: .leading, spacing: Space.s8) {
                    rules
                    EmptyStateView(
                        symbol: "figure.fencing",
                        title: "No duels yet",
                        action: EmptyStateAction(title: "Start a duel", symbol: "plus", identifier: "duels.new") {
                            showsNewDuel = true
                        }
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: Space.s20) {
                    VStack(alignment: .leading, spacing: Space.s12) {
                        ScreenHeadline(title: recordTitle, subtitle: recordSubtitle)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("duels.record")
                        rules
                    }
                    Button {
                        Haptics.tap()
                        showsNewDuel = true
                    } label: {
                        Label("New duel", systemImage: "plus")
                    }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("duels.new")
                }
            }

            if !lists.active.isEmpty {
                section("Active") {
                    ForEach(Array(lists.active.enumerated()), id: \.element.id) { index, duel in
                        NavigationLink(value: CompeteRoute.duel(id: duel.id)) {
                            ActiveDuelRow(duel: duel)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityIdentifier("duels.active.\(index)")
                        if index < lists.active.count - 1 { RowSeparator() }
                    }
                }
            }

            if !lists.incoming.isEmpty {
                section("Invites") {
                    ForEach(Array(lists.incoming.enumerated()), id: \.element.id) { index, duel in
                        IncomingDuelRow(
                            duel: duel,
                            isBusy: busyDuelId == duel.id,
                            accept: { perform(duel) { [id = duel.id] in try await DuelsAPI.accept(id: id) } },
                            decline: { perform(duel) { [id = duel.id] in try await DuelsAPI.decline(id: id) } }
                        )
                        .accessibilityIdentifier("duels.incoming.\(index)")
                        if index < lists.incoming.count - 1 { RowSeparator() }
                    }
                }
            }

            if !lists.outgoing.isEmpty {
                section("Sent") {
                    ForEach(Array(lists.outgoing.enumerated()), id: \.element.id) { index, duel in
                        OutgoingDuelRow(
                            duel: duel,
                            isBusy: busyDuelId == duel.id,
                            cancel: { perform(duel) { [id = duel.id] in try await DuelsAPI.cancel(id: id) } }
                        )
                        .accessibilityIdentifier("duels.outgoing.\(index)")
                        if index < lists.outgoing.count - 1 { RowSeparator() }
                    }
                }
            }

            if !lists.finished.isEmpty {
                section("Finished") {
                    ForEach(Array(lists.finished.enumerated()), id: \.element.id) { index, duel in
                        HStack(spacing: Space.s12) {
                            NavigationLink(value: CompeteRoute.duel(id: duel.id)) {
                                FinishedDuelRow(duel: duel)
                            }
                            .buttonStyle(.pressable)
                            .accessibilityIdentifier("duels.finished.\(index)")
                            if duel.them != nil {
                                Button("Rematch") {
                                    Haptics.tap()
                                    perform(duel) { [id = duel.id] in try await DuelsAPI.rematch(id: id) }
                                }
                                .buttonStyle(.compact)
                                .disabled(busyDuelId != nil)
                                .accessibilityIdentifier("duels.rematch.\(index)")
                            }
                        }
                        if index < lists.finished.count - 1 { RowSeparator() }
                    }
                }
            }

            CompeteLegalCaption()
        }
        .padding(.horizontal, Space.margin)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(title: title)
            VStack(spacing: 0) {
                content()
            }
            .glassList()
        }
    }

    /// The format, as pills: the same stake for both, best return wins.
    private var rules: some View {
        InfoPillRow(pills: [
            (symbol: "dollarsign.circle.fill", text: "$1K each"),
            (symbol: "trophy.fill", text: "Best return wins"),
        ])
    }

    /// "4–2", or "4–2–1" with draws: wins, losses, draws.
    private var recordTitle: String {
        guard let stats = store.stats else { return "Duels" }
        return stats.draws > 0
            ? "\(stats.wins)–\(stats.losses)–\(stats.draws)"
            : "\(stats.wins)–\(stats.losses)"
    }

    /// "Wins, losses · 2 in a row · best 4".
    private var recordSubtitle: String? {
        guard let stats = store.stats else { return nil }
        var parts = [stats.draws > 0 ? "Wins, losses, draws" : "Wins, losses"]
        if stats.currentStreak > 0 { parts.append("\(stats.currentStreak) in a row") }
        if stats.bestStreak > 0 { parts.append("best \(stats.bestStreak)") }
        return parts.joined(separator: " · ")
    }

    /// Runs one row action (accept, decline, cancel, rematch); the list refreshes
    /// behind it and a refusal shows as a plain-words alert.
    private func perform(_ duel: Duel, _ action: @escaping @MainActor () async throws -> Duel) {
        guard busyDuelId == nil else { return }
        busyDuelId = duel.id
        Task {
            do {
                let updated = try await action()
                Haptics.success()
                store.didChange(updated)
            } catch {
                Haptics.error()
                actionError = CompeteErrorText.message(for: error)
            }
            busyDuelId = nil
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            SkeletonBlock(width: 140, height: 44)
            SkeletonBlock(width: 220, height: 16)
            SkeletonBlock(height: Metrics.buttonHeight, cornerRadius: Metrics.buttonHeight / 2)
                .padding(.bottom, Space.s16)
            SkeletonBlock(width: 80, height: 18)
            ForEach(0..<4, id: \.self) { _ in SkeletonRow() }
        }
        .padding(.horizontal, Space.margin)
    }
}

// MARK: - Rows

/// Avatar | "vs @them" over the clock and a head-to-head bar | both returns.
private struct ActiveDuelRow: View {
    let duel: Duel

    var body: some View {
        HStack(spacing: Metrics.avatarGap) {
            OpponentAvatar(player: duel.them)
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: Space.s8) {
                    Text("vs \(duel.them?.handle ?? "open invite")")
                        .font(.rowTitle)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if duel.leader == .me {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundStyle(AchievementTier.gold.color)
                            .accessibilityLabel("You're leading")
                    }
                }
                HStack(spacing: Space.s8) {
                    if let end = duel.endDate {
                        CountdownText(end: end)
                    }
                    Text("· \(duel.durationLabel)")
                        .font(.caption13)
                        .foregroundStyle(Color.textTertiary)
                }
                HeadToHeadBar(mine: duel.me?.returnPct, theirs: duel.them?.returnPct, height: 4)
                    .frame(maxWidth: 140)
            }
            Spacer(minLength: Space.s8)
            VStack(alignment: .trailing, spacing: 2) {
                ChangeText(percent: duel.me?.returnPct, font: .rowValue)
                ChangeText(percent: duel.them?.returnPct)
                    .opacity(0.8)
            }
        }
        .frame(minHeight: Metrics.rowHeight + Space.s8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct IncomingDuelRow: View {
    let duel: Duel
    let isBusy: Bool
    let accept: () -> Void
    let decline: () -> Void

    var body: some View {
        HStack(spacing: Metrics.avatarGap) {
            OpponentAvatar(player: duel.them)
            VStack(alignment: .leading, spacing: 2) {
                Text(duel.them?.handle ?? "Someone")
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("Challenged you · \(duel.durationLabel)")
                    .font(.rowSubvalue)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s8)
            if isBusy {
                ProgressView().tint(Color.textSecondary)
            } else {
                Button {
                    Haptics.tap()
                    decline()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption13.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: Metrics.chipHeight, height: Metrics.chipHeight)
                        .background(Color.appSurfaceElevated, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Decline")
                .accessibilityIdentifier("duels.decline")
                Button("Accept") {
                    Haptics.commit()
                    accept()
                }
                .buttonStyle(.compact)
                .accessibilityIdentifier("duels.accept")
            }
        }
        .frame(minHeight: Metrics.rowHeight)
    }
}

private struct OutgoingDuelRow: View {
    let duel: Duel
    let isBusy: Bool
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: Metrics.avatarGap) {
            OpponentAvatar(player: duel.opponent)
            VStack(alignment: .leading, spacing: 2) {
                Text(duel.opponent?.handle ?? "Open invite")
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("Waiting · \(duel.durationLabel)")
                    .font(.rowSubvalue)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s8)
            if isBusy {
                ProgressView().tint(Color.textSecondary)
            } else {
                if let url = duel.inviteURL {
                    ShareLink(
                        item: url,
                        subject: Text("Duel me on Cooked"),
                        message: Text("Duel me on Cooked: $1,000 in paper money each, \(DuelDuration(rawValue: duel.durationHours)?.longLabel ?? duel.durationLabel), best return wins. No stakes, just bragging rights.")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption13.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .frame(width: Metrics.chipHeight, height: Metrics.chipHeight)
                            .background(Color.appSurfaceElevated, in: Circle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Share invite link")
                }
                Button("Cancel") {
                    Haptics.tap()
                    cancel()
                }
                .buttonStyle(.compact)
                .accessibilityIdentifier("duels.cancel")
            }
        }
        .frame(minHeight: Metrics.rowHeight)
    }
}

private struct FinishedDuelRow: View {
    let duel: Duel

    var body: some View {
        HStack(spacing: Metrics.avatarGap) {
            OutcomeBadge(outcome: duel.outcome)
            VStack(alignment: .leading, spacing: 2) {
                Text("vs \(duel.them?.handle ?? "—")")
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("\(PriceFormat.change(duel.me?.returnPct)) vs \(PriceFormat.change(duel.them?.returnPct)) · \(duel.durationLabel)")
                    .font(.rowSubvalue)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Metrics.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// W / L / D in a 40pt circle: the letter carries the result, color only backs it.
struct OutcomeBadge: View {
    let outcome: DuelOutcome?

    private var color: Color {
        switch outcome {
        case .won: .positive
        case .lost: .negative
        case .draw, nil: .textSecondary
        }
    }

    var body: some View {
        Circle()
            .fill(Color.appFill)
            .frame(width: Metrics.avatar, height: Metrics.avatar)
            .overlay(
                Text(outcome?.letter ?? "–")
                    .font(.rowTitle)
                    .foregroundStyle(color)
            )
            .accessibilityLabel(outcome?.title ?? "No result")
    }
}

/// The other player's avatar, or a dashed placeholder for an open invite.
struct OpponentAvatar: View {
    let player: DuelPlayer?
    var size: CGFloat = Metrics.avatar

    var body: some View {
        if let player {
            ProfileAvatar(seed: player.seed, name: player.shownName.hasPrefix("@") ? player.username : player.shownName, size: size)
        } else {
            Circle()
                .strokeBorder(Color.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "link")
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                )
                .accessibilityHidden(true)
        }
    }
}
