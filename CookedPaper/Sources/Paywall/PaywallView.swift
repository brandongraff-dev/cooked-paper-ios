import Foundation
import StoreKit
import SwiftUI

/// The hard paywall — the only door into the app. No free trial is granted by the
/// app itself, no skip button; see `SubscriptionStore` for why there's no
/// server-side gate to match (paper trading is free/unlimited on apps/api by
/// design, so the subscription is enforced entirely here).
struct PaywallView: View {
    let store = SubscriptionStore.shared
    @State private var selectedProductID = ProductID.annual
    @State private var isPurchasing = false
    /// Product ids whose introductory offer this Apple ID can still redeem — so a
    /// trial is only ever advertised to someone who will actually get it.
    @State private var trialEligibleIDs: Set<String> = []

    private var selectedProduct: Product? {
        store.products.first { $0.id == selectedProductID }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    brandCard
                    headline
                    features
                    plans
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.s24)
                .padding(.bottom, Space.s16)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
        .task(id: store.products.map(\.id)) { await refreshTrialEligibility() }
    }

    // MARK: - Sections

    private var brandCard: some View {
        HStack(spacing: Space.s12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(Color.accentFlame)
            Text("Cooked Paper")
                .font(.rowTitle)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text("PRO")
                .font(.caption13.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(Color.inverseText)
                .padding(.horizontal, Space.s8)
                .padding(.vertical, 2)
                .background(Color.accentFlame, in: Capsule())
        }
        .padding(Space.s20)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            Text("Trade like it's real.\nBecause it isn't.")
                .font(.appLargeTitle)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Practice with $10,000 in virtual cash on live market prices. No real money, ever.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            FeatureLine(symbol: "chart.xyaxis.line", text: "Live charts on real market prices")
            FeatureLine(symbol: "bolt", text: "Instant buys and sells, no setup")
            FeatureLine(symbol: "trophy", text: "Monthly leaderboard against other traders")
            FeatureLine(symbol: "checkmark.shield", text: "Simulated only — never real money")
        }
    }

    @ViewBuilder
    private var plans: some View {
        VStack(spacing: Space.s12) {
            if store.isLoadingProducts {
                PlanPlaceholder()
                PlanPlaceholder()
            } else if store.products.isEmpty {
                Text("Plans couldn't be loaded. Check your connection and try again.")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if let annual = store.annualProduct {
                    PlanRow(
                        title: "Yearly",
                        price: "\(annual.displayPrice)/\(periodUnit(annual))",
                        badge: savingsText(annual: annual),
                        trial: trialText(annual),
                        isSelected: selectedProductID == annual.id
                    ) { select(annual) }
                    .accessibilityIdentifier("paywall.planAnnual")
                }
                if let monthly = store.monthlyProduct {
                    PlanRow(
                        title: "Monthly",
                        price: "\(monthly.displayPrice)/\(periodUnit(monthly))",
                        badge: nil,
                        trial: trialText(monthly),
                        isSelected: selectedProductID == monthly.id
                    ) { select(monthly) }
                    .accessibilityIdentifier("paywall.planMonthly")
                }
            }

            if let error = store.purchaseError {
                Text(error)
                    .font(.caption13)
                    .foregroundStyle(Color.negative)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: Space.s12) {
            Button(action: primaryAction) {
                if store.isLoadingProducts || isPurchasing {
                    ProgressView().tint(Color.inverseText)
                } else if store.products.isEmpty {
                    Text("Try again")
                } else if let selectedProduct, trialText(selectedProduct) != nil {
                    Text("Start free trial")
                } else {
                    Text("Continue")
                }
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("paywall.subscribeButton")

            HStack(spacing: Space.s16) {
                Button("Restore") { Task { await store.restore() } }
                Link("Terms", destination: LegalLinks.terms)
                Link("Privacy", destination: LegalLinks.privacy)
            }
            .font(.caption13)
            .foregroundStyle(Color.textTertiary)

            Text(disclosure)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s12)
        .padding(.bottom, Space.s8)
        .background(Color.appBackground)
    }

    // MARK: - Actions

    private func select(_ product: Product) {
        guard selectedProductID != product.id else { return }
        Haptics.selection()
        selectedProductID = product.id
    }

    /// Never a dead button: while products load it shows a spinner and ignores taps;
    /// if they failed to load it retries; otherwise it purchases the selected plan.
    private func primaryAction() {
        guard !store.isLoadingProducts, !isPurchasing else { return }
        guard let product = selectedProduct ?? store.products.first else {
            Task { await store.loadProducts() }
            return
        }
        Task {
            isPurchasing = true
            await store.purchase(product)
            isPurchasing = false
            if store.isSubscribed { Haptics.success() }
        }
    }

    // MARK: - StoreKit display

    private func refreshTrialEligibility() async {
        var eligible: Set<String> = []
        for product in store.products {
            if let subscription = product.subscription,
               subscription.introductoryOffer?.paymentMode == .freeTrial,
               await subscription.isEligibleForIntroOffer {
                eligible.insert(product.id)
            }
        }
        trialEligibleIDs = eligible
    }

    private func periodUnit(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "period" }
        let unit: String = switch period.unit {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        @unknown default: "period"
        }
        return period.value == 1 ? unit : "\(period.value) \(unit)s"
    }

    /// "7-day free trial, then $29.99/year" — only for an eligible free-trial offer.
    private func trialText(_ product: Product) -> String? {
        guard trialEligibleIDs.contains(product.id),
              let offer = product.subscription?.introductoryOffer else { return nil }
        let length = offer.period.value
        let unit: String = switch offer.period.unit {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        @unknown default: "period"
        }
        return "\(length)-\(unit) free trial, then \(product.displayPrice)/\(periodUnit(product))"
    }

    /// "Save 69%" versus paying monthly for a year.
    private func savingsText(annual: Product) -> String? {
        guard let monthly = store.monthlyProduct, monthly.price > 0 else { return nil }
        let yearOfMonthly = monthly.price * 12
        guard yearOfMonthly > annual.price else { return nil }
        let saving = (1 - annual.price / yearOfMonthly) * 100
        let rounded = NSDecimalNumber(decimal: saving).intValue
        return rounded > 0 ? "Save \(rounded)%" : nil
    }

    private var disclosure: String {
        guard let selectedProduct else {
            return "Subscriptions auto-renew until canceled. Cancel anytime in Settings at least 24 hours before renewal."
        }
        return "\(selectedProduct.displayPrice)/\(periodUnit(selectedProduct)), auto-renews until canceled. Cancel anytime in Settings at least 24 hours before renewal."
    }
}

private struct FeatureLine: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: Space.s12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
        }
    }
}

/// One plan: title and price on the left, radio on the right. Selected gets a white
/// hairline border; nothing is tinted.
private struct PlanRow: View {
    let title: String
    let price: String
    let badge: String?
    let trial: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s12) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    HStack(spacing: Space.s8) {
                        Text(title)
                            .font(.rowTitle)
                            .foregroundStyle(Color.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(.caption13)
                                .foregroundStyle(Color.textPrimary)
                                .padding(.horizontal, Space.s8)
                                .padding(.vertical, 2)
                                .background(Color.appSurfaceElevated, in: Capsule())
                        }
                    }
                    Text(price)
                        .font(.rowSubvalue)
                        .foregroundStyle(Color.textSecondary)
                    if let trial {
                        Text(trial)
                            .font(.caption13)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Space.s16)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Color.textPrimary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PlanPlaceholder: View {
    var body: some View {
        SkeletonBlock(height: 76, cornerRadius: Radius.card)
    }
}

#Preview {
    PaywallView()
}
