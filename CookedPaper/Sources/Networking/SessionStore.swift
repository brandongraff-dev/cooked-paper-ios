import Foundation
import Observation

/// The app's one identity slot. `apps/api/src/paper/caller.ts` accepts a real access
/// JWT and a guest JWT through the exact same `Authorization: Bearer <token>` header —
/// it tries the real-user verifier first and falls back to the guest verifier, since
/// the two use disjoint signing audiences. So the client only ever needs to hold ONE
/// token: minted as a guest on first launch, and swapped in place for a real access
/// token the moment the user links an account — every other piece of state (active
/// portfolio id, whether the account is linked) hangs off that one swap.
@Observable
@MainActor
final class SessionStore {
    private enum Keys {
        static let token = "session.token"
        static let isGuest = "session.isGuest"
        static let portfolioId = "session.portfolioId"
        static let username = "session.username"
        static let userId = "session.userId"
    }

    private(set) var token: String?
    private(set) var isGuest: Bool = true
    private(set) var activePortfolioId: String?
    private(set) var username: String?
    private(set) var userId: String?

    static let shared = SessionStore()

    private init() {
        token = KeychainStore.get(Keys.token)
        isGuest = UserDefaults.standard.object(forKey: Keys.isGuest) as? Bool ?? true
        activePortfolioId = UserDefaults.standard.string(forKey: Keys.portfolioId)
        username = UserDefaults.standard.string(forKey: Keys.username)
        userId = UserDefaults.standard.string(forKey: Keys.userId)
    }

    var isSignedIn: Bool { token != nil }

    /// A brand-new guest session was minted (`POST /paper/portfolios/starter` or
    /// `POST /paper/portfolios` returned a non-null `guestToken`). Overwrites any
    /// prior guest token — the caller is responsible for not doing this when a real
    /// account is already linked (`isGuest == false`).
    func adoptGuestToken(_ token: String) {
        self.token = token
        isGuest = true
        KeychainStore.set(token, for: Keys.token)
        UserDefaults.standard.set(true, forKey: Keys.isGuest)
    }

    /// A real sign-in (or the post-claim response) replaced the guest token with a
    /// real access token. The guest token itself is discarded — everything it owned
    /// now belongs to this account server-side, via `POST /paper/portfolios/claim`.
    func adoptRealAccount(accessToken: String, userId: String, username: String) {
        token = accessToken
        isGuest = false
        self.userId = userId
        self.username = username
        KeychainStore.set(accessToken, for: Keys.token)
        UserDefaults.standard.set(false, forKey: Keys.isGuest)
        UserDefaults.standard.set(userId, forKey: Keys.userId)
        UserDefaults.standard.set(username, forKey: Keys.username)
    }

    /// A refreshed real access token (from `POST /auth/refresh`) replaces the stored
    /// one in place — identity and portfolio are unchanged.
    func updateAccessToken(_ accessToken: String) {
        token = accessToken
        KeychainStore.set(accessToken, for: Keys.token)
    }

    func setActivePortfolio(_ id: String) {
        activePortfolioId = id
        UserDefaults.standard.set(id, forKey: Keys.portfolioId)
    }

    /// Full sign-out. The active portfolio id is intentionally cleared too — a signed
    /// out session has no identity to own it, and the next launch mints a fresh guest.
    func clear() {
        token = nil
        isGuest = true
        activePortfolioId = nil
        username = nil
        userId = nil
        KeychainStore.remove(Keys.token)
        UserDefaults.standard.removeObject(forKey: Keys.isGuest)
        UserDefaults.standard.removeObject(forKey: Keys.portfolioId)
        UserDefaults.standard.removeObject(forKey: Keys.username)
        UserDefaults.standard.removeObject(forKey: Keys.userId)
    }
}
