import SwiftUI

/// One friend league: the season clock, the invite link, and the standings —
/// ranked members first, then those who haven't closed enough trades to qualify,
/// with your row highlighted. The owner can rename it, rotate the invite code,
/// remove members and delete it; members can leave.
struct LeagueDetailView: View {
    let leagueId: String

    @Environment(\.dismiss) private var dismiss
    @State private var league: League?
    @State private var standings: [LeagueStanding] = []
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var actionError: String?

    @State private var showsRename = false
    @State private var renameText = ""
    @State private var confirmRotate = false
    @State private var confirmDelete = false
    @State private var confirmLeave = false
    @State private var memberToRemove: LeagueStanding?

    private let store = LeaguesStore.shared

    init(leagueId: String, initial: League? = nil) {
        self.leagueId = leagueId
        _league = State(initialValue: initial)
    }

    private var ranked: [LeagueStanding] {
        standings.filter { $0.qualified && $0.rank != nil }.sorted { ($0.rank ?? 0) < ($1.rank ?? 0) }
    }

    private var unqualified: [LeagueStanding] {
        standings.filter { !($0.qualified && $0.rank != nil) }
    }

    var body: some View {
        Group {
            if let league {
                content(league)
            } else if !hasLoaded {
                skeleton
            } else {
                EmptyStateView(
                    symbol: "person.3",
                    title: "Couldn't open this league",
                    detail: errorMessage ?? "It may have been deleted."
                ) {
                    Task { await load() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground)
        .reservesTabBarSpace()
        .navigationTitle(league?.name ?? "League")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let league {
                    menu(league)
                }
            }
        }
        .task { await load() }
        .autoRefresh(every: 30) { await load() }
        .alert("Rename league", isPresented: $showsRename) {
            TextField("League name", text: $renameText)
            Button("Save") { Task { await rename() } }
                .disabled(!LeagueRules.isValidName(renameText))
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Up to \(LeagueRules.maxNameLength) characters.")
        }
        .confirmationDialog("New invite code?", isPresented: $confirmRotate, titleVisibility: .visible) {
            Button("Get a new code") { Task { await rotate() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current link stops working. Members already in the league stay.")
        }
        .confirmationDialog(
            memberToRemove.map { "Remove @\($0.username)?" } ?? "",
            isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }),
            titleVisibility: .visible,
            presenting: memberToRemove
        ) { member in
            Button("Remove", role: .destructive) { Task { await remove(member) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("They can rejoin only with a current invite code.")
        }
        .confirmationDialog("Delete this league?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete league", role: .destructive) { Task { await deleteLeague() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The league and its standings go for everyone. This can't be undone.")
        }
        .confirmationDialog("Leave this league?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave league", role: .destructive) { Task { await leave() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can come back with an invite code.")
        }
        .alert(
            "Couldn't update the league",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Content

    private func content(_ league: League) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                header(league)

                if let url = league.inviteURL {
                    ShareLink(
                        item: url,
                        subject: Text(league.name),
                        message: Text("Join my league \u{201C}\(league.name)\u{201D} on Cooked: paper trading, ranked on this season's returns. No stakes.")
                    ) {
                        Label("Invite friends", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("league.invite")
                }

                VStack(alignment: .leading, spacing: Space.headerGap) {
                    SectionHeader(title: "Standings", caption: "Simulated")
                    if standings.isEmpty && !hasLoaded {
                        VStack(spacing: 0) {
                            ForEach(0..<4, id: \.self) { _ in SkeletonRow() }
                        }
                    } else if ranked.isEmpty {
                        Text("Nobody has qualified yet. Close a couple of trades this season to get ranked.")
                            .font(.rowSubtitle)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(ranked.enumerated()), id: \.element.id) { index, row in
                                LeagueStandingRow(row: row, canRemove: league.isOwner) { memberToRemove = row }
                                    .accessibilityIdentifier("league.standing.\(index)")
                                if index < ranked.count - 1 {
                                    RowSeparator(leadingInset: LeagueStandingRow.textInset)
                                }
                            }
                        }
                    }
                }

                if !unqualified.isEmpty {
                    VStack(alignment: .leading, spacing: Space.headerGap) {
                        SectionHeader(title: "Not yet qualified")
                        VStack(spacing: 0) {
                            ForEach(Array(unqualified.enumerated()), id: \.element.id) { index, row in
                                LeagueStandingRow(row: row, canRemove: league.isOwner) { memberToRemove = row }
                                if index < unqualified.count - 1 {
                                    RowSeparator(leadingInset: LeagueStandingRow.textInset)
                                }
                            }
                        }
                    }
                }

                CompeteLegalCaption()
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s8)
            .padding(.bottom, Space.section)
        }
        .scrollIndicators(.hidden)
        .refreshable { await load() }
    }

    private func header(_ league: League) -> some View {
        HStack(alignment: .center, spacing: Space.s16) {
            LeagueAvatar(name: league.name, seed: league.id, size: 56)
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(league.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(memberLine(league))
                    .font(.rowSubvalue)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                if let season = league.season {
                    HStack(spacing: Space.s4) {
                        Text(season.label)
                            .font(.caption13)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                        if let end = season.endDate {
                            Text("·")
                                .font(.caption13)
                                .foregroundStyle(Color.textTertiary)
                            CountdownText(end: end, color: .textTertiary)
                        }
                    }
                }
            }
            Spacer(minLength: Space.s8)
            VStack(alignment: .trailing, spacing: Space.s4) {
                Text(league.yourRank.map { "#\($0)" } ?? "—")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                Text("Your rank")
                    .font(.caption13)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(Space.s20)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("league.header")
    }

    private func memberLine(_ league: League) -> String {
        let members = league.maxMembers.map { "\(league.memberCount) of \($0) members" } ?? "\(league.memberCount) members"
        if league.isOwner { return "\(members) · You own it" }
        guard let owner = league.ownerUsername else { return members }
        return "\(members) · Run by @\(owner)"
    }

    private func menu(_ league: League) -> some View {
        Menu {
            if league.isOwner {
                Button {
                    renameText = league.name
                    showsRename = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    confirmRotate = true
                } label: {
                    Label("New invite code", systemImage: "arrow.triangle.2.circlepath")
                }
                let others = standings.filter { !$0.isYou }
                if !others.isEmpty {
                    Menu {
                        ForEach(others) { member in
                            Button("@\(member.username)") { memberToRemove = member }
                        }
                    } label: {
                        Label("Remove member", systemImage: "person.badge.minus")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete league", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    confirmLeave = true
                } label: {
                    Label("Leave league", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            if isWorking {
                ProgressView().tint(Color.textSecondary)
            } else {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .disabled(isWorking)
        .accessibilityLabel("League options")
        .accessibilityIdentifier("league.menu")
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            SkeletonBlock(height: 104, cornerRadius: Radius.card)
            SkeletonBlock(height: Metrics.buttonHeight, cornerRadius: Metrics.buttonHeight / 2)
                .padding(.bottom, Space.s16)
            ForEach(0..<5, id: \.self) { _ in SkeletonRow() }
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s8)
    }

    // MARK: - Networking

    private func load() async {
        do {
            let detail = try await LeaguesAPI.detail(id: leagueId)
            withAnimation(Motion.standard) {
                league = detail.league
                standings = detail.standings
            }
            errorMessage = nil
            store.didChange(detail.league)
        } catch {
            if league == nil || !hasLoaded {
                errorMessage = CompeteErrorText.message(for: error, in: .league)
            }
            if (error as? APIError)?.code == "league_not_found" {
                // Deleted, or you were removed, while it was open.
                league = nil
                store.didRemove(leagueId: leagueId)
            }
        }
        hasLoaded = true
    }

    private func rename() async {
        let name = LeagueRules.sanitizedName(renameText)
        guard LeagueRules.isValidName(name) else { return }
        await perform {
            let updated = try await LeaguesAPI.rename(id: leagueId, name: name)
            league = updated
            store.didChange(updated)
        }
    }

    private func rotate() async {
        await perform {
            let updated = try await LeaguesAPI.rotateCode(id: leagueId)
            league = updated
            store.didChange(updated)
        }
    }

    private func remove(_ member: LeagueStanding) async {
        await perform {
            try await LeaguesAPI.removeMember(leagueId: leagueId, userId: member.userId)
            withAnimation(Motion.standard) {
                standings.removeAll { $0.userId == member.userId }
            }
            await load()
        }
    }

    private func deleteLeague() async {
        await perform {
            try await LeaguesAPI.delete(id: leagueId)
            store.didRemove(leagueId: leagueId)
            dismiss()
        }
    }

    private func leave() async {
        await perform {
            try await LeaguesAPI.leave(id: leagueId)
            store.didRemove(leagueId: leagueId)
            dismiss()
        }
    }

    /// One owner/member action: success haptic, or a plain-words alert.
    private func perform(_ action: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        do {
            try await action()
            Haptics.success()
        } catch {
            Haptics.error()
            actionError = CompeteErrorText.message(for: error, in: .league)
        }
        isWorking = false
    }
}

// MARK: - Row

/// rank | avatar (with tier) | name over closed trades | return %. Your row sits
/// on a lifted background; the owner can long-press another row to remove it.
private struct LeagueStandingRow: View {
    let row: LeagueStanding
    let canRemove: Bool
    let onRemove: () -> Void

    static let rankWidth: CGFloat = 24
    static let textInset: CGFloat = rankWidth + Space.s12 + Metrics.avatar + Metrics.avatarGap

    private var subtitle: String {
        let trips = row.roundTrips ?? 0
        let tripsText = "\(trips) closed \(trips == 1 ? "trade" : "trades")"
        if !row.qualified { return "\(tripsText) · not ranked yet" }
        guard let tier = row.tier else { return tripsText }
        return "\(SeasonTier(id: tier).defaultName) · \(tripsText)"
    }

    var body: some View {
        HStack(spacing: Space.s12) {
            Text(row.rank.map { "\($0)" } ?? "–")
                .font(.rowSubvalue)
                .foregroundStyle((row.rank ?? 99) <= 3 ? Color.textPrimary : Color.textTertiary)
                .frame(width: Self.rankWidth, alignment: .leading)
            ListRow(title: row.isYou ? "You" : row.shownName, subtitle: subtitle) {
                ProfileAvatar(seed: row.avatarSeed ?? row.userId, name: row.shownName)
                    .overlay(alignment: .bottomTrailing) {
                        if let tier = row.tier, row.qualified {
                            TierBadge(tier: SeasonTier(id: tier), size: 18)
                                .background(Color.appBackground, in: Circle())
                                .offset(x: Space.s4, y: Space.s4)
                        }
                    }
            } trailing: {
                if row.qualified {
                    ChangeText(percent: row.returnPct, font: .rowValue)
                } else {
                    Text("—")
                        .font(.rowValue)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(.horizontal, row.isYou ? Space.s8 : 0)
        .background {
            if row.isYou {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(Color.appSurfaceElevated)
            }
        }
        .padding(.horizontal, row.isYou ? -Space.s8 : 0)
        .accessibilityElement(children: .combine)
        .contextMenu {
            if canRemove && !row.isYou {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove @\(row.username)", systemImage: "person.badge.minus")
                }
            }
        }
    }
}
