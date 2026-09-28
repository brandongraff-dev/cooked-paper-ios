import Foundation
import SwiftUI

// The whole visual language in one file. Near-monochrome: color is information
// (green up, red down) plus one brand accent used in at most one or two places per
// screen. Hierarchy comes from type and spacing, never from gradients or glows.

// MARK: - Color

extension Color {
    /// Every screen's background.
    static let appBackground = Color(rgb: 0x000000)
    /// Cards and grouped rows.
    static let appSurface = Color(rgb: 0x111113)
    /// Sheets and pressed states.
    static let appSurfaceElevated = Color(rgb: 0x1C1C1E)
    /// Avatar monogram fill and other neutral placeholders.
    static let appFill = Color(rgb: 0x2C2C2E)
    static let appSeparator = Color.white.opacity(0.08)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.38)

    /// Up. Text color only — never a large fill.
    static let positive = Color(rgb: 0x30D158)
    /// Down. Text color only — never a large fill.
    static let negative = Color(rgb: 0xFF453A)

    /// The primary button's white capsule and the selected chip's fill.
    static let inverseFill = Color.white
    /// Text on `inverseFill`.
    static let inverseText = Color.black

    /// Flame orange. Reserved for the logo, the PRO badge and the selected tab.
    static let accentFlame = Color(rgb: 0xFF7A1A)

    /// Green for a gain, red for a loss, secondary gray for "unknown".
    static func direction(_ value: Decimal?) -> Color {
        guard let value else { return .textSecondary }
        return value >= 0 ? .positive : .negative
    }

    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Type

/// SF Pro only. Text styles are built on the system's Dynamic Type styles so body
/// copy scales with the user's setting; the two display sizes (hero price, amount
/// entry) are fixed on purpose — they are the layout. Every figure uses
/// `.monospacedDigit()` so live numbers never jitter sideways.
extension Font {
    /// 34 bold — the native large title.
    static let appLargeTitle = Font.largeTitle.bold()
    /// 44 semibold — the one price a screen is about. Pair with `.tracking(-0.5)`
    /// (see `heroPriceStyle()`).
    static let heroPrice = Font.system(size: 44, weight: .semibold).monospacedDigit()
    /// 64 semibold — the trade sheet's amount.
    static let amountEntry = Font.system(size: 64, weight: .semibold).monospacedDigit()
    /// 20 semibold, sentence case.
    static let sectionHeader = Font.title3.weight(.semibold)
    /// 17 semibold.
    static let rowTitle = Font.headline
    /// 15 regular.
    static let rowSubtitle = Font.subheadline
    /// 17 semibold with tabular digits — prices and values in rows and grids.
    static let rowValue = Font.headline.monospacedDigit()
    /// 15 regular with tabular digits — a row's secondary figure.
    static let rowSubvalue = Font.subheadline.monospacedDigit()
    /// 13 medium — captions and labels.
    static let caption13 = Font.footnote.weight(.medium)
    /// 13 medium with tabular digits.
    static let caption13Digits = Font.footnote.weight(.medium).monospacedDigit()
    /// 17 semibold — button labels.
    static let buttonLabel = Font.headline
}

extension View {
    func heroPriceStyle() -> some View {
        font(.heroPrice).tracking(-0.5)
    }
}

// MARK: - Layout

/// Strict 4pt grid.
enum Space {
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s48: CGFloat = 48

    /// Horizontal screen margin, everywhere. Headers, cards and rows share it.
    static let margin: CGFloat = 20
    /// Between sections.
    static let section: CGFloat = 32
    /// From a section header to its content.
    static let headerGap: CGFloat = 12
}

enum Metrics {
    static let rowHeight: CGFloat = 68
    static let avatar: CGFloat = 40
    static let avatarGap: CGFloat = 12
    static let buttonHeight: CGFloat = 56
    static let chipHeight: CGFloat = 32
}

enum Radius {
    static let small: CGFloat = 12
    static let card: CGFloat = 20
    static let sheet: CGFloat = 28
}

// MARK: - Motion

/// Short, critically damped springs — nothing bounces.
enum Motion {
    static let press = Animation.spring(response: 0.2, dampingFraction: 0.9)
    static let standard = Animation.spring(response: 0.3, dampingFraction: 1)
}

// MARK: - Number formatting

enum PriceFormat {
    private static let subscriptDigits: [Character] = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"]
    static let minus = "\u{2212}"

    /// ≥ $1 → 2 decimals ($1.83). $0.01–$1 → 4 significant digits, no trailing
    /// zeros ($0.1204). Below $0.01 → subscript-zero notation ($0.0₄2314).
    static func price(_ value: Decimal) -> String {
        let double = NSDecimalNumber(decimal: value).doubleValue
        let magnitude = abs(double)
        let sign = double < 0 ? minus : ""

        if magnitude >= 1 {
            return sign + "$" + magnitude.formatted(.number.precision(.fractionLength(2)))
        }
        if magnitude >= 0.01 {
            return sign + "$" + magnitude.formatted(.number.precision(.significantDigits(1...4)))
        }
        guard magnitude > 0 else { return "$0.00" }

        // 0.00002314 → exponent −5 → 4 zeros after the point, digits "2314".
        var exponent = Int(floor(log10(magnitude)))
        var digits = Int((magnitude * pow(10, Double(3 - exponent))).rounded())
        if digits >= 10_000 {
            digits /= 10
            exponent += 1
        }
        var digitString = String(digits)
        while digitString.count > 1 && digitString.hasSuffix("0") {
            digitString.removeLast()
        }
        let zeros = max(0, -exponent - 1)
        return sign + "$0.0" + subscripted(zeros) + digitString
    }

    /// $1.8B, $22M, $92.1M, $9.4K.
    static func compact(_ value: Decimal) -> String {
        let double = NSDecimalNumber(decimal: value).doubleValue
        let magnitude = abs(double)
        let sign = double < 0 ? minus : ""
        let (divisor, suffix): (Double, String) = switch magnitude {
        case 1_000_000_000...: (1_000_000_000, "B")
        case 1_000_000...: (1_000_000, "M")
        case 1_000...: (1_000, "K")
        default: (1, "")
        }
        if suffix.isEmpty {
            return sign + "$" + magnitude.formatted(.number.precision(.fractionLength(0...2)))
        }
        return sign + "$" + (magnitude / divisor).formatted(.number.precision(.fractionLength(0...1))) + suffix
    }

    /// Full dollars with cents: $6,412.37.
    static func usd(_ value: Decimal) -> String {
        let double = NSDecimalNumber(decimal: value).doubleValue
        let sign = double < 0 ? minus : ""
        return sign + "$" + abs(double).formatted(.number.precision(.fractionLength(2)))
    }

    /// +3.07% / −4.12%, with a real minus sign.
    static func change(_ percent: Decimal?) -> String {
        guard let percent else { return "—" }
        let double = NSDecimalNumber(decimal: percent).doubleValue
        return (double < 0 ? minus : "+") + abs(double).formatted(.number.precision(.fractionLength(2))) + "%"
    }

    /// +$0.08 / −$0.08 — the price-change amount, formatted like a price.
    static func signedPrice(_ value: Decimal) -> String {
        let sign = value < 0 ? minus : "+"
        return sign + price(value.magnitude)
    }

    /// +$564.04 / −$68.80.
    static func signedUSD(_ value: Decimal) -> String {
        let sign = value < 0 ? minus : "+"
        return sign + usd(value.magnitude)
    }

    /// Token quantities: 92M, 820, 2.7K, 0.004.
    static func quantity(_ value: Decimal) -> String {
        let double = NSDecimalNumber(decimal: value).doubleValue
        if abs(double) >= 10_000 {
            return double.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
        }
        return double.formatted(.number.precision(.significantDigits(1...4)))
    }

    private static func subscripted(_ number: Int) -> String {
        String(String(number).compactMap { char in
            char.wholeNumberValue.map { subscriptDigits[$0] }
        })
    }
}
