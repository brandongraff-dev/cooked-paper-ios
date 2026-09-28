import SwiftUI

struct AppShellView: View {
    let portfolioStore = PortfolioStore.shared
    let router = DeepLinkRouter.shared

    private var deepLinkTarget: DeepLinkTarget? {
        router.pendingTokenMint.map(DeepLinkTarget.init)
    }

    /// A custom binding rather than `$router.pendingTokenMint` directly: the setter
    /// runs on swipe-to-dismiss as well as programmatic dismissal, so `clear()` fires
    /// either way and a re-opened link with the same mint reliably re-triggers.
    private var deepLinkBinding: Binding<DeepLinkTarget?> {
        Binding(
            get: { deepLinkTarget },
            set: { newValue in
                if newValue == nil { router.clear() }
            }
        )
    }

    var body: some View {
        TabView {
            NavigationStack {
                DiscoverView()
            }
            .accessibilityIdentifier("tab.discover")
            .tabItem { Label("Discover", systemImage: "magnifyingglass") }

            NavigationStack {
                PortfolioView()
            }
            .accessibilityIdentifier("tab.portfolio")
            .tabItem { Label("Portfolio", systemImage: "chart.pie.fill") }

            NavigationStack {
                LeaderboardView()
            }
            .accessibilityIdentifier("tab.leaderboard")
            .tabItem { Label("Leaderboard", systemImage: "trophy.fill") }

            NavigationStack {
                SettingsView()
            }
            .accessibilityIdentifier("tab.settings")
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(CookedColor.Brand.fill)
        .task {
            await portfolioStore.bootstrapIfNeeded()
        }
        .sheet(item: deepLinkBinding) { target in
            NavigationStack {
                TokenDetailView(mint: target.mint)
            }
            .presentationDragIndicator(.visible)
        }
    }
}

private struct DeepLinkTarget: Identifiable {
    let mint: String
    var id: String { mint }
}
