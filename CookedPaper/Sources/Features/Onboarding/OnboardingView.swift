import SwiftUI

/// Shown once on first launch, before the paywall — chrome, not a dense trading
/// surface, so it lives on `Product.graphite` like `PaywallView` rather than
/// `Terminal.bgBase`. `RootView` owns the `hasSeenOnboarding` flag and decides when
/// this appears; this view only reports that the person is done.
struct OnboardingView: View {
    var onFinished: () -> Void

    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "dollarsign.circle.fill",
            headline: "Trade with $10,000 in practice cash",
            detail: "Real market prices, nothing is real money."
        ),
        OnboardingPage(
            symbol: "chart.xyaxis.line",
            headline: "Watch live charts",
            detail: "Candlestick charts on real market data, instant buy and sell."
        ),
        OnboardingPage(
            symbol: "trophy.fill",
            headline: "See how you'd have done",
            detail: "Track your simulated P&L, no real money ever at risk."
        ),
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack {
            CookedColor.Product.graphite.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        OnboardingPageView(page: item)
                            .tag(index)
                    }
                }
                // Native dots ignore the design system's palette entirely; a hand-drawn
                // indicator below can use `Brand.fill` for the active state instead.
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicator
                    .padding(.top, CookedSpacing.lg)

                actionButton
                    .padding(.horizontal, CookedSpacing.xl)
                    .padding(.top, CookedSpacing.xl)
                    .padding(.bottom, CookedSpacing.xl)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var pageIndicator: some View {
        HStack(spacing: CookedSpacing.xs) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? CookedColor.Brand.fill : CookedColor.Product.line)
                    .frame(width: index == page ? 20 : 6, height: 6)
            }
        }
        .animation(CookedMotion.standard, value: page)
    }

    // Same iOS-26-preferred `.glassProminent` treatment as the paywall's Subscribe
    // button, tinted `Brand.fill` — the two screens a user sees back-to-back should
    // match.
    @ViewBuilder
    private var actionButton: some View {
        if isLastPage {
            if #available(iOS 26.0, *) {
                Button("Get Started", action: onFinished)
                    .buttonStyle(.glassProminent)
                    .tint(CookedColor.Brand.fill)
                    .accessibilityIdentifier("onboarding.getStarted")
            } else {
                Button("Get Started", action: onFinished)
                    .buttonStyle(.cookedPrimary)
                    .accessibilityIdentifier("onboarding.getStarted")
            }
        } else {
            if #available(iOS 26.0, *) {
                Button("Next") {
                    withAnimation(CookedMotion.travel) { page += 1 }
                }
                .buttonStyle(.glassProminent)
                .tint(CookedColor.Brand.fill)
                .accessibilityIdentifier("onboarding.next")
            } else {
                Button("Next") {
                    withAnimation(CookedMotion.travel) { page += 1 }
                }
                .buttonStyle(.cookedPrimary)
                .accessibilityIdentifier("onboarding.next")
            }
        }
    }
}

private struct OnboardingPage {
    let symbol: String
    let headline: String
    let detail: String
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: CookedSpacing.xxl) {
            Spacer()

            Image(systemName: page.symbol)
                .font(.system(size: CookedIconSize.hero, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CookedColor.Brand.text)

            VStack(spacing: CookedSpacing.sm) {
                Text(page.headline)
                    .displayTextStyle(size: 28)
                    .foregroundStyle(CookedColor.Product.chalk)
                    .multilineTextAlignment(.center)

                Text(page.detail)
                    .font(CookedFont.body())
                    .foregroundStyle(CookedColor.Product.chalkMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, CookedSpacing.xxl)

            Spacer()
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(onFinished: {})
}
