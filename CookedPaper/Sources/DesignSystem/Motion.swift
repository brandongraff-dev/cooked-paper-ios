import SwiftUI

/// Ported from `apps/web/app/globals.css`'s motion tokens (`--ease-*`, `--dur-*`).
/// The web comment states its rule twice: **no bounce or overshoot anywhere** —
/// "this is a page of other people's money." That overrides `apple-design`'s default
/// of adding a little bounce to momentum-driven gestures: every spring below is
/// critically damped (`dampingFraction: 1.0`), on purpose, even for flicks and
/// releases. Calm settle, never a wobble on a number that means money.
enum CookedMotion {

    // MARK: - Simple state changes (color, opacity, a fade) — timing curves, ported
    // 1:1 from the CSS cubic-bezier control points.

    /// Settle curve for color/lift — `--ease-calm`.
    static let calm = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: Duration.base)
    /// Travel curve for anything covering ground — `--ease-out`.
    static let travel = Animation.timingCurve(0.23, 1, 0.32, 1, duration: Duration.base)
    /// `--ease-standard`, the platform-default feel for minor UI state.
    static let standard = Animation.timingCurve(0.4, 0, 0.2, 1, duration: Duration.state)
    /// `--ease-layout`, for a size/position change that is not gesture-driven.
    static let layout = Animation.timingCurve(0.32, 0.72, 0, 1, duration: Duration.layout)

    /// Raw durations (seconds), ported from `--dur-*`, for call sites that need a
    /// duration without a specific curve (e.g. as a spring's rough settle target).
    enum Duration {
        static let fast: Double = 0.14
        static let base: Double = 0.22
        static let slow: Double = 0.38
        static let hover: Double = 0.12
        static let state: Double = 0.16
        static let layout: Double = 0.22
        static let press: Double = 0.08
    }

    // MARK: - Gesture-driven UI (apple-design §3, §4) — springs, because only a
    // spring is interruptible mid-flight. Always critically damped: no bounce.

    /// Default for anything the user can grab, drag, or dismiss — a sheet, a
    /// crosshair drag, a swipe-to-dismiss.
    static let gesture = Animation.spring(response: 0.35, dampingFraction: 1.0)
    /// A touch-target's press state — instant down, quick settle up.
    static let press = Animation.spring(response: 0.22, dampingFraction: 1.0)
    /// A sheet or modal's presentation — slightly slower settle than a press.
    static let sheet = Animation.spring(response: 0.4, dampingFraction: 1.0)
}

enum CookedRadius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let pill: CGFloat = 999
    /// Buttons render at 16pt continuous corners, deliberately not the full pill
    /// radius — pills are reserved for genuine chips (timeframe segments, badges).
    static let button: CGFloat = 16
    /// Hero cards (portfolio equity, onboarding art, the paywall's membership card).
    static let xl: CGFloat = 28
}

enum CookedSpacing {
    static let xxs: CGFloat = 4
    /// The vertical padding inside a pill-shaped control (`CookedChip`, a compact
    /// button, a chart overlay label) — sits between `xxs` and `xs` because a capsule
    /// reads as cramped at 4pt and loses its "chip" proportions at 8pt.
    static let chip: CGFloat = 6
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
}

/// SF Symbol point sizes, independent of the text scale — an icon's visual weight
/// doesn't track a font size 1:1, so this is its own small ladder rather than reusing
/// `CookedFont`. Every bespoke `.font(.system(size: N))` on an `Image(systemName:)`
/// should trace back to one of these; a size that doesn't fit the ladder is a sign
/// the icon's role in the layout needs rethinking, not a new one-off number.
enum CookedIconSize {
    /// Inline with caption text — a trailing chip glyph, a warning triangle.
    static let xs: CGFloat = 11
    /// Inline with body/label text — a chevron, a direction arrow.
    static let sm: CGFloat = 14
    /// A tappable row glyph — the watchlist star, a toolbar icon's default weight.
    static let md: CGFloat = 18
    /// A standalone glyph carrying real visual weight — an empty-state icon.
    static let lg: CGFloat = 28
    /// A modal's headline glyph — a success checkmark, a confirmation state.
    static let xl: CGFloat = 48
    /// The largest a symbol appears anywhere — onboarding's one hero glyph per page.
    static let hero: CGFloat = 72
}
