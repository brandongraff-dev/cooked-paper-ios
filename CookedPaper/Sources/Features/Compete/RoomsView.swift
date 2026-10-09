import SwiftUI

/// Compete → Live Rooms. Market event rooms (CPI day, a Fed decision) that anyone can
/// join, your rooms, and hosting one of your own (Beat the Streamer): a fixed window,
/// a fresh $10,000 for everyone, and a board that freezes at the end. Free to join.
struct RoomsView: View {
    @State private var response: RoomListResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var code = ""
    @State private var isJoining = false
    @State private var showsHost = false
    @State private var actionError: String?
    @State private var openedRoomId: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                header
                if isLoading && response == nil {
                    SkeletonBlock(height: 160, cornerRadius: Radius.card)
                } else if let response {
                    if hasNoRooms {
                        EmptyStateView(
                            symbol: "dot.radiowaves.left.and.right",
                            title: "No rooms right now",
                            action: EmptyStateAction(title: "Host a room", symbol: "video.badge.plus", identifier: "rooms.hostEmpty") {
                                showsHost = true
                            },
                            compact: true
                        )
                    } else {
                        if !response.live.isEmpty {
                            section("Live now", rooms: response.live)
                        }
                        if !response.upcoming.isEmpty {
                            section("Coming up", rooms: response.upcoming)
                        }
                        if !response.mine.isEmpty {
                            section("Your rooms", rooms: response.mine)
                        }
                    }
                } else {
                    EmptyStateView(
                        symbol: "dot.radiowaves.left.and.right",
                        title: "Couldn't load rooms",
                        detail: errorMessage ?? "Check your connection and try again."
                    ) {
                        Task { await load() }
                    }
                }
                joinByCode
                if !hasNoRooms {
                    Button {
                        showsHost = true
                    } label: {
                        Label("Host a room", systemImage: "video.badge.plus")
                    }
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("rooms.host")
                }
                CompeteLegalCaption()
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.s16)
        }
        .screenBackground()
        .reservesTabBarSpace()
        .navigationTitle("Live Rooms")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .autoRefresh(every: 20) { await load() }
        .refreshable { await load() }
        .navigationDestination(item: $openedRoomId) { id in
            RoomDetailView(roomId: id)
        }
        .sheet(isPresented: $showsHost) {
            HostRoomSheet { room in
                showsHost = false
                openedRoomId = room.id
                Task { await load() }
            }
        }
        .alert(
            "Couldn't join",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    /// Nothing live, nothing scheduled, nothing of yours: the empty state offers hosting.
    private var hasNoRooms: Bool {
        guard let response else { return false }
        return response.live.isEmpty && response.upcoming.isEmpty && response.mine.isEmpty
    }

    /// "2 live · 3 coming up" over the format as pills.
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            if let response, !(response.live.isEmpty && response.upcoming.isEmpty) {
                HStack(spacing: Space.s8) {
                    Text("\(response.live.count) live")
                        .foregroundStyle(response.live.isEmpty ? Color.textSecondary : Color.textPrimary)
                    Text("·").foregroundStyle(Color.textTertiary)
                    Text("\(response.upcoming.count) coming up")
                        .foregroundStyle(Color.textSecondary)
                }
                .font(.rowTitle)
            }
            InfoPillRow(pills: [
                (symbol: "dollarsign.circle.fill", text: "$10K each"),
                (symbol: "trophy.fill", text: "Best return wins"),
            ])
        }
    }

    private func section(_ title: String, rooms: [RoomSummary]) -> some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(title: title)
            VStack(spacing: 0) {
                ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                    NavigationLink(value: CompeteRoute.room(id: room.id)) {
                        RoomRow(room: room)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("rooms.row.\(index)")
                    if index < rooms.count - 1 { RowSeparator(leadingInset: 36 + Space.s12) }
                }
            }
            .glassList()
        }
    }

    private var joinByCode: some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(title: "Join with a code")
            HStack(spacing: Space.s8) {
                TextField("Room code", text: $code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .padding(.horizontal, Space.s16)
                    .frame(height: Metrics.buttonHeight)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .accessibilityIdentifier("rooms.code")
                Button {
                    Task { await join() }
                } label: {
                    if isJoining { ProgressView() } else { Text("Join") }
                }
                .buttonStyle(.accent)
                .frame(width: 96)
                .disabled(code.trimmingCharacters(in: .whitespaces).count < 4 || isJoining)
            }
        }
    }

    private func load() async {
        isLoading = response == nil
        do {
            response = try await RoomAPI.list()
            errorMessage = nil
        } catch {
            if response == nil { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    private func join() async {
        isJoining = true
        defer { isJoining = false }
        do {
            let room = try await RoomAPI.join(code: code.trimmingCharacters(in: .whitespaces))
            Haptics.success()
            code = ""
            openedRoomId = room.id
            await load()
        } catch {
            actionError = (error as? APIError)?.code == "not_found"
                ? "That room code doesn't work. Check it with the host."
                : CompeteErrorText.message(for: error)
        }
    }
}

/// Kicker (live / upcoming / finished) over the title and its clock | players.
struct RoomRow: View {
    let room: RoomSummary

    private var kicker: String {
        let state = room.isLive ? "Live" : (room.isFinished ? "Finished" : "Upcoming")
        return room.kind == "host" ? "\(state) · Hosted" : state
    }

    var body: some View {
        HStack(spacing: Space.s12) {
            Image(systemName: room.kind == "host" ? "video.fill" : "calendar")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(room.isLive ? Color.accent : Color.textSecondary)
                .frame(width: 36, height: 36)
                .metalSurface(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Kicker(text: kicker)
                Text(room.title)
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if room.isLive, let end = room.endDate {
                    CountdownText(end: end)
                } else if !room.isFinished, let start = room.startDate {
                    Text(start.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption13Digits)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: Space.s8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(room.participantCount)")
                    .font(.rowValue)
                    .foregroundStyle(Color.textPrimary)
                Text(room.joined ? "Joined" : "Players")
                    .font(.caption13)
                    .foregroundStyle(room.joined ? Color.accent : Color.textSecondary)
            }
        }
        .frame(minHeight: Metrics.rowHeight)
        .contentShape(Rectangle())
    }
}

/// Host a room: a title, when it starts and how long it runs. You join it at once and
/// get a code to give your viewers.
struct HostRoomSheet: View {
    let onCreated: (RoomDetail) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var startsInMinutes = 0
    @State private var durationMinutes = 60
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Room") {
                    TextField("Title, like “Friday night stream”", text: $title)
                        .accessibilityIdentifier("hostRoom.title")
                }
                Section("When") {
                    Picker("Starts", selection: $startsInMinutes) {
                        Text("Now").tag(0)
                        Text("In 15 minutes").tag(15)
                        Text("In 30 minutes").tag(30)
                        Text("In 1 hour").tag(60)
                    }
                    Picker("Length", selection: $durationMinutes) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                        Text("4 hours").tag(240)
                    }
                }
                Section {
                    Text("Viewers join with your code. The board shows who\u{2019}s beating you.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Color.negative)
                }
            }
            .navigationTitle("Host a room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Creating…" : "Create") { Task { await create() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).count < 3 || isCreating)
                }
            }
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        do {
            let room = try await RoomAPI.create(
                title: title.trimmingCharacters(in: .whitespaces),
                startsAt: Date().addingTimeInterval(TimeInterval(startsInMinutes * 60)),
                durationMinutes: durationMinutes
            )
            Haptics.success()
            onCreated(room)
        } catch {
            errorMessage = CompeteErrorText.message(for: error)
        }
    }
}
