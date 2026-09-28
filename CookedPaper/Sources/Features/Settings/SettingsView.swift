import StoreKit
import SwiftUI

struct SettingsView: View {
    private let session = SessionStore.shared
    private let subscriptionStore = SubscriptionStore.shared
    private let portfolioStore = PortfolioStore.shared

    @State private var showLinkAccount = false
    @State private var showManageSubscriptions = false
    @State private var showResetConfirm = false
    @State private var isResetting = false

    var body: some View {
        List {
            Section {
                accountRow
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

            Section("Alerts") {
                if session.isGuest {
                    Button { showLinkAccount = true } label: {
                        SettingsRow(symbol: "bell", title: "Price alerts", detail: "Save progress first")
                    }
                } else {
                    NavigationLink { AlertsView() } label: {
                        SettingsRow(symbol: "bell", title: "Price alerts")
                    }
                    .accessibilityIdentifier("settings.priceAlerts")
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
            }
            .listRowBackground(Color.appSurface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .tint(Color.textPrimary)
        .navigationTitle("Settings")
        .sheet(isPresented: $showLinkAccount) { LinkAccountSheet() }
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
    }

    private var accountRow: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            HStack(spacing: Metrics.avatarGap) {
                MonogramAvatar(text: session.isGuest ? "Guest" : (session.username ?? "You"), size: 48)
                Text(session.isGuest ? "Guest" : (session.username ?? "Signed in"))
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Space.s8)
                if session.isGuest {
                    Button("Save progress") { showLinkAccount = true }
                        .buttonStyle(.compact)
                        .accessibilityIdentifier("settings.saveProgress")
                } else {
                    Button("Sign out") { Task { await signOut() } }
                        .font(.caption13)
                        .foregroundStyle(Color.negative)
                        .buttonStyle(.borderless)
                }
            }
            Label(
                session.isGuest ? "Progress is deleted after 7 days" : "Progress is saved to your account",
                systemImage: session.isGuest ? "exclamationmark.circle" : "checkmark.circle"
            )
            .labelStyle(InlineIconLabelStyle())
            .lineLimit(1)
        }
        .padding(.vertical, Space.s8)
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

    private func signOut() async {
        try? await AuthAPI.logout()
        session.clear()
        await portfolioStore.resetAndRebootstrap()
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

/// Icon and text on one line with a tight gap — for the account card's status line.
private struct InlineIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.s4) {
            configuration.icon
            configuration.title
        }
        .font(.rowSubtitle)
        .foregroundStyle(Color.textSecondary)
    }
}
