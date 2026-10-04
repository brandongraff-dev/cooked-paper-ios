import SwiftUI

/// The unlock celebration: a compact card that drops in from the top edge over
/// whatever screen is showing, with the medallion giving one soft bounce. The
/// success haptic fires from `AchievementCenter` on the same frame it appears.
/// Under Reduce Motion it fades in place and the medallion holds still. Tap opens
/// the achievements grid; swipe up (or wait ~4 seconds) dismisses it.
struct AchievementToastHost: View {
    private let center = AchievementCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let achievement = center.celebrating {
                AchievementToast(achievement: achievement, animatesIcon: !reduceMotion) {
                    center.dismissCurrent()
                    DeepLinkRouter.shared.openAchievements()
                } onDismiss: {
                    center.dismissCurrent()
                }
                .id(achievement.id)
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? Animation.easeInOut(duration: 0.2) : Motion.standard, value: center.celebrating?.id)
    }
}

private struct AchievementToast: View {
    let achievement: Achievement
    let animatesIcon: Bool
    let onOpen: () -> Void
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        Button {
            Haptics.tap()
            onOpen()
        } label: {
            HStack(spacing: Space.s12) {
                AchievementBadge(achievement: achievement, size: 44)
                    .scaleEffect(appeared || !animatesIcon ? 1 : 0.6)
                    .symbolEffect(.bounce, value: appeared && animatesIcon)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Achievement unlocked")
                        .font(.caption13)
                        .foregroundStyle(achievement.tierKind.color)
                    Text(achievement.title)
                        .font(.rowTitle)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(achievement.description)
                        .font(.rowSubtitle)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s8)
                Image(systemName: "chevron.right")
                    .font(.caption13)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(Space.s12)
            .padding(.trailing, Space.s4)
            .background(Color.appSurfaceElevated, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(achievement.tierKind.color.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s4)
        .offset(y: min(0, dragOffset))
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in dragOffset = value.translation.height }
                .onEnded { value in
                    if value.translation.height < -24 {
                        onDismiss()
                    } else {
                        withAnimation(Motion.standard) { dragOffset = 0 }
                    }
                }
        )
        .onAppear {
            withAnimation(animatesIcon ? Motion.standard.delay(0.1) : nil) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Achievement unlocked: \(achievement.title). \(achievement.description)")
        .accessibilityHint("Opens your achievements")
        .accessibilityIdentifier("achievement.toast")
    }
}
