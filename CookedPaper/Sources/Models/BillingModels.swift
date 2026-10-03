import Foundation

/// The server's view of the account's App Store subscription, as returned by both
/// `POST /billing/apple/transactions` and `GET /billing/apple/entitlement`.
struct AppleEntitlement: Decodable {
    let active: Bool
    let productId: String?
    /// ISO 8601.
    let expiresAt: String?
    let willRenew: Bool?
    /// "Sandbox" or "Production".
    let environment: String?
}

struct AppleEntitlementResponse: Decodable {
    let entitlement: AppleEntitlement
}

/// `POST /billing/apple/transactions`: one StoreKit 2 transaction, exactly as
/// StoreKit signed it (`VerificationResult.jwsRepresentation`); the server verifies
/// Apple's signature itself.
struct AppleTransactionBody: Encodable {
    let signedTransaction: String
}
