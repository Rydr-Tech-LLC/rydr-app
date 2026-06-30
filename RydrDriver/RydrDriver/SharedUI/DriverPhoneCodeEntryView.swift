//
//  DriverPhoneCodeEntryView.swift
//  Rydr Driver
//
//  Shared, full-screen "enter the 6-digit code" step. Used identically by the
//  driver login flow and the driver signup flow. The caller owns what happens on
//  success (sign in vs link), passed in via `onVerify`, so this view stays purely
//  about collecting the code and presenting the result.
//

import SwiftUI
import FirebaseAuth

struct DriverPhoneCodeEntryView: View {
    /// The verification ID for the current code session. Bound so a resend can
    /// swap in a new session without recreating this view.
    @Binding var verificationID: String
    /// The E.164 phone number the code was sent to (display only).
    let phoneNumber: String
    /// Called when the driver wants to go back and fix the number. If nil, no
    /// Edit affordance is shown.
    var onEditNumber: (() -> Void)? = nil
    /// Called when the driver requests a new code. The implementation should send
    /// a new Firebase verification and update `verificationID` on success.
    var onResendCode: () -> Void
    /// Called with the constructed PhoneAuthCredential once 6 digits are entered.
    /// The caller decides whether to `signIn(with:)` or `link(with:)`, and reports
    /// back success/failure via `completion`.
    var onVerify: (_ credential: PhoneAuthCredential, _ completion: @escaping (Result<User, Error>) -> Void) -> Void

    @State private var code = ""
    @State private var isVerifying = false
    @State private var errorMessage = ""
    @State private var canResend = false
    @State private var secondsRemaining = 30
    @State private var countdownTimer: Timer?
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer().frame(height: 6)

                logoLockup

                header

                codeBoxes

                Text("Enter the 6-digit code sent to your phone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !canResend {
                    resendPill
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }

                verifyButton

                securityCard

                resendFooter
            }
            .padding(.horizontal, 24)
        }
        .background(Color(.systemBackground))
        .hideKeyboardOnTap()
        .onAppear {
            isCodeFocused = true
            startCountdown()
        }
        .onDisappear {
            countdownTimer?.invalidate()
        }
    }

    // MARK: - Subviews

    private var logoLockup: some View {
        VStack(spacing: 4) {
            Image("Rydr - Driver")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

            Text("Rydr")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Styles.rydrGradient)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rydr Driver logo")
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.red.opacity(0.1)).frame(width: 56, height: 56)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Styles.rydrGradient)
            }

            HStack(spacing: 0) {
                Text("Verify ").foregroundColor(.primary)
                Text("your").foregroundStyle(Styles.rydrGradient)
                Text(" phone").foregroundColor(.primary)
            }
            .font(.system(size: 26, weight: .heavy, design: .rounded))

            VStack(spacing: 4) {
                Text("We've sent a 6-digit code to")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Text(formattedPhoneNumber)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    if let onEditNumber {
                        Button(action: onEditNumber) {
                            HStack(spacing: 3) {
                                Text("Edit").font(.subheadline.weight(.semibold))
                                Image(systemName: "pencil").font(.caption)
                            }
                            .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit phone number")
                    }
                }
            }
        }
    }

    private var codeBoxes: some View {
        ZStack {
            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    let chars = Array(code)
                    let filled = index < chars.count
                    let isCurrent = index == chars.count
                    Text(filled ? String(chars[index]) : "")
                        .font(.title2.weight(.semibold))
                        .frame(width: 44, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isCurrent ? Color.red : Color(.systemGray4), lineWidth: isCurrent ? 2 : 1)
                        )
                }
            }

            TextField("", text: Binding(
                get: { code },
                set: { code = String($0.filter { $0.isNumber }.prefix(6)) }
            ))
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($isCodeFocused)
            .opacity(0.02)
            .accessibilityLabel("Verification Code Field")
        }
        .contentShape(Rectangle())
        .onTapGesture { isCodeFocused = true }
    }

    private var resendPill: some View {
        Text("Resend code in \(String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60))")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.red)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.red.opacity(0.08)))
    }

    private var verifyButton: some View {
        Button(action: verify) {
            HStack {
                Image(systemName: "lock.fill")
                Text(isVerifying ? "Verifying..." : "Verify Code")
                    .fontWeight(.semibold)
                Spacer()
                ZStack {
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 28, height: 28)
                    Image(systemName: "arrow.right").font(.caption.weight(.bold))
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
        }
        .disabled(isVerifying || code.count != 6)
        .foregroundColor(.white)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(code.count == 6 && !isVerifying ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color.gray.opacity(0.5)))
        )
        .accessibilityLabel("Verify Code")
    }

    private var securityCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.red.opacity(0.1)).frame(width: 40, height: 40)
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(Styles.rydrGradient)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Your security matters")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text("Your number is used only for verification and account security. We never share your information.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.red.opacity(0.06)))
    }

    private var resendFooter: some View {
        HStack(spacing: 4) {
            Text("Didn't receive the code?")
                .foregroundStyle(.secondary)
            Button("Resend Code") {
                resendCode()
            }
            .disabled(!canResend)
            .foregroundColor(canResend ? .red : .secondary.opacity(0.5))
            .fontWeight(.semibold)
        }
        .font(.footnote)
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    private var formattedPhoneNumber: String {
        let digits = phoneNumber.filter { $0.isNumber }
        let national = digits.count > 10 ? String(digits.suffix(10)) : digits
        guard national.count == 10 else { return phoneNumber }
        let area = national.prefix(3)
        let mid = national.dropFirst(3).prefix(3)
        let last = national.suffix(4)
        return "+1 (\(area)) \(mid)-\(last)"
    }

    private func startCountdown() {
        canResend = false
        secondsRemaining = 30
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if secondsRemaining <= 1 {
                    secondsRemaining = 0
                    canResend = true
                    countdownTimer?.invalidate()
                    countdownTimer = nil
                } else {
                    secondsRemaining -= 1
                }
            }
        }
    }

    private func resendCode() {
        guard canResend else { return }
        code = ""
        errorMessage = ""
        onResendCode()
        startCountdown()
    }

    private func verify() {
        let trimmedID = verificationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            errorMessage = "Verification session is missing. Please resend the code and try again."
            return
        }
        guard code.count == 6 else { return }

        isVerifying = true
        errorMessage = ""
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: trimmedID,
            verificationCode: code
        )

        onVerify(credential) { result in
            Task { @MainActor in
                isVerifying = false
                switch result {
                case .success:
                    break // caller handles navigation/dismissal
                case .failure(let error):
                    if let authCode = AuthErrorCode(rawValue: (error as NSError).code),
                       authCode == .credentialAlreadyInUse || authCode == .providerAlreadyLinked {
                        errorMessage = "That phone number is already attached to another sign-in."
                    } else {
                        errorMessage = "Verification failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
