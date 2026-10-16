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
    var workspace: String? = nil

    var id: String { verificationID }
}

// One controller owns every rider SMS send, including resends from a presented sheet.
// The deadline is persisted per workspace; leaving a screen never resets it.
@MainActor
final class RiderSMSRequests: ObservableObject {
    static let shared = RiderSMSRequests()
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var latestSession: PhoneVerificationSession?
    @Published private(set) var now = Date()
    #if DEBUG && targetEnvironment(simulator)
    @Published private(set) var testRequestCount = 0
    #endif
    private let defaults: UserDefaults
    private let cooldown: TimeInterval
    private var timer: Timer?
    private var deadlineKey: String { "rydr.sms.nextRequest.\(RydrWorkspace.selected ?? "unresolved")" }
    var secondsRemaining: Int { max(0, Int(ceil(defaults.double(forKey: deadlineKey) - now.timeIntervalSince1970))) }
    var canSend: Bool { !isSending && secondsRemaining == 0 }
    var buttonTitle: String {
        isSending ? "Sending…" : secondsRemaining > 0 ? "Try again in \(secondsRemaining)s" : "Send Code"
    }

    private init() {
        #if DEBUG && targetEnvironment(simulator)
        let testing = ProcessInfo.processInfo.arguments.contains("-RydrSMSUITest")
        defaults = testing ? UserDefaults(suiteName: "rydr.sms.ui-tests")! : .standard
        cooldown = testing ? 5 : 60
        if testing && ProcessInfo.processInfo.arguments.contains("-RydrSMSResetUITest") {
            defaults.removePersistentDomain(forName: "rydr.sms.ui-tests")
        }
        #else
        defaults = .standard
        cooldown = 60
        #endif
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    @discardableResult
    func send(phone: String, onFinished: @escaping () -> Void = {}, completion: @escaping (PhoneVerificationSession) -> Void) -> Bool {
        now = Date()
        guard canSend else { return false }
        guard phone.count == 12, phone.hasPrefix("+1"), phone.dropFirst().allSatisfy({ $0.isNumber }) else {
            errorMessage = "Enter a valid 10-digit US phone number."
            return false
        }
        let workspace = RydrWorkspace.selected
        let key = deadlineKey
        isSending = true
        errorMessage = ""
        defaults.set(now.addingTimeInterval(cooldown).timeIntervalSince1970, forKey: key)
        let finished: (String?, Error?) -> Void = { [weak self] id, error in
            Task { @MainActor in
                guard let self else { return }
                self.isSending = false
                self.now = Date()
                guard workspace == RydrWorkspace.selected else { return }
                onFinished()
                if let error {
                    let code = AuthErrorCode(rawValue: (error as NSError).code)
                    if code == .tooManyRequests {
                        // This is a local backoff, not a promise that Firebase's block expires then.
                        #if DEBUG && targetEnvironment(simulator)
                        let delay: TimeInterval = ProcessInfo.processInfo.arguments.contains("-RydrSMSUITest") ? (ProcessInfo.processInfo.arguments.contains("-RydrSMSPersistenceUITest") ? 30 : 5) : 600
                        #else
                        let delay: TimeInterval = 600
                        #endif
                        self.defaults.set(self.now.addingTimeInterval(delay).timeIntervalSince1970, forKey: key)
                        self.errorMessage = "Firebase temporarily blocked SMS requests due to unusual activity. Stop requesting codes and try later, or use email and password to log in. This cooldown does not guarantee Firebase has lifted the block."
                    } else if code == .invalidPhoneNumber {
                        self.errorMessage = "Check your phone number and try again."
                    } else if code == .networkError {
                        self.errorMessage = "Unable to send a code. Check your connection and try again after the cooldown."
                    } else {
                        self.errorMessage = "Unable to send a code: \(error.localizedDescription)"
                    }
                    return
                }
                guard let id, !id.isEmpty else {
                    self.errorMessage = "No verification session was returned. Wait for the cooldown, then request another code."
                    return
                }
                let session = PhoneVerificationSession(verificationID: id, phoneNumber: phone, workspace: workspace)
                self.latestSession = session
                completion(session)
            }
        }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-RydrSMSUITest") {
            testRequestCount += 1
            let attempt = testRequestCount
            let failFirst = ProcessInfo.processInfo.arguments.contains("-RydrSMSBlockedUITest")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if failFirst || attempt == 2 {
                    finished(nil, NSError(domain: AuthErrorDomain, code: AuthErrorCode.tooManyRequests.rawValue))
                } else { finished("simulator-session-\(attempt)", nil) }
            }
            return true
        }
        #endif
        PhoneAuthProvider.provider(auth: RydrWorkspace.auth).verifyPhoneNumber(phone, uiDelegate: nil, completion: finished)
        return true
    }
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

    @ObservedObject private var sms = RiderSMSRequests.shared
    @State private var activeVerificationID = ""
    private var canResend: Bool { sms.canSend && !isVerifying }
    private var countdown: Int { sms.secondsRemaining }

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
                    #if DEBUG && targetEnvironment(simulator)
                    if ProcessInfo.processInfo.arguments.contains("-RydrSMSUITest") {
                        Text("SMS transport calls: \(sms.testRequestCount)").accessibilityIdentifier("smsCodeRequestCount")
                        Text(activeVerificationID).accessibilityIdentifier("smsActiveSession")
                    }
                    #endif
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
            activeVerificationID = verificationID
        }
        .onReceive(sms.$latestSession) { session in
            guard let session, session.phoneNumber == phoneNumber, session.workspace == RydrWorkspace.selected else { return }
            activeVerificationID = session.verificationID
            verificationCode = ""
            errorMessage = ""
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
        if !(sms.errorMessage.isEmpty && errorMessage.isEmpty) {
            Text([errorMessage, sms.errorMessage].filter { !$0.isEmpty }.joined(separator: "\n\n"))
                .font(.footnote.weight(.semibold))
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .accessibilityIdentifier("smsCodeError")
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
        .background {
            Styles.rydrGradient.opacity(verificationCode.count == 6 ? 1 : 0.45)
        }
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.red.opacity(verificationCode.count == 6 ? 0.22 : 0.04), radius: 18, x: 0, y: 12)
        .disabled(isVerifying || sms.isSending || verificationCode.count != 6)
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
                guard canResend else { return }
                onResendCode()
            } label: {
                Text(sms.isSending ? "Sending…" : canResend ? "Resend Code" : "Resend Code (\(countdown)s)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(canResend ? Styles.rydrGradient : LinearGradient(colors: [Palette.muted], startPoint: .leading, endPoint: .trailing))
            }
            .disabled(!canResend)
            .accessibilityIdentifier("smsResend")
            .accessibilityLabel(canResend ? "Resend code" : "Resend code available in \(countdown) seconds")
        }
    }

    private var formattedCountdown: String {
        String(format: "%02d:%02d", countdown / 60, countdown % 60)
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
        guard !isVerifying, !sms.isSending, verificationCode.count == 6 else { return }
        isVerifying = true
        errorMessage = ""
        let trimmedVerificationID = activeVerificationID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedVerificationID.isEmpty else {
            isVerifying = false
            errorMessage = "Verification session is missing. Please resend the code and try again."
            return
        }

        let credential = PhoneAuthProvider.provider(auth: RydrWorkspace.auth).credential(
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

        if linkToCurrentUser, let user = RydrWorkspace.auth.currentUser {
            user.link(with: credential, completion: completion)
        } else {
            RydrWorkspace.auth.signIn(with: credential, completion: completion)
        }
    }

}
