import SwiftUI

/// Every achievement in the catalog: unlocked ones in their tier color, locked ones
/// dimmed (with a progress bar when the server tracks progress). Tap for details
/// and, once unlocked, a share. Reached from Profile, from Compete's season page,
/// and from an unlock toast or push.
struct AchievementsView: View {
    private let center = AchievementCenter.shared
    @State private var selected: Achievement?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.s12, alignment: .top), count: 3)

    var body: some View {
        Group {
            if center.isLoading && center.response == nil {
                skeleton
            } else if center.isUnavailable {
                EmptyStateView(
                    symbol: "rosette",
                    title: "Achievements are on the way",
                    detail: "Milestones for your trades and duels will show up here soon."
                )
            } else if center.response == nil, let error = center.errorMessage {
                EmptyStateView(symbol: "wifi.slash", title: "Couldn't load achievements", detail: error) {
                    Task { await center.load() }
                }
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground)
        .reservesTabBarSpace()
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .task { await center.load() }
        .sheet(item: $selected) { achievement in
            AchievementDetailSheet(achievement: achievement)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s24) {
                summary
                LazyVGrid(columns: columns, spacing: Space.s20) {
                    ForEach(center.achievements) { achievement in
                        Button {
                            Haptics.tap()
                            selected = achievement
                        } label: {
                            AchievementCell(achievement: achievement)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityIdentifier("achievements.cell.\(achievement.id)")
                    }
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s8)
            .padding(.bottom, Space.section)
        }
        .scrollIndicators(.hidden)
        .refreshable { await center.load() }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(center.unlockedCount) of \(center.total)")
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                Text("unlocked")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
            ProgressTrack(fraction: center.total > 0 ? Double(center.unlockedCount) / Double(center.total) : 0)
        }
        .padding(Space.s16)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Space.s24) {
            SkeletonBlock(height: 72, cornerRadius: Radius.card)
            LazyVGrid(columns: columns, spacing: Space.s20) {
                ForEach(0..<9, id: \.self) { _ in
                    VStack(spacing: Space.s8) {
                        SkeletonBlock(width: 64, height: 64, cornerRadius: 32)
                        SkeletonBlock(width: 72, height: 12)
                    }
                }
            }
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s8)
    }
}

private struct AchievementCell: View {
    let achievement: Achievement

    var body: some View {
        VStack(spacing: Space.s8) {
            AchievementBadge(achievement: achievement)
            Text(achievement.title)
                .font(.caption13)
                .foregroundStyle(achievement.unlocked ? Color.textPrimary : Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !achievement.unlocked, let progress = achievement.progress {
                ProgressTrack(fraction: progress.fraction, tint: .textSecondary, height: 4)
                    .frame(width: 56)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if achievement.unlocked { return "\(achievement.title), unlocked" }
        if let progress = achievement.progress {
            return "\(achievement.title), locked, \(AchievementDetailSheet.progressText(progress))"
        }
        return "\(achievement.title), locked"
    }
}

/// One achievement up close: the medallion, what it takes, when it was unlocked
/// (or how close you are), and a share once it's yours.
struct AchievementDetailSheet: View {
    let achievement: Achievement
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.s24) {
                Spacer(minLength: Space.s8)
                AchievementBadge(achievement: achievement, size: 104)
                VStack(spacing: Space.s8) {
                    Text(achievement.tierKind.title.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(achievement.unlocked ? achievement.tierKind.color : Color.textTertiary)
                    Text(achievement.title)
                        .font(.appLargeTitle)
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(achievement.description)
                        .font(.rowSubtitle)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                status
                Spacer(minLength: 0)
                if achievement.unlocked {
                    ShareLink(item: "I unlocked \(achievement.title) on Cooked") {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("achievement.share")
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.s8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appSurfaceElevated)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(Color.appSurfaceElevated)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var status: some View {
        if achievement.unlocked {
            Text(unlockedLine)
                .font(.caption13)
                .foregroundStyle(Color.textTertiary)
        } else if let progress = achievement.progress {
            VStack(spacing: Space.s8) {
                ProgressTrack(fraction: progress.fraction)
                    .frame(maxWidth: 220)
                Text(Self.progressText(progress))
                    .font(.caption13Digits)
                    .foregroundStyle(Color.textSecondary)
            }
        } else {
            Text("Locked")
                .font(.caption13)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var unlockedLine: String {
        guard let raw = achievement.unlockedAt, let date = CompeteDate.parse(raw) else { return "Unlocked" }
        return "Unlocked \(date.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    /// "3 of 5".
    static func progressText(_ progress: AchievementProgress) -> String {
        let current = progress.current.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
        let target = progress.target.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
        return "\(current) of \(target)"
    }
}
