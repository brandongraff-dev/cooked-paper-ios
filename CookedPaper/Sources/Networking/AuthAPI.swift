import Foundation

/// Every login method this app offers (email OTP, Sign in with Apple, Google) goes
/// through Privy first and then converges on ONE backend call, `/auth/embedded/verify`
/// — Google and Apple both resolve to a Privy access token + Privy-minted embedded
/// Solana wallet the same as email does, so there is no separate `/auth/google` path
/// to wire here. See `Auth/PrivyClient.swift` for the piece that gets a provider
/// token and a signature in the first place.
enum AuthAPI {
    /// Step one of proving control of the embedded wallet's address — the exact same
    /// SIWS challenge an external wallet would sign (`WalletProof` in
    /// `packages/embedded-wallet/src/contract.ts` is deliberately the same shape and
    /// the same verifier as the external-wallet path).
    static func nonce(address: String) async throws -> NonceResponse {
        try await APIClient.shared.send(
            Endpoint(
                path: "/auth/nonce",
                method: "POST",
                body: APIClient.shared.encode(["address": address]),
                attachToken: false
            ),
            as: NonceResponse.self
        )
    }

    static func embeddedVerify(
        providerToken: String,
        message: String,
        signature: String,
        username: String?
    ) async throws -> SessionResponse {
        var body: [String: String] = [
            "providerToken": providerToken,
            "message": message,
            "signature": signature,
        ]
        body["username"] = username

        return try await APIClient.shared.send(
            Endpoint(
                path: "/auth/embedded/verify",
                method: "POST",
                body: APIClient.shared.encode(body),
                attachToken: false
            ),
            as: SessionResponse.self
        )
    }

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

    static func me() async throws -> PublicUser {
        struct Response: Decodable { let user: PublicUser }
        return try await APIClient.shared.send(Endpoint(path: "/auth/me"), as: Response.self).user
    }

    static func logout() async throws {
        try await APIClient.shared.sendIgnoringResponse(Endpoint(path: "/auth/logout", method: "POST"))
    }

    /// Moves every non-expired portfolio under a just-minted guest session onto the
    /// now-signed-in real account, history intact. Must be called with the REAL
    /// access token already active in `SessionStore` (this endpoint is `auth:
    /// 'bearer'`, the one paper route that refuses a guest token as the caller).
    static func claimGuestPortfolios(guestToken: String) async throws -> ClaimGuestPortfoliosResponse {
        try await APIClient.shared.send(
            Endpoint(
                path: "/paper/portfolios/claim",
                method: "POST",
                body: APIClient.shared.encode(["guestToken": guestToken])
            ),
            as: ClaimGuestPortfoliosResponse.self
        )
    }
}
