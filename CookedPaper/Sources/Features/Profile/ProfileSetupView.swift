import SwiftUI
import UIKit

/// Shown once, straight after the sign-in that created the account
/// (`SessionResponse.isNewAccount`): the server has already given them a handle
/// like `trader_ab12cd34`, and this is the moment to swap it for one they chose.
/// Skipping keeps the generated one; Settings → Profile can change it later.
///
/// Onboarding shows it as a step after sign-in; `RootView` shows it for a sign-in
/// that happens outside onboarding. Either way, `onFinished` runs after
/// `SessionStore.finishProfileSetup()`.
struct ProfileSetupView: View {
    var onFinished: () -> Void

    @State private var form: ProfileForm

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        let session = SessionStore.shared
        _form = State(initialValue: ProfileForm(username: session.username ?? "", displayName: session.displayName))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Space.s32) {
                    VStack(spacing: Space.s16) {
                        ProfileAvatar(seed: avatarSeed, name: previewName, size: 96)
                            .animation(Motion.standard, value: previewName)
                        VStack(spacing: Space.s12) {
                            Text("Make it yours")
                                .font(.appLargeTitle)
                                .foregroundStyle(Color.textPrimary)
                                .multilineTextAlignment(.center)
                            Text("Pick the name you'll trade under. It's how you show up on the leaderboard, and you can change it anytime in Settings.")
                                .font(.body)
                                .foregroundStyle(Color.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, Space.s24)

                    VStack(spacing: Space.s24) {
                        UsernameField(text: $form.username, current: form.currentUsername, status: $form.usernameStatus)
                        DisplayNameField(text: $form.displayName)
                    }
                    .padding(.horizontal, Space.margin)
                }
                .padding(.top, Space.s24)
                .padding(.bottom, Space.s16)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: Space.s12) {
                if let error = form.errorMessage {
                    Text(error)
                        .font(.caption13)
                        .foregroundStyle(Color.negative)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    dismissKeyboard()
                    Task {
                        if await form.save() { finish() }
                    }
                } label: {
                    if form.isSaving {
                        ProgressView().tint(Color.inverseText)
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(.primary)
                .disabled(!form.canSave)
                .accessibilityIdentifier("profileSetup.continue")

                Button {
                    Haptics.tap()
                    finish()
                } label: {
                    Text("Skip for now")
                        .font(.buttonLabel)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: Metrics.chipHeight + Space.s12)
                }
                .buttonStyle(.pressable)
                .disabled(form.isSaving)
                .accessibilityIdentifier("profileSetup.skip")
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s8)
            .padding(.bottom, Space.s8)
        }
        .screenBackground()
        .preferredColorScheme(.dark)
    }

    private var avatarSeed: String {
        SessionStore.shared.avatarSeed ?? SessionStore.shared.userId ?? form.currentUsername
    }

    /// The avatar's letter follows what they type.
    private var previewName: String {
        let name = form.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? form.username : name
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func finish() {
        SessionStore.shared.finishProfileSetup()
        onFinished()
    }
}
