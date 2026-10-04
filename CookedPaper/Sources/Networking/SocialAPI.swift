import Foundation

/// Price alerts and push-device registration (`auth: 'bearer'` — a signed-in
/// account; every screen that calls these is behind sign-in).
enum SocialAPI {
    static func alerts() async throws -> [PriceAlert] {
        try await APIClient.shared.send(
            Endpoint(path: "/social/alerts"),
            as: PriceAlertListResponse.self
        ).alerts
    }

    static func createAlert(_ body: CreatePriceAlertBody) async throws -> PriceAlert {
        try await APIClient.shared.send(
            Endpoint(path: "/social/alerts", method: "POST", body: APIClient.shared.encode(body)),
            as: PriceAlertResponse.self
        ).alert
    }

    static func setAlertActive(id: String, isActive: Bool) async throws -> PriceAlert {
        try await APIClient.shared.send(
            Endpoint(path: "/social/alerts/\(id)", method: "PATCH", body: APIClient.shared.encode(UpdatePriceAlertBody(isActive: isActive))),
            as: PriceAlertResponse.self
        ).alert
    }

    static func deleteAlert(id: String) async throws {
        try await APIClient.shared.sendIgnoringResponse(
            Endpoint(path: "/social/alerts/\(id)", method: "DELETE")
        )
    }

    /// Re-registering an existing token moves it to the calling account.
    static func registerAPNsToken(_ deviceToken: String, environment: String) async throws {
        try await APIClient.shared.send(
            Endpoint(
                path: "/social/apns-tokens",
                method: "POST",
                body: APIClient.shared.encode(RegisterAPNsTokenBody(deviceToken: deviceToken, environment: environment))
            ),
            as: OKResponse.self
        )
    }

    static func revokeAPNsToken(_ deviceToken: String) async throws {
        try await APIClient.shared.send(
            Endpoint(
                path: "/social/apns-tokens/revoke",
                method: "POST",
                body: APIClient.shared.encode(RevokeAPNsTokenBody(deviceToken: deviceToken))
            ),
            as: OKResponse.self,
            // Sign-out is already underway; a stale token shouldn't trigger a
            // refresh round-trip just to say goodbye.
            retryingOnAuthFailure: false
        )
    }
}
