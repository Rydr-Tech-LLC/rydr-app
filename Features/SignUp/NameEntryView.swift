//
//  NameEntryView.swift
//  RydrSignupFlow
//

import SwiftUI
import FirebaseAuth
import GoogleSignIn
import AuthenticationServices
import FirebaseCore
import FirebaseFirestore
import CryptoKit
import Security

struct RiderSocialAuthProfile {
    let firstName: String
    let lastName: String
    let email: String
    let providerID: String
}

struct NameEntryView: View {
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var preferredName: String
    @Binding var email: String
    var allowsSocialSignup = true

    var onContinueWithForm: () -> Void
    var onContinueWithSocial: (RiderSocialAuthProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var currentNonce: String?
    @State private var socialAuthAttemptID: UUID?

    private var canContinue: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSaving
    }

    var body: some View {
        SignupScreenScaffold(
            activeStep: 0,
            hero: {
                SignupAtlantaHero()
            },
            content: {
                VStack(spacing: 18) {
                    SignupBrandHeader()

                    SignupFormPanel {
                        SignupStepHeader(active: 0)

                        VStack(spacing: 8) {
                            Text("Tell Us Your Name")
                                .font(.system(size: 25, weight: .black, design: .rounded))
                                .foregroundStyle(SignupPalette.ink)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)

                            Text("Use the name your driver should recognize.")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(SignupPalette.muted)
                                .multilineTextAlignment(.center)
                        }

                        VStack(spacing: 12) {
                            SignupInputRow(icon: "person", placeholder: "First Name") {
                                TextField("First Name", text: $firstName)
                                    .textContentType(.givenName)
                            }

                            SignupInputRow(icon: "person.fill", placeholder: "Last Name") {
                                TextField("Last Name", text: $lastName)
                                    .textContentType(.familyName)
                            }

                            SignupInputRow(icon: "sparkles", placeholder: "Preferred Name (optional)") {
                                TextField("Preferred Name (optional)", text: $preferredName)
                                    .textContentType(.nickname)
                            }

                            SignupInputRow(icon: "envelope.fill", placeholder: "Email address") {
                                TextField("Email address", text: $email)
                                    .textContentType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .keyboardType(.emailAddress)
                            }
                        }

                        Button(isSaving ? "Saving..." : "Continue") {
                            isSaving = true
                            onContinueWithForm()
                            isSaving = false
                        }
                        .buttonStyle(SignupPrimaryButtonStyle())
                        .disabled(!canContinue)
                        .opacity(canContinue ? 1 : 0.56)

                        if allowsSocialSignup {
                            SignupDividerLabel(text: "or continue with")

                            SignInWithAppleButton(
                                .signUp,
                                onRequest: { request in
                                    request.requestedScopes = [.fullName, .email]
                                    let nonce = randomNonceString()
                                    currentNonce = nonce
                                    request.nonce = sha256(nonce)
                                },
                                onCompletion: { result in
                                    switch result {
                                    case .success(let authResults):
                                        handleAppleSignIn(result: authResults)
                                    case .failure(let error):
                                        errorMessage = "Apple sign-up failed: \(error.localizedDescription)"
                                    }
                                }
                            )
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .disabled(isSaving)

                            Button(action: handleGoogleSignIn) {
                                HStack(spacing: 10) {
                                    if isSaving {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "g.circle.fill")
                                            .font(.system(size: 21, weight: .bold))
                                    }
                                    Text(isSaving ? "Connecting..." : "Sign Up with Google")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(SignupPalette.softLine, lineWidth: 1)
                                }
                                .foregroundStyle(SignupPalette.ink)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSaving)
                        }

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundStyle(SignupPalette.red)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                        }

                        SignupSecurityFooter(text: "Your profile helps keep pickup and support personal.")
                    }
                }
            },
            onBack: { dismiss() }
        )
    }

    // MARK: - Google Sign-Up
    private func handleGoogleSignIn() {
        let rootViewController: UIViewController
        do {
            rootViewController = try RiderGoogleSignInCoordinator.presentingViewController()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let attemptID = beginSocialAuthAttempt()
        RiderGoogleSignInCoordinator.signIn(
            withPresenting: rootViewController,
            expectedEmail: email
        ) { result, error in
            Task { @MainActor in
                guard socialAuthAttemptID == attemptID else { return }
                if let error {
                    finishSocialAuthAttempt(attemptID, error: "Google sign-up failed: \(error.localizedDescription)")
                    return
                }
                guard let user = result?.user,
                      let idToken = user.idToken?.tokenString else {
                    finishSocialAuthAttempt(attemptID, error: "Google sign-up did not return a valid token.")
                    return
                }
                let accessToken = user.accessToken.tokenString
                let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
                authenticateWithSocialCredential(
                    credential,
                    profile: googleProfile(from: user),
                    attemptID: attemptID
                )
            }
        }
    }

    private func googleProfile(from user: GIDGoogleUser) -> RiderSocialAuthProfile {
        let givenName = user.profile?.givenName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let familyName = user.profile?.familyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName = user.profile?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let splitName = splitDisplayName(displayName)
        return RiderSocialAuthProfile(
            firstName: givenName.isEmpty ? splitName.first : givenName,
            lastName: familyName.isEmpty ? splitName.last : familyName,
            email: user.profile?.email ?? "",
            providerID: GoogleAuthProviderID
        )
    }

    private func authenticateWithSocialCredential(
        _ credential: AuthCredential,
        profile: RiderSocialAuthProfile,
        attemptID existingAttemptID: UUID? = nil
    ) {
        let attemptID = existingAttemptID ?? beginSocialAuthAttempt()
        if let currentUser = Auth.auth().currentUser {
            currentUser.link(with: credential) { _, err in
                Task { @MainActor in
                    guard socialAuthAttemptID == attemptID else { return }
                    if let err = err as NSError? {
                        if err.code == AuthErrorCode.providerAlreadyLinked.rawValue {
                            completeSocialSignup(profile: profile, attemptID: attemptID)
                            return
                        }
                        finishSocialAuthAttempt(attemptID, error: socialSignupErrorMessage(err))
                        return
                    }
                    completeSocialSignup(profile: profile, attemptID: attemptID)
                }
            }
        } else {
            Auth.auth().signIn(with: credential) { _, err in
                Task { @MainActor in
                    guard socialAuthAttemptID == attemptID else { return }
                    if let err {
                        finishSocialAuthAttempt(attemptID, error: "Social sign-up failed: \(err.localizedDescription)")
                        return
                    }
                    completeSocialSignup(profile: profile, attemptID: attemptID)
                }
            }
        }
    }

    @MainActor
    private func completeSocialSignup(profile: RiderSocialAuthProfile, attemptID: UUID) {
        applySocialProfile(profile)
        finishSocialAuthAttempt(attemptID)
        onContinueWithSocial(profile)
    }

    @MainActor
    private func beginSocialAuthAttempt() -> UUID {
        let attemptID = UUID()
        socialAuthAttemptID = attemptID
        isSaving = true
        errorMessage = ""
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard socialAuthAttemptID == attemptID else { return }
            finishSocialAuthAttempt(
                attemptID,
                error: "Sign-up is taking longer than expected. Check your connection and try again."
            )
        }
        return attemptID
    }

    @MainActor
    private func finishSocialAuthAttempt(_ attemptID: UUID, error: String? = nil) {
        guard socialAuthAttemptID == attemptID else { return }
        socialAuthAttemptID = nil
        isSaving = false
        if let error {
            errorMessage = error
        }
    }

    private func socialSignupErrorMessage(_ error: NSError) -> String {
        switch AuthErrorCode(rawValue: error.code) {
        case .credentialAlreadyInUse, .emailAlreadyInUse, .accountExistsWithDifferentCredential:
            return "That social account is already connected to an existing Rydr account. Return to sign in instead."
        default:
            return "Social sign-up failed: \(error.localizedDescription)"
        }
    }

    private func applySocialProfile(_ profile: RiderSocialAuthProfile) {
        if firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            firstName = profile.firstName
        }
        if lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastName = profile.lastName
        }
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            email = profile.email
        }
    }

    // MARK: - Apple Sign-Up
    private func handleAppleSignIn(result: ASAuthorization) {
        guard let appleCred = result.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleCred.identityToken,
              let tokenStr = String(data: identityToken, encoding: .utf8) else {
            errorMessage = "Apple credential or token missing"
            return
        }

        guard let nonce = currentNonce else {
            errorMessage = "Apple sign-up could not verify this request. Please try again."
            return
        }
        currentNonce = nil

        let oauth = OAuthProvider.appleCredential(
            withIDToken: tokenStr,
            rawNonce: nonce,
            fullName: appleCred.fullName
        )

        let splitName = splitDisplayName(Auth.auth().currentUser?.displayName ?? "")
        let profile = RiderSocialAuthProfile(
            firstName: appleCred.fullName?.givenName ?? splitName.first,
            lastName: appleCred.fullName?.familyName ?? splitName.last,
            email: appleCred.email ?? Auth.auth().currentUser?.email ?? "",
            providerID: "apple.com"
        )

        authenticateWithSocialCredential(oauth, profile: profile)
    }

    private func splitDisplayName(_ displayName: String) -> (first: String, last: String) {
        let parts = displayName
            .split(separator: " ")
            .map(String.init)
        guard let first = parts.first else { return ("", "") }
        return (first, parts.dropFirst().joined(separator: " "))
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
            }

            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < UInt8(charset.count) {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }
}

private struct SignupDividerLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(SignupPalette.softLine).frame(height: 1)
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(SignupPalette.muted)
                .lineLimit(1)
            Rectangle().fill(SignupPalette.softLine).frame(height: 1)
        }
    }
}
