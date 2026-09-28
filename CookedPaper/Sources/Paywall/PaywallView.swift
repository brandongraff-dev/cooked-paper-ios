import Foundation
import StoreKit
import SwiftUI
import UIKit

/// The hard paywall — the only door into the app. No free trial, no skip button; see
/// `SubscriptionStore` for why there's no server-side gate to match (paper trading is
/// free/unlimited on apps/api by design, so the subscription is enforced entirely
/// here).
struct PaywallView: View {
    let store = SubscriptionStore.shared
    @State private var selectedProductID = ProductID.annual
    @State private var isPurchasing = false
    @State private var isHeaderVisible = false
    @State private var isFeaturesVisible = false
    @State private var isPlansVisible = false

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    var body: some View {
        ZStack {
            AmbientBackground(
                colors: [CookedColor.Prism.indigo, CookedColor.Brand.fill, CookedColor.Prism.amber],
                base: CookedColor.Product.graphite
            )

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: CookedSpacing.xl) {
                        heroCard
                            .entrance(isHeaderVisible, reduceMotion: reduceMotion)
                        header
                            .entrance(isHeaderVisible, reduceMotion: reduceMotion, delay: 0.05)
                        features
                            .entrance(isFeaturesVisible, reduceMotion: reduceMotion, delay: 0.1)
                        plans
                            .entrance(isPlansVisible, reduceMotion: reduceMotion, delay: 0.16)
                    }
                    .padding(.horizontal, CookedSpacing.lg)
                    .padding(.top, CookedSpacing.xl)
                    .padding(.bottom, CookedSpacing.md)
                }
                .scrollIndicators(.hidden)

                footer
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            isHeaderVisible = true
            isFeaturesVisible = true
            isPlansVisible = true
        }
    }

    // MARK: - Sections

    /// The membership card — the one object this purchase actually buys, drawn as a
    /// glass card with a light sweep across it and tokens floating around it.
    private var heroCard: some View {
        ZStack {
            CoinView(size: 44, symbol: "chart.line.uptrend.xyaxis")
                .offset(x: -140, y: -58)
                .floating(amplitude: 6, period: 3)
            CoinView(size: 34, symbol: "bolt.fill", colors: [CookedColor.Prism.cyan, CookedColor.Prism.indigo])
                .offset(x: 146, y: 54)
                .floating(amplitude: 5, period: 2.6, delay: 0.5)

            VStack(alignment: .leading, spacing: CookedSpacing.sm) {
                HStack {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [CookedColor.Prism.amber, CookedColor.Brand.dangerFill], startPoint: .top, endPoint: .bottom)
                        )
                    Text("COOKED PAPER")
                        .font(CookedFont.label(12))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Text("PRO")
                        .font(CookedFont.badge(11))
                        .tracking(1)
                        .foregroundStyle(CookedColor.Brand.onFill)
                        .padding(.horizontal, CookedSpacing.xs)
                        .padding(.vertical, 3)
                        .background(
                            LinearGradient(colors: [CookedColor.Prism.cyan, CookedColor.Brand.fill], startPoint: .leading, endPoint: .trailing),
                            in: Capsule()
                        )
                }
                Spacer(minLength: 0)
                Text("$10,000.00")
                    .font(CookedFont.priceDisplay(30))
                    .foregroundStyle(.white)
                Text("Unlimited paper trading · every market")
                    .font(CookedFont.caption(12))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(CookedSpacing.lg)
            .frame(maxWidth: 300)
            .frame(height: 160)
            .background(
                LinearGradient(
                    colors: [CookedColor.Prism.indigo.opacity(0.6), CookedColor.Brand.fill.opacity(0.2), CookedColor.Prism.amber.opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: CookedRadius.xl, style: .continuous)
            )
            .glassPanel(cornerRadius: CookedRadius.xl, tint: CookedColor.Prism.indigo)
            .shineSweep(cornerRadius: CookedRadius.xl)
            .shadow(color: CookedColor.Prism.indigo.opacity(0.55), radius: 30, y: 14)
            .rotation3DEffect(.degrees(-6), axis: (x: 1, y: 0.3, z: 0), perspective: 0.5)
            .floating(amplitude: 4, period: 4)
        }
        .frame(height: 200)
    }

    private var header: some View {
        VStack(spacing: CookedSpacing.sm) {
            Text("Trade like it's real.\nBecause it isn't.")
                .multilineTextAlignment(.center)
                .displayTextStyle(size: 32)
                .foregroundStyle(CookedColor.Product.chalk)

            Text("Practice with $10,000 in virtual cash on live market prices. No real money, ever.")
                .font(CookedFont.body(16))
                .foregroundStyle(CookedColor.Product.chalkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CookedSpacing.sm)
        }
    }

    private var features: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: CookedSpacing.sm), GridItem(.flexible(), spacing: CookedSpacing.sm)],
            spacing: CookedSpacing.sm
        ) {
            FeatureTile(symbol: "chart.xyaxis.line", color: CookedColor.Prism.teal, title: "Live charts", detail: "Real market prices")
            FeatureTile(symbol: "bolt.fill", color: CookedColor.Prism.amber, title: "Instant fills", detail: "Buy & sell in a tap")
            FeatureTile(symbol: "trophy.fill", color: CookedColor.Prism.indigo, title: "Leaderboard", detail: "Rank against traders")
            FeatureTile(symbol: "checkmark.shield.fill", color: CookedColor.Terminal.buy, title: "Zero risk", detail: "Never real money")
        }
    }

    private var plans: some View {
        VStack(spacing: CookedSpacing.sm) {
            if store.isLoadingProducts {
                ProgressView()
                    .tint(CookedColor.Brand.fill)
                    .padding(.vertical, CookedSpacing.xl)
            } else {
                CookedGlassContainer(spacing: CookedSpacing.sm) {
                    VStack(spacing: CookedSpacing.sm) {
                        if let monthly = store.monthlyProduct {
                            PlanCard(
                                product: monthly,
                                badge: nil,
                                isSelected: selectedProductID == monthly.id,
                                subtitle: "Billed monthly"
                            ) { selectedProductID = monthly.id }
                            .accessibilityIdentifier("paywall.planMonthly")
                        }
                        if let annual = store.annualProduct {
                            PlanCard(
                                product: annual,
                                badge: "BEST VALUE",
                                isSelected: selectedProductID == annual.id,
                                subtitle: perMonthEquivalent(annual)
                            ) { selectedProductID = annual.id }
                            .accessibilityIdentifier("paywall.planAnnual")
                        }
                    }
                }
            }

            if !store.isLoadingProducts && store.products.isEmpty {
                HStack(spacing: CookedSpacing.sm) {
                    IconTile(symbol: "icloud.slash", color: CookedColor.Product.lineStrong, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plans unavailable")
                            .font(CookedFont.headline(15))
                            .foregroundStyle(CookedColor.Product.chalk)
                        Text("Couldn't reach the App Store. Check your connection.")
                            .font(CookedFont.caption(12))
                            .foregroundStyle(CookedColor.Product.chalkMuted)
                    }
                    Spacer(minLength: 0)
                    Button("Retry") { Task { await store.loadProducts() } }
                        .buttonStyle(.cookedCompact)
                }
                .padding(CookedSpacing.md)
                .glassPanel(cornerRadius: CookedRadius.md)
            }

            if let error = store.purchaseError {
                Text(error)
                    .font(CookedFont.caption())
                    .foregroundStyle(CookedColor.Terminal.sell)
                    .multilineTextAlignment(.center)
                    .padding(.top, CookedSpacing.xxs)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: CookedSpacing.sm) {
            // The one CTA in the app important enough to reach past `PrimaryButtonStyle`
            // for the system's own prominent glass treatment on 26+ — everywhere else
            // goes through `.cookedPrimary` so the app has one primary-button look.
            if #available(iOS 26.0, *) {
                Button {
                    guard let product = store.products.first(where: { $0.id == selectedProductID }) else { return }
                    Task {
                        isPurchasing = true
                        await store.purchase(product)
                        isPurchasing = false
                        if store.isSubscribed { Haptics.success() }
                    }
                } label: {
                    if isPurchasing {
                        ProgressView().tint(CookedColor.Brand.onFill)
                    } else {
                        Text("Subscribe")
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(CookedColor.Brand.fill)
                .disabled(isPurchasing || store.products.isEmpty)
                .accessibilityIdentifier("paywall.subscribeButton")
            } else {
                Button {
                    guard let product = store.products.first(where: { $0.id == selectedProductID }) else { return }
                    Task {
                        isPurchasing = true
                        await store.purchase(product)
                        isPurchasing = false
                        if store.isSubscribed { Haptics.success() }
                    }
                } label: {
                    if isPurchasing {
                        ProgressView().tint(CookedColor.Brand.onFill)
                    } else {
                        Text("Subscribe")
                    }
                }
                .buttonStyle(.cookedPrimary(enabled: store.products.first(where: { $0.id == selectedProductID }) != nil))
                .disabled(isPurchasing || store.products.isEmpty)
                .accessibilityIdentifier("paywall.subscribeButton")
            }

            HStack(spacing: CookedSpacing.md) {
                Button("Restore Purchases") {
                    Task { await store.restore() }
                }
                Link("Terms of Use", destination: LegalLinks.terms)
                Link("Privacy Policy", destination: LegalLinks.privacy)
            }
            .font(CookedFont.caption())
            .foregroundStyle(CookedColor.Product.chalkMuted)

            Text("Auto-renews until canceled. Cancel anytime in Settings.")
                .font(CookedFont.footnote())
                .foregroundStyle(CookedColor.Product.chalkMuted.opacity(0.7))
        }
        .padding(.horizontal, CookedSpacing.lg)
        .padding(.top, CookedSpacing.sm)
        .padding(.bottom, CookedSpacing.md)
        .background(
            LinearGradient(
                colors: [CookedColor.Product.graphite.opacity(0), CookedColor.Product.graphite],
                startPoint: .top,
                endPoint: .init(x: 0.5, y: 0.25)
            )
        )
    }

    private func perMonthEquivalent(_ annual: Product) -> String {
        let perMonth = annual.price / 12
        let formatted = perMonth.formatted(annual.priceFormatStyle)
        return "Billed yearly · \(formatted)/mo"
    }
}

struct EntranceModifier: ViewModifier {
    let isVisible: Bool
    let reduceMotion: Bool
    var delay: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (isVisible ? 0 : 12))
            .animation(
                reduceMotion ? .easeInOut(duration: 0.2).delay(delay) : CookedMotion.calm.delay(delay),
                value: isVisible
            )
    }
}

extension View {
    /// Fade-and-rise entrance for a paywall section, staggered by `delay` so
    /// header/features/plans arrive in sequence on first appear. Reduce-motion keeps
    /// only the fade — no rise (apple-design §14: cross-fade, don't slide).
    func entrance(_ isVisible: Bool, reduceMotion: Bool, delay: Double = 0) -> some View {
        modifier(EntranceModifier(isVisible: isVisible, reduceMotion: reduceMotion, delay: delay))
    }
}

private struct FeatureTile: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: CookedSpacing.xs) {
            IconTile(symbol: symbol, color: color, size: 34)
            Text(title)
                .font(CookedFont.headline(15))
                .foregroundStyle(CookedColor.Product.chalk)
            Text(detail)
                .font(CookedFont.caption(12))
                .foregroundStyle(CookedColor.Product.chalkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CookedSpacing.md)
        .glassPanel(cornerRadius: CookedRadius.lg, tint: color)
    }
}

private struct PlanCard: View {
    let product: Product
    let badge: String?
    let isSelected: Bool
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: CookedSpacing.xs) {
                        Text(product.displayName.isEmpty ? product.displayPrice : product.displayName)
                            .font(CookedFont.headline())
                            .foregroundStyle(CookedColor.Product.chalk)
                        if let badge {
                            Text(badge)
                                .font(CookedFont.badge())
                                .tracking(0.5)
                                .foregroundStyle(CookedColor.Brand.onFill)
                                .padding(.horizontal, CookedSpacing.xs)
                                .padding(.vertical, 2)
                                .background(CookedColor.Brand.fill)
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(CookedFont.caption())
                        .foregroundStyle(CookedColor.Product.chalkMuted)
                }

                Spacer()

                Text(product.displayPrice)
                    .font(CookedFont.priceLarge())
                    .foregroundStyle(CookedColor.Product.chalk)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: CookedIconSize.md))
                    .foregroundStyle(isSelected ? CookedColor.Brand.fill : CookedColor.Product.lineStrong)
                    .padding(.leading, CookedSpacing.xs)
            }
            .padding(CookedSpacing.md)
            .modifier(PlanCardBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
        .animation(CookedMotion.standard, value: isSelected)
    }
}

/// Selected is exactly Apple's "context-sensitive selection control" glass case — the
/// chosen plan should read as physically different, not just outlined. Unselected
/// stays the flat `slate` card so only the act of choosing changes the surface.
private struct PlanCardBackground: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content.cookedGlass(
                tint: CookedColor.Brand.fill,
                interactive: true,
                in: RoundedRectangle(cornerRadius: CookedRadius.md, style: .continuous)
            )
        } else {
            content.glassPanel(cornerRadius: CookedRadius.md)
        }
    }
}

#Preview {
    PaywallView()
}
