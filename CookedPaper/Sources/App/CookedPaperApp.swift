import GoogleSignIn
import SwiftUI

@main
struct CookedPaperApp: App {
    init() {
        #if DEBUG
        MockAPI.prepareSessionIfNeeded()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // Google's sign-in callback comes back as a URL too.
                    if GIDSignIn.sharedInstance.handle(url) { return }
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
    let session = SessionStore.shared
    let network = NetworkMonitor.shared
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            if store.isLoadingProducts && !store.isSubscribed {
                LaunchScreen()
            } else if !hasSeenOnboarding && !store.isSubscribed {
                OnboardingView(onFinished: { hasSeenOnboarding = true })
            } else if !session.isSignedIn {
                // Everyone trades as a signed-in account; there are no guests.
                SignInView {
                    Task { await PortfolioStore.shared.resetAndRebootstrap() }
                }
            } else if session.needsProfileSetup {
                // A sign-in outside onboarding just created the account (onboarding
                // shows this as its own step instead).
                ProfileSetupView {}
            } else if store.isSubscribed {
                AppShellView()
            } else {
                PaywallView()
            }
        }
        .animation(Motion.standard, value: store.isSubscribed)
        .animation(Motion.standard, value: session.isSignedIn)
        .animation(Motion.standard, value: session.needsProfileSetup)
        .overlay(alignment: .top) {
            if !network.isOnline {
                OfflineBanner()
                    .padding(.top, Space.s4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.standard, value: network.isOnline)
    }
}

private struct LaunchScreen: View {
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            BrandMark(height: 96)
        }
    }
}
