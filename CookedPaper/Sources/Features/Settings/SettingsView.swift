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

            Section("Subscription") {
                Button("Manage Subscription") { showManageSubscriptions = true }
                    .font(CookedFont.body())
                Button("Restore Purchases") { Task { await subscriptionStore.restore() } }
                    .font(CookedFont.body())
            }

            Section("Portfolio") {
                Button("Reset Portfolio", role: .destructive) { showResetConfirm = true }
                    .font(CookedFont.body())
                    .disabled(isResetting)
                if isResetting {
                    ProgressView().tint(CookedColor.Brand.fill)
                }
            }

            Section("Alerts") {
                if session.isGuest {
                    Button("Save Progress to set price alerts") { showLinkAccount = true }
                        .font(CookedFont.body())
                        .foregroundStyle(CookedColor.Terminal.textMuted)
                } else {
                    NavigationLink("Price Alerts") { AlertsView() }
                        .font(CookedFont.body())
                }
            }

            Section("Legal") {
                Link("Terms of Use", destination: LegalLinks.terms)
                    .font(CookedFont.body())
                Link("Privacy Policy", destination: LegalLinks.privacy)
                    .font(CookedFont.body())
            }

            Section {
                Text("Cooked Paper is a simulated trading experience. Nothing in this app involves real money, and nothing you do here executes on-chain.")
                    .font(CookedFont.caption())
                    .foregroundStyle(CookedColor.Terminal.textMuted)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(CookedColor.Terminal.bgBase.ignoresSafeArea())
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if session.isGuest {
                    Text("Guest session")
                        .font(CookedFont.headline())
                        .foregroundStyle(CookedColor.Terminal.textPrimary)
                    Text("Not saved past 7 days")
                        .font(CookedFont.caption())
                        .foregroundStyle(CookedColor.Terminal.warn)
                } else {
                    Text(session.username ?? "Signed in")
                        .font(CookedFont.headline())
                        .foregroundStyle(CookedColor.Terminal.textPrimary)
                    Text("Progress saved to your account")
                        .font(CookedFont.caption())
                        .foregroundStyle(CookedColor.Terminal.textMuted)
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
        .padding(.vertical, CookedSpacing.xxs)
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
