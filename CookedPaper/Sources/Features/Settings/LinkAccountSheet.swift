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
            VStack(spacing: Space.s20) {
                switch stage {
                case .chooseMethod: chooseMethod
                case .enterEmail: enterEmail
                case .enterCode: enterCode
                case .done: done
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Font.caption13)
                        .foregroundStyle(Color.negative)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(Space.margin)
            .background(Color.appSurfaceElevated.ignoresSafeArea())
            .navigationTitle("Save your progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(Color.appSurfaceElevated)
    }

    private var chooseMethod: some View {
        VStack(spacing: Space.s12) {
            Text("Your practice portfolio is only saved on this device for 7 days. Sign in to keep it forever.")
                .font(Font.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, Space.s16)

            Button {
                Task { await signIn { try await privy.signInWithApple(username: nil) } }
            } label: {
                Label("Continue with Apple", systemImage: "apple.logo")
            }
            .buttonStyle(.secondary)

            Button {
                Task { await signIn { try await privy.signInWithGoogle(username: nil) } }
            } label: {
                Label("Continue with Google", systemImage: "g.circle.fill")
            }
            .buttonStyle(.secondary)

            Button {
                stage = .enterEmail
            } label: {
                // Deliberately not `.secondary`: social sign-in is the fast,
                // expected path on iOS, so email reads as the slower fallback link,
                // not a third identical option.
                Text("Continue with email")
                    .font(Font.body)
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, Space.s4)

            if isBusy { ProgressView().padding(.top, Space.s12) }
        }
    }

    private var enterEmail: some View {
        VStack(spacing: Space.s12) {
            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(Space.s12)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .foregroundStyle(Color.textPrimary)
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
                if isBusy { ProgressView().tint(Color.inverseText) } else { Text("Send code") }
            }
            .buttonStyle(.primary)
            .disabled(email.isEmpty || isBusy)
        }
    }

    private var enterCode: some View {
        VStack(spacing: Space.s12) {
            Text("Enter the code sent to \(email)")
                .font(Font.caption13)
                .foregroundStyle(Color.textSecondary)

            TextField("123456", text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(Font.title2.weight(.semibold).monospacedDigit())
                .padding(Space.s12)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .foregroundStyle(Color.textPrimary)
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
                if isBusy { ProgressView().tint(Color.inverseText) } else { Text("Verify") }
            }
            .buttonStyle(.primary)
            .disabled(code.count < 4 || isBusy)
        }
    }

    private var done: some View {
        VStack(spacing: Space.s12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.positive)
            Text("You're signed in")
                .font(Font.rowTitle)
                .foregroundStyle(Color.textPrimary)
            Button("Done") { dismiss() }
                .buttonStyle(.primary)
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
