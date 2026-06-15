//
//  Untitled.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/14/25.
//
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct LoginView: View {
    private struct LoginProfile {
        let name: String
        let email: String
        let phoneNumber: String
    }

    private struct PhoneLoginRepair {
        let profile: LoginProfile
        let credential: AuthCredential
        let duplicatePhoneUser: User
    }

    @EnvironmentObject var session: UserSessionManager
    
    @State private var isUsingEmail = false
    @State private var phoneNumber = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showLogo = false
    @State private var errorMessage = ""
    @State private var showPasswordResetAlert = false
    @State private var verificationSession: PhoneVerificationSession?
    @State private var pendingPhoneLoginRepair: PhoneLoginRepair?
    @State private var phoneRepairPassword = ""
    @State private var isRepairingPhoneLogin = false
    
    private var formattedPhoneNumber: String {
        let digits = phoneNumber.filter { $0.isNumber }.prefix(10)
        return "+1" + digits
    }

    private var canSubmitEmail: Bool {
        !email.isEmpty && !password.isEmpty
    }

    private var canSendPhoneCode: Bool {
        phoneNumber.filter { $0.isNumber }.count == 10
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
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

            RiderLoginCitySilhouette()
                .frame(height: 190)
                .opacity(0.22)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityHidden(true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    header

                    VStack(spacing: 18) {
                        if isUsingEmail {
                            emailLoginSection
                        } else {
                            phoneLoginSection
                        }

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                                .accessibilityLabel(errorMessage)
                        }

                        divider
                        socialLoginSection
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 54)
                .padding(.bottom, 42)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .hideKeyboardOnTap()
        .alert(isPresented: $showPasswordResetAlert) {
            Alert(
                title: Text("Reset Email Sent"),
                message: Text("Check your inbox at \(email) for a link to reset your password."),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(item: $verificationSession) { verificationSession in
            VerificationCodeView(
                verificationID: verificationSession.verificationID,
                phoneNumber: verificationSession.phoneNumber,
                linkToCurrentUser: false,
                onSuccess: { user in
                    self.verificationSession = nil
                    completePhoneLogin(for: user)
                },
                onCredentialSuccess: { credential, user in
                    self.verificationSession = nil
                    completePhoneLogin(for: user, credential: credential)
                },
                onResendCode: {
                    sendCode()
                }
            )
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image("RydrLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
                .opacity(showLogo ? 1 : 0)
                .scaleEffect(showLogo ? 1 : 0.94)
                .animation(.easeOut(duration: 0.7), value: showLogo)
                .onAppear { showLogo = true }
                .accessibilityLabel("Rydr logo")

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("Hello")
                        .foregroundColor(Color(red: 0.05, green: 0.09, blue: 0.16))
                    Text("There!")
                        .foregroundStyle(Styles.rydrGradient)
                }
                .font(.system(size: 39, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.82)

                Text("Let's get you started.")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var phoneLoginSection: some View {
        VStack(spacing: 18) {
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("🇺🇸")
                        .font(.title3)
                    Text("+1")
                        .font(.headline.weight(.bold))
                        .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.14))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                }
                .frame(width: 138)
                .frame(maxHeight: .infinity)
                .background(Color(.systemGray6).opacity(0.75))

                TextField("Phone number", text: Binding(
                    get: { phoneNumber },
                    set: { phoneNumber = String($0.filter { $0.isNumber }.prefix(10)) }
                ))
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 20)
                .accessibilityLabel("US phone number field")
            }
            .frame(height: 66)
            .background(Color.white.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.09), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 8)

            Text("US numbers only. Enter your 10-digit number.")
                .font(.footnote.weight(.medium))
                .foregroundColor(.secondary)

            Button {
                sendCode()
            } label: {
                Label("Send Code", systemImage: "message")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
            }
            .background(Styles.rydrGradient.opacity(canSendPhoneCode ? 1 : 0.45))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.red.opacity(canSendPhoneCode ? 0.24 : 0.05), radius: 18, x: 0, y: 12)
            .disabled(!canSendPhoneCode)
            .accessibilityLabel("Send verification code")

            Button {
                withAnimation(.easeInOut(duration: 0.22)) { isUsingEmail = true }
            } label: {
                Text("Use email and password instead")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Styles.rydrGradient)
            }
            .accessibilityLabel("Switch to email and password login")

            phoneRepairSection
        }
    }

    @ViewBuilder
    private var phoneRepairSection: some View {
        if let repair = pendingPhoneLoginRepair {
            VStack(alignment: .leading, spacing: 12) {
                Text("Confirm your password for \(repair.profile.email) to enable phone login on this account.")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                SecureField("Password", text: $phoneRepairPassword)
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(0.09), lineWidth: 1)
                    )
                    .accessibilityLabel("Password for phone login link")

                Button(isRepairingPhoneLogin ? "Linking..." : "Link Phone and Log In") {
                    repairPhoneLogin()
                }
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(phoneRepairPassword.isEmpty || isRepairingPhoneLogin ? Color.gray.opacity(0.45) : Color.black)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(phoneRepairPassword.isEmpty || isRepairingPhoneLogin)
            }
            .padding(16)
            .background(.white.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var emailLoginSection: some View {
        VStack(spacing: 14) {
            LoginInputField(title: "Email", text: $email, systemImage: "envelope", isSecure: false, keyboard: .emailAddress)
                .textInputAutocapitalization(.never)

            LoginInputField(title: "Password", text: $password, systemImage: "lock", isSecure: true, keyboard: .default)

            Button {
                loginWithEmail()
            } label: {
                Label("Log In with Email", systemImage: "arrow.right.circle")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
            }
            .disabled(!canSubmitEmail)
            .background(Styles.rydrGradient.opacity(canSubmitEmail ? 1 : 0.45))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.red.opacity(canSubmitEmail ? 0.2 : 0.05), radius: 18, x: 0, y: 12)
            .accessibilityLabel("Login with email")

            HStack {
                Button("Forgot Password?") {
                    sendPasswordReset()
                }
                .font(.footnote.weight(.bold))
                .foregroundColor(.secondary)
                .accessibilityLabel("Reset password via email")

                Spacer()

                Button("Use phone number") {
                    withAnimation(.easeInOut(duration: 0.22)) { isUsingEmail = false }
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(Styles.rydrGradient)
                .accessibilityLabel("Switch to phone login")
            }
        }
    }

    private var divider: some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
            Text("OR")
                .font(.footnote.weight(.bold))
                .foregroundColor(.secondary)
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }

    private var socialLoginSection: some View {
        VStack(spacing: 14) {
            Button(action: {
                // TODO: Handle Apple Sign-In
            }) {
                Label("Sign in with Apple", systemImage: "apple.logo")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
            }
            .background(Color(red: 0.05, green: 0.06, blue: 0.08))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
            .accessibilityLabel("Sign in with Apple")

            Button(action: {
                // TODO: Handle Google Sign-In
            }) {
                HStack(spacing: 12) {
                    GoogleGlyph()
                        .frame(width: 24, height: 24)
                    Text("Sign in with Google")
                        .font(.headline.weight(.bold))
                }
                .foregroundColor(Color(red: 0.16, green: 0.17, blue: 0.22))
                .frame(maxWidth: .infinity)
                .frame(height: 62)
            }
            .background(Color.white.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 8)
            .accessibilityLabel("Sign in with Google")
        }
    }
    
    // MARK: - Password Reset
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx =
        "(?:[A-Z0-9a-z._%+-]+)@(?:[A-Z0-9a-z.-]+)\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegEx)
        return predicate.evaluate(with: email)
    }
    
    private func sendPasswordReset() {
        // Simple email format validation
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address."
            return
        }
        
        // Firebase password reset
        Auth.auth().sendPasswordReset(withEmail: email) { error in
            if let error = error as NSError?,
               let errorCode = AuthErrorCode(rawValue: error.code) {
                switch errorCode {
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
    
    private func sendCode() {
        let formattedNumber = formattedPhoneNumber // always +1 plus digits
        pendingPhoneLoginRepair = nil
        phoneRepairPassword = ""
        isRepairingPhoneLogin = false
        
        PhoneAuthProvider.provider().verifyPhoneNumber(formattedNumber, uiDelegate: nil) { verificationID, error in
            Task { @MainActor in
                if let error = error {
                    errorMessage = "Failed to send code: \(error.localizedDescription)"
                    print("❌ Firebase OTP error:", error.localizedDescription)
                    return
                }

                guard let verificationID, !verificationID.isEmpty else {
                    errorMessage = "Firebase did not return a verification session. Please resend the code."
                    return
                }

                print("✅ Code sent. VerificationID:", verificationID)
                self.verificationSession = PhoneVerificationSession(
                    verificationID: verificationID,
                    phoneNumber: formattedNumber
                )
            }
        }
    }

    private func loginWithEmail() {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter both email and password."
            return
        }

        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address."
            return
        }

        errorMessage = ""
        Auth.auth().signIn(withEmail: email, password: password) { result, error in
            Task { @MainActor in
                if let error {
                    errorMessage = "Login failed: \(error.localizedDescription)"
                    return
                }

                guard let user = result?.user else {
                    errorMessage = "Login failed. Please try again."
                    return
                }

                completeEmailLogin(for: user, fallbackEmail: email)
            }
        }
    }

    private func completeEmailLogin(for user: User, fallbackEmail: String) {
        Firestore.firestore()
            .collection("riders")
            .document(user.uid)
            .getDocument { snapshot, error in
                Task { @MainActor in
                    if let error {
                        errorMessage = "Login failed while loading your profile: \(error.localizedDescription)"
                        return
                    }

                    let profile = snapshot?.data() ?? [:]
                    let loginProfile = makeLoginProfile(from: profile, user: user, fallbackEmail: fallbackEmail)
                    session.login(name: loginProfile.name, email: loginProfile.email)
                }
            }
    }

    private func makeLoginProfile(from profile: [String: Any], user: User, fallbackEmail: String) -> LoginProfile {
        let first = profile["firstName"] as? String ?? ""
        let last = profile["lastName"] as? String ?? ""
        let preferred = profile["preferredName"] as? String ?? ""
        let legalName = [first, last]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let name = preferred.isEmpty
            ? (legalName.isEmpty ? user.displayName ?? "Rydr User" : legalName)
            : preferred
        let email = profile["email"] as? String ?? user.email ?? fallbackEmail
        let phoneNumber = profile["phoneNumber"] as? String ?? ""

        return LoginProfile(name: name, email: email, phoneNumber: phoneNumber)
    }

    private func completePhoneLogin(for user: User, credential: AuthCredential? = nil) {
        let phone = user.phoneNumber ?? formattedPhoneNumber

        Firestore.firestore()
            .collection("riders")
            .whereField("phoneNumber", isEqualTo: phone)
            .limit(to: 2)
            .getDocuments { snapshot, error in
                Task { @MainActor in
                    if let error {
                        try? Auth.auth().signOut()
                        errorMessage = "Unable to load phone account: \(error.localizedDescription)"
                        return
                    }

                    let matchingProfiles = snapshot?.documents ?? []
                    if let profile = matchingProfiles.first(where: { $0.documentID != user.uid }) {
                        let loginProfile = makeLoginProfile(
                            from: profile.data(),
                            user: user,
                            fallbackEmail: profile.data()["email"] as? String ?? ""
                        )

                        if let credential {
                            pendingPhoneLoginRepair = PhoneLoginRepair(
                                profile: loginProfile,
                                credential: credential,
                                duplicatePhoneUser: user
                            )
                            phoneRepairPassword = ""
                            errorMessage = "This phone number belongs to \(loginProfile.email). Confirm your password to link phone login."
                        } else {
                            try? Auth.auth().signOut()
                            errorMessage = "This phone number is saved on \(loginProfile.email). Sign in with email first, then verify this phone number to link phone login."
                        }
                        return
                    }

                    let profile = matchingProfiles.first?.data() ?? [:]
                    let first = profile["firstName"] as? String ?? ""
                    let last = profile["lastName"] as? String ?? ""
                    let preferred = profile["preferredName"] as? String ?? ""
                    let displayName = preferred.isEmpty
                        ? [first, last].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                        : preferred
                    let email = profile["email"] as? String ?? user.email ?? ""

                    session.login(
                        name: displayName.isEmpty ? user.displayName ?? "Rydr User" : displayName,
                        email: email
                    )
                }
            }
    }

    private func repairPhoneLogin() {
        guard let repair = pendingPhoneLoginRepair else { return }
        guard !phoneRepairPassword.isEmpty else {
            errorMessage = "Enter your password to link phone login."
            return
        }

        isRepairingPhoneLogin = true
        errorMessage = ""

        repair.duplicatePhoneUser.delete { deleteError in
            if let deleteError {
                Task { @MainActor in
                    isRepairingPhoneLogin = false
                    errorMessage = "Unable to prepare phone login linking: \(deleteError.localizedDescription)"
                }
                return
            }

            Auth.auth().signIn(withEmail: repair.profile.email, password: phoneRepairPassword) { result, signInError in
                if let signInError {
                    Task { @MainActor in
                        isRepairingPhoneLogin = false
                        errorMessage = "Password confirmation failed: \(signInError.localizedDescription)"
                    }
                    return
                }

                guard let emailUser = result?.user else {
                    Task { @MainActor in
                        isRepairingPhoneLogin = false
                        errorMessage = "Unable to load your email account after password confirmation."
                    }
                    return
                }

                emailUser.link(with: repair.credential) { _, linkError in
                    Task { @MainActor in
                        isRepairingPhoneLogin = false

                        if let linkError {
                            errorMessage = "Unable to link phone login: \(linkError.localizedDescription)"
                            return
                        }

                        pendingPhoneLoginRepair = nil
                        phoneRepairPassword = ""
                        session.login(name: repair.profile.name, email: repair.profile.email)
                    }
                }
            }
        }
    }
}

private struct LoginInputField: View {
    let title: String
    @Binding var text: String
    let systemImage: String
    let isSecure: Bool
    let keyboard: UIKeyboardType

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 24)

            Group {
                if isSecure {
                    SecureField(title, text: $text)
                        .textContentType(.password)
                } else {
                    TextField(title, text: $text)
                        .textContentType(.emailAddress)
                }
            }
            .keyboardType(keyboard)
            .font(.body.weight(.semibold))
            .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.14))
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(Color.white.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

private struct GoogleGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)

            Text("G")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.26, green: 0.52, blue: 0.96),
                            Color(red: 0.92, green: 0.26, blue: 0.21),
                            Color(red: 0.98, green: 0.74, blue: 0.18),
                            Color(red: 0.20, green: 0.66, blue: 0.32)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .accessibilityHidden(true)
    }
}

private struct RiderLoginCitySilhouette: View {
    private let buildingHeights: [CGFloat] = [
        0.42, 0.64, 0.50, 0.78, 0.56, 0.70, 0.48, 0.86,
        0.60, 0.45, 0.76, 0.54, 0.68, 0.49, 0.82, 0.58
    ]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let maxHeight = proxy.size.height
            let buildingWidth = max(18, width / CGFloat(buildingHeights.count + 4))

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Styles.rydrGradient)
                    .frame(width: width * 1.18, height: maxHeight * 0.34)
                    .blur(radius: 18)
                    .offset(y: maxHeight * 0.22)
                    .opacity(0.42)

                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(buildingHeights.indices, id: \.self) { index in
                        VStack(spacing: 4) {
                            if index % 4 == 1 {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color.white.opacity(0.42))
                                    .frame(width: buildingWidth * 0.48, height: 5)
                            }

                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Styles.rydrGradient)
                                .frame(
                                    width: buildingWidth,
                                    height: maxHeight * buildingHeights[index]
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)

                Rectangle()
                    .fill(Styles.rydrGradient)
                    .frame(height: maxHeight * 0.18)
                    .blur(radius: 1)
            }
        }
        .allowsHitTesting(false)
    }
}
