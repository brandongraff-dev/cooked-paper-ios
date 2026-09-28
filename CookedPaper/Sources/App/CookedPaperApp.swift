import SwiftUI

@main
struct CookedPaperApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    DeepLinkRouter.shared.handle(url)
                }
        }
    }
}

/// The paywall gate. `SubscriptionStore` resolves `isSubscribed` asynchronously at
/// launch (StoreKit's `Transaction.currentEntitlements`), so there are three states,
/// not two: still resolving, subscribed, not subscribed — collapsing the first into
/// either of the other two would flash the paywall at every paying user on launch.
struct RootView: View {
    let store = SubscriptionStore.shared
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            if store.isLoadingProducts && !store.isSubscribed {
                LaunchScreen()
            } else if store.isSubscribed {
                AppShellView()
            } else if !hasSeenOnboarding {
                OnboardingView(onFinished: { hasSeenOnboarding = true })
            } else {
                PaywallView()
            }
        }
        .animation(CookedMotion.calm, value: store.isSubscribed)
    }
}

private struct LaunchScreen: View {
    var body: some View {
        ZStack {
            CookedColor.Product.graphite.ignoresSafeArea()
            Text("Cooked Paper")
                .font(CookedFont.title())
                .foregroundStyle(CookedColor.Product.chalkMuted)
        }
    }
}
