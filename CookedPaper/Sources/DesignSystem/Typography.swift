import SwiftUI

/// "Numbers read as a terminal, prose reads as an app" — `design-tokens.ts` and
/// `globals.css` apply `font-variant-numeric: tabular-nums` to every price/PnL figure
/// on web, set in IBM Plex Mono, while chrome text stays on the system font (Inter on
/// web, literal `System` on the Expo app, matching this app's use of San Francisco).
///
/// This port uses the system's built-in `.monospaced` font design rather than
/// bundling the IBM Plex Mono TTFs — SF Mono gives the same tabular-figure, terminal
/// read without shipping font binaries this session has no way to fetch. Swap in the
/// real IBM Plex Mono files under `Resources/Fonts` later if brand parity down to the
/// exact typeface matters more than the one extra dependency.
enum CookedFont {

    // MARK: - Prose (San Francisco, the platform default — apple-design §15: prefer
    // the system font before a custom face; it already ships optical sizing).

    static func display(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    static func title(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func headline(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    static func caption(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    /// Legal/compliance fine print only (subscription terms, disclosures) — one step
    /// below `caption`. Never use this for anything a reader needs to act on; if it's
    /// worth noticing, it's worth `caption` or larger.
    static func footnote(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    /// A short, uppercase-tracked marketing badge ("BEST VALUE") — bold, default
    /// design. Distinct from `SimulatedBadge`'s monospaced treatment on purpose: that
    /// one reads as a stamped disclosure, this one as a UI tag.
    static func badge(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    // MARK: - Numerals (monospaced design, tabular by construction — prices, PnL,
    // cash balances, quantities. Never use `.body`/`.title` for a figure that moves.)

    static func priceDisplay(_ size: CGFloat = 40) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    static func priceLarge(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    static func priceMedium(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    static func priceSmall(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

/// apple-design §15: tracking is size-specific, never one value for every size —
/// large display text wants negative tracking, small text near zero. Applied as a
/// view modifier so a call site states its size once and gets the right tracking for
/// free rather than a magic `.tracking()` literal repeated at every call site.
struct DisplayTextStyle: ViewModifier {
    var size: CGFloat

    func body(content: Content) -> some View {
        content
            .font(CookedFont.display(size))
            .tracking(size >= 32 ? -0.02 * size : -0.01 * size)
            .lineSpacing(size * 0.05)
    }
}

extension View {
    func displayTextStyle(size: CGFloat = 34) -> some View {
        modifier(DisplayTextStyle(size: size))
    }
}
