//
//  DriverPhoneEntryView.swift
//  Rydr Driver
//
//  Shared, full-screen "enter your phone number" step. Used identically by the
//  driver login flow and the driver signup flow so both present the same design
//  and the same Firebase Phone Auth behavior. Sends a real verification code via
//  Firebase and hands the verificationID + E.164 phone number back to the caller,
//  which is responsible for presenting DriverPhoneCodeEntryView next.
//

import SwiftUI
import Combine
import FirebaseAuth

struct DriverSMSVerificationSession {
    let verificationID: String
    let phoneNumber: String
    var workspace: String? = nil
}

// One controller owns every driver SMS send, including resends from a presented sheet.
// The deadline is persisted per workspace; leaving a screen never resets it.
@MainActor
final class DriverSMSRequests: ObservableObject {
    static let shared = DriverSMSRequests()
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var latestSession: DriverSMSVerificationSession?
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
        defaults = testing ? UserDefaults(suiteName: "rydr.driver.sms.ui-tests")! : .standard
        cooldown = testing ? 5 : 60
        if testing && ProcessInfo.processInfo.arguments.contains("-RydrSMSResetUITest") {
            defaults.removePersistentDomain(forName: "rydr.driver.sms.ui-tests")
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
    func send(phone: String, onFinished: @escaping () -> Void = {}, completion: @escaping (DriverSMSVerificationSession) -> Void) -> Bool {
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
                let session = DriverSMSVerificationSession(verificationID: id, phoneNumber: phone, workspace: workspace)
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

struct DriverPhoneEntryView: View {
    /// Called once Firebase has accepted the phone number and sent a verification code.
    var onCodeSent: (_ verificationID: String, _ e164Phone: String) -> Void
    /// Called when the driver taps Close. Pass `nil` to hide the close button
    /// (e.g. when the host already provides its own, like a NavigationStack toolbar).
    var onClose: (() -> Void)? = nil

    @State private var phoneNumber = ""
    @ObservedObject private var sms = DriverSMSRequests.shared
    @FocusState private var isFieldFocused: Bool

    private func digitsOnly(_ s: String) -> String { s.filter { $0.isNumber } }
    private var sanitizedDigits: String { String(digitsOnly(phoneNumber).prefix(10)) }
    private var isPhoneValid: Bool { sanitizedDigits.count == 10 }
    private var e164Phone: String { "+1" + sanitizedDigits }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                closeButtonRow

                logoLockup

                VStack(spacing: 10) {
                    iconBadge(systemName: "lock.shield.fill")

                    HStack(spacing: 0) {
                        Text("Verify ").foregroundColor(.primary)
                        Text("your").foregroundStyle(Styles.rydrGradient)
                        Text(" phone").foregroundColor(.primary)
                    }
                    .font(.system(size: 28, weight: .heavy, design: .rounded))

                    Text("Enter your mobile number and we'll send you a code to get started.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                phoneField

                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Your number is used only for verification and account security.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                if !sms.errorMessage.isEmpty {
                    Text(sms.errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("smsLoginError")
                }

                sendCodeButton
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("-RydrSMSUITest") {
                    Text("SMS transport calls: \(sms.testRequestCount)").accessibilityIdentifier("smsRequestCount")
                }
                #endif

                decorativeDivider

                featureRow

                Text("By continuing, you agree to Rydr's [Terms of Service](https://rydr-go.com/terms.html) and [Privacy Policy](https://rydr-go.com/privacy.html)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .tint(.red)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
        }
        .background(Color(.systemBackground))
        .hideKeyboardOnTap()
        .onAppear { isFieldFocused = true }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var closeButtonRow: some View {
        if let onClose {
            HStack {
                Button(action: onClose) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                        Text("Close")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Styles.rydrGradient)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
            }
            .padding(.top, 6)
        } else {
            Spacer().frame(height: 6)
        }
    }

    private var logoLockup: some View {
        VStack(spacing: 4) {
            Image("Rydr - Driver")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            Text("Rydr")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(Styles.rydrGradient)

            Text("Drive Different")
                .font(.system(size: 11, weight: .medium))
                .italic()
                .foregroundStyle(Styles.rydrGradient.opacity(0.85))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rydr Driver logo")
    }

    private func iconBadge(systemName: String) -> some View {
        ZStack {
            Circle().fill(Color.red.opacity(0.1)).frame(width: 56, height: 56)
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Styles.rydrGradient)
        }
    }

    private var phoneField: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("🇺🇸")
                Text(verbatim: "+1").fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)

            Divider().frame(height: 24)

            TextField("Enter phone number", text: Binding(
                get: { phoneNumber },
                set: { phoneNumber = String($0.filter { $0.isNumber }.prefix(10)) }
            ))
            .keyboardType(.numberPad)
            .textContentType(.telephoneNumber)
            .focused($isFieldFocused)
            .padding(.vertical, 16)
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .accessibilityLabel("Phone Number Field")
            .accessibilityIdentifier("smsPhoneNumber")
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.systemGray4), lineWidth: 1.2)
        )
    }

    private var sendCodeButton: some View {
        Button(action: sendCode) {
            HStack {
                Image(systemName: "paperplane.fill")
                Text(sms.buttonTitle)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
        .disabled(!sms.canSend || !isPhoneValid)
        .foregroundColor(.white)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isPhoneValid && sms.canSend ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color.gray.opacity(0.5)))
        )
        .shadow(color: Color.red.opacity(isPhoneValid ? 0.25 : 0), radius: 12, y: 6)
        .accessibilityLabel(sms.buttonTitle)
        .accessibilityIdentifier("smsSend")
    }

    private var decorativeDivider: some View {
        HStack {
            VStack { Divider() }
            ZStack {
                Circle().fill(Color.red.opacity(0.1)).frame(width: 28, height: 28)
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(Styles.rydrGradient)
            }
            VStack { Divider() }
        }
    }

    private var featureRow: some View {
        HStack(spacing: 0) {
            featureColumn(icon: "checkmark.shield.fill", title: "Secure", subtitle: "Your info is encrypted and protected.")
            Divider().frame(height: 48)
            featureColumn(icon: "bolt.fill", title: "Quick", subtitle: "Verification takes less than 30 seconds.")
            Divider().frame(height: 48)
            featureColumn(icon: "person.fill", title: "Reliable", subtitle: "We'll never share your number or spam you.")
        }
    }

    private func featureColumn(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(Color.red.opacity(0.1)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Styles.rydrGradient)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Firebase

    private func sendCode() {
        guard isPhoneValid else { return }
        sms.send(phone: e164Phone) { session in
            onCodeSent(session.verificationID, session.phoneNumber)
        }
    }
}
