import StoreKit
import SwiftUI

// MARK: - One-time offer

/// Whether the one-time annual offer has been shown on this device. It is shown at
/// most once, after the onboarding paywall is closed without buying, and the screen
/// says so; there is no countdown and no "only today", because neither would be true.
enum OneTimeOffer {
    private static let key = "paywall.oneTimeOfferShown"

    static var hasBeenShown: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markShown() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

/// Pro at the offer's annual price, shown once. The billed price is the largest
/// figure on the screen, as App Review asks; the regular annual price is struck
/// through beside it only when StoreKit actually sells that plan for more.
struct OneTimeOfferView: View {
    let offer: Product
    /// The regular annual plan, for the comparison. Nil hides it.
    let regular: Product?
    let onFinish: () -> Void

    private let store = SubscriptionStore.shared
    @State private var isPurchasing = false
    @State private var appeared = false

    private var savingsPercent: Int? {
        guard let regular, regular.price > offer.price, regular.price > 0 else { return nil }
        let saving = NSDecimalNumber(decimal: (1 - offer.price / regular.price) * 100).doubleValue
        let rounded = Int(saving.rounded())
        return rounded > 0 ? rounded : nil
    }

    private var perWeek: String {
        (offer.price / 52).formatted(offer.priceFormatStyle)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Space.s24) {
                    IconTile(symbol: "gift.fill", color: .tilePink, size: 72)
                        .scaleEffect(appeared ? 1 : 0.6)
                        .opacity(appeared ? 1 : 0)
                        .padding(.top, Space.s48)

                    VStack(spacing: Space.s12) {
                        Text("A one-time offer")
                            .font(.caption13)
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.textSecondary)
                        if let savingsPercent {
                            Text("\(savingsPercent)% off Pro,\nevery year you stay.")
                                .font(.system(size: 34, weight: .bold))
                                .tracking(-0.8)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Color.textPrimary)
                        } else {
                            Text("Pro for less,\nevery year you stay.")
                                .font(.system(size: 34, weight: .bold))
                                .tracking(-0.8)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Color.textPrimary)
                        }
                    }

                    VStack(spacing: Space.s8) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s12) {
                            if let regular, savingsPercent != nil {
                                Text(regular.displayPrice)
                                    .font(.title3.weight(.semibold).monospacedDigit())
                                    .strikethrough()
                                    .foregroundStyle(Color.textTertiary)
                            }
                            Text("\(offer.displayPrice)/year")
                                .font(.system(size: 40, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                        }
                        Text("That's \(perWeek) a week.")
                            .font(.rowSubtitle)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(Space.s24)
                    .frame(maxWidth: .infinity)
                    .glassCard(tint: .accent)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(LinearGradient.brand, lineWidth: 2)
                    }

                    Text("We'll only show this once.")
                        .font(.footnote)
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, Space.s24)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: Space.s16) {
                Button {
                    Task { await buy() }
                } label: {
                    if isPurchasing {
                        ProgressView().tint(Color.accentInk)
                    } else {
                        Text("Claim \(offer.displayPrice)/year")
                    }
                }
                .buttonStyle(.accent)
                .accessibilityIdentifier("offer.claim")

                Button("No thanks", action: onFinish)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityIdentifier("offer.decline")

                if let error = store.purchaseError {
                    Text(error)
                        .font(.caption13)
                        .foregroundStyle(Color.negative)
                        .multilineTextAlignment(.center)
                }

                Text("\(offer.displayPrice) today, then every year until you cancel. Cancel anytime in Settings.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Space.s32) {
                    Link("Terms of Service", destination: LegalLinks.terms)
                    Link("Privacy Policy", destination: LegalLinks.privacy)
                }
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, Space.s24)
            .padding(.top, Space.s16)
            .padding(.bottom, Space.s8)
        }
        .screenBackground()
        .preferredColorScheme(.dark)
        .onAppear {
            OneTimeOffer.markShown()
            Funnel.track(.offerShown)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appeared = true }
        }
    }

    private func buy() async {
        isPurchasing = true
        await store.purchase(offer)
        isPurchasing = false
        guard store.isSubscribed else { return }
        Funnel.track(.subscribed, ["product": offer.id])
        Haptics.success()
        onFinish()
    }
}

// MARK: - Proud-moment upsell

/// An inline card for a moment that just went well (a survived crash, a passed
/// challenge): one line on what Pro adds next, opening the paywall with `reason`.
/// Renders nothing for someone already on Pro.
struct ProUpsellCard: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let reason: PaywallReason

    @State private var showsPaywall = false

    var body: some View {
        if !FreeTier.shared.isPro {
            Button {
                Haptics.tap()
                Funnel.track(.upsellTapped, ["title": title])
                showsPaywall = true
            } label: {
                HStack(spacing: Space.s12) {
                    IconTile(symbol: symbol, color: color, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Space.s8) {
                            Text(title)
                                .font(.rowTitle)
                                .foregroundStyle(Color.textPrimary)
                            ProBadge()
                        }
                        Text(detail)
                            .font(.rowSubtitle)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption13)
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(Space.s16)
                .glassCard(tint: color)
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("upsell.card")
            .fullScreenCover(isPresented: $showsPaywall) {
                PaywallView(reason: reason) { showsPaywall = false }
            }
        }
    }
}
