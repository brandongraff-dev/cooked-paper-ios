import AuthenticationServices
import CryptoKit
import Foundation
import GoogleSignIn
import SwiftUI

/// Everyone signs in before trading, with Apple or Google. Each path
/// proves identity to the server, which mints the session and owns the portfolio,
/// so progress follows the account to any device.
struct SignInView: View {
    /// Shown above the buttons. Onboarding uses it to say why ("save your
    /// portfolio"); a returning signed-out user sees the plain version.
    var title = "Sign in to Cooked"
    var subtitle = "Trade live prices with paper money. Your portfolio is saved to your account."
    var onSignedIn: () -> Void

    @State private var auth = SignInModel()

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Space.s24)

            VStack(spacing: Space.s24) {
                BrandWordmark(height: 36)
                VStack(spacing: Space.s12) {
                    Text(title)
                        .font(.appLargeTitle)
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Space.s24)

            Spacer(minLength: Space.s24)

            VStack(spacing: Space.s12) {
                SignInWithAppleButton(.continue) { request in
                    auth.prepareApple(request)
                } onCompletion: { result in
                    Task { await auth.finishApple(result, onSignedIn: onSignedIn) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: Metrics.buttonHeight)
                .clipShape(Capsule())
                .disabled(auth.isWorking || auth.appleNonce == nil)
                .accessibilityIdentifier("signin.apple")

                Button {
                    Task { await auth.signInWithGoogle(onSignedIn: onSignedIn) }
                } label: {
                    HStack(spacing: Space.s12) {
                        Image("LogoGoogle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("Continue with Google")
                    }
                }
                .buttonStyle(.secondary)
                .disabled(auth.isWorking)
                .accessibilityIdentifier("signin.google")

                if auth.isWorking {
                    ProgressView().tint(Color.textSecondary)
                        .padding(.top, Space.s4)
                }
                if let error = auth.errorMessage {
                    Text(error)
                        .font(.caption13)
                        .foregroundStyle(Color.negative)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Space.margin)

            legal
                .padding(.top, Space.s24)
                .padding(.bottom, Space.s8)
        }
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
        .task { await auth.loadAppleNonce() }
    }

    private var legal: some View {
        VStack(spacing: Space.s4) {
            Text("By continuing you agree to the Terms and Privacy Policy.")
                .font(.caption13)
                .foregroundStyle(Color.textTertiary)
            HStack(spacing: Space.s16) {
                Link("Terms", destination: LegalLinks.terms)
                Link("Privacy", destination: LegalLinks.privacy)
            }
            .font(.caption13)
            .foregroundStyle(Color.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Space.s24)
    }
}

// MARK: - Model

@Observable
@MainActor
final class SignInModel {
    var isWorking = false
    var errorMessage: String?
    /// Server-issued, fetched before the Apple button is tapped: Apple's request
    /// callback is synchronous, so the nonce has to be in hand already.
    private(set) var appleNonce: String?

    func loadAppleNonce() async {
        appleNonce = try? await AuthAPI.appleNonce().nonce
    }

    /// Apple is given SHA-256 of the nonce; the server checks the token carries that
    /// hash and then spends the raw nonce, so a captured token can't be replayed.
    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        errorMessage = nil
        request.requestedScopes = [.fullName, .email]
        if let appleNonce { request.nonce = Self.sha256(appleNonce) }
    }

    func finishApple(_ result: Result<ASAuthorization, Error>, onSignedIn: @escaping () -> Void) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Apple sign-in didn't finish. Try again."
            }
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8),
                let nonce = appleNonce
            else {
                errorMessage = "Apple didn't return a sign-in token. Try again."
                return
            }
            isWorking = true
            defer { isWorking = false }
            let name = credential.fullName.map {
                AppleSignInBody.FullName(givenName: $0.givenName, familyName: $0.familyName)
            }
            do {
                let session = try await AuthAPI.apple(AppleSignInBody(identityToken: identityToken, nonce: nonce, fullName: name))
                complete(session, method: "apple", onSignedIn: onSignedIn)
            } catch {
                errorMessage = Self.message(for: error)
            }
            // Each nonce is single-use; get a fresh one for any next attempt.
            appleNonce = nil
            await loadAppleNonce()
        }
    }

    func signInWithGoogle(onSignedIn: @escaping () -> Void) async {
        errorMessage = nil
        #if DEBUG
        // UI screenshot runs: Google's own sheet can't be driven from a test, so
        // the mock server's session stands in for it.
        if MockAPI.isEnabled {
            isWorking = true
            defer { isWorking = false }
            if let session = try? await AuthAPI.google(idToken: "demo-google-id-token") {
                complete(session, method: "google", onSignedIn: onSignedIn)
            }
            return
        }
        #endif
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty, !clientID.contains("REPLACE") else {
            errorMessage = "Google sign-in isn't configured in this build."
            return
        }
        guard let presenter = Self.topViewController() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let nonce = try await AuthAPI.googleNonce().nonce
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: nil,
                nonce: nonce
            )
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google didn't return a sign-in token. Try again."
                return
            }
            let session = try await AuthAPI.google(idToken: idToken)
            complete(session, method: "google", onSignedIn: onSignedIn)
        } catch let error as GIDSignInError where error.code == .canceled {
            return
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func complete(_ session: SessionResponse, method: String, onSignedIn: () -> Void) {
        SessionStore.shared.signIn(session, method: method)
        Haptics.success()
        onSignedIn()
    }

    static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? "Sign-in failed. Try again."
        }
        return "Sign-in failed. Check your connection and try again."
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
