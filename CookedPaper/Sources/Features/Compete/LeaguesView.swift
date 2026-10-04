import SwiftUI
import UIKit

/// Compete → Leagues: the private leaderboards you're in (name, members, your
/// rank), with Create and Join. A league ranks its members on the same number as
/// the season — each one's main-portfolio return this month.
struct LeaguesView: View {
    private let store = LeaguesStore.shared

    @State private var showsCreate = false
    @State private var showsJoin = false
    /// Set by a create/join sheet as it closes; opened once it's gone.
    @State private var pendingLeague: League?
    /// The id of a just-created or just-joined league to push.
    @State private var openedLeagueId: String?

    var body: some View {
        ScrollView {
            Group {
                if store.isLoading && store.leagues == nil {
                    skeleton
                } else if store.isUnavailable {
                    EmptyStateView(
                        symbol: "person.3",
                        title: "Leagues are almost here",
                        detail: "Private leaderboards for you and your friends are on their way. Check back soon."
                    )
                } else if let leagues = store.leagues {
                    content(leagues)
                } else {
                    EmptyStateView(
                        symbol: "wifi.slash",
                        title: "Couldn't load your leagues",
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
        .background(Color.appBackground)
        .refreshable { await store.load() }
        .reservesTabBarSpace()
        .task { await store.load() }
        .autoRefresh(every: 60) { await store.refreshSilently() }
        .sheet(isPresented: $showsCreate, onDismiss: openPending) {
            CreateLeagueSheet { league in pendingLeague = league }
        }
        .sheet(isPresented: $showsJoin, onDismiss: openPending) {
            JoinLeagueSheet(initialCode: nil) { league in pendingLeague = league }
        }
        .navigationDestination(item: $openedLeagueId) { id in
            LeagueDetailView(leagueId: id, initial: store.leagues?.first { $0.id == id })
        }
    }

    private func openPending() {
        guard let league = pendingLeague else { return }
        pendingLeague = nil
        openedLeagueId = league.id
    }

    private func content(_ leagues: [League]) -> some View {
        VStack(alignment: .leading, spacing: Space.section) {
            if leagues.isEmpty {
                VStack(spacing: Space.s16) {
                    EmptyStateView(
                        symbol: "person.3",
                        title: "No leagues yet",
                        detail: "Start a private leaderboard for your group chat, or join one with an invite code. Free, no stakes."
                    )
                    actionButtons
                }
            } else {
                actionButtons
                VStack(alignment: .leading, spacing: Space.headerGap) {
                    SectionHeader(title: "Your leagues", caption: "Simulated")
                    VStack(spacing: 0) {
                        ForEach(Array(leagues.enumerated()), id: \.element.id) { index, league in
                            NavigationLink(value: CompeteRoute.league(id: league.id)) {
                                LeagueRow(league: league)
                            }
                            .buttonStyle(.pressable)
                            .accessibilityIdentifier("leagues.row.\(index)")
                            if index < leagues.count - 1 { RowSeparator() }
                        }
                    }
                }
            }
            CompeteLegalCaption()
        }
        .padding(.horizontal, Space.margin)
    }

    private var actionButtons: some View {
        HStack(spacing: Space.s12) {
            Button {
                Haptics.tap()
                showsCreate = true
            } label: {
                Label("Create a league", systemImage: "plus")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("leagues.create")
            Button {
                Haptics.tap()
                showsJoin = true
            } label: {
                Label("Join with code", systemImage: "number")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("leagues.join")
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            SkeletonBlock(height: Metrics.buttonHeight, cornerRadius: Metrics.buttonHeight / 2)
                .padding(.bottom, Space.s16)
            SkeletonBlock(width: 120, height: 18)
            ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
        }
        .padding(.horizontal, Space.margin)
    }
}

/// Monogram | name over members | your rank.
private struct LeagueRow: View {
    let league: League

    var body: some View {
        ListRow(
            title: league.name,
            subtitle: "\(league.memberCount) \(league.memberCount == 1 ? "member" : "members")\(league.isOwner ? " · Owner" : "")"
        ) {
            LeagueAvatar(name: league.name, seed: league.id)
        } trailing: {
            if let rank = league.yourRank {
                Text("#\(rank)")
                    .font(.rowValue)
                    .foregroundStyle(Color.textPrimary)
                Text("Your rank")
                    .font(.rowSubvalue)
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text("Unranked")
                    .font(.rowSubvalue)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A league's badge: the same seeded gradient people get, keyed on the league id.
struct LeagueAvatar: View {
    let name: String
    let seed: String
    var size: CGFloat = Metrics.avatar

    var body: some View {
        ProfileAvatar(seed: seed, name: name, size: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

// MARK: - Create

/// Name a league; on success the sheet closes and the caller opens it.
struct CreateLeagueSheet: View {
    let onCreated: (League) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var canSubmit: Bool { !isSubmitting && LeagueRules.isValidName(name) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.s24) {
                VStack(alignment: .leading, spacing: Space.s8) {
                    Text("New league")
                        .font(.appLargeTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("A private leaderboard for your friends, ranked on this season's paper returns. Up to 50 members.")
                        .font(.rowSubtitle)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: Space.s8) {
                    HStack {
                        Text("Name")
                            .font(.caption13)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("\(LeagueRules.sanitizedName(name).count)/\(LeagueRules.maxNameLength)")
                            .font(.caption13Digits)
                            .foregroundStyle(LeagueRules.sanitizedName(name).count > LeagueRules.maxNameLength ? Color.negative : Color.textTertiary)
                    }
                    TextField("Group chat degens", text: $name)
                        .font(.rowTitle)
                        .foregroundStyle(Color.textPrimary)
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit { Task { await submit() } }
                        .onChange(of: name) { _, _ in errorMessage = nil }
                        .padding(.horizontal, Space.s16)
                        .frame(height: Metrics.buttonHeight)
                        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                        .accessibilityIdentifier("createLeague.name")
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption13)
                        .foregroundStyle(Color.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().tint(Color.inverseText)
                    } else {
                        Text("Create league")
                    }
                }
                .buttonStyle(.primary)
                .disabled(!canSubmit)
                .accessibilityIdentifier("createLeague.submit")
                CompeteLegalCaption()
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s8)
            .padding(.bottom, Space.s8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.appSurfaceElevated)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(Color.appSurfaceElevated)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSubmitting)
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            let league = try await LeaguesAPI.create(name: LeagueRules.sanitizedName(name))
            Haptics.success()
            LeaguesStore.shared.didChange(league)
            onCreated(league)
            dismiss()
        } catch {
            Haptics.error()
            errorMessage = CompeteErrorText.message(for: error, in: .league)
        }
        isSubmitting = false
    }
}

// MARK: - Join

/// Enter or paste an invite code (or a whole invite link). From the Leagues list
/// the sheet closes on success and the caller opens the league (`onJoined`); from
/// a deep link (`onJoined` nil) the code is prefilled and the sheet becomes the
/// league's screen.
struct JoinLeagueSheet: View {
    let initialCode: String?
    var onJoined: ((League) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var joined: League?

    private var cleanCode: String { LeagueRules.inviteCode(from: code) }

    var body: some View {
        NavigationStack {
            Group {
                if let joined {
                    LeagueDetailView(leagueId: joined.id, initial: joined)
                } else {
                    form
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(joined == nil ? "Cancel" : "Done") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appSurfaceElevated)
        .interactiveDismissDisabled(isJoining)
        .onAppear {
            if code.isEmpty, let initialCode { code = initialCode }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.s24) {
            VStack(alignment: .leading, spacing: Space.s8) {
                Text(initialCode == nil ? "Join a league" : "You're invited")
                    .font(.appLargeTitle)
                    .foregroundStyle(Color.textPrimary)
                Text("Join a friend's private leaderboard. You're ranked on this season's paper return — no entry, no stakes.")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Space.s8) {
                Text("Invite code")
                    .font(.caption13)
                    .foregroundStyle(Color.textSecondary)
                HStack(spacing: Space.s8) {
                    TextField("Q7m2Lx9a", text: $code)
                        .font(.rowTitle.monospaced())
                        .foregroundStyle(Color.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.join)
                        .onSubmit { Task { await join() } }
                        .onChange(of: code) { _, _ in errorMessage = nil }
                        .accessibilityIdentifier("joinLeague.code")
                    Button("Paste") {
                        if let pasted = UIPasteboard.general.string {
                            Haptics.tap()
                            code = LeagueRules.inviteCode(from: pasted)
                        }
                    }
                    .buttonStyle(.compact)
                }
                .padding(.leading, Space.s16)
                .padding(.trailing, Space.s12)
                .frame(height: Metrics.buttonHeight)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption13)
                    .foregroundStyle(Color.negative)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("joinLeague.error")
            }
            Spacer(minLength: 0)
            Button {
                Task { await join() }
            } label: {
                if isJoining {
                    ProgressView().tint(Color.inverseText)
                } else {
                    Text("Join league")
                }
            }
            .buttonStyle(.primary)
            .disabled(cleanCode.isEmpty || isJoining)
            .accessibilityIdentifier("joinLeague.join")
            CompeteLegalCaption()
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s8)
        .padding(.bottom, Space.s8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appSurfaceElevated)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func join() async {
        guard !cleanCode.isEmpty, !isJoining else { return }
        isJoining = true
        errorMessage = nil
        do {
            let league = try await LeaguesAPI.join(inviteCode: cleanCode)
            Haptics.success()
            LeaguesStore.shared.didChange(league)
            if let onJoined {
                onJoined(league)
                dismiss()
            } else {
                withAnimation(Motion.standard) { joined = league }
            }
        } catch {
            Haptics.error()
            errorMessage = CompeteErrorText.message(for: error, in: .league)
        }
        isJoining = false
    }
}
