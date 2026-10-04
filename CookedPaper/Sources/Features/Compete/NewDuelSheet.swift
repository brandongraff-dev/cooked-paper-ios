import SwiftUI
import UIKit

/// Start a duel: challenge someone by username, or make an open invite link anyone
/// can take; pick 1 hour, 24 hours or 7 days. The username is checked by the
/// server on submit (`user_not_found`, `duel_self`, …) and any refusal reads as a
/// plain sentence under the field.
struct NewDuelSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .username
    @State private var username = ""
    @State private var duration: DuelDuration = .day
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var created: Duel?
    @State private var didCopy = false
    @FocusState private var usernameFocused: Bool

    enum Mode: String, CaseIterable, Identifiable {
        case username, link
        var id: String { rawValue }
        var title: String { self == .username ? "Username" : "Invite link" }
    }

    private var trimmedUsername: String {
        var value = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("@") { value.removeFirst() }
        return value
    }

    private var canSubmit: Bool {
        !isSubmitting && (mode == .link || !trimmedUsername.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let created {
                    CreatedDuelView(duel: created, didCopy: $didCopy) { dismiss() }
                } else {
                    form
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appSurfaceElevated)
            .navigationTitle("New duel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(created == nil ? "Cancel" : "Done") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(Color.appSurfaceElevated)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSubmitting)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s24) {
                VStack(alignment: .leading, spacing: Space.s8) {
                    Text("Head to head")
                        .font(.appLargeTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("You each get a fresh $1,000 paper portfolio. Best return when the clock runs out wins.")
                        .font(.rowSubtitle)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Space.s4) {
                    ForEach(Mode.allCases) { option in
                        Segment(title: option.title, isSelected: mode == option) {
                            errorMessage = nil
                            mode = option
                            usernameFocused = option == .username
                        }
                        .accessibilityIdentifier("newDuel.mode.\(option.rawValue)")
                    }
                }
                .padding(Space.s4)
                .background(Color.appSurface, in: Capsule())

                if mode == .username {
                    VStack(alignment: .leading, spacing: Space.s8) {
                        Text("Opponent")
                            .font(.caption13)
                            .foregroundStyle(Color.textSecondary)
                        HStack(spacing: Space.s4) {
                            Text("@")
                                .font(.rowTitle)
                                .foregroundStyle(Color.textTertiary)
                            TextField("username", text: $username)
                                .font(.rowTitle)
                                .foregroundStyle(Color.textPrimary)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.username)
                                .submitLabel(.send)
                                .focused($usernameFocused)
                                .onSubmit { Task { await submit() } }
                                .onChange(of: username) { _, _ in errorMessage = nil }
                                .accessibilityIdentifier("newDuel.username")
                        }
                        .padding(.horizontal, Space.s16)
                        .frame(height: Metrics.buttonHeight)
                        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                    }
                } else {
                    HStack(alignment: .top, spacing: Space.s12) {
                        Image(systemName: "link")
                            .font(.body)
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 24)
                        Text("Get a link to send anywhere. The first person to open it takes the duel, and it starts right away.")
                            .font(.rowSubtitle)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Space.s16)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                }

                VStack(alignment: .leading, spacing: Space.s8) {
                    Text("Duration")
                        .font(.caption13)
                        .foregroundStyle(Color.textSecondary)
                    HStack(spacing: Space.s8) {
                        ForEach(DuelDuration.allCases) { option in
                            Button {
                                guard duration != option else { return }
                                Haptics.selection()
                                duration = option
                            } label: {
                                Text(option.label)
                                    .font(.rowTitle)
                                    .monospacedDigit()
                                    .foregroundStyle(duration == option ? Color.inverseText : Color.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(
                                        duration == option ? Color.inverseFill : Color.appSurface,
                                        in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                    )
                            }
                            .buttonStyle(.pressable)
                            .animation(Motion.standard, value: duration)
                            .accessibilityIdentifier("newDuel.duration.\(option.rawValue)")
                            .accessibilityAddTraits(duration == option ? .isSelected : [])
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption13)
                        .foregroundStyle(Color.negative)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("newDuel.error")
                }

                VStack(spacing: Space.s12) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().tint(Color.inverseText)
                        } else {
                            Text(mode == .username ? "Send challenge" : "Create invite link")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("newDuel.submit")

                    CompeteLegalCaption()
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s8)
            .padding(.bottom, Space.s24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            let duel = try await DuelsAPI.create(
                opponentUsername: mode == .username ? trimmedUsername : nil,
                durationHours: duration.rawValue
            )
            Haptics.success()
            usernameFocused = false
            withAnimation(Motion.standard) { created = duel }
            DuelsStore.shared.didChange(duel)
        } catch {
            Haptics.error()
            errorMessage = CompeteErrorText.message(for: error)
        }
        isSubmitting = false
    }
}

/// After creating: who it went to (or the link to share), and Done.
private struct CreatedDuelView: View {
    let duel: Duel
    @Binding var didCopy: Bool
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: Space.s24) {
            Spacer()
            Image(systemName: duel.opponent == nil ? "link.circle.fill" : "paperplane.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.textPrimary)
            VStack(spacing: Space.s8) {
                Text(duel.opponent.map { "Challenge sent to \($0.handle)" } ?? "Your invite is ready")
                    .font(.sectionHeader)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = duel.inviteURL {
                HStack(spacing: Space.s12) {
                    Text(url.absoluteString)
                        .font(.rowSubvalue)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button {
                        UIPasteboard.general.url = url
                        Haptics.success()
                        withAnimation(Motion.standard) { didCopy = true }
                    } label: {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(didCopy ? Color.positive : Color.textPrimary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(didCopy ? "Copied" : "Copy invite link")
                }
                .padding(.horizontal, Space.s16)
                .frame(height: Metrics.buttonHeight)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            }
            Spacer()
            if let url = duel.inviteURL {
                ShareLink(
                    item: url,
                    subject: Text("Duel me on Cooked"),
                    message: Text("Duel me on Cooked: $1,000 in paper money each, best return in \(DuelDuration(rawValue: duel.durationHours)?.longLabel ?? duel.durationLabel) wins. No stakes, just bragging rights.")
                ) {
                    Label("Share invite link", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("newDuel.share")
                Button("Done", action: onDone)
                    .buttonStyle(.secondary)
            } else {
                Button("Done", action: onDone)
                    .buttonStyle(.primary)
            }
            CompeteLegalCaption()
        }
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.s8)
    }

    private var detail: String {
        let length = DuelDuration(rawValue: duel.durationHours)?.longLabel ?? duel.durationLabel
        if duel.opponent != nil {
            return "The \(length) clock starts when they accept. You'll get a notification."
        }
        return "Send it to anyone. The \(length) clock starts the moment someone joins. Invites expire after 24 hours."
    }
}
