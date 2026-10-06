import SwiftUI

/// One room: its clock, the board (live while it runs, frozen at the end), how many
/// are beating the host in a streamer's room, and your room portfolio with Trade.
/// Refreshes every few seconds while live.
struct RoomDetailView: View {
    let roomId: String

    @State private var room: RoomDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var portfolio: DuelPortfolioStore?
    @State private var isJoining = false
    @State private var actionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                if let room {
                    header(room)
                    if room.kind == "host", let beating = room.beatingHost, let host = room.host {
                        beatTheHost(beating: beating, host: host.username, room: room)
                    }
                    if !room.joined && !room.isFinished {
                        Button {
                            Task { await join() }
                        } label: {
                            if isJoining { ProgressView() } else { Text("Join with $10,000") }
                        }
                        .buttonStyle(.accent)
                        .accessibilityIdentifier("room.join")
                    }
                    if let me = room.me {
                        myStanding(me, room: room)
                    }
                    if let portfolio {
                        ContestPortfolioSection(
                            title: "Your room portfolio",
                            portfolio: portfolio,
                            canTrade: room.isLive,
                            emptyDetail: room.isLive ? "Tap Trade to start." : "Trading opens when the room starts.",
                            onTraded: { await load() }
                        )
                    }
                    standings(room)
                    Text(room.disclaimer ?? "Paper room: simulated prices, no stakes, no prizes.")
                        .font(.caption13)
                        .foregroundStyle(Color.textTertiary)
                } else if isLoading {
                    SkeletonBlock(height: 240, cornerRadius: Radius.card)
                } else {
                    EmptyStateView(
                        symbol: "dot.radiowaves.left.and.right",
                        title: "Couldn't open this room",
                        detail: errorMessage ?? "It may be private to its players."
                    ) {
                        Task { await load() }
                    }
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.s16)
        }
        .background(Color.appBackground)
        .reservesTabBarSpace()
        .navigationTitle(room?.title ?? "Room")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .autoRefresh(every: 5) { await load() }
        .refreshable { await load() }
        .alert(
            "Couldn't join",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private func header(_ room: RoomDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            HStack(spacing: Space.s8) {
                if room.isLive {
                    Circle().fill(Color.positive).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text("Live")
                        .font(.caption13)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    if let end = room.endDate { CountdownText(end: end, font: .rowValue, color: .textPrimary) }
                } else if room.isFinished {
                    Text("Finished")
                        .font(.caption13)
                        .foregroundStyle(Color.textSecondary)
                } else if let start = room.startDate {
                    Text("Starts in")
                        .font(.caption13)
                        .foregroundStyle(Color.textSecondary)
                    CountdownText(end: start, suffix: "", font: .rowValue, color: .textPrimary)
                }
            }
            Text("\(room.participantCount) players · $10,000 each")
                .font(.rowSubtitle)
                .foregroundStyle(Color.textSecondary)
            if let code = room.inviteCode {
                HStack {
                    Text("Code: \(code)")
                        .font(.rowTitle.monospaced())
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                    Spacer()
                    ShareLink(item: "Join my paper trading room on Cooked and try to beat me. Room code: \(code)") {
                        Label("Invite", systemImage: "square.and.arrow.up")
                    }
                }
                .padding(Space.s12)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            }
        }
    }

    private func beatTheHost(beating: Int, host: String, room: RoomDetail) -> some View {
        let others = max(room.sampleSize - 1, 0)
        return VStack(alignment: .leading, spacing: Space.s4) {
            Text("Beat the Streamer")
                .font(.sectionHeader)
                .foregroundStyle(Color.textPrimary)
            Text("\(beating) of \(others) players are beating @\(host)")
                .font(.rowTitle)
                .foregroundStyle(Color.textPrimary)
        }
        .padding(Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func myStanding(_ me: RoomDetail.Me, room: RoomDetail) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(me.rank.map { "You're #\($0) of \(room.sampleSize)" } ?? "Not ranked yet")
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                Text(room.isFinished ? "Final" : "Live")
                    .font(.caption13)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            ChangeText(percent: me.returnPct, font: .rowValue)
        }
        .padding(Space.s16)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func standings(_ room: RoomDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(title: room.isFinished ? "Final board" : "Board")
            if room.standings.isEmpty {
                Text("No one has joined yet.")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(room.standings) { row in
                        HStack(spacing: Space.s12) {
                            Text("\(row.rank)")
                                .font(.rowSubvalue)
                                .foregroundStyle(row.rank <= 3 ? Color.textPrimary : Color.textTertiary)
                                .frame(width: 28, alignment: .leading)
                            Text(row.isYou ? "You" : "@\(row.username)")
                                .font(.rowTitle)
                                .foregroundStyle(Color.textPrimary)
                            if row.isHost {
                                Text("HOST")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.accent)
                            }
                            Spacer()
                            ChangeText(percent: row.returnPct, font: .rowValue)
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = room == nil
        do {
            let fresh = try await RoomAPI.get(id: roomId)
            room = fresh
            errorMessage = nil
            if let id = fresh.me?.portfolioId {
                if portfolio?.portfolioId != id {
                    portfolio = DuelPortfolioStore(portfolioId: id, duelId: fresh.id, label: "ROOM")
                }
                await portfolio?.refresh()
            }
        } catch {
            if room == nil { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    private func join() async {
        isJoining = true
        defer { isJoining = false }
        do {
            room = try await RoomAPI.join(id: roomId)
            Haptics.success()
            await load()
        } catch {
            actionError = CompeteErrorText.message(for: error)
        }
    }
}
