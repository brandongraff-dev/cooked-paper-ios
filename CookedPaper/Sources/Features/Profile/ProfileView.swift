import SwiftUI
import UIKit

/// Settings → Profile: who this account is to everyone else (avatar, display
/// name, @handle), when it joined, how it signs in, and its referral code. Shows
/// what `SessionStore` already knows straight away, then refreshes from
/// `GET /auth/me` for the fields only the server has (join date, referral code).
struct ProfileView: View {
    private let session = SessionStore.shared
    private let achievements = AchievementCenter.shared

    @State private var user: PublicUser?
    @State private var showEdit = false
    @State private var didCopyCode = false

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Button {
                    Haptics.tap()
                    showEdit = true
                } label: {
                    ProfileRow(symbol: "pencil", title: "Edit profile", trailingSymbol: "chevron.right")
                }
                .accessibilityIdentifier("profile.edit")
            }
            .listRowBackground(Color.appSurface)

            // Hidden entirely on a server without achievements (404).
            if !achievements.isUnavailable {
                Section("Achievements") {
                    NavigationLink {
                        AchievementsView()
                    } label: {
                        AchievementsSummaryRow(center: achievements)
                    }
                    .accessibilityIdentifier("profile.achievements")
                }
                .listRowBackground(Color.appSurface)
            }

            Section("Account") {
                ProfileRow(symbol: "at", title: "Username", detail: session.username.map { "@\($0)" })
                if let method = signInMethodLabel {
                    ProfileRow(symbol: method.symbol, title: "Signed in with", detail: method.name)
                }
                if let joined = joinedLabel {
                    ProfileRow(symbol: "calendar", title: "Joined", detail: joined)
                }
            }
            .listRowBackground(Color.appSurface)

            if let code = user?.referralCode, !code.isEmpty {
                Section {
                    HStack(spacing: Space.s12) {
                        Image(systemName: "gift")
                            .font(.body)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Space.s4) {
                            Text("Referral code")
                                .font(.rowSubtitle)
                                .foregroundStyle(Color.textSecondary)
                            Text(code)
                                .font(.rowValue)
                                .foregroundStyle(Color.textPrimary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = code
                            Haptics.success()
                            withAnimation(Motion.standard) { didCopyCode = true }
                        } label: {
                            Image(systemName: didCopyCode ? "checkmark" : "doc.on.doc")
                                .font(.body)
                                .foregroundStyle(didCopyCode ? Color.positive : Color.textPrimary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(didCopyCode ? "Copied" : "Copy referral code")
                        ShareLink(item: "Trade memecoins with paper money on Cooked Paper. Use my code \(code) when you join.") {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body)
                                .foregroundStyle(Color.textPrimary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Share referral code")
                    }
                    .padding(.vertical, Space.s4)
                } header: {
                    Text("Invite friends")
                }
                .listRowBackground(Color.appSurface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .reservesTabBarSpace()
        .tint(Color.textPrimary)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .task { await achievements.load() }
        .refreshable { await refresh() }
        .sheet(isPresented: $showEdit) {
            EditProfileView()
        }
    }

    private var header: some View {
        VStack(spacing: Space.s12) {
            ProfileAvatar(seed: avatarSeed, name: displayTitle, size: 88)
            VStack(spacing: Space.s4) {
                Text(displayTitle)
                    .font(.sectionHeader)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                if session.displayName != nil, let username = session.username {
                    Text("@\(username)")
                        .font(.rowSubtitle)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s16)
        .accessibilityElement(children: .combine)
    }

    private var displayTitle: String {
        session.displayName ?? session.username.map { "@\($0)" } ?? "Paper account"
    }

    private var avatarSeed: String {
        session.avatarSeed ?? session.userId ?? session.username ?? "cooked"
    }

    private var signInMethodLabel: (name: String, symbol: String)? {
        switch session.method {
        case "apple": return (name: "Apple", symbol: "apple.logo")
        case "google": return (name: "Google", symbol: "g.circle")
        default: return nil
        }
    }

    /// "September 2026", from the server's ISO8601 `createdAt`.
    private var joinedLabel: String? {
        guard let createdAt = user?.createdAt,
              let date = Self.isoFractional.date(from: createdAt) ?? Self.isoPlain.date(from: createdAt)
        else { return nil }
        return date.formatted(.dateTime.month(.wide).year())
    }

    private func refresh() async {
        guard let fresh = try? await AuthAPI.me() else { return }
        session.apply(fresh)
        user = fresh
    }

    private static let isoPlain = ISO8601DateFormatter()
    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - Edit

/// Change the handle and display name, with the same live checks as first-run
/// setup. Saves through `PATCH /auth/me` and closes; errors stay inline.
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var form: ProfileForm

    init() {
        let session = SessionStore.shared
        _form = State(initialValue: ProfileForm(username: session.username ?? "", displayName: session.displayName))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.s24) {
                    ProfileAvatar(seed: avatarSeed, name: previewName, size: 72)
                        .padding(.top, Space.s8)
                    UsernameField(text: $form.username, current: form.currentUsername, status: $form.usernameStatus)
                    DisplayNameField(text: $form.displayName)
                    if let error = form.errorMessage {
                        Text(error)
                            .font(.caption13)
                            .foregroundStyle(Color.negative)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.s24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.appBackground)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if form.isSaving {
                        ProgressView().tint(Color.textSecondary)
                    } else {
                        Button("Save") {
                            Task {
                                if await form.save() { dismiss() }
                            }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accent)
                        .disabled(!form.canSave || !form.hasChanges)
                        .accessibilityIdentifier("profile.save")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(form.isSaving)
    }

    private var avatarSeed: String {
        SessionStore.shared.avatarSeed ?? SessionStore.shared.userId ?? form.currentUsername
    }

    private var previewName: String {
        let name = form.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? form.username : name
    }
}

/// A Profile row: plain SF Symbol, title, optional trailing detail or glyph — the
/// same anatomy as Settings' rows.
private struct ProfileRow: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var trailingSymbol: String? = nil

    var body: some View {
        HStack(spacing: Space.s12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.caption13)
                    .foregroundStyle(Color.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Profile's achievements row: the count, and the latest few medallions.
private struct AchievementsSummaryRow: View {
    let center: AchievementCenter

    private var recent: [Achievement] {
        Array(center.achievements.filter(\.unlocked).prefix(4))
    }

    var body: some View {
        HStack(spacing: Space.s12) {
            Image(systemName: "rosette")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Achievements")
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                if center.response != nil {
                    Text("\(center.unlockedCount) of \(center.total) unlocked")
                        .font(.caption13Digits)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            Spacer(minLength: Space.s8)
            HStack(spacing: -Space.s8) {
                ForEach(recent) { achievement in
                    AchievementBadge(achievement: achievement, size: 28)
                        .background(Color.appSurface, in: Circle())
                }
            }
        }
        .padding(.vertical, Space.s4)
        .contentShape(Rectangle())
    }
}
