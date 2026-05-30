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
    @EnvironmentObject var session: UserSessionManager
    
    @State private var isUsingEmail = false
    @State private var phoneNumber = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showLogo = false
    @State private var errorMessage = ""
    @State private var showPasswordResetAlert = false
    @State private var verificationSession: PhoneVerificationSession?
    
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
                            session.login(name: user.displayName ?? "Rydr User", email: user.email ?? email)
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

    private func completePhoneLogin(for user: User) {
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
                        let email = profile.data()["email"] as? String ?? "the email on this account"
                        try? Auth.auth().signOut()
                        errorMessage = "This phone number is saved on \(email). Sign in with email first, then verify this phone number to link phone login."
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
}
