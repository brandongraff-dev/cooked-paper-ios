import Foundation
import SwiftUI
import UIKit

/// Whether ambient, looping decoration (drifting backgrounds, floating art, shine
/// sweeps) should move. Off under Reduce Motion (apple-design §14), and off when the
/// UI screenshot walkthrough sets `UITEST_STILL_FRAMES=1` — a view that redraws every
/// frame keeps XCUITest's "wait for app to idle" from ever settling, and still frames
/// also make screenshots deterministic. Every looping effect in the app checks this;
/// one-shot entrance animations don't need to.
enum AmbientMotion {
    static var isEnabled: Bool {
        !UIAccessibility.isReduceMotionEnabled
            && ProcessInfo.processInfo.environment["UITEST_STILL_FRAMES"] != "1"
    }
}

// MARK: - Ambient background

/// A slow-drifting aurora of color behind a screen's content. It is what gives the
/// Liquid Glass surfaces above it something to refract — glass over flat black reads
/// as nothing. A `MeshGradient` on iOS 18+, soft blurred orbs below that.
struct AmbientBackground: View {
    var colors: [Color]
    var base: Color = CookedColor.Terminal.bgBase
    var intensity: Double = 1

    var body: some View {
        ZStack {
            base
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !AmbientMotion.isEnabled)) { timeline in
                let t = AmbientMotion.isEnabled ? timeline.date.timeIntervalSinceReferenceDate : 20
                field(t)
            }
            .opacity(intensity)
            // Fades the glow out toward the bottom so dense content lower on the
            // screen always sits on near-black and keeps its contrast.
            LinearGradient(
                colors: [.clear, base.opacity(0.55), base],
                startPoint: .init(x: 0.5, y: 0.35),
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func color(_ index: Int) -> Color {
        guard !colors.isEmpty else { return CookedColor.Brand.fill }
        return colors[index % colors.count]
    }

    @ViewBuilder
    private func field(_ t: Double) -> some View {
        if #available(iOS 18.0, *) {
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.meshPoints(t),
                colors: [
                    color(0).opacity(0.62), color(1).opacity(0.42), color(2).opacity(0.58),
                    color(2).opacity(0.10), color(0).opacity(0.24), color(1).opacity(0.12),
                    .clear, .clear, .clear,
                ],
                background: .clear,
                smoothsColors: true
            )
        } else {
            orbs(t)
        }
    }

    private static func meshPoints(_ t: Double) -> [SIMD2<Float>] {
        func p(_ x: Double, _ y: Double) -> SIMD2<Float> { SIMD2<Float>(Float(x), Float(y)) }
        let topMid: Double = 0.5 + 0.12 * sin(t * 0.31)
        let leftMid: Double = 0.42 + 0.08 * sin(t * 0.43)
        let centerX: Double = 0.5 + 0.16 * cos(t * 0.37)
        let centerY: Double = 0.42 + 0.1 * sin(t * 0.52)
        let rightMid: Double = 0.38 + 0.08 * cos(t * 0.29)
        let bottomMid: Double = 0.5 + 0.1 * cos(t * 0.23)
        return [
            p(0, 0), p(topMid, 0), p(1, 0),
            p(0, leftMid), p(centerX, centerY), p(1, rightMid),
            p(0, 1), p(bottomMid, 1), p(1, 1),
        ]
    }

    private func orbs(_ t: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Circle().fill(color(0).opacity(0.5))
                    .frame(width: w * 0.9)
                    .offset(x: -w * 0.3 + 30 * sin(t * 0.3), y: -w * 0.45 + 24 * cos(t * 0.4))
                Circle().fill(color(1).opacity(0.38))
                    .frame(width: w * 0.8)
                    .offset(x: w * 0.35 + 26 * cos(t * 0.35), y: -w * 0.35 + 20 * sin(t * 0.5))
                Circle().fill(color(2).opacity(0.3))
                    .frame(width: w * 0.7)
                    .offset(x: 20 * sin(t * 0.27), y: w * 0.05 + 18 * cos(t * 0.33))
            }
            .frame(width: w, height: geo.size.height, alignment: .top)
            .blur(radius: 70)
        }
    }
}

extension AmbientBackground {
    /// The default app-wide aurora: brand blue into indigo and teal.
    static var brand: AmbientBackground {
        AmbientBackground(colors: [CookedColor.Prism.indigo, CookedColor.Brand.fill, CookedColor.Prism.teal])
    }
}

// MARK: - Token identity

/// A deterministic two-tone palette per token (or person), derived from a stable
/// FNV-1a hash of its symbol/mint — never `Hasher`, which is randomly seeded per
/// launch and would reshuffle every avatar's color on every run.
struct TokenPalette {
    let primary: Color
    let secondary: Color
    let hue: Double

    init(seed: String) {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in seed.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        hue = Double(hash % 360) / 360
        primary = Color(hue: hue, saturation: 0.58, brightness: 1.0)
        secondary = Color(hue: (hue + 0.09).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.62)
    }
}

/// A glossy generated avatar — the stand-in for any token without a logo image, and
/// for people on the leaderboard. A gradient sphere with a specular highlight, a thin
/// rim, and a soft colored shadow, so a list of them reads like objects, not letters.
struct TokenAvatar: View {
    let seed: String
    let label: String
    var size: CGFloat = 36

    var body: some View {
        let palette = TokenPalette(seed: seed)
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [palette.primary, palette.secondary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.5), .clear],
                    center: UnitPoint(x: 0.3, y: 0.2),
                    startRadius: 0,
                    endRadius: size * 0.6
                ))
            Text(initials)
                .font(.system(size: size * (initials.count > 1 ? 0.34 : 0.44), weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            Circle()
                .strokeBorder(.white.opacity(0.25), lineWidth: max(1, size / 40))
        }
        .frame(width: size, height: size)
        .shadow(color: palette.secondary.opacity(0.5), radius: size * 0.16, y: size * 0.08)
        .accessibilityHidden(true)
    }

    private var initials: String {
        let letters = label.filter { $0.isLetter || $0.isNumber }
        return String(letters.prefix(size >= 44 ? 2 : 1)).uppercased()
    }
}

// MARK: - Small pieces

/// A gain/loss percentage as a tinted capsule with a direction arrow — reads faster
/// in a dense list than bare colored text. Same color rule as `PnLText`: green/red
/// mean direction and nothing else; `nil` is "unpriced", never 0%.
struct ChangePill: View {
    let value: Decimal?
    var font: Font = CookedFont.priceSmall(12)

    var body: some View {
        let isGain = (value ?? 0) >= 0
        let color = value == nil
            ? CookedColor.Terminal.textMuted
            : (isGain ? CookedColor.Terminal.buy : CookedColor.Terminal.sell)
        HStack(spacing: 3) {
            if value != nil {
                Image(systemName: isGain ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .heavy))
            }
            Text(text)
        }
        .font(font)
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
    }

    private var text: String {
        guard let value else { return "—" }
        return "\(value.magnitude.formatted(.number.precision(.fractionLength(2))))%"
    }
}

/// An iOS-Settings-style colored icon square.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }
}

/// A figure that rolls up into place on first appear (digit-by-digit via
/// `.numericText`) and rolls again whenever its value changes. With ambient motion
/// off it simply shows the final value.
struct RollingNumber: View {
    let value: Double
    let format: (Double) -> String
    var font: Font = CookedFont.priceDisplay()
    var color: Color = CookedColor.Terminal.textPrimary

    @State private var shown: Double?

    var body: some View {
        let current = shown ?? (AmbientMotion.isEnabled ? 0 : value)
        Text(format(current))
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText(value: current))
            .onAppear {
                guard shown == nil else { return }
                if AmbientMotion.isEnabled {
                    withAnimation(.smooth(duration: 1.2).delay(0.15)) { shown = value }
                } else {
                    shown = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.smooth(duration: 0.6)) { shown = newValue }
            }
    }
}

// MARK: - Motion modifiers

/// A specular highlight that sweeps across a card every few seconds, like light
/// catching glass.
struct ShineSweep: ViewModifier {
    var cornerRadius: CGFloat
    @State private var progress: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.22), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.4, height: geo.size.height * 2)
                    .rotationEffect(.degrees(20))
                    .offset(x: progress * geo.size.width * 1.5, y: -geo.size.height * 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .allowsHitTesting(false)
            }
            .onAppear {
                guard AmbientMotion.isEnabled else { return }
                withAnimation(.easeInOut(duration: 2.4).delay(0.8).repeatForever(autoreverses: false)) {
                    progress = 1.2
                }
            }
    }
}

/// A gentle vertical bob, for floating decorative objects.
struct Floating: ViewModifier {
    var amplitude: CGFloat = 6
    var period: Double = 3
    var delay: Double = 0
    @State private var isUp = false

    func body(content: Content) -> some View {
        content
            .offset(y: isUp ? -amplitude : amplitude)
            .onAppear {
                guard AmbientMotion.isEnabled else { return }
                withAnimation(.easeInOut(duration: period / 2).delay(delay).repeatForever(autoreverses: true)) {
                    isUp = true
                }
            }
    }
}

extension View {
    func shineSweep(cornerRadius: CGFloat = CookedRadius.lg) -> some View {
        modifier(ShineSweep(cornerRadius: cornerRadius))
    }

    func floating(amplitude: CGFloat = 6, period: Double = 3, delay: Double = 0) -> some View {
        modifier(Floating(amplitude: amplitude, period: period, delay: delay))
    }

    /// A colored glow behind a view — a soft, blurred copy of `color` in its shape.
    func glow(_ color: Color, radius: CGFloat = 24, opacity: Double = 0.55) -> some View {
        background(
            Circle()
                .fill(color.opacity(opacity))
                .blur(radius: radius)
                .allowsHitTesting(false)
        )
    }
}

// MARK: - Formatting

extension Decimal {
    /// `$1.83B` / `$22.0M` / `$9.1K` — for stat tiles where the full figure would
    /// overflow and the precision doesn't matter.
    func compactUSD() -> String {
        let value = NSDecimalNumber(decimal: self).doubleValue
        let magnitude = abs(value)
        let (divisor, suffix): (Double, String) = switch magnitude {
        case 1_000_000_000...: (1_000_000_000, "B")
        case 1_000_000...: (1_000_000, "M")
        case 1_000...: (1_000, "K")
        default: (1, "")
        }
        let scaled = value / divisor
        let digits = suffix.isEmpty ? 2 : (abs(scaled) >= 100 ? 0 : 1)
        return "$" + scaled.formatted(.number.precision(.fractionLength(digits))) + suffix
    }

    /// Price formatting that keeps sub-dollar memecoin prices readable.
    func priceString() -> String {
        usdString(fractionDigits: self < 1 ? 6 : 2)
    }
}
