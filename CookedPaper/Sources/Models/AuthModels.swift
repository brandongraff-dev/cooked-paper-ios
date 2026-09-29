import Foundation

struct PublicUser: Decodable {
    let id: String
    let username: String
    let displayName: String?
    /// Null for accounts that never linked a wallet — every account in this app.
    let walletAddress: String?
    let foundingMember: Bool?
}

/// Every session-minting response (`/auth/google`, `/auth/apple`, `/auth/refresh`). `refreshToken` is in the body because the
/// app sends `X-Cooked-Client: ios`; web gets it as an httpOnly cookie instead.
struct SessionResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let user: PublicUser
    let refreshToken: String?
    let refreshExpiresAt: String?
}

struct AuthNonceResponse: Decodable {
    let nonce: String
    let expiresAt: String
}

struct GoogleSignInBody: Encodable {
    let idToken: String
}

struct AppleSignInBody: Encodable {
    struct FullName: Encodable {
        let givenName: String?
        let familyName: String?
    }
    let identityToken: String
    let nonce: String
    let fullName: FullName?
}

struct RefreshBody: Encodable {
    let refreshToken: String
}
