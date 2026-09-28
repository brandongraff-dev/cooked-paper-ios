import Foundation
import StoreKit
import SwiftUI

/// The hard paywall — the only door into the app. No skip button; see
/// `SubscriptionStore` for why there's no server-side gate to match (paper trading
/// is free/unlimited on apps/api by design, so the subscription is enforced entirely
/// here). Every price, period and trial term shown is read from StoreKit.
struct PaywallView: View {
    let store = SubscriptionStore.shared
    @State private var selectedProductID = ProductID.annual
    @State private var isPurchasing = false
    /// Product ids whose introductory offer this Apple ID can still redeem — a trial
    /// is only ever advertised to someone who will actually get it.
    @State private var trialEligibleIDs: Set<String> = []

    private var selectedProduct: Product? {
        store.products.first { $0.id == selectedProductID }
    }

    /// Yearly, Weekly, Monthly — the order the plans are presented in.
    private var orderedPlans: [Product] {
        [store.annualProduct, store.weeklyProduct, store.monthlyProduct].compactMap { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Space.s32) {
                    hero
                    features
                    plans
                }
                .padding(.horizontal, Space.s24)
                .padding(.top, Space.s8)
                .padding(.bottom, Space.s16)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .background(alignment: .top) { backdrop }
        .background(Color.appBackground)
        .overlay(alignment: .topTrailing) {
            Button("Restore") { Task { await store.restore() } }
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, Space.s24)
                .padding(.top, Space.s8)
        }
        .preferredColorScheme(.dark)
        .task { await PortfolioStore.shared.bootstrapIfNeeded() }
        .task(id: store.products.map(\.id)) {
            await refreshTrialEligibility()
            if selectedProduct == nil, let first = orderedPlans.first(where: { $0.id == ProductID.annual }) ?? orderedPlans.first {
                selectedProductID = first.id
            }
        }
    }

    /// A faint blue light behind the logo — the one decorative touch on this screen.
    private var backdrop: some View {
        RadialGradient(
            colors: [Color.accent.opacity(0.14), Color.accent.opacity(0)],
            center: .top,
            startRadius: 0,
            endRadius: 360
        )
        .frame(height: 420)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Sections

    /// The positions the user just opened in onboarding (or holds from before) —
    /// the paywall is about keeping them.
    private var heldPositions: [PaperPosition] {
        PortfolioStore.shared.snapshot?.positions ?? []
    }

    private var hero: some View {
        VStack(spacing: Space.s20) {
            BrandWordmark(height: 34)
                .padding(.top, Space.s48)

            Text(heldPositions.isEmpty ? "Trade live prices\nwith paper money." : "Keep your\nportfolio.")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.8)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(heldPositions.isEmpty
                 ? "Every fill uses the real market price. Every loss stays on your record."
                 : "\(positionNames) \(heldPositions.count == 1 ? "is" : "are") moving with the market right now. Subscribe to keep trading them.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !heldPositions.isEmpty {
                positionsCard
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "WIF, BONK and JUP"
    private var positionNames: String {
        let names = heldPositions.prefix(3).map { $0.token?.symbol ?? "Your coin" }
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }

    private var positionsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(heldPositions.prefix(3).enumerated()), id: \.element.id) { index, position in
                HStack(spacing: Space.s12) {
                    TokenAvatar(mint: position.tokenMint, symbol: position.token?.symbol, size: 32)
                    Text(position.token?.symbol ?? "?")
                        .font(.rowTitle)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(PriceFormat.usd(position.valueUsd))
                            .font(.rowValue)
                            .foregroundStyle(Color.textPrimary)
                        Text(position.unrealizedPnlUsd.map(PriceFormat.signedUSD) ?? "—")
                            .font(.caption13Digits)
                            .foregroundStyle(Color.direction(position.unrealizedPnlUsd))
                    }
                }
                .padding(.horizontal, Space.s16)
                .frame(minHeight: 60)
                if index < min(heldPositions.count, 3) - 1 {
                    RowSeparator(leadingInset: Space.s16 + 32 + Space.s12)
                }
            }
        }
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(.top, Space.s4)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            FeatureCheck(text: "Unlimited paper trades on live tokens")
            FeatureCheck(text: "Your full record: win rate, P&L, every trade")
            FeatureCheck(text: "A monthly leaderboard to climb")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var plans: some View {
        VStack(spacing: Space.s16) {
            if store.isLoadingProducts {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonBlock(height: 84, cornerRadius: Radius.card)
                }
            } else if orderedPlans.isEmpty {
                Text("Plans couldn't be loaded. Check your connection and try again.")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(orderedPlans, id: \.id) { product in
                    PlanRow(
                        title: planTitle(product),
                        badge: product.id == ProductID.annual ? savingsText(annual: product) : nil,
                        subtitle: planSubtitle(product),
                        price: "\(product.displayPrice)/\(shortUnit(product))",
                        detail: planDetail(product),
                        isSelected: selectedProductID == product.id
                    ) { select(product) }
                    .accessibilityIdentifier("paywall.plan.\(product.id)")
                }
            }

            if let error = store.purchaseError {
                Text(error)
                    .font(.caption13)
                    .foregroundStyle(Color.negative)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: Space.s16) {
            Button(action: primaryAction) {
                if store.isLoadingProducts || isPurchasing {
                    ProgressView().tint(Color.accentInk)
                } else {
                    Text(ctaTitle)
                }
            }
            .buttonStyle(.accent)
            .accessibilityIdentifier("paywall.subscribeButton")

            Text(disclosure)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.s32) {
                Link("Terms", destination: LegalLinks.terms)
                Link("Privacy", destination: LegalLinks.privacy)
            }
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, Space.s24)
        .padding(.top, Space.s16)
        .padding(.bottom, Space.s8)
    }

    // MARK: - Actions

    private func select(_ product: Product) {
        guard selectedProductID != product.id else { return }
        Haptics.selection()
        withAnimation(Motion.standard) { selectedProductID = product.id }
    }

    /// Never a dead button: while products load it shows a spinner and ignores taps;
    /// if they failed to load it retries; otherwise it purchases the selected plan.
    private func primaryAction() {
        guard !store.isLoadingProducts, !isPurchasing else { return }
        guard let product = selectedProduct ?? orderedPlans.first else {
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

    private func trialOffer(_ product: Product) -> Product.SubscriptionOffer? {
        guard trialEligibleIDs.contains(product.id) else { return nil }
        return product.subscription?.introductoryOffer
    }

    /// "3 days" / "1 week" — a trial's length, spelled out.
    private func trialLength(_ offer: Product.SubscriptionOffer) -> String {
        let value = offer.period.value
        let unit = unitName(offer.period.unit)
        return "\(value) \(unit)\(value == 1 ? "" : "s")"
    }

    private var ctaTitle: String {
        if orderedPlans.isEmpty { return "Try again" }
        guard let selectedProduct else { return "Continue" }
        if let offer = trialOffer(selectedProduct) {
            return "Start my \(offer.period.value)-\(unitName(offer.period.unit)) free trial"
        }
        return "Subscribe · \(selectedProduct.displayPrice)/\(unitName(periodUnit(selectedProduct)))"
    }

    private func planTitle(_ product: Product) -> String {
        switch periodUnit(product) {
        case .year: "Yearly"
        case .month: "Monthly"
        case .week: "Weekly"
        case .day: "Daily"
        @unknown default: product.displayName
        }
    }

    private func planSubtitle(_ product: Product) -> String {
        if let offer = trialOffer(product) {
            return "\(trialLength(offer)) free, then \(product.displayPrice)/\(unitName(periodUnit(product)))"
        }
        switch periodUnit(product) {
        case .year: return "Billed once a year"
        case .month: return "Billed every month"
        case .week: return "Billed every week"
        default: return "Billed every \(unitName(periodUnit(product)))"
        }
    }

    /// The small line under the price: a weekly equivalent for longer plans, or
    /// "after trial" when the plan starts with one.
    private func planDetail(_ product: Product) -> String? {
        if trialOffer(product) != nil { return "after trial" }
        let weeks: Decimal
        switch periodUnit(product) {
        case .year: weeks = 52
        case .month: weeks = Decimal(52) / 12
        default: return nil
        }
        let perWeek = product.price / weeks
        return "\(perWeek.formatted(product.priceFormatStyle))/week"
    }

    private func periodUnit(_ product: Product) -> Product.SubscriptionPeriod.Unit {
        product.subscription?.subscriptionPeriod.unit ?? .month
    }

    private func shortUnit(_ product: Product) -> String {
        switch periodUnit(product) {
        case .year: "yr"
        case .month: "mo"
        case .week: "wk"
        case .day: "day"
        @unknown default: "period"
        }
    }

    private func unitName(_ unit: Product.SubscriptionPeriod.Unit) -> String {
        switch unit {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        @unknown default: "period"
        }
    }

    /// "SAVE 69%" — yearly versus a year of monthly.
    private func savingsText(annual: Product) -> String? {
        guard let monthly = store.monthlyProduct, monthly.price > 0 else { return nil }
        let yearOfMonthly = monthly.price * 12
        guard yearOfMonthly > annual.price else { return nil }
        let saving = NSDecimalNumber(decimal: (1 - annual.price / yearOfMonthly) * 100).doubleValue
        let rounded = Int(saving.rounded())
        return rounded > 0 ? "SAVE \(rounded)%" : nil
    }

    private var disclosure: String {
        guard let selectedProduct else {
            return "Subscriptions renew automatically until you cancel. Cancel anytime in Settings."
        }
        let unit = unitName(periodUnit(selectedProduct))
        if let offer = trialOffer(selectedProduct) {
            return "Free for \(trialLength(offer)), then \(selectedProduct.displayPrice) every \(unit) until you cancel. Cancel before the trial ends and you won't be charged."
        }
        return "\(selectedProduct.displayPrice) today, then every \(unit) until you cancel. Cancel anytime in Settings."
    }
}

private struct FeatureCheck: View {
    let text: String

    var body: some View {
        HStack(spacing: Space.s16) {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Radio | title (+ badge) over subtitle | price over detail. Selected gets the
/// accent border, a faint accent wash, and a filled radio.
private struct PlanRow: View {
    let title: String
    let badge: String?
    let subtitle: String
    let price: String
    let detail: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        Button(action: action) {
            HStack(spacing: Space.s16) {
                RadioMark(isSelected: isSelected)

                VStack(alignment: .leading, spacing: Space.s4) {
                    HStack(spacing: Space.s8) {
                        Text(title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Color.accent)
                                .padding(.horizontal, Space.s8)
                                .padding(.vertical, Space.s4)
                                .background(Color.accent.opacity(0.16), in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }

                Spacer(minLength: Space.s8)

                VStack(alignment: .trailing, spacing: Space.s4) {
                    Text(price)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                    if let detail {
                        Text(detail)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .padding(Space.s20)
            .background(isSelected ? Color.accent.opacity(0.08) : Color.appSurface, in: shape)
            .overlay(shape.strokeBorder(isSelected ? Color.accent : Color.appSeparator, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct RadioMark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? Color.accent : Color.textTertiary, lineWidth: 1.5)
            if isSelected {
                Circle().fill(Color.accent)
                Circle().fill(Color.appBackground).frame(width: 9, height: 9)
            }
        }
        .frame(width: 24, height: 24)
        .animation(Motion.standard, value: isSelected)
        .accessibilityHidden(true)
    }
}

#Preview {
    PaywallView()
}
