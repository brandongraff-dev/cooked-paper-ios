import SwiftUI

/// The Compete tab: this month's season, head-to-head duels, and the existing
/// paper leaderboard, behind one segmented control.
struct CompeteView: View {
    @State private var section: CompeteSection = .season

    var body: some View {
        Group {
            switch section {
            case .season: SeasonView()
            case .duels: DuelsView()
            case .leaderboard: LeaderboardView(title: "Compete")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { picker }
        .background(Color.appBackground)
        .navigationTitle("Compete")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: CompeteRoute.self) { route in
            route.destination
        }
    }

    private var picker: some View {
        HStack(spacing: Space.s4) {
            ForEach(CompeteSection.allCases) { option in
                Segment(title: option.title, isSelected: section == option) {
                    withAnimation(Motion.standard) { section = option }
                }
                .accessibilityIdentifier("compete.segment.\(option.rawValue)")
                .accessibilityAddTraits(section == option ? .isSelected : [])
            }
        }
        .padding(Space.s4)
        .background(Color.appSurface, in: Capsule())
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s8)
        .background(Color.appBackground)
    }
}

enum CompeteSection: String, CaseIterable, Identifiable {
    case season, duels, leaderboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .season: "Season"
        case .duels: "Duels"
        case .leaderboard: "Leaderboard"
        }
    }
}

/// Screens pushed inside the Compete tab. `nonisolated` so its `Hashable`
/// conformance is usable from SwiftUI's navigation generics.
nonisolated enum CompeteRoute: Hashable {
    case achievements
    case seasonHistory
    case seasonResults(id: String, label: String)
    case duel(id: String)

    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .achievements: AchievementsView()
        case .seasonHistory: SeasonHistoryView()
        case .seasonResults(let id, let label): SeasonResultsView(seasonId: id, label: label)
        case .duel(let id): DuelDetailView(duelId: id)
        }
    }
}
