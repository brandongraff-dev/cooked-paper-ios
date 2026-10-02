import StoreKit
import SwiftUI

struct SettingsView: View {
    private let session = SessionStore.shared
    private let subscriptionStore = SubscriptionStore.shared
    private let portfolioStore = PortfolioStore.shared

    @State private var showManageSubscriptions = false
    @State private var showResetConfirm = false
    @State private var isResetting = false
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        List {
            Section {
                // The account itself, as iOS Settings puts it: tap through to Profile.
                NavigationLink {
                    ProfileView()
                } label: {
                    accountRow
                }
                .accessibilityIdentifier("settings.profile")
            }
            .listRowBackground(Color.appSurface)

            Section("Subscription") {
                Button { showManageSubscriptions = true } label: {
                    SettingsRow(symbol: "creditcard", title: "Manage subscription")
                }
                Button { Task { await subscriptionStore.restore() } } label: {
                    SettingsRow(symbol: "arrow.clockwise", title: "Restore purchases")
                }
            }
            .listRowBackground(Color.appSurface)

            Section {
                Link(destination: LegalLinks.terms) {
                    SettingsRow(symbol: "doc.text", title: "Terms of Use", trailingSymbol: "arrow.up.right")
                }
                Link(destination: LegalLinks.privacy) {
                    SettingsRow(symbol: "hand.raised", title: "Privacy Policy", trailingSymbol: "arrow.up.right")
                }
            } header: {
                Text("Legal")
            } footer: {
                Text("Cooked Paper is a simulated trading experience. Nothing here involves real money or executes on-chain.")
                    .font(.caption13)
                    .foregroundStyle(Color.textTertiary)
            }
            .listRowBackground(Color.appSurface)

            Section {
                Button { showSignOutConfirm = true } label: {
                    SettingsRow(symbol: "rectangle.portrait.and.arrow.right", title: "Sign out")
                }
                .accessibilityIdentifier("settings.signOut")
                // The destructive actions live together, each behind a confirmation.
                Button(role: .destructive) { showResetConfirm = true } label: {
                    HStack {
                        Text("Reset portfolio")
                            .font(.body)
                            .foregroundStyle(Color.negative)
                        Spacer()
                        if isResetting { ProgressView() }
                    }
                }
                .disabled(isResetting)
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    HStack {
                        Text("Delete account")
                            .font(.body)
                            .foregroundStyle(Color.negative)
                        Spacer()
                        if isDeleting { ProgressView() }
                    }
                }
                .disabled(isDeleting)
                if let deleteError {
                    Text(deleteError)
                        .font(.caption13)
                        .foregroundStyle(Color.negative)
                }
            } header: {
                Text("Account")
            } footer: {
                VStack(spacing: Space.s8) {
                    BrandWordmark(height: 22, color: .textTertiary)
                    Text("Paper trading · Version \(appVersion)")
                        .font(.caption13)
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Space.s32)
            }
            .listRowBackground(Color.appSurface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .reservesTabBarSpace()
        .tint(Color.textPrimary)
        .navigationTitle("Settings")
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .confirmationDialog(
            "Reset portfolio?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { Task { await resetPortfolio() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every trade in this portfolio and restores your starting balance. It can't be undone.")
        }
        .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your portfolio stays saved to your account.")
        }
        .confirmationDialog("Delete your account?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, portfolio and trade history. It can't be undone. An App Store subscription is cancelled separately, in Manage subscription.")
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var accountRow: some View {
        HStack(spacing: Metrics.avatarGap) {
            ProfileAvatar(
                seed: session.avatarSeed ?? session.userId ?? session.username ?? "cooked",
                name: session.displayName ?? session.username ?? "Cooked",
                size: 48
            )
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(session.displayName ?? session.username.map { "@\($0)" } ?? "Paper account")
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                if session.displayName != nil, let username = session.username {
                    Text("@\(username)")
                        .font(.rowSubvalue)
                        .foregroundStyle(Color.textSecondary)
                }
                if let method = signInMethodLabel {
                    Text(method)
                        .font(.rowSubvalue)
                        .foregroundStyle(Color.textTertiary)
                }
                if let snapshot = portfolioStore.snapshot {
                    Text("\(PriceFormat.usd(snapshot.equityUsd)) · started with \(PriceFormat.compact(snapshot.portfolio.startingBalanceUsd))")
                        .font(.rowSubvalue)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.s8)
    }

    private var signInMethodLabel: String? {
        switch session.method {
        case "apple": "Signed in with Apple"
        case "google": "Signed in with Google"
        default: nil
        }
    }

    private func signOut() async {
        await AuthAPI.logout(refreshToken: session.refreshToken)
        session.clear()
        portfolioStore.signedOut()
        Haptics.success()
    }

    private func deleteAccount() async {
        isDeleting = true
        deleteError = nil
        do {
            try await AuthAPI.deleteAccount()
            session.clear()
            portfolioStore.signedOut()
            Haptics.success()
        } catch {
            Haptics.error()
            deleteError = (error as? APIError)?.errorDescription ?? "Couldn't delete your account. Try again."
        }
        isDeleting = false
    }

    private func resetPortfolio() async {
        guard let id = session.activePortfolioId else { return }
        isResetting = true
        Haptics.warning()
        try? await PaperAPI.reset(portfolioId: id)
        try? await portfolioStore.refresh()
        isResetting = false
        Haptics.success()
    }
}

/// One Settings row: a plain SF Symbol in secondary gray, a title, and an optional
/// detail or trailing glyph.
private struct SettingsRow: View {
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
