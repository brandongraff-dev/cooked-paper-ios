import Foundation

/// Sign-in with Apple or Google, both ending in the same session
/// shape. Each provider proves identity to the server; the server mints the session.
enum AuthAPI {
    static func googleNonce() async throws -> AuthNonceResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/auth/google/nonce", method: "POST", attachToken: false),
            as: AuthNonceResponse.self
        )
    }

    static func google(idToken: String) async throws -> SessionResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/auth/google", method: "POST", body: APIClient.shared.encode(GoogleSignInBody(idToken: idToken)), attachToken: false),
            as: SessionResponse.self,
            retryingOnAuthFailure: false
        )
    }

    static func appleNonce() async throws -> AuthNonceResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/auth/apple/nonce", method: "POST", attachToken: false),
            as: AuthNonceResponse.self
        )
    }

    static func apple(_ body: AppleSignInBody) async throws -> SessionResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/auth/apple", method: "POST", body: APIClient.shared.encode(body), attachToken: false),
            as: SessionResponse.self,
            retryingOnAuthFailure: false
        )
    }

    /// Trades the stored refresh token for a new session. `retryingOnAuthFailure:
    /// false` is load-bearing — a refresh that itself 401s must not recurse.
    static func refresh(refreshToken: String) async throws -> SessionResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/auth/refresh", method: "POST", body: APIClient.shared.encode(RefreshBody(refreshToken: refreshToken)), attachToken: false),
            as: SessionResponse.self,
            retryingOnAuthFailure: false
        )
    }

    static func logout(refreshToken: String?) async {
        let body = refreshToken.map { APIClient.shared.encode(RefreshBody(refreshToken: $0)) }
        _ = try? await APIClient.shared.send(
            Endpoint(path: "/auth/logout", method: "POST", body: body),
            as: EmptyResponse.self,
            retryingOnAuthFailure: false
        )
    }

    /// The signed-in account, fresh from the server.
    static func me() async throws -> PublicUser {
        try await APIClient.shared.send(Endpoint(path: "/auth/me"), as: UserResponse.self).user
    }

    /// Changes the handle and/or display name. Pass nil to leave one as it is, and
    /// an empty display name to clear it. A bad or taken handle comes back as an
    /// `APIError` with reason `username_invalid` / `username_taken`.
    static func updateProfile(username: String?, displayName: String?) async throws -> PublicUser {
        try await APIClient.shared.send(
            Endpoint(
                path: "/auth/me",
                method: "PATCH",
                body: APIClient.shared.encode(UpdateProfileBody(username: username, displayName: displayName))
            ),
            as: UserResponse.self
        ).user
    }

    /// Live feedback while someone types a handle; `PATCH /auth/me` re-checks on save.
    static func usernameAvailable(_ username: String) async throws -> UsernameAvailability {
        try await APIClient.shared.send(
            Endpoint(path: "/auth/username-available", query: ["username": username]),
            as: UsernameAvailability.self
        )
    }

    /// Permanently deletes the account and its paper data (App Store 5.1.1(v)).
    static func deleteAccount() async throws {
        try await APIClient.shared.sendIgnoringResponse(Endpoint(path: "/auth/account", method: "DELETE"))
    }
}
