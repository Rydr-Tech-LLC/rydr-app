//
//  DriverLogin.swift
//  Rydr Driver
//
//  Driver login aligned with the rider app phone authentication flow.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

struct DriverLoginView: View {
    private struct DriverLoginProfile {
        let name: String
        let email: String
    }

    @EnvironmentObject var session: DriverSessionManager

    @State private var isUsingEmail = false
    @State private var phoneNumber = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showLogo = false
    @State private var errorMessage = ""
    @State private var showPasswordResetAlert = false
    @State private var isSendingCode = false
    @State private var isLoggingIn = false
    @State private var showingSignup = false
    @State private var verificationSession: DriverPhoneVerificationSession?

    private var sanitizedDigits: String {
        String(phoneNumber.filter { $0.isNumber }.prefix(10))
    }

    private var isPhoneValid: Bool {
        sanitizedDigits.count == 10
    }

    private var e164Phone: String {
        "+1" + sanitizedDigits
    }

    var body: some View {
        VStack(spacing: 25) {
            Image("Rydr - Driver")
                .resizable()
                .scaledToFit()
                .frame(width: 210, height: 210)
                .opacity(showLogo ? 1 : 0)
                .scaleEffect(showLogo ? 1 : 0.92)
                .animation(.spring(response: 0.75, dampingFraction: 0.82), value: showLogo)
                .onAppear { showLogo = true }
                .padding(.top, 12)
                .accessibilityLabel("Rydr Driver logo")

            Text("Driver Sign In")
                .font(.title)
                .foregroundStyle(Styles.rydrGradient)

            HStack {
                Text("Not a driver yet?")
                Button(action: { showingSignup = true }) {
                    Text("Sign up")
                        .underline()
                        .fontWeight(.semibold)
                        .foregroundStyle(Styles.rydrGradient)
                }
                .buttonStyle(.plain)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 8)

            if !isUsingEmail {
                phoneLoginFields
            }

            if isUsingEmail {
                emailLoginFields
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
        .hideKeyboardOnTap()
        .alert(isPresented: $showPasswordResetAlert) {
            Alert(
                title: Text("Reset Email Sent"),
                message: Text("Check your inbox at \(email) for a link to reset your password."),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showingSignup) {
            DriverSignupCoordinator()
                .environmentObject(session)
        }
        .sheet(item: $verificationSession) { verificationSession in
            DriverVerificationCodeView(
                verificationID: verificationSession.verificationID,
                phoneNumber: verificationSession.phoneNumber,
                onSuccess: { user in
                    self.verificationSession = nil
                    completePhoneLogin(for: user)
                },
                onResendCode: {
                    sendCode()
                }
            )
        }
    }

    private var phoneLoginFields: some View {
        VStack(spacing: 12) {
            HStack {
                Text("🇺🇸 +1")
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                TextField("Phone number", text: Binding(
                    get: { phoneNumber },
                    set: { phoneNumber = String($0.filter { $0.isNumber }.prefix(10)) }
                ))
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .textContentType(.telephoneNumber)
                .accessibilityLabel("US Phone Number Field")
            }
            .padding(.bottom, 4)

            Text("US numbers only. Enter your 10-digit number.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(isSendingCode ? "Sending..." : "Send Code") {
                sendCode()
            }
            .disabled(isSendingCode || !isPhoneValid)
            .frame(maxWidth: .infinity)
            .padding()
            .background(isPhoneValid && !isSendingCode ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color.gray))
            .foregroundColor(.white)
            .cornerRadius(10)
            .accessibilityLabel("Send Verification Code")

            Button("Use email and password instead") {
                withAnimation { isUsingEmail = true }
            }
            .font(.caption)
            .accessibilityLabel("Switch to email and password login")
        }
    }

    private var emailLoginFields: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .accessibilityLabel("Email Field")

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .accessibilityLabel("Password Field")

            Button(isLoggingIn ? "Logging In..." : "Log In with Email") {
                emailPasswordLogin()
            }
            .disabled(isLoggingIn || email.isEmpty || password.isEmpty || !isValidEmail(email))
            .opacity(email.isEmpty || password.isEmpty || !isValidEmail(email) ? 0.5 : 1.0)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Styles.rydrGradient)
            .foregroundColor(.white)
            .cornerRadius(10)
            .accessibilityLabel("Login with Email")

            Button("Forgot Password?") {
                sendPasswordReset()
            }
            .font(.caption)
            .foregroundColor(.blue)
            .accessibilityLabel("Reset password via email")

            Button("Use phone number instead") {
                withAnimation { isUsingEmail = false }
            }
            .font(.caption)
            .accessibilityLabel("Switch to phone login")
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "(?:[A-Z0-9a-z._%+-]+)@(?:[A-Z0-9a-z.-]+)\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", emailRegEx).evaluate(with: email)
    }

    private func emailPasswordLogin() {
        guard !email.isEmpty, !password.isEmpty, isValidEmail(email) else {
            errorMessage = "Please enter a valid email and password."
            return
        }

        errorMessage = ""
        isLoggingIn = true
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            Task { @MainActor in
                isLoggingIn = false
                if let error {
                    errorMessage = "Login failed: \(error.localizedDescription)"
                    return
                }

                guard let user = result?.user else {
                    errorMessage = "Login failed: missing user."
                    return
                }

                loadDriverProfile(for: user, fallbackEmail: email)
            }
        }
    }

    private func sendPasswordReset() {
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address."
            return
        }

        Auth.auth().sendPasswordReset(withEmail: email) { error in
            Task { @MainActor in
                if let error = error as NSError?,
                   let code = AuthErrorCode(rawValue: error.code) {
                    switch code {
                    case .userNotFound:
                        errorMessage = "No account found with this email."
                    case .invalidRecipientEmail:
                        errorMessage = "The reset email address is invalid."
                    case .invalidSender:
                        errorMessage = "Invalid email sender. Please contact support."
                    default:
                        errorMessage = "Reset failed: \(error.localizedDescription)"
                    }
                } else {
                    errorMessage = ""
                    showPasswordResetAlert = true
                }
            }
        }
    }

    private func sendCode() {
        guard isPhoneValid else {
            errorMessage = "Please enter a valid 10-digit phone number."
            return
        }

        let phone = e164Phone
        errorMessage = ""
        isSendingCode = true

        PhoneAuthProvider.provider().verifyPhoneNumber(phone, uiDelegate: nil) { verificationID, error in
            Task { @MainActor in
                isSendingCode = false
                if let error {
                    errorMessage = "Failed to send code: \(error.localizedDescription)"
                    return
                }

                guard let verificationID, !verificationID.isEmpty else {
                    errorMessage = "Firebase did not return a verification session. Please resend the code."
                    return
                }

                verificationSession = DriverPhoneVerificationSession(
                    verificationID: verificationID,
                    phoneNumber: phone
                )
            }
        }
    }

    private func completePhoneLogin(for user: User) {
        let phone = user.phoneNumber ?? e164Phone

        Firestore.firestore()
            .collection("drivers")
            .document(user.uid)
            .getDocument { snapshot, error in
                Task { @MainActor in
                    if let error {
                        try? Auth.auth().signOut()
                        errorMessage = "Unable to load driver account: \(error.localizedDescription)"
                        return
                    }

                    if let snapshot, snapshot.exists {
                        let profile = makeLoginProfile(from: snapshot.data() ?? [:], user: user, fallbackEmail: user.email ?? "")
                        session.login(name: profile.name, email: profile.email)
                        return
                    }

                    lookupDriverByPhone(phone, signedInUser: user)
                }
            }
    }

    private func lookupDriverByPhone(_ phone: String, signedInUser user: User) {
        Firestore.firestore()
            .collection("drivers")
            .whereField("phoneE164", isEqualTo: phone)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                Task { @MainActor in
                    if let error {
                        try? Auth.auth().signOut()
                        errorMessage = "Unable to load phone account: \(error.localizedDescription)"
                        return
                    }

                    if let document = snapshot?.documents.first {
                        handlePhoneMatchedDriver(documentID: document.documentID, data: document.data(), user: user)
                        return
                    }

                    lookupDriverByLegacyPhone(phone, signedInUser: user)
                }
            }
    }

    private func lookupDriverByLegacyPhone(_ phone: String, signedInUser user: User) {
        Firestore.firestore()
            .collection("drivers")
            .whereField("phoneNumber", isEqualTo: phone)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                Task { @MainActor in
                    if let error {
                        try? Auth.auth().signOut()
                        errorMessage = "Unable to load phone account: \(error.localizedDescription)"
                        return
                    }

                    guard let document = snapshot?.documents.first else {
                        try? Auth.auth().signOut()
                        errorMessage = "No driver account was found for this phone number. Please sign up or use email login."
                        return
                    }

                    handlePhoneMatchedDriver(documentID: document.documentID, data: document.data(), user: user)
                }
            }
    }

    private func handlePhoneMatchedDriver(documentID: String, data: [String: Any], user: User) {
        guard documentID == user.uid else {
            try? Auth.auth().signOut()
            let profile = makeLoginProfile(from: data, user: user, fallbackEmail: data["email"] as? String ?? "")
            errorMessage = "This phone number belongs to \(profile.email). Sign in with email first, then verify this phone number to link phone login."
            return
        }

        let profile = makeLoginProfile(from: data, user: user, fallbackEmail: user.email ?? "")
        session.login(name: profile.name, email: profile.email)
    }

    private func loadDriverProfile(for user: User, fallbackEmail: String) {
        Firestore.firestore()
            .collection("drivers")
            .document(user.uid)
            .getDocument { snapshot, error in
                Task { @MainActor in
                    if let error {
                        errorMessage = "Login failed while loading your profile: \(error.localizedDescription)"
                        return
                    }

                    let profile = makeLoginProfile(from: snapshot?.data() ?? [:], user: user, fallbackEmail: fallbackEmail)
                    session.login(name: profile.name, email: profile.email)
                }
            }
    }

    private func makeLoginProfile(from profile: [String: Any], user: User, fallbackEmail: String) -> DriverLoginProfile {
        let first = profile["firstName"] as? String ?? ""
        let last = profile["lastName"] as? String ?? ""
        let preferred = profile["preferredName"] as? String ?? ""
        let displayName = profile["displayName"] as? String ?? ""
        let legalName = [first, last]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        let name: String
        if !displayName.isEmpty {
            name = displayName
        } else if !preferred.isEmpty {
            name = preferred
        } else if !legalName.isEmpty {
            name = legalName
        } else {
            name = user.displayName ?? "Rydr Driver"
        }

        let email = profile["email"] as? String ?? user.email ?? fallbackEmail
        return DriverLoginProfile(name: name, email: email)
    }
}

private struct DriverPhoneVerificationSession: Identifiable, Hashable {
    let verificationID: String
    let phoneNumber: String

    var id: String { verificationID }
}

private struct DriverVerificationCodeView: View {
    let verificationID: String
    let phoneNumber: String
    var onSuccess: (User) -> Void
    var onResendCode: () -> Void

    @State private var verificationCode = ""
    @State private var isVerifying = false
    @State private var errorMessage = ""
    @State private var canResend = false
    @State private var countdown = 30
    @State private var progress: CGFloat = 1.0
    @State private var timer: Timer?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 10) {
                Text("Verify Your Phone")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("We sent a code to:")
                    .foregroundColor(.gray)

                Text(phoneNumber)
                    .font(.headline)
            }

            TextField("Enter 6-digit code", text: Binding(
                get: { verificationCode },
                set: { verificationCode = String($0.filter { $0.isNumber }.prefix(6)) }
            ))
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onAppear {
                isFocused = true
                startCountdown()
            }

            if !canResend {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)

                        Capsule()
                            .fill(Styles.rydrGradient)
                            .frame(width: progress * proxy.size.width, height: 6)
                            .animation(.linear(duration: 1), value: progress)
                    }
                }
                .frame(height: 6)
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            Button(action: verifyCode) {
                Text(isVerifying ? "Verifying..." : "Continue")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(verificationCode.count == 6 ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color.gray))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(isVerifying || verificationCode.count != 6)

            if canResend {
                Button("Resend Code") {
                    onResendCode()
                    startCountdown()
                }
                .foregroundColor(.blue)
            } else {
                Text("You can resend in \(countdown)s")
                    .foregroundColor(.gray)
                    .font(.footnote)
            }

            Spacer()
        }
        .padding()
        .onDisappear {
            timer?.invalidate()
        }
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

        Auth.auth().signIn(with: credential) { result, error in
            Task { @MainActor in
                isVerifying = false
                if let error {
                    if let authCode = AuthErrorCode(rawValue: (error as NSError).code),
                       authCode == .credentialAlreadyInUse || authCode == .providerAlreadyLinked {
                        errorMessage = "That phone number is already attached to another sign-in. Sign in with the original account or remove the duplicate test phone user in Firebase, then try again."
                    } else {
                        errorMessage = "Verification failed: \(error.localizedDescription)"
                    }
                    return
                }

                guard let user = result?.user else {
                    errorMessage = "Verification failed: missing user."
                    return
                }

                onSuccess(user)
            }
        }
    }

    private func startCountdown() {
        canResend = false
        countdown = 30
        progress = 1.0
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            if countdown > 0 {
                countdown -= 1
                progress = CGFloat(countdown) / 30.0
            } else {
                canResend = true
                progress = 0.0
                t.invalidate()
            }
        }
    }
}

// MARK: - Small tap-to-dismiss keyboard helper
extension View {
    func hideKeyboardOnTap() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded {
                #if canImport(UIKit)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
            }, including: .all
        )
    }
}
