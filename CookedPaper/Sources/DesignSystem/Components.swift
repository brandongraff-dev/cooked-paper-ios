import Foundation
import SwiftUI

// MARK: - Brand

/// The Cooked pan mark (template image, so it takes the foreground color).
struct BrandMark: View {
    var height: CGFloat = 28
    var color: Color = .textPrimary

    var body: some View {
        Image("LogoPan")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(height: height)
            .foregroundStyle(color)
            .accessibilityLabel("Cooked")
    }
}

/// The "Cooked" wordmark with the pan as its "o".
struct BrandWordmark: View {
    var height: CGFloat = 24
    var color: Color = .textPrimary

    var body: some View {
        Image("LogoWordmark")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(height: height)
            .foregroundStyle(color)
            .accessibilityLabel("Cooked")
    }
}

// MARK: - Avatars

/// A token's real logo (the feed's `logoUri` when present, else the API's logo
/// endpoint), falling back to a gray circle with a white monogram.
struct TokenAvatar: View {
    let mint: String
    var symbol: String? = nil
    var logoURL: URL? = nil
    var size: CGFloat = Metrics.avatar

    var body: some View {
        AsyncImage(url: logoURL ?? TokenAPI.logoURL(mint: mint)) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                MonogramAvatar(text: symbol ?? mint, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Gray circle, white single-letter monogram. People and logo-less tokens.
struct MonogramAvatar: View {
    let text: String
    var size: CGFloat = Metrics.avatar

    var body: some View {
        Circle()
            .fill(Color.appFill)
            .frame(width: size, height: size)
            .overlay(
                Text(String(text.first(where: { $0.isLetter || $0.isNumber }) ?? "?").uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
            )
            .accessibilityHidden(true)
    }
}

/// A person's own avatar: a solid colored circle picked deterministically from
/// the account's `avatarSeed` (the user id when there isn't one), with the first
/// letter of their name on it. The color is the account's, so the same person looks
/// the same on every device.
struct ProfileAvatar: View {
    let seed: String
    /// Display name, else username; the monogram is its first letter or digit.
    let name: String
    var size: CGFloat = Metrics.avatar

    var body: some View {
        let hue = Self.hue(for: seed)
        Circle()
            .fill(Color(hue: hue, saturation: 0.62, brightness: 0.82))
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.first(where: { $0.isLetter || $0.isNumber }) ?? "?").uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
            )
            .accessibilityHidden(true)
    }

    /// FNV-1a over the seed's bytes, folded into 0..<1. Not `Hasher`: that is
    /// randomized per launch, and the color must never change.
    static func hue(for seed: String) -> Double {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Double(hash % 360) / 360
    }
}

// MARK: - Numbers

/// A price, formatted by `PriceFormat.price` and animated digit-by-digit when it
/// changes.
struct PriceText: View {
    let value: Decimal?
    var font: Font = .rowValue
    var color: Color = .textPrimary

    var body: some View {
        Text(value.map(PriceFormat.price) ?? "—")
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText(value: value.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0))
            .animation(Motion.standard, value: value)
    }
}

/// "+3.07%" / "−4.12%" in a tinted capsule with a direction arrow — for the one
/// headline change on a screen. Rows use `ChangeText`.
struct ChangePill: View {
    let percent: Decimal?
    var font: Font = .rowSubvalue.weight(.semibold)

    var body: some View {
        let color = Color.direction(percent)
        HStack(spacing: 3) {
            if let percent {
                Image(systemName: percent >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption.weight(.bold))
            }
            Text(PriceFormat.change(percent))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(font)
        .foregroundStyle(color)
        .padding(.horizontal, Space.s8)
        .padding(.vertical, 4)
        .background(color.opacity(0.16), in: Capsule())
        .animation(Motion.standard, value: percent)
    }
}

/// "+3.07%" / "−4.12%" as colored text. No pill, no arrow.
struct ChangeText: View {
    let percent: Decimal?
    var font: Font = .rowSubvalue

    var body: some View {
        Text(PriceFormat.change(percent))
            .font(font)
            .monospacedDigit()
            .foregroundStyle(Color.direction(percent))
            .contentTransition(.numericText())
    }
}

// MARK: - Buttons

/// White capsule, black label, 56pt. Disabled keeps its shape at 35% opacity.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.buttonLabel)
            .foregroundStyle(Color.inverseText)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeight)
            .background(Color.inverseFill, in: Capsule())
            .opacity(isEnabled ? 1 : 0.35)
            .pressEffect(configuration.isPressed)
    }
}

/// Solid gunmetal capsule, white label, 56pt.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.buttonLabel)
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeight)
            .metalSurface()
            .opacity(isEnabled ? 1 : 0.35)
            .pressEffect(configuration.isPressed)
    }
}

/// Solid accent capsule, dark label, 56pt — the screen's one main action.
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.buttonLabel)
            .foregroundStyle(Color.accentInk)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.buttonHeight)
            .background(Color.accent, in: Capsule())
            .opacity(isEnabled ? 1 : 0.35)
            .pressEffect(configuration.isPressed)
    }
}

extension ButtonStyle where Self == AccentButtonStyle {
    static var accent: AccentButtonStyle { AccentButtonStyle() }
}

/// A small white capsule for inline actions ("Save progress").
struct CompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption13)
            .foregroundStyle(Color.inverseText)
            .padding(.horizontal, Space.s12)
            .frame(height: Metrics.chipHeight)
            .background(Color.inverseFill, in: Capsule())
            .pressEffect(configuration.isPressed)
    }
}

/// Press feedback for tappable rows and cards: a quick 0.97 scale.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .pressEffect(configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == CompactButtonStyle {
    static var compact: CompactButtonStyle { CompactButtonStyle() }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

private struct PressEffect: ViewModifier {
    let isPressed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isPressed && reduceMotion ? 0.7 : 1)
            .animation(Motion.press, value: isPressed)
    }
}

extension View {
    func pressEffect(_ isPressed: Bool) -> some View {
        modifier(PressEffect(isPressed: isPressed))
    }
}

// MARK: - Chips

/// A filter/segment chip. Selected: white fill, black text. Unselected: surface
/// fill, secondary text. Fires the selection haptic itself.
struct Chip: View {
    let title: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            guard !isSelected else { return }
            Haptics.selection()
            action()
        } label: {
            Text(title)
                .font(.caption13)
                .foregroundStyle(isSelected ? Color.inverseText : Color.textSecondary)
                .padding(.horizontal, Space.s12)
                .frame(height: Metrics.chipHeight)
                .background {
                    if isSelected {
                        Capsule().fill(Color.inverseFill)
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                            .environment(\.colorScheme, .dark)
                    }
                }
        }
        .buttonStyle(.pressable)
        .animation(Motion.standard, value: isSelected)
    }
}

/// A plain-text segment: selected is white text on an elevated capsule.
struct Segment: View {
    let title: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            guard !isSelected else { return }
            Haptics.selection()
            action()
        } label: {
            Text(title)
                .font(.caption13)
                .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.chipHeight)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    }
                }
        }
        .buttonStyle(.pressable)
        .animation(Motion.standard, value: isSelected)
    }
}

// MARK: - Layout pieces

/// 20 semibold, sentence case, on the screen margin.
struct SectionHeader: View {
    let title: String
    var caption: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.sectionHeader)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            if let caption {
                Text(caption)
                    .font(.caption13)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// The standard 68pt row: 40pt leading view, title over subtitle, and an optional
/// right-aligned value over sub-value.
struct ListRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Metrics.avatarGap) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.rowTitle)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.rowSubvalue)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.s8)
            VStack(alignment: .trailing, spacing: 2) {
                trailing
            }
        }
        .frame(minHeight: Metrics.rowHeight)
        .contentShape(Rectangle())
    }
}

extension View {
    /// Puts a stack of rows on one glass card, inset from its edges.
    func glassList() -> some View {
        padding(.horizontal, Space.s16)
            .padding(.vertical, Space.s4)
            .glassCard()
    }
}

/// A hairline between rows, inset to start under the row's text (past the avatar).
struct RowSeparator: View {
    var leadingInset: CGFloat = Metrics.avatar + Metrics.avatarGap

    var body: some View {
        Rectangle()
            .fill(Color.appSeparator)
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}

struct StatItem: Identifiable {
    let label: String
    let value: String
    var color: Color = .textPrimary
    /// A small icon tile beside the label, when set.
    var symbol: String? = nil
    var tint: Color = .tileBlue
    var id: String { label }
}

/// Two columns of label (13 secondary) over value (17 semibold) on a neutral card.
struct StatGrid: View {
    let items: [StatItem]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Space.s16, alignment: .leading), GridItem(.flexible(), spacing: Space.s16, alignment: .leading)],
            alignment: .leading,
            spacing: Space.s20
        ) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: Space.s4) {
                    HStack(spacing: Space.s8) {
                        if let symbol = item.symbol {
                            IconTile(symbol: symbol, color: item.tint, size: 22)
                        }
                        Text(item.label)
                            .font(.caption13)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Text(item.value)
                        .font(.rowValue)
                        .foregroundStyle(item.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Space.s16)
        .glassCard()
    }
}

/// "Paper · Simulated" — the disclosure the backend requires on paper stats, as a
/// quiet caption rather than a badge.
struct SimulatedCaption: View {
    var body: some View {
        Text("Paper · Simulated")
            .font(.caption13)
            .foregroundStyle(Color.textTertiary)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let detail: String
    /// An error state's way out: shows a compact "Try again" button when set.
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Space.s8) {
            IconTile(symbol: symbol, color: .tileGray, size: 52)
                .padding(.bottom, Space.s8)
            Text(title)
                .font(.rowTitle)
                .foregroundStyle(Color.textPrimary)
            Text(detail)
                .font(.rowSubtitle)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try again") {
                    Haptics.tap()
                    retry()
                }
                .buttonStyle(.compact)
                .padding(.top, Space.s8)
                .accessibilityIdentifier("emptyState.retry")
            }
        }
        .padding(.vertical, Space.s48)
        .padding(.horizontal, Space.s24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Loading placeholders

/// A neutral placeholder block with a slow opacity pulse (static under Reduce
/// Motion).
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.appSurfaceElevated)
            .frame(width: width, height: height)
            .opacity(dim ? 0.5 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

/// Shaped like a `ListRow`, so the swap to real content doesn't reflow.
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: Metrics.avatarGap) {
            SkeletonBlock(width: Metrics.avatar, height: Metrics.avatar, cornerRadius: Metrics.avatar / 2)
            VStack(alignment: .leading, spacing: Space.s8) {
                SkeletonBlock(width: 96, height: 14)
                SkeletonBlock(width: 64, height: 12)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Space.s8) {
                SkeletonBlock(width: 72, height: 14)
                SkeletonBlock(width: 48, height: 12)
            }
        }
        .frame(height: Metrics.rowHeight)
    }
}

// MARK: - Floating tab bar clearance

extension EnvironmentValues {
    /// Height the app shell's floating tab bar occupies at the bottom edge. Set on
    /// each tab's NavigationStack, so it also reaches every pushed screen.
    @Entry var tabBarInset: CGFloat = 0
}

private struct ReservesTabBarSpace: ViewModifier {
    @Environment(\.tabBarInset) private var inset

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: inset)
        }
    }
}

extension View {
    /// Keeps a screen's content and pinned bars clear of the floating tab bar.
    /// Apply outermost, after the screen's own bottom insets.
    func reservesTabBarSpace() -> some View {
        modifier(ReservesTabBarSpace())
    }
}
