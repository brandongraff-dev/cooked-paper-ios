import StoreKit
import SwiftUI

struct SettingsView: View {
    private let session = SessionStore.shared
    private let subscriptionStore = SubscriptionStore.shared
    private let portfolioStore = PortfolioStore.shared

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
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var accountRow: some View {
        HStack(spacing: Metrics.avatarGap) {
            BrandMark(height: 30)
                .frame(width: 48, height: 48)
                .background(Color.appSurfaceElevated, in: Circle())
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Paper account")
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
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
