import SwiftUI

/// `cookedpaper://duel/<code>`: confirm, then `POST /paper/duels/join`, which
/// takes the open invite and starts the duel at once. On success the sheet turns
/// into that duel's detail screen.
struct JoinDuelSheet: View {
    let inviteCode: String

    @Environment(\.dismiss) private var dismiss
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var joined: Duel?

    var body: some View {
        NavigationStack {
            Group {
                if let joined {
                    DuelDetailView(duelId: joined.id, initial: joined)
                } else {
                    confirm
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(joined == nil ? "Not now" : "Done") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .interactiveDismissDisabled(isJoining)
    }

    private var confirm: some View {
        VStack(spacing: Space.s24) {
            Spacer()
            Image(systemName: "figure.fencing")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 96, height: 96)
                .background(Color.appSurface, in: Circle())
            VStack(spacing: Space.s8) {
                Text("You've been challenged")
                    .font(.appLargeTitle)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Join this duel and you both start now with a fresh $1,000 paper portfolio. Best return when the clock runs out wins.")
                    .font(.rowSubtitle)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Invite \(inviteCode)")
                .font(.caption13Digits)
                .foregroundStyle(Color.textTertiary)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption13)
                    .foregroundStyle(Color.negative)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("joinDuel.error")
            }
            Spacer()
            Button {
                Task { await join() }
            } label: {
                if isJoining {
                    ProgressView().tint(Color.inverseText)
                } else {
                    Text("Join duel")
                }
            }
            .buttonStyle(.primary)
            .disabled(isJoining)
            .accessibilityIdentifier("joinDuel.join")
            CompeteLegalCaption()
        }
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.s8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }

    private func join() async {
        isJoining = true
        errorMessage = nil
        do {
            let duel = try await DuelsAPI.join(inviteCode: inviteCode)
            Haptics.success()
            DuelsStore.shared.didChange(duel)
            withAnimation(Motion.standard) { joined = duel }
        } catch {
            Haptics.error()
            errorMessage = CompeteErrorText.message(for: error)
        }
        isJoining = false
    }
}
