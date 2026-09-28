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
    @State private var isGlowPulsing = false
    @State private var isHeaderVisible = false
    @State private var isFeaturesVisible = false
    @State private var isPlansVisible = false

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    var body: some View {
        ZStack {
            CookedColor.Product.graphite.ignoresSafeArea()
            heroGlow

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: CookedSpacing.xxl) {
                        header
                            .entrance(isHeaderVisible, reduceMotion: reduceMotion)
                        features
                            .entrance(isFeaturesVisible, reduceMotion: reduceMotion, delay: 0.08)
                        plans
                            .entrance(isPlansVisible, reduceMotion: reduceMotion, delay: 0.16)
                    }
                    .padding(.horizontal, CookedSpacing.lg)
                    .padding(.top, CookedSpacing.xxxl)
                    .padding(.bottom, CookedSpacing.md)
                }

                footer
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !reduceMotion { isGlowPulsing = true }
            isHeaderVisible = true
            isFeaturesVisible = true
            isPlansVisible = true
        }
    }

    // MARK: - Sections

    /// The pulse is a plain `easeInOut` loop, not a `CookedMotion` spring — nothing
    /// here is gesture-driven, and the ~2.5s period is far outside the spring tokens'
    /// range, which are all state-change durations under half a second. Dropped
    /// entirely under reduce-motion rather than reduced in amplitude (apple-design
    /// §14): a full-bleed radial glow breathing behind the content is exactly the kind
    /// of large moving surface that guidance calls out.
    private var heroGlow: some View {
        RadialGradient(
            colors: [CookedColor.Prism.indigo.opacity(isGlowPulsing ? 0.4 : 0.24), .clear],
            center: .top,
            startRadius: 0,
            endRadius: isGlowPulsing ? 470 : 400
        )
        .ignoresSafeArea()
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
            value: isGlowPulsing
        )
    }

    private var header: some View {
        VStack(spacing: CookedSpacing.sm) {
            Text("Cooked Paper")
                .font(CookedFont.label(13))
                .tracking(0.06 * 13)
                .foregroundStyle(CookedColor.Brand.text)
                .textCase(.uppercase)

            Text("Trade like it's real.\nBecause it isn't.")
                .multilineTextAlignment(.center)
                .displayTextStyle(size: 32)
                .foregroundStyle(CookedColor.Product.chalk)

            Text("Practice with $10,000 in virtual cash on live market prices. No real money, ever.")
                .font(CookedFont.body())
                .foregroundStyle(CookedColor.Product.chalkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CookedSpacing.md)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: CookedSpacing.md) {
            FeatureRow(symbol: "chart.xyaxis.line", text: "Live charts on real market prices")
            FeatureRow(symbol: "bolt.fill", text: "Instant buy/sell, no setup")
            FeatureRow(symbol: "trophy.fill", text: "See how your picks would've done")
            FeatureRow(symbol: "checkmark.shield.fill", text: "Simulated trading only — nothing here is real money")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct FeatureRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: CookedSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: CookedIconSize.sm, weight: .semibold))
                .foregroundStyle(CookedColor.Brand.text)
                .frame(width: 24)
            Text(text)
                .font(CookedFont.body())
                .foregroundStyle(CookedColor.Product.chalk)
        }
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
            content
                .background(CookedColor.Product.slate)
                .clipShape(RoundedRectangle(cornerRadius: CookedRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CookedRadius.md, style: .continuous)
                        .strokeBorder(CookedColor.Product.line, lineWidth: 1)
                )
        }
    }
}

#Preview {
    PaywallView()
}
