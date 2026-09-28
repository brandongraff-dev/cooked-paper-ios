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
            .listRowBackground(rowBackground)

            Section("Subscription") {
                Button { showManageSubscriptions = true } label: {
                    SettingsRow(symbol: "crown.fill", color: CookedColor.Prism.amber, title: "Manage Subscription")
                }
                Button { Task { await subscriptionStore.restore() } } label: {
                    SettingsRow(symbol: "arrow.clockwise", color: CookedColor.Brand.fill, title: "Restore Purchases")
                }
            }
            .listRowBackground(rowBackground)

            Section("Portfolio") {
                Button(role: .destructive) { showResetConfirm = true } label: {
                    SettingsRow(symbol: "arrow.counterclockwise", color: CookedColor.Brand.dangerFill, title: "Reset Portfolio", titleColor: CookedColor.Terminal.sell)
                }
                .disabled(isResetting)
                if isResetting {
                    ProgressView().tint(CookedColor.Brand.fill)
                }
            }
            .listRowBackground(rowBackground)

            Section("Alerts") {
                if session.isGuest {
                    Button { showLinkAccount = true } label: {
                        SettingsRow(symbol: "bell.badge.fill", color: CookedColor.Product.lineStrong, title: "Save Progress to set price alerts", titleColor: CookedColor.Terminal.textMuted)
                    }
                } else {
                    NavigationLink { AlertsView() } label: {
                        SettingsRow(symbol: "bell.badge.fill", color: CookedColor.Brand.dangerFill, title: "Price Alerts")
                    }
                    .accessibilityIdentifier("settings.priceAlerts")
                }
            }
            .listRowBackground(rowBackground)

            Section("Legal") {
                Link(destination: LegalLinks.terms) {
                    SettingsRow(symbol: "doc.text.fill", color: CookedColor.Prism.indigo, title: "Terms of Use", trailingSymbol: "arrow.up.right")
                }
                Link(destination: LegalLinks.privacy) {
                    SettingsRow(symbol: "hand.raised.fill", color: CookedColor.Prism.teal, title: "Privacy Policy", trailingSymbol: "arrow.up.right")
                }
            }
            .listRowBackground(rowBackground)

            Section {
                HStack(alignment: .top, spacing: CookedSpacing.sm) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(CookedColor.Terminal.buy)
                    Text("Cooked Paper is a simulated trading experience. Nothing in this app involves real money, and nothing you do here executes on-chain.")
                        .font(CookedFont.caption(12))
                        .foregroundStyle(CookedColor.Terminal.textMuted)
                }
            }
            .listRowBackground(rowBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AmbientBackground(colors: [CookedColor.Prism.indigo, CookedColor.Prism.sky, CookedColor.Prism.teal], intensity: 0.8))
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

    /// Frosted rows over the aurora — translucent enough to let its color through.
    private var rowBackground: some View {
        Rectangle().fill(.ultraThinMaterial).overlay(Color.white.opacity(0.03))
    }

    private var accountRow: some View {
        HStack(spacing: CookedSpacing.sm) {
            TokenAvatar(
                seed: session.username ?? "guest",
                label: session.username ?? "G",
                size: 52
            )
            VStack(alignment: .leading, spacing: 3) {
                if session.isGuest {
                    Text("Guest session")
                        .font(CookedFont.headline())
                        .foregroundStyle(CookedColor.Terminal.textPrimary)
                    Label("Not saved past 7 days", systemImage: "clock.badge.exclamationmark")
                        .font(CookedFont.caption(12))
                        .foregroundStyle(CookedColor.Terminal.warn)
                } else {
                    Text(session.username ?? "Signed in")
                        .font(CookedFont.headline(18))
                        .foregroundStyle(CookedColor.Terminal.textPrimary)
                    Label("Progress saved to your account", systemImage: "checkmark.icloud.fill")
                        .font(CookedFont.caption(12))
                        .foregroundStyle(CookedColor.Terminal.buy)
                }
            }
            Spacer()
            if session.isGuest {
                Button("Save Progress") { showLinkAccount = true }
                    .buttonStyle(.cookedCompact)
            } else {
                Button("Sign Out") { Task { await signOut() } }
                    .font(CookedFont.body())
                    .foregroundStyle(CookedColor.Terminal.sell)
            }
        }
        .padding(.vertical, CookedSpacing.xs)
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

/// One Settings row: a colored icon tile, a title, and an optional trailing glyph.
private struct SettingsRow: View {
    let symbol: String
    let color: Color
    let title: String
    var titleColor: Color = CookedColor.Terminal.textPrimary
    var trailingSymbol: String? = nil

    var body: some View {
        HStack(spacing: CookedSpacing.sm) {
            IconTile(symbol: symbol, color: color, size: 30)
            Text(title)
                .font(CookedFont.body(16))
                .foregroundStyle(titleColor)
            Spacer()
            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.system(size: CookedIconSize.xs, weight: .bold))
                    .foregroundStyle(CookedColor.Terminal.textMuted)
            }
        }
        .contentShape(Rectangle())
    }
}
