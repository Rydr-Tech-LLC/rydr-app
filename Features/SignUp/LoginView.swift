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
    
    var body: some View {
        VStack(spacing: 25) {
            Image("RydrLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .opacity(showLogo ? 1 : 0)
                .animation(.easeIn(duration: 1.0), value: showLogo)
                .onAppear { showLogo = true }
                .padding(.top)
                .accessibilityLabel("Rydr logo")
            
            Text("Hello There!")
                .font(.title)
                .foregroundStyle(Styles.rydrGradient)
            
            // MARK: - Phone Login
            if !isUsingEmail {
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
                    .accessibilityLabel("US Phone Number Field")
                }
                .padding(.bottom, 4)
                Text("US numbers only. Enter your 10-digit number.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Send Code") {
                    sendCode()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Styles.rydrGradient)
                .foregroundColor(.white)
                .cornerRadius(10)
                .accessibilityLabel("Send Verification Code")
                
                Button("Use email and password instead") {
                    withAnimation { isUsingEmail = true }
                }
                .font(.caption)
                .accessibilityLabel("Switch to email and password login")

                if let repair = pendingPhoneLoginRepair {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Confirm your password for \(repair.profile.email) to enable phone login on this account.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        SecureField("Password", text: $phoneRepairPassword)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Password for Phone Login Link")

                        Button(isRepairingPhoneLogin ? "Linking..." : "Link Phone and Log In") {
                            repairPhoneLogin()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(phoneRepairPassword.isEmpty || isRepairingPhoneLogin ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .disabled(phoneRepairPassword.isEmpty || isRepairingPhoneLogin)
                    }
                    .padding(.top, 8)
                }
            }
            
            // MARK: - Email Login
            if isUsingEmail {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .accessibilityLabel("Email Field")
                
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Password Field")
                
                Button("Log In with Email") {
                    guard !email.isEmpty, !password.isEmpty else {
                        errorMessage = "Please enter both email and password."
                        return
                    }
                    
                    guard isValidEmail(email) else {
                        errorMessage = "Please enter a valid email address."
                        return
                    }
                    
                    Auth.auth().signIn(withEmail: email, password: password) { result, error in
                        if let error = error {
                            errorMessage = "Login failed: \(error.localizedDescription)"
                        } else if let user = result?.user {
                            completeEmailLogin(for: user, fallbackEmail: email)
                        }
                        
                    }
                
                }
                .disabled(email.isEmpty || password.isEmpty)
                .opacity(email.isEmpty || password.isEmpty ? 0.5 : 1.0)
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
            
            Divider().padding(.vertical)
            
            // MARK: - Apple & Google Sign-In
            Button(action: {
                // TODO: Handle Apple Sign-In
            }) {
                Label("Sign in with Apple", systemImage: "apple.logo")
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color.black)
            .foregroundColor(.white)
            .cornerRadius(10)
            .accessibilityLabel("Sign in with Apple")
            
            Button(action: {
                // TODO: Handle Google Sign-In
            }) {
                Label("Sign in with Google", systemImage: "globe")
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color.white)
            .foregroundColor(.black)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
            )
            .accessibilityLabel("Sign in with Google")
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
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
