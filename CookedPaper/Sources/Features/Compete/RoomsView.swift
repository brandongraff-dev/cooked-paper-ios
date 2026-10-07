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
                    section("Live now", rooms: response.live, empty: "No event room is live right now.")
                    section("Coming up", rooms: response.upcoming, empty: "Nothing scheduled yet. Check back before the next big market event.")
                    if !response.mine.isEmpty {
                        section("Your rooms", rooms: response.mine, empty: "")
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
                Button {
                    showsHost = true
                } label: {
                    Label("Host a room", systemImage: "video.badge.plus")
                }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("rooms.host")
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

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Text("Same $10K, same window. Best return wins.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func section(_ title: String, rooms: [RoomSummary], empty: String) -> some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(title: title)
            if rooms.isEmpty {
                Text(empty)
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                        NavigationLink(value: CompeteRoute.room(id: room.id)) {
                            RoomRow(room: room)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityIdentifier("rooms.row.\(index)")
                        if index < rooms.count - 1 { RowSeparator() }
                    }
                }
                .glassList()
            }
        }
    }

    private var joinByCode: some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(title: "Join a streamer's room")
            HStack(spacing: Space.s8) {
                TextField("Room code", text: $code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .padding(Space.s12)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
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

struct RoomRow: View {
    let room: RoomSummary

    var body: some View {
        HStack(spacing: Space.s12) {
            Image(systemName: room.kind == "host" ? "video.fill" : "calendar")
                .foregroundStyle(room.isLive ? Color.positive : Color.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(room.title)
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Group {
                    if room.isLive, let end = room.endDate {
                        CountdownText(end: end)
                    } else if room.isFinished {
                        Text("Finished")
                    } else if let start = room.startDate {
                        Text("Starts \(start.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                .font(.rowSubtitle)
                .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(room.participantCount)")
                    .font(.rowValue)
                    .foregroundStyle(Color.textPrimary)
                Text(room.joined ? "joined" : "players")
                    .font(.caption13)
                    .foregroundStyle(room.joined ? Color.positive : Color.textSecondary)
            }
        }
        .frame(minHeight: 60)
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
