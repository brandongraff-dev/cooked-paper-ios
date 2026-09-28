import SwiftUI

/// Cooked's palette, ported from `packages/config/design-tokens.ts` — that file is
/// the single source of truth across web and the Expo app, and this is the third
/// copy of the same values rather than a derivation, because SwiftUI has no way to
/// share a TypeScript module. Keep the two in sync by hand; do not invent a color
/// here that does not trace back to a named token there.
enum CookedColor {

    /// The dense, trading-surface palette (`terminal` in design-tokens.ts). This app
    /// is a chart+trade screen from launch to paywall, so `Terminal` is the primary
    /// palette everywhere except the one accent reserved for "the product speaking" —
    /// see `Brand` below.
    enum Terminal {
        static let bgBase = Color(hex: 0x030305)
        static let bgSurface = Color(hex: 0x1C1C20)
        static let bgSurfaceHi = Color(hex: 0x2B2B30)

        static let border = Color.white.opacity(0.07)
        static let borderStrong = Color.white.opacity(0.14)

        static let textPrimary = Color(hex: 0xF5F5F7)
        static let textSecondary = Color(hex: 0x9B9BA5)
        static let textMuted = Color(hex: 0x94949F)

        static let buy = Color(hex: 0x16C784)
        static let buyBg = Color(hex: 0x16C784).opacity(0.12)
        static let sell = Color(hex: 0xFF5D67)
        static let sellBg = Color(hex: 0xEA3943).opacity(0.12)
        static let warn = Color(hex: 0xF0A020)
        /// The dense-surface accent — chart highlights and in-terminal emphasis only.
        /// Never a CTA; see `Brand.accent` for "the product speaking".
        static let accent = Color(hex: 0x22D3A6)

        static let chartGrid = Color.white.opacity(0.045)
        static let chartCrosshair = Color.white.opacity(0.24)
        static let chartCrosshairSoft = Color.white.opacity(0.16)
        static let chartAreaBuy = Color(hex: 0x16C784).opacity(0.18)
        static let chartAreaSell = Color(hex: 0xEA3943).opacity(0.16)
    }

    /// The product chrome palette — onboarding, the paywall, settings, and anywhere
    /// that is not itself a dense trading grid. Warm near-black, never a pure neutral.
    enum Product {
        static let graphite = Color(hex: 0x0F0E0D)
        static let slate = Color(hex: 0x161513)
        static let sunken = Color(hex: 0x0B0A09)

        static let chalk = Color(hex: 0xF1F1F0)
        static let chalkMuted = Color(hex: 0xA4A3A3)

        static let clover = Color(hex: 0x00E58A)
        static let flagText = Color(hex: 0xFF7797)

        static let line = Color(hex: 0x262524)
        static let lineStrong = Color(hex: 0x32312F)
    }

    /// The one accent hue in the whole product. Reserved for the primary CTA, the
    /// active tab indicator, and a progress fill — never for gain/loss (that is
    /// `Terminal.buy`/`Terminal.sell`) and never for verification (`Verification.mark`).
    /// A near-black-of-the-hue ink prints on top of it, not white: white-on-`fill`
    /// measures under WCAG AA.
    enum Brand {
        static let fill = Color(hex: 0x5AA9FF)
        static let text = Color(hex: 0x5AA9FF)
        static let onFill = Color(hex: 0x051426)
        static let dangerFill = Color(hex: 0xFF4D78)
        static let onDanger = Color(hex: 0x160207)
    }

    /// A third semantic channel, deliberately never blue (the brand accent) and never
    /// green/red (gain/loss) — a verified-token badge is a claim about provenance,
    /// not performance or "the product speaking," and mixing that claim into either of
    /// the other two channels would make both mean less.
    enum Verification {
        static let mark = Color(hex: 0x7EE0FF)
    }

    /// Decorative-only, non-text, never gain/loss or verification. Used for the
    /// paywall's hero gradient and nothing else that reads as data.
    enum Prism {
        static let indigo = Color(hex: 0x6F8CFF)
        static let sky = Color(hex: 0x58C8F5)
        static let amber = Color(hex: 0xFFB26B)
        static let cyan = Color(hex: 0x7EE0FF)
        static let teal = Color(hex: 0x62E0C8)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
