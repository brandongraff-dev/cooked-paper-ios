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

    /// Permanently deletes the account and its paper data (App Store 5.1.1(v)).
    static func deleteAccount() async throws {
        try await APIClient.shared.sendIgnoringResponse(Endpoint(path: "/auth/account", method: "DELETE"))
    }
}
