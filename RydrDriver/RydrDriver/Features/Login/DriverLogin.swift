//
//  DriverLogin.swift
//  Rydr Driver
//
//  Driver login aligned with the rider app phone authentication flow.
//

import SwiftUI
import Combine
import AuthenticationServices
import FirebaseAuth
import FirebaseFirestore

struct DriverLoginView: View {
    private struct DriverLoginProfile {
        let name: String
        let email: String
    }

    @EnvironmentObject var session: DriverSessionManager

    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var showLogo = false
    @State private var errorMessage = ""
    @State private var showPasswordResetAlert = false
    @State private var isLoggingIn = false
    @State private var showingSignup = false
    @State private var currentNonce: String?

    // Dedicated full-screen phone verification flow (shared with driver signup).
    @State private var showPhoneFlow = false
    @State private var phoneFlowPath: [DriverLoginPhoneStep] = []
    @State private var pendingVerificationID = ""
    @State private var pendingPhone = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                logoLockup
                    .padding(.top, 12)

                VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        Text("Driver ")
                            .foregroundColor(.primary)
                        Text("Sign In")
                            .foregroundStyle(Styles.rydrGradient)
                    }
                    .font(.system(size: 32, weight: .heavy, design: .rounded))

                    Text("Access your dashboard and manage your rides.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                socialLoginFields

                signupPrompt

                promoCard

                emailLoginFields

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }

                featureRow
            }
            .padding(.horizontal, 20)
        }
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
        .fullScreenCover(isPresented: $showPhoneFlow) {
            phoneFlowCover
        }
    }

    private var signupPrompt: some View {
        Button(action: { showingSignup = true }) {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.plus.fill")
                    .font(.subheadline.weight(.semibold))
                Text("Don't have an account? Sign Up")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
        }
        .foregroundStyle(Styles.rydrGradient)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.red.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.red.opacity(0.18), lineWidth: 1)
        )
        .buttonStyle(.plain)
        .accessibilityLabel("Sign up for a driver account")
    }

    private enum DriverLoginPhoneStep: Hashable {
        case code
    }

    private var phoneFlowCover: some View {
        NavigationStack(path: $phoneFlowPath) {
            DriverPhoneEntryView(
                onCodeSent: { verificationID, phone in
                    pendingVerificationID = verificationID
                    pendingPhone = phone
                    phoneFlowPath.append(.code)
                },
                onClose: { showPhoneFlow = false }
            )
            .navigationDestination(for: DriverLoginPhoneStep.self) { step in
                switch step {
                case .code:
                    DriverPhoneCodeEntryView(
                        verificationID: $pendingVerificationID,
                        phoneNumber: pendingPhone,
                        onEditNumber: {
                            if !phoneFlowPath.isEmpty { phoneFlowPath.removeLast() }
                        },
                        onResendCode: { resendLoginCode() },
                        onVerify: { credential, completion in
                            Auth.auth().signIn(with: credential) { result, error in
                                Task { @MainActor in
                                    if let error {
                                        completion(.failure(error))
                                        return
                                    }
                                    guard let user = result?.user else {
                                        completion(.failure(NSError(domain: "DriverLogin", code: -1, userInfo: [NSLocalizedDescriptionKey: "Verification failed: missing user."])))
                                        return
                                    }
                                    completion(.success(user))
                                    showPhoneFlow = false
                                    phoneFlowPath = []
                                    completePhoneLogin(for: user)
                                }
                            }
                        }
                    )
                }
            }
        }
    }

    private var logoLockup: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    Styles.rydrGradient,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 6])
                )
                .frame(width: 220, height: 220)

            VStack(spacing: 2) {
                Image("Rydr - Driver")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .accessibilityHidden(true)

                Text("Rydr")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Styles.rydrGradient)

                Text("Drive Different")
                    .font(.system(size: 13, weight: .medium))
                    .italic()
                    .foregroundStyle(Styles.rydrGradient.opacity(0.85))
            }
        }
        .opacity(showLogo ? 1 : 0)
        .scaleEffect(showLogo ? 1 : 0.92)
        .animation(.spring(response: 0.75, dampingFraction: 0.82), value: showLogo)
        .onAppear { showLogo = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rydr Driver logo")
    }

    private var promoCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "shield.checkered")
                    .foregroundStyle(Styles.rydrGradient)
                    .font(.system(size: 18, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("You're in control")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)
                Text("Flexible driving. Great earnings. Unmatched support.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Divider().frame(height: 32)

            Image(systemName: "arrow.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Styles.rydrGradient)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.red.opacity(0.06))
        )
    }

    private var featureRow: some View {
        HStack(spacing: 0) {
            featureColumn(icon: "dollarsign.circle.fill", title: "Keep More", subtitle: "Higher earnings")
            Divider().frame(height: 36)
            featureColumn(icon: "clock.fill", title: "Work Your Way", subtitle: "Drive when you want")
            Divider().frame(height: 36)
            featureColumn(icon: "shield.checkered", title: "We've Got You", subtitle: "Safety first, always")
        }
        .padding(.top, 8)
    }

    private func featureColumn(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Styles.rydrGradient)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var orDivider: some View {
        HStack {
            VStack { Divider() }
            Text("OR")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack { Divider() }
        }
        .padding(.vertical, 4)
    }

    private var socialLoginFields: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                    let nonce = DriverSocialAuthService.randomNonceString()
                    currentNonce = nonce
                    request.nonce = DriverSocialAuthService.sha256(nonce)
                },
                onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        socialLoginWithApple(authorization)
                    case .failure(let error):
                        errorMessage = "Apple sign-in failed: \(error.localizedDescription)"
                    }
                }
            )
            .signInWithAppleButtonStyle(.black)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(action: socialLoginWithGoogle) {
                HStack {
                    Image(systemName: "g.circle.fill")
                    Text("Continue with Google")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .frame(height: 54)
            }
            .foregroundColor(.primary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
            .buttonStyle(.plain)
        }
    }

    private var emailLoginFields: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(Styles.rydrGradient)
                    .frame(width: 20)

                TextField("Email address", text: $email)
                    .autocapitalization(.none)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .accessibilityLabel("Email Field")
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )

            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Styles.rydrGradient)
                    .frame(width: 20)

                Group {
                    if isPasswordVisible {
                        TextField("Password", text: $password)
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                .textContentType(.password)
                .accessibilityLabel("Password Field")

                Button(action: { isPasswordVisible.toggle() }) {
                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )

            Button(isLoggingIn ? "Logging In..." : "Log In with Email") {
                emailPasswordLogin()
            }
            .disabled(isLoggingIn || email.isEmpty || password.isEmpty || !isValidEmail(email))
            .opacity(email.isEmpty || password.isEmpty || !isValidEmail(email) ? 0.5 : 1.0)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Styles.rydrGradient)
            .foregroundColor(.white)
            .cornerRadius(14)
            .padding(.top, 4)
            .accessibilityLabel("Login with Email")

            Button("Forgot Password?") {
                sendPasswordReset()
            }
            .font(.caption)
            .foregroundColor(.blue)
            .accessibilityLabel("Reset password via email")

            orDivider

            Button(action: { showPhoneFlow = true }) {
                HStack {
                    Image(systemName: "phone.fill")
                    Text("Use phone number instead")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 18)
                .frame(height: 54)
            }
            .foregroundStyle(Styles.rydrGradient)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Styles.rydrGradient, lineWidth: 1.5)
            )
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

    private func socialLoginWithGoogle() {
        errorMessage = ""
        isLoggingIn = true
        DriverSocialAuthService.signInWithGoogle { result in
            switch result {
            case .success(let payload):
                signInWithSocialCredential(payload.0, fallbackEmail: payload.1.email)
            case .failure(let error):
                Task { @MainActor in
                    isLoggingIn = false
                    errorMessage = "Google sign-in failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func socialLoginWithApple(_ authorization: ASAuthorization) {
        guard let nonce = currentNonce else {
            errorMessage = "Apple sign-in could not verify this request. Please try again."
            return
        }

        switch DriverSocialAuthService.credential(from: authorization, nonce: nonce) {
        case .success(let payload):
            errorMessage = ""
            isLoggingIn = true
            signInWithSocialCredential(payload.0, fallbackEmail: payload.1.email)
        case .failure(let error):
            errorMessage = "Apple sign-in failed: \(error.localizedDescription)"
        }
    }

    private func signInWithSocialCredential(_ credential: AuthCredential, fallbackEmail: String) {
        Auth.auth().signIn(with: credential) { result, error in
            Task { @MainActor in
                isLoggingIn = false
                if let error {
                    errorMessage = "Sign-in failed: \(error.localizedDescription)"
                    return
                }

                guard let user = result?.user else {
                    errorMessage = "Sign-in failed: missing user."
                    return
                }

                loadDriverProfile(for: user, fallbackEmail: fallbackEmail)
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

    /// Sends a fresh Firebase verification code for the in-progress login phone
    /// number, updating `pendingVerificationID` in place so the presented
    /// DriverPhoneCodeEntryView (bound to it) doesn't need to be recreated.
    private func resendLoginCode() {
        guard !pendingPhone.isEmpty else { return }
        PhoneAuthProvider.provider().verifyPhoneNumber(pendingPhone, uiDelegate: nil) { verificationID, error in
            Task { @MainActor in
                guard let verificationID, !verificationID.isEmpty, error == nil else { return }
                pendingVerificationID = verificationID
            }
        }
    }

    private func completePhoneLogin(for user: User) {
        let phone = user.phoneNumber ?? pendingPhone

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
                        backfillPhoneIndexIfNeeded(phone: phone, uid: user.uid)
                        return
                    }

                    lookupDriverByPhone(phone, signedInUser: user)
                }
            }
    }

    private func lookupDriverByPhone(_ phone: String, signedInUser user: User) {
        // /drivers disallows `list` entirely (to prevent phone-number enumeration), so we
        // can't query it by phone field directly. Resolve via the dedicated phone->uid
        // pointer doc instead, then fetch the driver's own document by uid (a `get`,
        // which the rules allow for the owning uid or a verified-phone match).
        Firestore.firestore()
            .collection("driverPhoneIndex")
            .document(phone)
            .getDocument { snapshot, error in
                Task { @MainActor in
                    if let error {
                        try? Auth.auth().signOut()
                        errorMessage = "Unable to load phone account: \(error.localizedDescription)"
                        return
                    }

                    guard let mappedUid = snapshot?.data()?["uid"] as? String else {
                        try? Auth.auth().signOut()
                        errorMessage = "No driver account was found for this phone number. Please sign up or use email login."
                        return
                    }

                    fetchDriverDocument(uid: mappedUid, signedInUser: user)
                }
            }
    }

    /// Self-heals accounts created before the driverPhoneIndex pointer existed, so future
    /// phone-based lookups for this driver don't need to fall back to a blocked query.
    private func backfillPhoneIndexIfNeeded(phone: String, uid: String) {
        let index = Firestore.firestore().collection("driverPhoneIndex").document(phone)
        index.getDocument { snapshot, _ in
            guard snapshot?.exists != true else { return }
            index.setData(["uid": uid, "createdAt": FieldValue.serverTimestamp()])
        }
    }

    private func fetchDriverDocument(uid: String, signedInUser user: User) {
        Firestore.firestore()
            .collection("drivers")
            .document(uid)
            .getDocument { snapshot, error in
                Task { @MainActor in
                    if let error {
                        try? Auth.auth().signOut()
                        errorMessage = "Unable to load driver account: \(error.localizedDescription)"
                        return
                    }

                    guard let snapshot, snapshot.exists else {
                        try? Auth.auth().signOut()
                        errorMessage = "No driver account was found for this phone number. Please sign up or use email login."
                        return
                    }

                    handlePhoneMatchedDriver(documentID: snapshot.documentID, data: snapshot.data() ?? [:], user: user)
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
        let first = (profile["firstName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (profile["lastName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = (profile["preferredName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (profile["displayName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let legalName = [first, last]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let name: String
        if !preferred.isEmpty {
            name = preferred
        } else if !legalName.isEmpty {
            name = legalName
        } else if !displayName.isEmpty, displayName != "Rydr Driver" {
            name = displayName
        } else {
            name = user.displayName ?? "Rydr Driver"
        }

        let email = profile["email"] as? String ?? user.email ?? fallbackEmail
        return DriverLoginProfile(name: name, email: email)
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
