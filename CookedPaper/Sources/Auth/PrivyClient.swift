import Foundation
import PrivySDK
import os

/// Fill these in from the Privy Dashboard before this app can authenticate anyone —
/// see `apps/ios/README.md`. `appClientId` is required for native (non-web) apps.
enum PrivyConfiguration {
    static let appId = "REPLACE_WITH_PRIVY_APP_ID"
    static let appClientId = "REPLACE_WITH_PRIVY_APP_CLIENT_ID"
    /// Must also be registered as an allowed redirect scheme in the Privy Dashboard.
    static let redirectURLScheme = "cookedpaper"
}

enum PrivyAuthError: Error, LocalizedError {
    case noAuthenticatedUser
    case signatureEncodingFailed
    case accessTokenFailed(underlying: Error)
    case walletCreationFailed(underlying: Error)
    case challengeFailed(underlying: Error)
    case backendVerifyFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noAuthenticatedUser: "Sign-in didn't complete. Try again."
        case .signatureEncodingFailed: "Couldn't verify the wallet signature. Try again."
        case .accessTokenFailed: "Couldn't confirm your sign-in. Try again."
        case .walletCreationFailed: "Couldn't set up your wallet. Try again."
        case .challengeFailed: "Couldn't verify your wallet. Try again."
        case .backendVerifyFailed: "Couldn't finish signing in. Try again."
        }
    }
}

/// Wraps Privy's iOS SDK and the three-step dance apps/api's embedded-wallet auth
/// requires: (1) authenticate with Privy by whatever method, which mints a Privy
/// access token and — on this platform, unlike web, wallet creation is NOT automatic
/// — (2) get-or-create the user's embedded Solana wallet and sign our backend's SIWS
/// challenge with it, then (3) exchange both for a Cooked session via
/// `POST /auth/embedded/verify`. Every login method converges on the same
/// `completeLogin` tail once Privy itself has authenticated the user.
///
/// This wallet is never used to hold funds or sign a real transaction — its only job
/// is proving "the person who just proved their email/Apple/Google identity also
/// controls this address," the same proof an external wallet gives via SIWS.
@MainActor
final class PrivyClient {
    static let shared = PrivyClient()

    private static let logger = Logger(subsystem: "app.cooked.paper", category: "auth")

    private let privy: Privy

    /// Guards `existingOrNewSolanaWallet` against a second concurrent login
    /// minting a second wallet — see that method.
    private var inFlightWalletCreation: Task<EmbeddedSolanaWallet, Error>?

    private init() {
        let config = PrivyConfig(
            appId: PrivyConfiguration.appId,
            appClientId: PrivyConfiguration.appClientId
        )
        privy = PrivySdk.initialize(config: config)
    }

    // MARK: - Login methods

    func sendEmailCode(to email: String) async throws {
        try await privy.email.sendCode(to: email)
    }

    func verifyEmailCode(_ code: String, sentTo email: String, username: String?) async throws -> SessionResponse {
        _ = try await privy.email.loginWithCode(code, sentTo: email)
        return try await completeLogin(username: username)
    }

    func signInWithApple(username: String?) async throws -> SessionResponse {
        _ = try await privy.oAuth.login(with: OAuthProvider.apple)
        return try await completeLogin(username: username)
    }

    func signInWithGoogle(username: String?) async throws -> SessionResponse {
        _ = try await privy.oAuth.login(with: OAuthProvider.google, appUrlScheme: PrivyConfiguration.redirectURLScheme)
        return try await completeLogin(username: username)
    }

    // MARK: - The shared tail

    private func completeLogin(username: String?) async throws -> SessionResponse {
        guard let user = privy.user else { throw PrivyAuthError.noAuthenticatedUser }

        let providerToken: String
        do {
            providerToken = try await user.getAccessToken()
        } catch {
            Self.logger.error("access token fetch failed: \(error.localizedDescription, privacy: .public)")
            throw PrivyAuthError.accessTokenFailed(underlying: error)
        }

        let wallet: EmbeddedSolanaWallet
        do {
            wallet = try await existingOrNewSolanaWallet(for: user)
        } catch {
            Self.logger.error("embedded wallet creation failed: \(error.localizedDescription, privacy: .public)")
            throw PrivyAuthError.walletCreationFailed(underlying: error)
        }

        let challengeMessage: String
        let signatureBase58: String
        do {
            let challenge = try await AuthAPI.nonce(address: wallet.address)
            challengeMessage = challenge.message
            signatureBase58 = try await sign(challenge.message, with: wallet)
        } catch {
            Self.logger.error("SIWS challenge sign failed: \(error.localizedDescription, privacy: .public)")
            throw PrivyAuthError.challengeFailed(underlying: error)
        }

        // Capture the guest token BEFORE it's overwritten below — this is the only
        // moment the app can still name the portfolio to claim.
        let priorGuestToken = SessionStore.shared.isGuest ? SessionStore.shared.token : nil

        let session: SessionResponse
        do {
            session = try await AuthAPI.embeddedVerify(
                providerToken: providerToken,
                message: challengeMessage,
                signature: signatureBase58,
                username: username
            )
        } catch {
            Self.logger.error("backend verify failed: \(error.localizedDescription, privacy: .public)")
            throw PrivyAuthError.backendVerifyFailed(underlying: error)
        }

        SessionStore.shared.adoptRealAccount(
            accessToken: session.accessToken,
            userId: session.user.id,
            username: session.user.username
        )

        if let priorGuestToken {
            // Best-effort: a failed claim leaves the guest portfolio exactly where it
            // was (still readable on its original 7-day expiry) rather than losing it,
            // so a transient failure here must not fail the sign-in itself.
            _ = try? await AuthAPI.claimGuestPortfolios(guestToken: priorGuestToken)
        }

        return session
    }

    private func existingOrNewSolanaWallet(for user: PrivyUser) async throws -> EmbeddedSolanaWallet {
        if let existing = privy.user?.embeddedSolanaWallets.first {
            return existing
        }
        // A second concurrent caller (a future screen also triggering login) must
        // await the wallet already being created rather than start its own — Privy
        // has no idempotency here, so two concurrent `createSolanaWallet()` calls
        // would mint two wallets.
        if let inFlightWalletCreation {
            return try await inFlightWalletCreation.value
        }
        let creation = Task { try await user.createSolanaWallet() }
        inFlightWalletCreation = creation
        defer { inFlightWalletCreation = nil }
        return try await creation.value
    }

    /// Privy's embedded-wallet signer speaks base64 in and out; apps/api's SIWS
    /// verifier — shared with the external-wallet path — expects base58, matching
    /// every other Solana wallet's convention. This is the one conversion point.
    private func sign(_ message: String, with wallet: EmbeddedSolanaWallet) async throws -> String {
        let messageBase64 = Data(message.utf8).base64EncodedString()
        // UNCONFIRMED against real Privy SDK docs (written without Xcode/the SDK
        // available): assumes `signMessage` takes `message:` and returns a plain
        // base64 `String` directly, not a result struct wrapping one. Verify this
        // exact call signature and return type against the real SDK on first build.
        let signatureBase64 = try await wallet.provider.signMessage(message: messageBase64)
        guard let signatureBytes = Data(base64Encoded: signatureBase64) else {
            throw PrivyAuthError.signatureEncodingFailed
        }
        return Base58.encode(signatureBytes)
    }
}
