import Foundation
import SwiftUI

/// The handle and display name being edited, shared by first-run setup
/// (`ProfileSetupView`) and Edit Profile (`EditProfileView`). Saves through
/// `PATCH /auth/me`, sending only what changed.
@Observable
@MainActor
final class ProfileForm {
    var username: String
    var displayName: String
    /// Driven by `UsernameField` while typing, and by `save()` when the server
    /// turns the handle down.
    var usernameStatus: UsernameStatus = .unchanged
    private(set) var isSaving = false
    var errorMessage: String?

    private let originalUsername: String
    private let originalDisplayName: String

    init(username: String, displayName: String?) {
        self.username = username
        self.displayName = displayName ?? ""
        originalUsername = username
        originalDisplayName = displayName ?? ""
    }

    /// The handle the account has now — always "available" to itself.
    var currentUsername: String { originalUsername }

    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDisplayName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var hasChanges: Bool {
        trimmedUsername != originalUsername || trimmedDisplayName != originalDisplayName
    }

    var canSave: Bool {
        !isSaving && usernameStatus.allowsSaving && trimmedDisplayName.count <= DisplayNameField.maxLength
    }

    /// True once the server has the new profile (or there was nothing to send).
    func save() async -> Bool {
        guard hasChanges else { return true }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let user = try await AuthAPI.updateProfile(
                username: trimmedUsername != originalUsername ? trimmedUsername : nil,
                // Empty clears the display name on the server.
                displayName: trimmedDisplayName != originalDisplayName ? trimmedDisplayName : nil
            )
            SessionStore.shared.apply(user)
            Haptics.success()
            return true
        } catch {
            Haptics.error()
            let apiError = error as? APIError
            if let apiError, [apiError.reason, apiError.code].contains(where: { $0 == "username_invalid" || $0 == "username_taken" }) {
                // Shown under the field itself, where the problem is.
                usernameStatus = .unavailable(apiError.errorDescription ?? "That username isn't available.")
            } else {
                errorMessage = apiError?.errorDescription ?? "Couldn't save your profile. Check your connection and try again."
            }
            return false
        }
    }
}

// MARK: - Username

enum UsernameStatus: Equatable {
    /// The account's own handle.
    case unchanged
    /// Waiting out the debounce or the server's answer.
    case checking
    case available
    /// Breaks a rule or is taken/reserved; the sentence says which.
    case unavailable(String)
    /// The check itself failed (offline). Saving is still allowed — the server
    /// re-checks on `PATCH` and its answer lands in `.unavailable`.
    case unknown

    var allowsSaving: Bool {
        switch self {
        case .unchanged, .available, .unknown: true
        case .checking, .unavailable: false
        }
    }
}

/// The server's handle rules, checked locally first so most typos never need a
/// request. The server stays the authority (reserved words, uniqueness).
enum UsernameRules {
    static let minLength = 4
    static let maxLength = 24
    static let hint = "4–24 letters, numbers or _"

    /// Why `candidate` can't be a handle, or nil if it might be.
    static func problem(with candidate: String) -> String? {
        if candidate.count < minLength { return "At least \(minLength) characters." }
        if candidate.count > maxLength { return "\(maxLength) characters at most." }
        let allowed = candidate.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_")
        }
        if !allowed { return "Only letters, numbers and _." }
        return nil
    }

    /// Fallback copy for a server `reason` that came without a `message`.
    static func message(for reason: String?) -> String {
        switch reason {
        case "taken": "That username is taken."
        case "reserved": "That username is reserved."
        default: "That username isn't allowed."
        }
    }
}

/// "@handle" text field with live availability: local rules immediately, then
/// `GET /auth/username-available` after a 350 ms pause in typing. A checkmark or a
/// red sentence under the field says where it stands.
struct UsernameField: View {
    @Binding var text: String
    /// The account's handle now; typing it back reads as unchanged, not taken.
    let current: String?
    @Binding var status: UsernameStatus

    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Text("Username")
                .font(.caption13)
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: Space.s4) {
                Text("@")
                    .font(.body)
                    .foregroundStyle(Color.textTertiary)
                TextField("", text: $text, prompt: Text("username").foregroundStyle(Color.textTertiary))
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .submitLabel(.done)
                    .accessibilityIdentifier("profile.username")
                indicator
                    .frame(width: 20, height: 20)
            }
            .padding(.horizontal, Space.s16)
            .frame(height: Metrics.buttonHeight)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )

            footnote
                .font(.caption13)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(Color.accent)
        .onAppear { check(text) }
        .onChange(of: text) { _, newValue in check(newValue) }
        .onDisappear { checkTask?.cancel() }
    }

    @ViewBuilder
    private var indicator: some View {
        switch status {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .tint(Color.textSecondary)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.positive)
                .accessibilityLabel("Available")
        case .unavailable:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.negative)
                .accessibilityLabel("Not available")
        case .unchanged, .unknown:
            Color.clear
        }
    }

    @ViewBuilder
    private var footnote: some View {
        switch status {
        case .unavailable(let message):
            Text(message)
                .foregroundStyle(Color.negative)
                .accessibilityIdentifier("profile.username.message")
        case .available:
            Text("Available")
                .foregroundStyle(Color.positive)
        default:
            Text(UsernameRules.hint)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var borderColor: Color {
        if case .unavailable = status { return Color.negative.opacity(0.6) }
        return Color.appSeparator
    }

    private func check(_ value: String) {
        checkTask?.cancel()
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let current, candidate.caseInsensitiveCompare(current) == .orderedSame {
            status = .unchanged
            return
        }
        if let problem = UsernameRules.problem(with: candidate) {
            status = .unavailable(problem)
            return
        }
        status = .checking
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            do {
                let result = try await AuthAPI.usernameAvailable(candidate)
                guard !Task.isCancelled else { return }
                status = result.available
                    ? .available
                    : .unavailable(result.message ?? UsernameRules.message(for: result.reason))
            } catch {
                guard !Task.isCancelled else { return }
                status = .unknown
            }
        }
    }
}

// MARK: - Display name

/// Free-text name shown above the handle. Optional; capped at the server's 48.
struct DisplayNameField: View {
    static let maxLength = 48

    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Text("Display name")
                .font(.caption13)
                .foregroundStyle(Color.textSecondary)

            TextField("", text: $text, prompt: Text("Optional").foregroundStyle(Color.textTertiary))
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .textInputAutocapitalization(.words)
                .textContentType(.name)
                .submitLabel(.done)
                .accessibilityIdentifier("profile.displayName")
                .padding(.horizontal, Space.s16)
                .frame(height: Metrics.buttonHeight)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .stroke(Color.appSeparator, lineWidth: 1)
                )

            Text("Shown on your profile. Leave it empty to just use your username.")
                .font(.caption13)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(Color.accent)
        .onChange(of: text) { _, newValue in
            if newValue.count > Self.maxLength { text = String(newValue.prefix(Self.maxLength)) }
        }
    }
}
