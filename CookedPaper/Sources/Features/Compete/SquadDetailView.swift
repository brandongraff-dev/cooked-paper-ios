import SwiftUI

/// One squad: the shared portfolio, the members, open proposals to vote on, recent
/// decisions, and proposing a trade. A proposal runs the moment most of the squad votes
/// yes. Refreshes every few seconds while open.
struct SquadDetailView: View {
    let squadId: String

    @Environment(\.dismiss) private var dismiss
    @State private var squad: Squad?
    @State private var errorMessage: String?
    @State private var showsPicker = false
    @State private var pendingIntent: DuelTradeIntent?
    @State private var proposal: ProposalDraft?
    @State private var confirmsLeave = false
    @State private var actionError: String?
    @State private var votingId: String?

    /// Only used to drive the coin picker; a squad's holdings come in the squad itself.
    @State private var pickerPortfolio = DuelPortfolioStore(portfolioId: "", duelId: "", label: "SQUAD")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                if let squad {
                    header(squad)
                    proposals(squad)
                    holdings(squad)
                    members(squad)
                    if !squad.recent.isEmpty { recent(squad) }
                    Button(isOwner(squad) ? "Disband squad" : "Leave squad", role: .destructive) {
                        confirmsLeave = true
                    }
                    .frame(maxWidth: .infinity)
                    CompeteLegalCaption()
                } else if let errorMessage {
                    EmptyStateView(symbol: "person.3", title: "Couldn't open this squad", detail: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    SkeletonBlock(height: 260, cornerRadius: Radius.card)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.s16)
        }
        .background(Color.appBackground)
        .reservesTabBarSpace()
        .navigationTitle(squad?.name ?? "Squad")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .autoRefresh(every: 5) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showsPicker, onDismiss: {
            if let intent = pendingIntent {
                pendingIntent = nil
                proposal = ProposalDraft(side: "buy", mint: intent.mint, symbol: intent.symbol)
            }
        }) {
            DuelCoinPicker(portfolio: pickerPortfolio) { intent in
                pendingIntent = intent
            }
        }
        .sheet(item: $proposal) { draft in
            ProposeSquadTradeSheet(draft: draft, cashUsd: squad?.cashUsd) { body in
                do {
                    squad = try await SquadAPI.propose(squadId: squadId, body: body)
                    Haptics.success()
                    proposal = nil
                } catch {
                    actionError = CompeteErrorText.message(for: error)
                }
            }
        }
        .confirmationDialog(
            squad.map { isOwner($0) ? "Disband this squad?" : "Leave this squad?" } ?? "",
            isPresented: $confirmsLeave,
            titleVisibility: .visible
        ) {
            Button(squad.map { isOwner($0) ? "Disband" : "Leave" } ?? "Leave", role: .destructive) {
                Task { await leave() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(squad.map { isOwner($0) ? "The squad and its shared portfolio are deleted for everyone." : "You can rejoin with the code while there's room." } ?? "")
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

    private func isOwner(_ squad: Squad) -> Bool {
        squad.members.first(where: { $0.isOwner })?.username == SessionStore.shared.username
    }

    // MARK: - Sections

    private func header(_ squad: Squad) -> some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            HStack(alignment: .firstTextBaseline) {
                Text(squad.equityUsd.map { PriceFormat.usd($0) } ?? "—")
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                ChangeText(percent: squad.returnPct, font: .rowValue)
            }
            Text("Shared by \(squad.members.count) of \(squad.maxMembers) · every trade needs a majority")
                .font(.rowSubtitle)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: Space.s8) {
                Button {
                    showsPicker = true
                } label: {
                    Label("Propose a trade", systemImage: "hand.raised")
                }
                .buttonStyle(.accent)
                .accessibilityIdentifier("squad.propose")
                ShareLink(item: "Join my trading squad on Cooked. Squad code: \(squad.inviteCode)") {
                    Image(systemName: "person.badge.plus")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.secondary)
                .frame(width: 64)
                .accessibilityLabel("Invite to the squad")
            }
        }
    }

    @ViewBuilder
    private func proposals(_ squad: Squad) -> some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(title: "Vote")
            if squad.open.isEmpty {
                Text("No trades waiting for a vote.")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(squad.open) { item in
                    VStack(alignment: .leading, spacing: Space.s8) {
                        HStack {
                            Text(item.summary)
                                .font(.rowTitle)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            if let end = item.expiryDate { CountdownText(end: end) }
                        }
                        Text("@\(item.proposer) · \(item.yes) yes, \(item.no) no · needs \(item.needed)")
                            .font(.rowSubtitle)
                            .foregroundStyle(Color.textSecondary)
                        if let mine = item.myVote {
                            Text("You voted \(mine)")
                                .font(.caption13.weight(.semibold))
                                .foregroundStyle(mine == "yes" ? Color.positive : Color.negative)
                        } else {
                            HStack(spacing: Space.s8) {
                                Button("Yes") { Task { await vote(item, yes: true) } }
                                    .buttonStyle(.accent)
                                Button("No") { Task { await vote(item, yes: false) } }
                                    .buttonStyle(.secondary)
                            }
                            .disabled(votingId != nil)
                        }
                    }
                    .padding(Space.s16)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
            }
        }
    }

    private func holdings(_ squad: Squad) -> some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(title: "Shared portfolio", caption: squad.cashUsd.map { "\(PriceFormat.usd($0)) cash" })
            if squad.positions.isEmpty {
                Text("All cash. Propose the first trade.")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(squad.positions) { position in
                        Button {
                            proposal = ProposalDraft(side: "sell", mint: position.tokenMint, symbol: position.symbol ?? "token")
                        } label: {
                            ListRow(title: position.symbol ?? "Unknown", subtitle: "Tap to propose a sell") {
                                TokenAvatar(mint: position.tokenMint, symbol: position.symbol)
                            } trailing: {
                                Text(PriceFormat.usd(position.valueUsd))
                                    .font(.rowValue)
                                    .foregroundStyle(Color.textPrimary)
                                ChangeText(percent: position.unrealizedReturnPct)
                            }
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
        }
    }

    private func members(_ squad: Squad) -> some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(title: "Members", caption: "Code: \(squad.inviteCode)")
            ForEach(squad.members, id: \.username) { member in
                HStack {
                    MonogramAvatar(text: member.username)
                    Text("@\(member.username)")
                        .font(.rowTitle)
                        .foregroundStyle(Color.textPrimary)
                    if member.isOwner {
                        Text("OWNER")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accent)
                    }
                    Spacer()
                }
            }
        }
    }

    private func recent(_ squad: Squad) -> some View {
        VStack(alignment: .leading, spacing: Space.headerGap) {
            SectionHeader(title: "Recent")
            ForEach(squad.recent) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.summary)
                            .font(.rowTitle)
                            .foregroundStyle(Color.textPrimary)
                        Text(item.failure ?? "@\(item.proposer) · \(item.yes) yes, \(item.no) no")
                            .font(.rowSubtitle)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(item.status.capitalized)
                        .font(.caption13.weight(.semibold))
                        .foregroundStyle(item.status == "executed" ? Color.positive : Color.textSecondary)
                }
                .frame(minHeight: 52)
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        do {
            squad = try await SquadAPI.get(id: squadId)
            errorMessage = nil
        } catch {
            if squad == nil { errorMessage = error.localizedDescription }
        }
    }

    private func vote(_ item: SquadProposal, yes: Bool) async {
        votingId = item.id
        defer { votingId = nil }
        Haptics.commit()
        do {
            squad = try await SquadAPI.vote(squadId: squadId, proposalId: item.id, yes: yes)
        } catch {
            actionError = CompeteErrorText.message(for: error)
            await load()
        }
    }

    private func leave() async {
        do {
            try await SquadAPI.leave(id: squadId)
            dismiss()
        } catch {
            actionError = CompeteErrorText.message(for: error)
        }
    }
}

struct ProposalDraft: Identifiable {
    let id = UUID()
    let side: String
    let mint: String
    let symbol: String
}

/// The amount for a squad proposal: dollars for a buy, a percentage for a sell.
struct ProposeSquadTradeSheet: View {
    let draft: ProposalDraft
    let cashUsd: Decimal?
    let onSubmit: (ProposeSquadTradeBody) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var percent = 100
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                if draft.side == "buy" {
                    Section {
                        TextField("Amount in dollars", text: $amount)
                            .keyboardType(.decimalPad)
                        if let cashUsd {
                            Text("Squad cash: \(PriceFormat.usd(cashUsd))")
                                .font(.footnote)
                                .foregroundStyle(Color.textSecondary)
                        }
                    } header: {
                        Text("Buy \(draft.symbol)")
                    }
                } else {
                    Section("Sell \(draft.symbol)") {
                        Picker("How much", selection: $percent) {
                            ForEach([25, 50, 75, 100], id: \.self) { Text("\($0)%").tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section {
                    Text("Your yes counts now. It runs when most of the squad agrees, within 30 minutes.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .navigationTitle("Propose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Sending…" : "Propose") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || (draft.side == "buy" && (Decimal(string: amount) ?? 0) <= 0))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        var body = ProposeSquadTradeBody(side: draft.side, tokenMint: draft.mint)
        if draft.side == "buy" {
            body.notionalUsd = amount
        } else {
            body.sellPercent = percent
        }
        await onSubmit(body)
    }
}
