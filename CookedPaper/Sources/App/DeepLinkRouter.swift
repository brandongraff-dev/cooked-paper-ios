import Foundation
import Observation

/// One parsed deep link: what `DeepLinkRouter.handle` opens. Kept apart from the
/// router so the URL parsing is testable without touching the shared router.
///
/// - `cookedpaper://token/<mint>` — a token's detail.
/// - `cookedpaper://duel/<code>` — an open duel invite: a confirm sheet, then
///   `POST /paper/duels/join`.
/// - `cookedpaper://duel-id/<id>` — one of the account's duels.
/// - `cookedpaper://league/<code>` — a friend-league invite: a join sheet with the
///   code filled in.
/// - `cookedpaper://league-id/<id>` — one of the account's leagues.
/// - `cookedpaper://achievements` — the achievements grid.
/// - `https://cooked.trade/d/<code>` and `https://cooked.trade/l/<code>` (also on
///   `www.`) — the web invite links, the same invites as `duel/<code>` and
///   `league/<code>`. They reach the app as universal links (the Associated Domains
///   entitlement in project.yml, matched by the site's
///   `/.well-known/apple-app-site-association`), which SwiftUI delivers through
///   `.onOpenURL` like the custom scheme.
///
/// Foundation parses the two-segment custom-scheme form with the kind landing in
/// `.host` and "/<value>" in `.path`, so extraction reads those rather than
/// `.pathComponents[0]`.
enum DeepLink: Equatable {
    case token(mint: String)
    case duelInvite(code: String)
    case duel(id: String)
    case leagueInvite(code: String)
    case league(id: String)
    case achievements

    /// The hosts serving the web invite pages (the apex redirects to www).
    static let webHosts: Set<String> = ["cooked.trade", "www.cooked.trade"]

    /// Nil for anything the app doesn't open.
    static func parse(_ url: URL) -> DeepLink? {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()
        let parts = url.pathComponents.filter { $0 != "/" }

        if scheme == "https" {
            guard let host = host, webHosts.contains(host) else { return nil }
            guard parts.count == 2, !parts[1].isEmpty else { return nil }
            switch parts[0] {
            case "d": return .duelInvite(code: parts[1])
            case "l": return .leagueInvite(code: parts[1])
            default: return nil
            }
        }

        guard scheme == "cookedpaper" else { return nil }
        let value = parts.first ?? ""
        switch host ?? "" {
        case "token": return value.isEmpty ? nil : .token(mint: value)
        case "duel": return value.isEmpty ? nil : .duelInvite(code: value)
        case "duel-id": return value.isEmpty ? nil : .duel(id: value)
        case "league": return value.isEmpty ? nil : .leagueInvite(code: value)
        case "league-id": return value.isEmpty ? nil : .league(id: value)
        case "achievements": return .achievements
        default: return nil
        }
    }
}

/// The app's deep links (see `DeepLink`), handed off from `CookedPaperApp`'s
/// `.onOpenURL` (and from tapped pushes via `AppDelegate`) and consumed by
/// `AppShellView`'s sheet.
@Observable
@MainActor
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    private(set) var pendingTokenMint: String?
    private(set) var pendingDuelInviteCode: String?
    private(set) var pendingDuelId: String?
    private(set) var showsAchievements = false
    private(set) var pendingLeagueInviteCode: String?
    private(set) var pendingLeagueId: String?
    /// A tab a screen asked to switch to ("Make your first trade" → Discover).
    /// `AppShellView` selects it and clears it.
    private(set) var requestedTab: AppTab?

    private init() {}

    /// Switches the app to `tab`, from a screen inside another tab.
    func openTab(_ tab: AppTab) {
        requestedTab = tab
    }

    func clearTabRequest() {
        requestedTab = nil
    }

    func handle(_ url: URL) {
        guard let link = DeepLink.parse(url) else { return }
        switch link {
        case .token(let mint):
            clear()
            pendingTokenMint = mint
        case .duelInvite(let code):
            open(duelInviteCode: code)
        case .duel(let id):
            openDuel(id: id)
        case .leagueInvite(let code):
            open(leagueInviteCode: code)
        case .league(let id):
            openLeague(id: id)
        case .achievements:
            openAchievements()
        }
    }

    /// Opens a token's detail sheet from inside the app (a tapped price-alert
    /// notification) through the same `cookedpaper://token/<mint>` handling.
    func openToken(mint: String) {
        guard let url = URL(string: "cookedpaper://token/\(mint)") else { return }
        handle(url)
    }

    /// A tapped duel push (`duelId`), or a duel link.
    func openDuel(id: String) {
        clear()
        pendingDuelId = id
    }

    func open(duelInviteCode code: String) {
        clear()
        pendingDuelInviteCode = code
    }

    func open(leagueInviteCode code: String) {
        clear()
        pendingLeagueInviteCode = code
    }

    /// A tapped league push (`leagueId`), or a league link.
    func openLeague(id: String) {
        clear()
        pendingLeagueId = id
    }

    /// A tapped achievement push (`achievementId`), or the toast.
    func openAchievements() {
        clear()
        showsAchievements = true
    }

    func clear() {
        pendingTokenMint = nil
        pendingDuelInviteCode = nil
        pendingDuelId = nil
        showsAchievements = false
        pendingLeagueInviteCode = nil
        pendingLeagueId = nil
    }
}
