//
//  VerificationCodeView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/15/25.
//
import SwiftUI
import FirebaseAuth

struct PhoneVerificationSession: Identifiable, Hashable {
    let verificationID: String
    let phoneNumber: String

    var id: String { verificationID }
}

struct VerificationCodeView: View {
    private enum Palette {
        static let ink = Color(red: 0.06, green: 0.09, blue: 0.14)
        static let supportingInk = Color(red: 0.18, green: 0.19, blue: 0.23)
        static let muted = Color(red: 0.54, green: 0.55, blue: 0.60)
        static let divider = Color.black.opacity(0.08)
        static let inputBorder = Color.black.opacity(0.09)
        static let inputFill = Color.white.opacity(0.96)
        static let iconFill = Color(red: 0.965, green: 0.966, blue: 0.975)
    }

    let verificationID: String
    let phoneNumber: String
    var linkToCurrentUser = false
    var onSuccess: (User) -> Void
    var onCredentialSuccess: ((AuthCredential, User) -> Void)? = nil
    var onResendCode: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var verificationCode = ""
    @State private var isVerifying = false
    @State private var errorMessage = ""
    @FocusState private var isFocused: Bool

    @State private var canResend = false
    @State private var countdown = 30
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 0.99, green: 0.98, blue: 0.99),
                    Color(red: 1.0, green: 0.95, blue: 0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 30) {
                    topBar
                    verificationHeader
                    codeEntry
                    countdownCard
                    errorText
                    continueButton
                    securityDivider
                    resendSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 36)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(isVerifying)
        .hideKeyboardOnTap()
        .onAppear {
            isFocused = true
            startCountdown()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.bold))
                    .foregroundColor(Palette.ink)
                    .frame(width: 50, height: 50)
                    .background(Color.white.opacity(0.86))
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
            }
            .disabled(isVerifying)
            .accessibilityLabel("Back")

            Spacer()
        }
    }

    private var verificationHeader: some View {
        VStack(spacing: 24) {
            ZStack {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .stroke(
                            Color.red.opacity(0.12 - Double(index) * 0.02),
                            style: StrokeStyle(lineWidth: 1, dash: [1.2, 4.5])
                        )
                        .frame(width: CGFloat(72 + index * 38), height: CGFloat(72 + index * 38))
                }

                Circle()
                    .fill(Color.white)
                    .frame(width: 84, height: 84)
                    .shadow(color: Color.red.opacity(0.08), radius: 22, x: 0, y: 12)

                ZStack {
                    Image(systemName: "message")
                        .font(.system(size: 44, weight: .regular))
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .bold))
                        .offset(y: -1)
                }
                .foregroundStyle(Styles.rydrGradient)
            }
            .frame(height: 174)
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                HStack(spacing: 7) {
                    Text("Verify")
                        .foregroundColor(Palette.ink)
                    Text("Your Phone")
                        .foregroundStyle(Styles.rydrGradient)
                }
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.78)

                Text("We sent a 6-digit code to:")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Palette.muted)

                Text(formattedPhoneNumber)
                    .font(.headline.weight(.bold))
                    .foregroundColor(Palette.ink)
            }
            .multilineTextAlignment(.center)
        }
    }

    private var codeEntry: some View {
        ZStack {
            HStack(spacing: 11) {
                ForEach(0..<6, id: \.self) { index in
                    codeBox(at: index)
                }
            }

            TextField("", text: $verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .foregroundColor(.clear)
                .accentColor(.clear)
                .tint(.clear)
                .frame(height: 64)
                .opacity(0.02)
                .onChange(of: verificationCode) { _, newValue in
                    let sanitized = String(newValue.filter { $0.isNumber }.prefix(6))
                    if sanitized != newValue {
                        verificationCode = sanitized
                    }
                }
                .accessibilityLabel("Six digit verification code")
        }
        .onTapGesture { isFocused = true }
    }

    private func codeBox(at index: Int) -> some View {
        let characters = Array(verificationCode)
        let hasCharacter = index < characters.count
        let isActive = isFocused && index == min(verificationCode.count, 5)

        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.inputFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isActive || hasCharacter ? Color.red.opacity(0.72) : Palette.inputBorder,
                            lineWidth: isActive || hasCharacter ? 1.5 : 1
                        )
                )
                .shadow(color: Color.black.opacity(0.035), radius: 10, x: 0, y: 6)

            if hasCharacter {
                Text(String(characters[index]))
                    .font(.title2.weight(.bold))
                    .foregroundColor(Palette.ink)
            } else if isActive {
                Capsule()
                    .fill(Palette.ink)
                    .frame(width: 3, height: 26)
            }
        }
        .frame(height: 64)
    }

    private var countdownCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Styles.rydrGradient)

            Text(canResend ? "You can request a new code" : "Resend available in")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Palette.supportingInk)

            Spacer()

            Text(canResend ? "Now" : formattedCountdown)
                .font(.footnote.weight(.heavy))
                .foregroundStyle(Styles.rydrGradient)
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(Color.white.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.07), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(canResend ? "You can request a new code now" : "Resend available in \(formattedCountdown)")
    }

    @ViewBuilder
    private var errorText: some View {
        if !errorMessage.isEmpty {
            Text(errorMessage)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .accessibilityLabel(errorMessage)
        }
    }

    private var continueButton: some View {
        Button(action: verifyCode) {
            HStack {
                Spacer()
                Text(isVerifying ? "Verifying..." : "Continue")
                    .font(.headline.weight(.bold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.bold))
            }
            .frame(height: 64)
            .padding(.horizontal, 24)
        }
        .background(Styles.rydrGradient.opacity(verificationCode.count == 6 ? 1 : 0.45))
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.red.opacity(verificationCode.count == 6 ? 0.22 : 0.04), radius: 18, x: 0, y: 12)
        .disabled(isVerifying || verificationCode.count != 6)
        .accessibilityLabel(isVerifying ? "Verifying code" : "Continue")
    }

    private var securityDivider: some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(Palette.divider)
                .frame(height: 1)

            Image(systemName: "lock.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(Palette.muted)
                .frame(width: 32, height: 32)
                .background(Palette.iconFill)
                .clipShape(Circle())

            Rectangle()
                .fill(Palette.divider)
                .frame(height: 1)
        }
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    private var resendSection: some View {
        VStack(spacing: 10) {
            Text("Didn't receive the code?")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Palette.muted)

            Button {
                onResendCode()
                startCountdown()
            } label: {
                Text(canResend ? "Resend Code" : "Resend Code (\(countdown)s)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(canResend ? Styles.rydrGradient : LinearGradient(colors: [Palette.muted], startPoint: .leading, endPoint: .trailing))
            }
            .disabled(!canResend)
            .accessibilityLabel(canResend ? "Resend code" : "Resend code available in \(countdown) seconds")
        }
    }

    private var formattedCountdown: String {
        String(format: "00:%02d", countdown)
    }

    private var formattedPhoneNumber: String {
        let digits = phoneNumber.filter { $0.isNumber }
        guard digits.count == 11, digits.first == "1" else {
            return phoneNumber
        }

        let area = digits.dropFirst().prefix(3)
        let prefix = digits.dropFirst(4).prefix(3)
        let line = digits.suffix(4)
        return "+1 (\(area)) \(prefix)-\(line)"
    }

    private func verifyCode() {
        isVerifying = true
        errorMessage = ""
        let trimmedVerificationID = verificationID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedVerificationID.isEmpty else {
            isVerifying = false
            errorMessage = "Verification session is missing. Please resend the code and try again."
            return
        }

        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: trimmedVerificationID,
            verificationCode: verificationCode
        )

        let completion: (AuthDataResult?, Error?) -> Void = { result, error in
            Task { @MainActor in
                isVerifying = false
                if let error = error {
                    if let authCode = AuthErrorCode(rawValue: (error as NSError).code),
                       authCode == .credentialAlreadyInUse || authCode == .providerAlreadyLinked {
                        errorMessage = "That phone number is already attached to another sign-in. Sign in with the original account or remove the duplicate test phone user in Firebase, then try again."
                    } else {
                        errorMessage = "Verification failed: \(error.localizedDescription)"
                    }
                } else if let user = result?.user {
                    print("✅ Phone verified and signed in")
                    if let onCredentialSuccess {
                        onCredentialSuccess(credential, user)
                        return
                    }
                    onSuccess(user)
                }
            }
        }

        if linkToCurrentUser, let user = Auth.auth().currentUser {
            user.link(with: credential, completion: completion)
        } else {
            Auth.auth().signIn(with: credential, completion: completion)
        }
    }

    private func startCountdown() {
        canResend = false
        countdown = 30
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if countdown > 0 {
                countdown -= 1
            } else {
                canResend = true
                t.invalidate()
            }
        }
    }
}
