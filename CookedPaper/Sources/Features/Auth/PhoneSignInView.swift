import Foundation
import SwiftUI

/// Phone sign-in: enter a number, get a 6-digit code by SMS, enter it. The server
/// sends and checks the code; the app never sees it except as typed.
struct PhoneSignInView: View {
    var onSignedIn: (SessionResponse) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Stage { case number, code }

    @State private var stage: Stage = .number
    @State private var countryCode = "1"
    @State private var number = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var resendAvailableAt = Date.distantPast
    @FocusState private var focused: Bool

    /// E.164: "+" and digits only.
    private var e164: String {
        "+" + countryCode.filter(\.isNumber) + number.filter(\.isNumber)
    }

    private var numberIsPlausible: Bool {
        let digits = number.filter(\.isNumber).count
        return countryCode == "1" ? digits == 10 : (6...14).contains(digits)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.s24) {
                VStack(alignment: .leading, spacing: Space.s8) {
                    Text(stage == .number ? "What's your number?" : "Enter the code")
                        .font(.appLargeTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text(stage == .number
                         ? "We'll text you a 6-digit code. Message and data rates may apply."
                         : "Sent to \(formattedNumber).")
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if stage == .number { numberField } else { codeField }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption13)
                        .foregroundStyle(Color.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if stage == .code {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = Int(resendAvailableAt.timeIntervalSince(context.date).rounded(.up))
                        Button(remaining > 0 ? "Resend code in \(remaining)s" : "Resend code") {
                            Task { await sendCode() }
                        }
                        .font(.rowSubtitle)
                        .foregroundStyle(remaining > 0 ? Color.textTertiary : Color.accent)
                        .disabled(remaining > 0 || isWorking)
                        .frame(maxWidth: .infinity)
                    }
                }

                Button {
                    Task { stage == .number ? await sendCode() : await verify() }
                } label: {
                    if isWorking {
                        ProgressView().tint(Color.inverseText)
                    } else {
                        Text(stage == .number ? "Send code" : "Verify")
                    }
                }
                .buttonStyle(.primary)
                .disabled(isWorking || (stage == .number ? !numberIsPlausible : code.count != 6))
                .accessibilityIdentifier("signin.phone.submit")
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s16)
            .padding(.bottom, Space.s8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.appSurfaceElevated)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(stage == .code ? "Back" : "Cancel") {
                        if stage == .code {
                            withAnimation(Motion.standard) { stage = .number }
                            code = ""
                            errorMessage = nil
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(Color.textPrimary)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Radius.sheet)
        .presentationBackground(Color.appSurfaceElevated)
    }

    private var numberField: some View {
        HStack(spacing: Space.s8) {
            HStack(spacing: 2) {
                Text("+")
                TextField("1", text: $countryCode)
                    .keyboardType(.numberPad)
                    .frame(width: 36)
                    .onChange(of: countryCode) { _, new in countryCode = String(new.filter(\.isNumber).prefix(3)) }
                    .accessibilityLabel("Country code")
            }
            .padding(.horizontal, Space.s12)
            .frame(height: Metrics.buttonHeight)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))

            TextField("Phone number", text: $number)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($focused)
                .padding(.horizontal, Space.s16)
                .frame(height: Metrics.buttonHeight)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .accessibilityIdentifier("signin.phone.number")
        }
        .font(.title3.monospacedDigit())
        .foregroundStyle(Color.textPrimary)
    }

    private var codeField: some View {
        TextField("000000", text: $code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($focused)
            .font(.system(size: 34, weight: .semibold).monospacedDigit())
            .tracking(8)
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.textPrimary)
            .frame(height: 72)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .onChange(of: code) { _, new in
                code = String(new.filter(\.isNumber).prefix(6))
                if code.count == 6 { Task { await verify() } }
            }
            .accessibilityIdentifier("signin.phone.code")
    }

    private var formattedNumber: String {
        let digits = number.filter(\.isNumber)
        guard countryCode == "1", digits.count == 10 else { return e164 }
        let a = digits.prefix(3), b = digits.dropFirst(3).prefix(3), c = digits.suffix(4)
        return "+1 (\(a)) \(b)-\(c)"
    }

    private func sendCode() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await AuthAPI.phoneStart(phone: e164)
            resendAvailableAt = Date().addingTimeInterval(30)
            withAnimation(Motion.standard) { stage = .code }
            focused = true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Couldn't send a code. Check the number and try again."
        }
    }

    private func verify() async {
        guard !isWorking, code.count == 6 else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let session = try await AuthAPI.phoneVerify(phone: e164, code: code)
            onSignedIn(session)
        } catch {
            Haptics.error()
            code = ""
            errorMessage = (error as? APIError)?.errorDescription ?? "That code didn't work. Try again."
        }
    }
}
