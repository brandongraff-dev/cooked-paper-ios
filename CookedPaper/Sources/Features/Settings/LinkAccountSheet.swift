import SwiftUI

/// Turns the current guest portfolio into a real account — email OTP, Apple, or
/// Google, all via `PrivyClient`, which also silently claims the guest portfolio
/// onto the new account once the login completes (see `PrivyClient.completeLogin`).
struct LinkAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let privy = PrivyClient.shared

    @State private var stage: Stage = .chooseMethod
    @State private var email = ""
    @State private var code = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @FocusState private var isEmailFieldFocused: Bool
    @FocusState private var isCodeFieldFocused: Bool

    private enum Stage {
        case chooseMethod
        case enterEmail
        case enterCode
        case done
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: CookedSpacing.lg) {
                switch stage {
                case .chooseMethod: chooseMethod
                case .enterEmail: enterEmail
                case .enterCode: enterCode
                case .done: done
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(CookedFont.caption())
                        .foregroundStyle(CookedColor.Terminal.sell)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(CookedSpacing.lg)
            .background(CookedColor.Product.graphite.ignoresSafeArea())
            .navigationTitle("Save your progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var chooseMethod: some View {
        VStack(spacing: CookedSpacing.sm) {
            Text("Your practice portfolio is only saved on this device for 7 days. Sign in to keep it forever.")
                .font(CookedFont.body())
                .foregroundStyle(CookedColor.Product.chalkMuted)
                .multilineTextAlignment(.center)
                .padding(.bottom, CookedSpacing.md)

            Button {
                Task { await signIn { try await privy.signInWithApple(username: nil) } }
            } label: {
                Label("Continue with Apple", systemImage: "apple.logo")
            }
            .buttonStyle(.cookedSecondary)

            Button {
                Task { await signIn { try await privy.signInWithGoogle(username: nil) } }
            } label: {
                Label("Continue with Google", systemImage: "g.circle.fill")
            }
            .buttonStyle(.cookedSecondary)

            Button {
                stage = .enterEmail
            } label: {
                // Deliberately not `.cookedSecondary`: social sign-in is the fast,
                // expected path on iOS, so email reads as the slower fallback link,
                // not a third identical option.
                Text("Continue with email")
                    .font(CookedFont.body())
                    .foregroundStyle(CookedColor.Product.chalkMuted)
            }
            .buttonStyle(.plain)
            .padding(.top, CookedSpacing.xxs)

            if isBusy { ProgressView().tint(CookedColor.Brand.fill).padding(.top, CookedSpacing.sm) }
        }
    }

    private var enterEmail: some View {
        VStack(spacing: CookedSpacing.sm) {
            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(CookedSpacing.sm)
                .background(CookedColor.Product.slate)
                .clipShape(RoundedRectangle(cornerRadius: CookedRadius.sm, style: .continuous))
                .foregroundStyle(CookedColor.Product.chalk)
                .focused($isEmailFieldFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isEmailFieldFocused = false }
                    }
                }

            Button {
                Task {
                    isBusy = true
                    errorMessage = nil
                    do {
                        try await privy.sendEmailCode(to: email)
                        stage = .enterCode
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    isBusy = false
                }
            } label: {
                if isBusy { ProgressView().tint(CookedColor.Brand.onFill) } else { Text("Send code") }
            }
            .buttonStyle(.cookedPrimary(enabled: !email.isEmpty))
            .disabled(email.isEmpty || isBusy)
        }
    }

    private var enterCode: some View {
        VStack(spacing: CookedSpacing.sm) {
            Text("Enter the code sent to \(email)")
                .font(CookedFont.caption())
                .foregroundStyle(CookedColor.Product.chalkMuted)

            TextField("123456", text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(CookedFont.priceLarge())
                .padding(CookedSpacing.sm)
                .background(CookedColor.Product.slate)
                .clipShape(RoundedRectangle(cornerRadius: CookedRadius.sm, style: .continuous))
                .foregroundStyle(CookedColor.Product.chalk)
                .focused($isCodeFieldFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isCodeFieldFocused = false }
                    }
                }

            Button {
                Task {
                    await signIn { try await privy.verifyEmailCode(code, sentTo: email, username: nil) }
                }
            } label: {
                if isBusy { ProgressView().tint(CookedColor.Brand.onFill) } else { Text("Verify") }
            }
            .buttonStyle(.cookedPrimary(enabled: code.count >= 4))
            .disabled(code.count < 4 || isBusy)
        }
    }

    private var done: some View {
        VStack(spacing: CookedSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: CookedIconSize.xl))
                .foregroundStyle(CookedColor.Terminal.buy)
            Text("You're signed in")
                .font(CookedFont.headline())
                .foregroundStyle(CookedColor.Product.chalk)
            Button("Done") { dismiss() }
                .buttonStyle(.cookedPrimary)
        }
    }

    private func signIn(_ action: @escaping () async throws -> SessionResponse) async {
        isBusy = true
        errorMessage = nil
        do {
            _ = try await action()
            Haptics.success()
            stage = .done
        } catch {
            Haptics.error()
            errorMessage = error.localizedDescription
        }
        isBusy = false
    }
}
