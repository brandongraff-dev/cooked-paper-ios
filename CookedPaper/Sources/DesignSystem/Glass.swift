import SwiftUI
import UIKit

// The depth layer: a lit backdrop behind every screen, frosted glass cards over it,
// and colored icon tiles so a row reads at a glance before its words do. Gains and
// losses keep green and red to themselves; the tile palette never uses either.

// MARK: - Palette

extension Color {
    /// Second brand color, paired with `accent` in the brand gradient.
    static let accentViolet = Color(rgb: 0x8B7BFF)

    // Icon tile colors (iOS-style squircles). Never green or red: those mean up and down.
    static let tileBlue = Color(rgb: 0x3D8BFF)
    static let tileIndigo = Color(rgb: 0x6E62FF)
    static let tilePurple = Color(rgb: 0xA35BFF)
    static let tilePink = Color(rgb: 0xFF4F9A)
    static let tileOrange = Color(rgb: 0xFF8A2B)
    static let tileYellow = Color(rgb: 0xF5B800)
    static let tileTeal = Color(rgb: 0x16C2C2)
    static let tileGray = Color(rgb: 0x6B6B73)
}

@MainActor
extension LinearGradient {
    /// Blue into violet: the paywall's CTA, the PRO badge, the brand moments.
    static var brand: LinearGradient {
        LinearGradient(
            colors: [Color.accent, Color.accentViolet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// A tile's fill: the color, lit from the top-left.
    static func tile(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.blended(with: .white, by: 0.22), color, color.blended(with: .black, by: 0.18)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    /// Linear sRGB mix — `Color.mix(with:by:)` is iOS 18+ (hence the different name), and this app supports 17.
    func blended(with other: Color, by amount: Double) -> Color {
        let a = UIColor(self).rgba
        let b = UIColor(other).rgba
        let t = min(max(amount, 0), 1)
        return Color(
            .sRGB,
            red: a.r + (b.r - a.r) * t,
            green: a.g + (b.g - a.g) * t,
            blue: a.b + (b.b - a.b) * t,
            opacity: a.a + (b.a - a.a) * t
        )
    }
}

private extension UIColor {
    var rgba: (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
}

// MARK: - Screen backdrop

/// Black with two soft pools of brand light at the top and a faint teal one low on
/// the left: enough color for the glass cards above it to pick up, never enough to
/// compete with a number. Static, so it costs nothing while scrolling.
struct ScreenBackdrop: View {
    var body: some View {
        ZStack {
            Color.appBackground
            RadialGradient(
                colors: [Color.accent.opacity(0.20), .clear],
                center: UnitPoint(x: 0.1, y: -0.05),
                startRadius: 0,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.accentViolet.opacity(0.16), .clear],
                center: UnitPoint(x: 0.95, y: 0.08),
                startRadius: 0,
                endRadius: 380
            )
            RadialGradient(
                colors: [Color.tileTeal.opacity(0.07), .clear],
                center: UnitPoint(x: 0, y: 0.85),
                startRadius: 0,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The app's screen background: `ScreenBackdrop` behind the content.
    func screenBackground() -> some View {
        background { ScreenBackdrop() }
    }
}

// MARK: - Glass card

private struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.appSurface.opacity(0.62))
                    if let tint {
                        shape.fill(
                            LinearGradient(
                                colors: [tint.opacity(0.22), tint.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                }
                .environment(\.colorScheme, .dark)
            }
            .overlay {
                // A lit top edge fading out toward the bottom: the glass's rim.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
}

extension View {
    /// Frosted glass over the screen backdrop, with a lit rim and a soft drop shadow.
    /// `tint` washes the glass with a color, for cards that lead to a feature.
    func glassCard(cornerRadius: CGFloat = Radius.card, tint: Color? = nil) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, tint: tint))
    }
}

// MARK: - Icon tile

/// A white SF Symbol on a lit, colored squircle — the way iOS Settings marks a row.
/// Bounces once when it first appears (not under Reduce Motion).
struct IconTile: View {
    let symbol: String
    var color: Color = .tileBlue
    var size: CGFloat = 30

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient.tile(color))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            }
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: appeared)
            }
            .shadow(color: color.opacity(0.35), radius: size * 0.18, y: size * 0.08)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion, !appeared else { return }
                appeared = true
            }
    }
}

// MARK: - Badges

/// "PRO" on the brand gradient.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2.weight(.heavy))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(LinearGradient.brand, in: Capsule())
            .accessibilityLabel("Pro")
    }
}

/// A `List` row's glass, for `.listRowBackground(_:)`.
struct GlassRowBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Color.appSurface.opacity(0.62))
        }
        .environment(\.colorScheme, .dark)
    }
}
