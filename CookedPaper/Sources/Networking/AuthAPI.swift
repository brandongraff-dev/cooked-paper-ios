import Foundation

/// The app runs on guest paper sessions only (minted by `POST /paper/portfolios/
/// starter`); there is no sign-in flow. `refresh` stays for a session that was
/// created as a real account before sign-in was removed, so its token can still
/// be renewed by `APIClient`'s one-shot 401 retry.
enum AuthAPI {
    /// Trades the httpOnly refresh cookie (already in `URLSession`'s shared cookie
    /// jar) for a new access token. `retryingOnAuthFailure: false` on the inner call
    /// is load-bearing — without it, a refresh that itself 401s would recurse into
    /// this same function forever.
    static func refresh() async throws -> SessionResponse {
        try await APIClient.shared.send(
            Endpoint(path: "/auth/refresh", method: "POST", attachToken: false),
            as: SessionResponse.self,
            retryingOnAuthFailure: false
        )
    }
}
