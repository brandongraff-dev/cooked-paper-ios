import SwiftUI

/// Compete → Squads: your squads, starting one, and joining one by code. A squad is 3
/// to 5 friends sharing one paper portfolio where every trade is a vote.
struct SquadsView: View {
    @State private var squads: [SquadSummary]?
    @State private var errorMessage: String?
    @State private var newName = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var actionError: String?
    @State private var openedSquadId: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                VStack(alignment: .leading, spacing: Space.s8) {
                    Text("Trade as a squad")
                        .font(.appLargeTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("3 to 5 friends, one $10,000 paper portfolio. Anyone proposes a trade; it runs when most of the squad votes yes.")
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let squads {
                    if !squads.isEmpty {
                        VStack(alignment: .leading, spacing: Space.headerGap) {
                            SectionHeader(title: "Your squads")
                            VStack(spacing: 0) {
                                ForEach(Array(squads.enumerated()), id: \.element.id) { index, squad in
                                    NavigationLink(value: CompeteRoute.squad(id: squad.id)) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(squad.name)
                                                    .font(.rowTitle)
                                                    .foregroundStyle(Color.textPrimary)
                                                Text("\(squad.memberCount) members")
                                                    .font(.rowSubtitle)
                                                    .foregroundStyle(Color.textSecondary)
                                            }
                                            Spacer()
                                            if squad.openProposals > 0 {
                                                Text("\(squad.openProposals) to vote")
                                                    .font(.caption13.weight(.semibold))
                                                    .foregroundStyle(Color.accent)
                                            }
                                            Image(systemName: "chevron.right")
                                                .foregroundStyle(Color.textTertiary)
                                        }
                                        .frame(minHeight: 56)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.pressable)
                                    .accessibilityIdentifier("squads.row.\(index)")
                                    if index < squads.count - 1 { RowSeparator() }
                                }
                            }
                        }
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.rowSubtitle)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    SkeletonBlock(height: 100, cornerRadius: Radius.card)
                }

                field(title: "Start a squad", placeholder: "Squad name", text: $newName, action: "Start") {
                    await create()
                }
                field(title: "Join with a code", placeholder: "Squad code", text: $code, action: "Join") {
                    await join()
                }
                CompeteLegalCaption()
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.s16)
        }
        .background(Color.appBackground)
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

    private func field(
        title: String,
        placeholder: String,
        text: Binding<String>,
        action: String,
        run: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(title: title)
            HStack(spacing: Space.s8) {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(Space.s12)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
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
