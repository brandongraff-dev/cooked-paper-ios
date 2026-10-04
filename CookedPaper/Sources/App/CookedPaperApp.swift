import GoogleSignIn
import SwiftUI

@main
struct CookedPaperApp: App {
    /// APNs callbacks and notification taps (see `AppDelegate`).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
///
/// Order: onboarding (as a guest) → sign-in ("Save your portfolio", which claims
/// the guest portfolio) → paywall → the app. Sign-in comes after the guest has
/// traded and watched their positions move, but before the purchase, so every
/// subscription is bought by an account (`appAccountToken` set, entitlement
/// reconciled by the server, restorable on any device). A fresh account picks its
/// username before the paywall.
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
            } else if session.isSignedIn && session.needsProfileSetup {
                // A sign-in outside onboarding just created the account (onboarding
                // shows this as its own step instead).
                ProfileSetupView {}
            } else if !session.isSignedIn {
                // Before the paywall, so the purchase belongs to an account. Also
                // reached by someone subscribed on this device but signed out.
                SignInView(
                    title: session.isGuest ? "Save your portfolio" : "Sign in to Cooked",
                    subtitle: session.isGuest
                        ? "Sign in so your positions are saved to your account, on any device."
                        : "Trade live prices with paper money. Your portfolio is saved to your account."
                ) {
                    Task { await PortfolioStore.shared.resetAndRebootstrap() }
                }
            } else if !store.isSubscribed {
                PaywallView()
            } else {
                AppShellView()
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
        // On launch with a session, and again after every sign-in: hand the APNs
        // token to this account and reconcile the subscription with the server.
        .task(id: session.userId) {
            guard session.userId != nil else {
                store.clearServerEntitlement()
                return
            }
            await PushRegistrar.shared.uploadIfSignedIn()
            await store.syncWithServer()
        }
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
