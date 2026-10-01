import Foundation

struct PublicUser: Decodable {
    let id: String
    let username: String
    let displayName: String?
    /// Null for accounts that never linked a wallet — every account in this app.
    let walletAddress: String?
    let foundingMember: Bool?
    /// Seeds the gradient behind the avatar monogram (`ProfileAvatar`). Optional
    /// here, and below, so an older server's user still decodes.
    let avatarSeed: String?
    /// ISO8601; "Joined <Month Year>" on the profile.
    let createdAt: String?
    let verified: Bool?
    let referralCode: String?
}

/// `GET /auth/me` and `PATCH /auth/me`.
struct UserResponse: Decodable {
    let user: PublicUser
}

/// `PATCH /auth/me`. A nil field is left out of the JSON and so left unchanged on
/// the server; an empty `displayName` clears it.
struct UpdateProfileBody: Encodable {
    let username: String?
    let displayName: String?
}

/// `GET /auth/username-available`. `reason` is "invalid", "taken" or "reserved"
/// when `available` is false; `message` is the server's sentence for it.
struct UsernameAvailability: Decodable {
    let available: Bool
    let reason: String?
    let message: String?
}

/// Every session-minting response (`/auth/google`, `/auth/apple`, `/auth/refresh`). `refreshToken` is in the body because the
/// app sends `X-Cooked-Client: ios`; web gets it as an httpOnly cookie instead.
struct SessionResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let user: PublicUser
    let refreshToken: String?
    let refreshExpiresAt: String?
    /// True only on the `/auth/apple` or `/auth/google` sign-in that created the
    /// account, which is what shows `ProfileSetupView`. Absent on refreshes.
    let isNewAccount: Bool?
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
    /// Apple's one-time authorization code, UTF-8. The server exchanges it for an
    /// Apple refresh token so it can revoke Apple's grant when the account is
    /// deleted (App Store 5.1.1(v)).
    let authorizationCode: String?
}

struct RefreshBody: Encodable {
    let refreshToken: String
}
