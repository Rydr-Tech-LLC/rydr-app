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

struct NameEntryView: View {
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var preferredName: String
    var allowsSocialSignup = true

    var onContinueWithForm: () -> Void
    var onContinueWithSocial: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage = ""
    @State private var isSaving = false

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

                            Button(action: handleGoogleSignIn) {
                                HStack(spacing: 10) {
                                    Image(systemName: "g.circle.fill")
                                        .font(.system(size: 21, weight: .bold))
                                    Text("Sign Up with Google")
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
        guard FirebaseApp.app()?.options.clientID != nil else {
            errorMessage = "Missing client ID"
            return
        }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            errorMessage = "Unable to access root view controller"
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error = error {
                errorMessage = "Google sign-up failed: \(error.localizedDescription)"
                return
            }
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                errorMessage = "Google auth data missing"
                return
            }
            let accessToken = user.accessToken.tokenString
            let cred = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            Auth.auth().signIn(with: cred) { _, err in
                if let err = err {
                    errorMessage = "Firebase Google auth failed: \(err.localizedDescription)"
                } else {
                    onContinueWithSocial()
                }
            }
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

        let oauth = OAuthProvider.credential(
            providerID: .apple,
            idToken: tokenStr,
            rawNonce: ""
        )

        Auth.auth().signIn(with: oauth) { _, err in
            if let err = err {
                errorMessage = "Apple sign-up failed: \(err.localizedDescription)"
            } else {
                onContinueWithSocial()
            }
        }
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
