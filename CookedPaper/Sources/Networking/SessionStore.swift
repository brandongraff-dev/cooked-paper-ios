import Foundation
import Observation

/// The signed-in account. Everyone signs in (Apple, Google or phone) before trading;
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
        static let userId = "session.userId"
        static let method = "session.method"
        static let legacyIsGuest = "session.isGuest"
    }

    private(set) var token: String?
    private(set) var refreshToken: String?
    private(set) var activePortfolioId: String?
    private(set) var username: String?
    private(set) var userId: String?
    /// How the person signed in ("apple", "google", "phone"), for Settings.
    private(set) var method: String?

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
        userId = UserDefaults.standard.string(forKey: Keys.userId)
        method = UserDefaults.standard.string(forKey: Keys.method)
    }

    var isSignedIn: Bool { token != nil }

    /// A sign-in (any method) minted a session.
    func signIn(_ session: SessionResponse, method: String) {
        adopt(session)
        self.method = method
        userId = session.user.id
        username = session.user.username
        UserDefaults.standard.set(method, forKey: Keys.method)
        UserDefaults.standard.set(session.user.id, forKey: Keys.userId)
        UserDefaults.standard.set(session.user.username, forKey: Keys.username)
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
        userId = nil
        method = nil
        KeychainStore.remove(Keys.token)
        KeychainStore.remove(Keys.refreshToken)
        for key in [Keys.portfolioId, Keys.username, Keys.userId, Keys.method] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
