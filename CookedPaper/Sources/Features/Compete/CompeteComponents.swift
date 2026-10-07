import SwiftUI
import UIKit

// Shared pieces for the Compete screens: tier colors and badges, the live
// countdown, the head-to-head bar, and the legal line. Tier colors are the one
// place these screens add color beyond green/red — they are the reward itself, and
// they only ever tint small icons, never fills or text blocks.

// MARK: - Tier styling

extension AchievementTier {
    var color: Color {
        switch self {
        case .bronze: Color(rgb: 0xD08C5A)
        case .silver: Color(rgb: 0xC9D1DC)
        case .gold: Color(rgb: 0xF2C14E)
        case .legendary: Color(rgb: 0xB892FF)
        }
    }
}

extension SeasonTier {
    var color: Color {
        switch self {
        case .michelin: AchievementTier.legendary.color
        case .headChef: AchievementTier.gold.color
        case .sousChef: AchievementTier.silver.color
        case .lineCook: AchievementTier.bronze.color
        case .prepCook: .textSecondary
        case .unranked, .unknown: .textTertiary
        }
    }

    var symbol: String {
        switch self {
        case .michelin: "star.fill"
        case .headChef: "flame.fill"
        case .sousChef: "flame"
        case .lineCook: "fork.knife"
        case .prepCook: "carrot"
        case .unranked: "circle.dashed"
        case .unknown: "circle"
        }
    }
}

/// An SF Symbol name from the server, or a safe stand-in when this iOS version
/// doesn't have it (an unknown name would otherwise render as nothing).
enum CompeteSymbol {
    static func resolved(_ name: String, fallback: String = "star.fill") -> String {
        UIImage(systemName: name) == nil ? fallback : name
    }
}

/// A season tier as a tinted icon in a soft circle, optionally with its name.
struct TierBadge: View {
    let tier: SeasonTier
    var name: String? = nil
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: Space.s8) {
            medal
            if let name {
                Text(name)
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name ?? tier.defaultName)
    }

    /// A flat medal: a solid disc in the tier's color with a darker rim and a dark
    /// glyph. Unranked tiers are gunmetal with a gray glyph.
    private var medal: some View {
        let ranked = tier != .unranked && tier != .unknown && tier != .prepCook
        let fill = ranked ? tier.color : Color.metalMid
        return Circle()
            .fill(fill)
            .overlay(
                Circle().strokeBorder(
                    ranked ? fill.blended(with: .black, by: 0.3) : Color.white.opacity(0.14),
                    lineWidth: max(1.5, size * 0.07)
                )
            )
            .overlay(
                Image(systemName: CompeteSymbol.resolved(tier.symbol, fallback: "circle"))
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(ranked ? Color.black.opacity(0.68) : Color.textSecondary)
            )
            .frame(width: size, height: size)
    }
}

/// An achievement's medallion: tier-colored when unlocked, dimmed when locked.
struct AchievementBadge: View {
    let achievement: Achievement
    var size: CGFloat = 64

    var body: some View {
        let color = achievement.tierKind.color
        ZStack {
            Circle()
                .fill(achievement.unlocked ? color.opacity(0.14) : Color.appSurface)
            Circle()
                .strokeBorder(achievement.unlocked ? color.opacity(0.55) : Color.appSeparator, lineWidth: 1.5)
            Image(systemName: CompeteSymbol.resolved(achievement.icon))
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(achievement.unlocked ? color : Color.textTertiary)
        }
        .frame(width: size, height: size)
        .opacity(achievement.unlocked ? 1 : 0.6)
        .overlay(alignment: .bottomTrailing) {
            if !achievement.unlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: max(9, size * 0.15), weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(size * 0.06)
                    .background(Color.appBackground, in: Circle())
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Progress

/// A slim rounded progress track.
struct ProgressTrack: View {
    let fraction: Double
    var tint: Color = .textPrimary
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.appFill)
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, proxy.size.width * min(1, max(0, fraction))))
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .animation(Motion.standard, value: fraction)
        .accessibilityElement()
        .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded())) percent")
    }
}

// MARK: - Countdown

/// "18d 6h left", ticking every second. "Ended" once past.
struct CountdownText: View {
    let end: Date
    var suffix: String = " left"
    var font: Font = .caption13Digits
    var color: Color = .textSecondary

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(CompeteDate.remaining(until: end, from: context.date).map { $0 + suffix } ?? "Ended")
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }
}

// MARK: - Head to head

/// Two players' returns as one split capsule: your share in white, theirs in gray,
/// tipped toward whoever is ahead (a 20-point gap fills most of it).
struct HeadToHeadBar: View {
    let mine: Decimal?
    let theirs: Decimal?
    var height: CGFloat = 6

    private var share: Double {
        guard let mine, let theirs else { return 0.5 }
        let gap = NSDecimalNumber(decimal: mine - theirs).doubleValue
        return 0.5 + min(0.42, max(-0.42, gap / 40))
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                Capsule()
                    .fill(Color.textPrimary)
                    .frame(width: max(height, (proxy.size.width - 2) * share))
                Capsule()
                    .fill(Color.appFill)
            }
        }
        .frame(height: height)
        .animation(Motion.standard, value: share)
        .accessibilityHidden(true)
    }
}

// MARK: - Legal

/// "No stakes. Paper money only. Results are simulated." — on every screen that
/// creates a duel or shows season results.
struct CompeteLegalCaption: View {
    var body: some View {
        Text("No stakes. Paper money only. Results are simulated.")
            .font(.caption13)
            .foregroundStyle(Color.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("compete.legal")
    }
}

// MARK: - Formatting

enum CompeteFormat {
    /// "1,310".
    static func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    /// "#42 of 1,310", or "#42" when the field size is unknown.
    static func rank(_ rank: Int, of total: Int?) -> String {
        guard let total else { return "#\(count(rank))" }
        return "#\(count(rank)) of \(count(total))"
    }
}
