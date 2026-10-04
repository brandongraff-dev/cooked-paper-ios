import Foundation
import Observation

/// The app's deep links, handed off from `CookedPaperApp`'s `.onOpenURL` (and from
/// tapped pushes via `AppDelegate`) and consumed by `AppShellView`'s sheet:
///
/// - `cookedpaper://token/<mint>` — a token's detail.
/// - `cookedpaper://duel/<code>` — an open duel invite: a confirm sheet, then
///   `POST /paper/duels/join`. `https://cooked.trade/d/<code>` is the same invite.
/// - `cookedpaper://duel-id/<id>` — one of the account's duels.
/// - `cookedpaper://achievements` — the achievements grid.
///
/// Foundation parses the two-segment form with the kind landing in `.host` and
/// "/<value>" in `.path`, so extraction reads those rather than
/// `.pathComponents[0]`.
@Observable
@MainActor
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    private(set) var pendingTokenMint: String?
    private(set) var pendingDuelInviteCode: String?
    private(set) var pendingDuelId: String?
    private(set) var showsAchievements = false

    private init() {}

    func handle(_ url: URL) {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()
        let value = url.pathComponents.first(where: { $0 != "/" })

        // The web invite link, should it ever be opened by the app.
        if scheme == "https", host == "cooked.trade" || host == "www.cooked.trade" {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count == 2, parts[0] == "d", !parts[1].isEmpty {
                open(duelInviteCode: parts[1])
            }
            return
        }

        guard scheme == "cookedpaper" else { return }
        switch host ?? "" {
        case "token":
            guard let mint = value, !mint.isEmpty else { return }
            clear()
            pendingTokenMint = mint
        case "duel":
            guard let code = value, !code.isEmpty else { return }
            open(duelInviteCode: code)
        case "duel-id":
            guard let id = value, !id.isEmpty else { return }
            openDuel(id: id)
        case "achievements":
            openAchievements()
        default:
            return
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
    }
}
