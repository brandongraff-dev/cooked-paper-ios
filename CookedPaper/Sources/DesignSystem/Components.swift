import Foundation
import SwiftUI
import UIKit

/// A raised card in the dense/terminal surface family: `bgSurface` fill, one hairline
/// edge, no drop shadow — this palette separates layers by the hairline, not by a big
/// lightness jump (design-tokens.ts: "a card reads as a card from its hairline").
struct CookedCard<Content: View>: View {
    var padding: CGFloat = CookedSpacing.md
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(CookedColor.Terminal.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: CookedRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CookedRadius.md, style: .continuous)
                    .strokeBorder(CookedColor.Terminal.border, lineWidth: 1)
            )
    }
}

/// The one primary action style in the app — brand blue fill, near-black-of-the-hue
/// ink on top (never white; see `CookedColor.Brand`). Presses respond on pointer-down
/// via `ButtonStyle`'s `configuration.isPressed`, which SwiftUI drives from the touch
/// itself — no debounce, no waiting for touch-up (apple-design §1).
struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        let fill = isDestructive ? CookedColor.Brand.dangerFill : CookedColor.Brand.fill
        let ink = isDestructive ? CookedColor.Brand.onDanger : CookedColor.Brand.onFill
        let shape = RoundedRectangle(cornerRadius: CookedRadius.button, style: .continuous)

        configuration.label
            .font(CookedFont.headline())
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [fill.opacity(isEnabled ? 1 : 0.4), fill.opacity(isEnabled ? 0.8 : 0.32)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: shape
            )
            // A light-catching top rim — what makes the fill read as a lit, raised
            // object rather than a flat rectangle.
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            )
            .shadow(color: fill.opacity(isEnabled ? 0.45 : 0), radius: 16, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(CookedMotion.press, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CookedFont.headline())
            .foregroundStyle(CookedColor.Terminal.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .glassPanel(cornerRadius: CookedRadius.button)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(CookedMotion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var cookedPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func cookedPrimary(destructive: Bool = false, enabled: Bool = true) -> PrimaryButtonStyle {
        PrimaryButtonStyle(isDestructive: destructive, isEnabled: enabled)
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var cookedSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// An inline, row-trailing CTA — "Save Progress" in Settings' account row, and
/// anywhere else a full-width `PrimaryButtonStyle` would be wrong for the context.
/// A glass pill where available (this is exactly the "context-sensitive control"
/// Apple's own Liquid Glass guidance calls out), a tinted material pill below iOS 26.
struct CompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(CookedFont.label())
            .foregroundStyle(CookedColor.Brand.onFill)
            .padding(.horizontal, CookedSpacing.sm)
            .padding(.vertical, CookedSpacing.xxs + 2)

        Group {
            if #available(iOS 26.0, *) {
                label.glassEffect(.regular.tint(CookedColor.Brand.fill).interactive(), in: .capsule)
            } else {
                label.background(CookedColor.Brand.fill).clipShape(Capsule())
            }
        }
        .scaleEffect(configuration.isPressed ? 0.95 : 1)
        .animation(CookedMotion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CompactButtonStyle {
    static var cookedCompact: CompactButtonStyle { CompactButtonStyle() }
}

/// A quick-size chip for the trade sheet's 25/50/75/100% row and the timeframe
/// selector on the chart — the app's one genuinely pill-shaped control family.
/// Fires its own selection haptic (Apple's dedicated generator for a picker/segment
/// changing) — callers pass only the state change, never their own haptic, so every
/// chip in the app feels identical without each screen having to remember to add one.
struct CookedChip: View {
    let title: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(title)
                .font(CookedFont.label())
                .foregroundStyle(isSelected ? CookedColor.Brand.onFill : CookedColor.Terminal.textSecondary)
                .padding(.horizontal, CookedSpacing.sm)
                .padding(.vertical, CookedSpacing.chip)
                .modifier(ChipBackground(isSelected: isSelected))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(CookedMotion.standard, value: isSelected)
    }
}

/// The three visual states a chip can be in — unselected, selected-with-glass
/// (iOS 26+), selected-solid (below iOS 26) — genuinely need different view trees
/// (`glassEffect` vs. a flat color), which is why this is its own `ViewModifier`
/// rather than a `.background()` value picked by a ternary.
private struct ChipBackground: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected, #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(CookedColor.Brand.fill).interactive(), in: .capsule)
        } else if isSelected {
            content.background(CookedColor.Brand.fill)
        } else {
            content.background(CookedColor.Terminal.bgSurfaceHi)
        }
    }
}

/// The literal "PAPER · SIMULATED" disclosure the backend requires travel with every
/// paper-leaderboard entry — mirrored here as a persistent badge so paper vs. real
/// data is never presented as a reskin of the same screen (apps/api won't even let a
/// paper stat serialize without this string attached).
struct SimulatedBadge: View {
    var body: some View {
        Text("PAPER · SIMULATED")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(0.06 * 10)
            .foregroundStyle(CookedColor.Terminal.textMuted)
            .padding(.horizontal, CookedSpacing.xs)
            .padding(.vertical, 3)
            .cookedGlass(in: Capsule())
    }
}

/// A token's icon, loaded from `GET /tokens/:mint/logo` — cacheable for a year
/// server-side, so `AsyncImage`'s default `URLCache` behavior is exactly right with
/// no extra caching layer needed here.
///
/// Until (or unless) the image arrives, it shows a generated `TokenAvatar` keyed on
/// the mint, so a token without a logo still gets a distinct, stable identity.
struct TokenLogo: View {
    let mint: String
    var symbol: String? = nil
    var size: CGFloat = 32

    var body: some View {
        AsyncImage(url: TokenAPI.logoURL(mint: mint)) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                TokenAvatar(seed: mint, label: symbol ?? mint, size: size)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A gain/loss figure. Color is the ONLY channel `buy`/`sell` ever carry — never
/// reused for anything else in this app (brand's own rule: red/green must mean
/// direction and nothing else).
struct PnLText: View {
    let value: Decimal?
    let isPercent: Bool
    var font: Font = CookedFont.priceMedium()

    var body: some View {
        if let value {
            let isGain = value >= 0
            Text(formatted(value))
                .font(font)
                .foregroundStyle(isGain ? CookedColor.Terminal.buy : CookedColor.Terminal.sell)
        } else {
            // Null is "unpriced", never zero — apps/api's own rule, carried into the UI.
            Text("—")
                .font(font)
                .foregroundStyle(CookedColor.Terminal.textMuted)
        }
    }

    private func formatted(_ value: Decimal) -> String {
        let sign = value >= 0 ? "+" : ""
        if isPercent {
            return "\(sign)\(value.formatted(.number.precision(.fractionLength(2))))%"
        }
        return "\(sign)\(value.formatted(.currency(code: "USD").precision(.fractionLength(2))))"
    }
}

/// A loading placeholder — `bgSurfaceHi` fill with a moving highlight, so a screen's
/// first frame reads as "content is arriving" rather than "content vanished behind a
/// spinner." The highlight is a `LinearGradient` band swept across on a plain
/// `repeatForever` loop, not a spring: this is an ambient, un-interruptible loop with
/// no gesture or state behind it, so `CookedMotion`'s springs and one-shot curves
/// don't apply — but it keeps that system's spirit of no bounce/overshoot (`.linear`
/// and `.easeInOut` only). Respects `UIAccessibility.isReduceMotionEnabled`
/// (apple-design §14): the sweep is dropped for a static, non-spatial opacity pulse.
struct SkeletonView: View {
    var cornerRadius: CGFloat = CookedRadius.xs
    @State private var isAnimating = false

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CookedColor.Terminal.bgSurfaceHi)
            .overlay { if !reduceMotion { shimmer } }
            .opacity(reduceMotion && isAnimating ? 0.55 : 1)
            .onAppear {
                let animation: Animation = reduceMotion
                    ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                    : .linear(duration: 1.6).repeatForever(autoreverses: false)
                withAnimation(animation) { isAnimating = true }
            }
    }

    private var shimmer: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.07), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: proxy.size.width * 0.7)
            .offset(x: isAnimating ? proxy.size.width : -proxy.size.width)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A placeholder for a row shaped like `DiscoverRow`/`PositionRow` — a logo circle,
/// two leading lines, two trailing lines — so the swap from skeleton to real content
/// doesn't reflow the row.
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: CookedSpacing.sm) {
            SkeletonView(cornerRadius: 18)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                SkeletonView().frame(width: 110, height: 14)
                SkeletonView().frame(width: 70, height: 11)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                SkeletonView().frame(width: 64, height: 14)
                SkeletonView().frame(width: 40, height: 11)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A placeholder sized like the candlestick chart area (`TokenDetailView` renders
/// `CandleChartView` at a fixed 280pt height).
struct SkeletonChart: View {
    var height: CGFloat = 280

    var body: some View {
        SkeletonView(cornerRadius: CookedRadius.md)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
    }
}
