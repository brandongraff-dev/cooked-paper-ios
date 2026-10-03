import Foundation

/// Server-side validation of App Store subscriptions (`auth: 'bearer'`). Additive
/// to StoreKit: a 404 (backend not deployed yet) or any network failure leaves the
/// paywall to StoreKit alone — see `SubscriptionStore.syncWithServer`.
enum BillingAPI {
    static func submitAppleTransaction(_ signedTransaction: String) async throws -> AppleEntitlement {
        try await APIClient.shared.send(
            Endpoint(
                path: "/billing/apple/transactions",
                method: "POST",
                body: APIClient.shared.encode(AppleTransactionBody(signedTransaction: signedTransaction))
            ),
            as: AppleEntitlementResponse.self
        ).entitlement
    }

    static func appleEntitlement() async throws -> AppleEntitlement {
        try await APIClient.shared.send(
            Endpoint(path: "/billing/apple/entitlement"),
            as: AppleEntitlementResponse.self
        ).entitlement
    }
}
