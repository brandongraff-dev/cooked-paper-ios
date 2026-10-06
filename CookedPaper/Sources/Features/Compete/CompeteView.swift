import SwiftUI

/// The Compete tab: this month's season, head-to-head duels, friend leagues and
/// the existing paper leaderboard, behind one segmented control.
struct CompeteView: View {
    @State private var section: CompeteSection = .season

    var body: some View {
        Group {
            switch section {
            case .season: SeasonView()
            case .duels: DuelsView()
            case .leagues: LeaguesView()
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
    case season, duels, leagues, leaderboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .season: "Season"
        case .duels: "Duels"
        case .leagues: "Leagues"
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
    case league(id: String)
    case recap
    case challenges
    case rooms
    case room(id: String)
    case squads
    case squad(id: String)

    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .achievements: AchievementsView()
        case .seasonHistory: SeasonHistoryView()
        case .seasonResults(let id, let label): SeasonResultsView(seasonId: id, label: label)
        case .duel(let id): DuelDetailView(duelId: id)
        case .league(let id): LeagueDetailView(leagueId: id, initial: LeaguesStore.shared.leagues?.first { $0.id == id })
        case .recap: RecapView()
        case .challenges: ChallengesView()
        case .rooms: RoomsView()
        case .room(let id): RoomDetailView(roomId: id)
        case .squads: SquadsView()
        case .squad(let id): SquadDetailView(squadId: id)
        }
    }
}
