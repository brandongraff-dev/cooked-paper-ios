import Foundation
import Observation

/// The signed-in account. Everyone signs in (Apple or Google) before trading;
/// there are no guest sessions. The access token is short-lived; the refresh token
/// (returned in the body because every request carries `X-Cooked-Client: ios`) lives
/// in the Keychain and is traded for a new access token on a 401 by `APIClient`.
@Observable
@MainActor
final class SessionStore {
    private enum Keys {
        static let token = "session.token"
        static let refreshToken = "session.refreshToken"
        static let portfolioId = "session.portfolioId"
        static let username = "session.username"
        static let displayName = "session.displayName"
        static let avatarSeed = "session.avatarSeed"
        static let needsProfileSetup = "session.needsProfileSetup"
        static let userId = "session.userId"
        static let method = "session.method"
        static let legacyIsGuest = "session.isGuest"
    }

    private(set) var token: String?
    private(set) var refreshToken: String?
    private(set) var activePortfolioId: String?
    private(set) var username: String?
    /// Optional on the account; when nil, screens show `username` instead.
    private(set) var displayName: String?
    private(set) var avatarSeed: String?
    private(set) var userId: String?
    /// How the person signed in ("apple" or "google"), for Settings.
    private(set) var method: String?
    /// The sign-in that created this account hasn't been through
    /// `ProfileSetupView` yet. Persisted, so quitting mid-setup still shows it once.
    private(set) var needsProfileSetup = false

    static let shared = SessionStore()

    private init() {
        // A token left over from the old guest-session build is not an account.
        if UserDefaults.standard.object(forKey: Keys.legacyIsGuest) as? Bool == true {
            KeychainStore.remove(Keys.token)
            UserDefaults.standard.removeObject(forKey: Keys.legacyIsGuest)
            UserDefaults.standard.removeObject(forKey: Keys.portfolioId)
        }
        token = KeychainStore.get(Keys.token)
        refreshToken = KeychainStore.get(Keys.refreshToken)
        activePortfolioId = UserDefaults.standard.string(forKey: Keys.portfolioId)
        username = UserDefaults.standard.string(forKey: Keys.username)
        displayName = UserDefaults.standard.string(forKey: Keys.displayName)
        avatarSeed = UserDefaults.standard.string(forKey: Keys.avatarSeed)
        needsProfileSetup = UserDefaults.standard.bool(forKey: Keys.needsProfileSetup)
        userId = UserDefaults.standard.string(forKey: Keys.userId)
        method = UserDefaults.standard.string(forKey: Keys.method)
    }

    var isSignedIn: Bool { token != nil }

    /// A sign-in (any method) minted a session.
    func signIn(_ session: SessionResponse, method: String) {
        adopt(session)
        self.method = method
        UserDefaults.standard.set(method, forKey: Keys.method)
        apply(session.user)
        needsProfileSetup = session.isNewAccount == true
        UserDefaults.standard.set(needsProfileSetup, forKey: Keys.needsProfileSetup)
    }

    /// The server's current view of the account (`GET`/`PATCH /auth/me`, or a
    /// sign-in): keeps the handle, display name and avatar seed every screen reads.
    func apply(_ user: PublicUser) {
        userId = user.id
        username = user.username
        displayName = user.displayName.flatMap { $0.isEmpty ? nil : $0 }
        avatarSeed = user.avatarSeed
        UserDefaults.standard.set(user.id, forKey: Keys.userId)
        UserDefaults.standard.set(user.username, forKey: Keys.username)
        UserDefaults.standard.set(displayName, forKey: Keys.displayName)
        UserDefaults.standard.set(avatarSeed, forKey: Keys.avatarSeed)
    }

    /// `ProfileSetupView` saved or was skipped; it doesn't come back.
    func finishProfileSetup() {
        needsProfileSetup = false
        UserDefaults.standard.removeObject(forKey: Keys.needsProfileSetup)
    }

    /// `POST /auth/refresh` rotated the session: new access token, and a new refresh
    /// token when the server sends one.
    func adopt(_ session: SessionResponse) {
        token = session.accessToken
        KeychainStore.set(session.accessToken, for: Keys.token)
        if let refresh = session.refreshToken {
            refreshToken = refresh
            KeychainStore.set(refresh, for: Keys.refreshToken)
        }
    }

    func setActivePortfolio(_ id: String) {
        activePortfolioId = id
        UserDefaults.standard.set(id, forKey: Keys.portfolioId)
    }

    /// Full sign-out: every credential and the portfolio pointer go.
    func clear() {
        token = nil
        refreshToken = nil
        activePortfolioId = nil
        username = nil
        displayName = nil
        avatarSeed = nil
        userId = nil
        method = nil
        needsProfileSetup = false
        KeychainStore.remove(Keys.token)
        KeychainStore.remove(Keys.refreshToken)
        for key in [
            Keys.portfolioId, Keys.username, Keys.displayName, Keys.avatarSeed,
            Keys.userId, Keys.method, Keys.needsProfileSetup,
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
