import SwiftUI

/// Compete → Squads: your squads, starting one, and joining one by code. A squad is 3
/// to 5 friends sharing one paper portfolio where every trade is a vote.
struct SquadsView: View {
    private enum Field: Hashable { case name, code }

    @State private var squads: [SquadSummary]?
    @State private var errorMessage: String?
    @State private var newName = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var actionError: String?
    @State private var openedSquadId: String?
    @FocusState private var focusedField: Field?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                VStack(alignment: .leading, spacing: Space.s12) {
                    if let squads, !squads.isEmpty {
                        // "2 squads · 1 trade to vote on", like Crash Replay's summary line.
                        HStack(spacing: Space.s8) {
                            Text(squads.count == 1 ? "1 squad" : "\(squads.count) squads")
                                .foregroundStyle(Color.textPrimary)
                            if let waiting = votesWaiting(squads) {
                                Text("·").foregroundStyle(Color.textTertiary)
                                Text(waiting).foregroundStyle(Color.accent)
                            }
                        }
                        .font(.rowTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    }
                    InfoPillRow(pills: [
                        (symbol: "person.3.fill", text: "$10K for 3–5 friends"),
                        (symbol: "hand.raised.fill", text: "Trade by vote"),
                    ])
                }

                if let squads {
                    if squads.isEmpty {
                        EmptyStateView(
                            symbol: "person.3.fill",
                            title: "No squad yet",
                            action: EmptyStateAction(title: "Start a squad", symbol: "plus", identifier: "squads.start") {
                                focusedField = .name
                            },
                            compact: true
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(squads.enumerated()), id: \.element.id) { index, squad in
                                NavigationLink(value: CompeteRoute.squad(id: squad.id)) {
                                    SquadRow(squad: squad)
                                }
                                .buttonStyle(.pressable)
                                .accessibilityIdentifier("squads.row.\(index)")
                                if index < squads.count - 1 { RowSeparator() }
                            }
                        }
                        .glassList()
                    }
                } else if let errorMessage {
                    EmptyStateView(symbol: "wifi.slash", title: "Couldn't load squads", detail: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    SkeletonBlock(height: 100, cornerRadius: Radius.card)
                }

                field(title: "Start a squad", placeholder: "Squad name", text: $newName, focus: .name, action: "Start") {
                    await create()
                }
                field(title: "Join with a code", placeholder: "Squad code", text: $code, focus: .code, action: "Join") {
                    await join()
                }
                CompeteLegalCaption()
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.s16)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .reservesTabBarSpace()
        .navigationTitle("Squads")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable { await load() }
        .navigationDestination(item: $openedSquadId) { id in
            SquadDetailView(squadId: id)
        }
        .alert(
            "Couldn't do that",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    /// "2 trades to vote on", or nil when nothing is waiting.
    private func votesWaiting(_ squads: [SquadSummary]) -> String? {
        let open = squads.reduce(0) { $0 + $1.openProposals }
        guard open > 0 else { return nil }
        return open == 1 ? "1 trade to vote on" : "\(open) trades to vote on"
    }

    private func field(
        title: String,
        placeholder: String,
        text: Binding<String>,
        focus: Field,
        action: String,
        run: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(title: title)
            HStack(spacing: Space.s8) {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: focus)
                    .padding(.horizontal, Space.s16)
                    .frame(height: Metrics.buttonHeight)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                Button(action) { Task { await run() } }
                    .buttonStyle(.accent)
                    .frame(width: 96)
                    .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).count < 2 || isWorking)
            }
        }
    }

    private func load() async {
        do {
            squads = try await SquadAPI.list()
            errorMessage = nil
        } catch {
            if squads == nil { errorMessage = error.localizedDescription }
        }
    }

    private func create() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let squad = try await SquadAPI.create(name: newName.trimmingCharacters(in: .whitespaces))
            newName = ""
            Haptics.success()
            openedSquadId = squad.id
            await load()
        } catch {
            actionError = CompeteErrorText.message(for: error)
        }
    }

    private func join() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let squad = try await SquadAPI.join(code: code.trimmingCharacters(in: .whitespaces))
            code = ""
            Haptics.success()
            openedSquadId = squad.id
            await load()
        } catch {
            actionError = (error as? APIError)?.code == "not_found"
                ? "That squad code doesn't work."
                : CompeteErrorText.message(for: error)
        }
    }
}

/// Squad tile | kicker (members) over the name | votes waiting.
private struct SquadRow: View {
    let squad: SquadSummary

    var body: some View {
        HStack(spacing: Metrics.avatarGap) {
            IconTile(symbol: "person.3.fill", color: .tileIndigo, size: Metrics.avatar)
            VStack(alignment: .leading, spacing: 2) {
                Kicker(text: "\(squad.memberCount) members")
                Text(squad.name)
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s8)
            if squad.openProposals > 0 {
                Text("\(squad.openProposals) to vote")
                    .font(.caption13.weight(.semibold))
                    .foregroundStyle(Color.accentInk)
                    .padding(.horizontal, Space.s8)
                    .padding(.vertical, 3)
                    .background(Color.accent, in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption13.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Metrics.rowHeight)
        .contentShape(Rectangle())
    }
}
