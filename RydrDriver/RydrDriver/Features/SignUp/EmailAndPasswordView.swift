//
//  EmailAndPasswordView.swift
//  Rydr Driver
//
//  Step 2 of driver signup: "Create Your Login" — restyled to match the
//  premium onboarding mockup (icon-prefixed fields, eye-toggle on password
//  fields, requirement chips, reassurance card, gradient Continue button,
//  shared step indicator).
//

import SwiftUI
import AuthenticationServices
import FirebaseAuth

struct EmailAndPasswordView: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var confirmPassword: String

    var currentStep: Int = 2
    var totalSteps: Int = 8

    var onNext: () -> Void
    var onContinueWithGoogle: (() -> Void)? = nil
    var onContinueWithApple: ((ASAuthorization, String) -> Void)? = nil

    @State private var errorMessage = ""
    @State private var isPasswordVisible = false
    @State private var isConfirmVisible = false
    @State private var currentNonce: String?

    private let rules: [(key: String, label: String)] = [
        ("length", "8 characters"),
        ("uppercase", "1 uppercase"),
        ("number", "1 number"),
        ("special", "1 special char")
    ]

    private func passes(_ key: String) -> Bool {
        switch key {
        case "length": return password.count >= 8
        case "uppercase": return password.rangeOfCharacter(from: .uppercaseLetters) != nil
        case "number": return password.rangeOfCharacter(from: .decimalDigits) != nil
        case "special": return password.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+{}|:<>?-=[];,./")) != nil
        default: return false
        }
    }

    private var allValid: Bool {
        rules.allSatisfy { passes($0.key) } && !confirmPassword.isEmpty && password == confirmPassword && !email.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                DriverOnboardingStepIndicator(currentStep: currentStep, totalSteps: totalSteps, stepTitle: "Create Your Login")

                VStack(spacing: 8) {
                    Text("Create Your Login")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Styles.rydrGradient)
                    Text("This is how you'll sign in to drive with Rydr.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    HStack {
                        Image(systemName: "envelope.fill").foregroundColor(.gray)
                        TextField("Email Address", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))

                    passwordField(
                        placeholder: "Create Password",
                        text: $password,
                        isVisible: $isPasswordVisible
                    )

                    requirementChips

                    passwordField(
                        placeholder: "Confirm Password",
                        text: $confirmPassword,
                        isVisible: $isConfirmVisible
                    )

                    if !confirmPassword.isEmpty && password != confirmPassword {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                            Text("Passwords do not match.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                    }
                }

                SignupContinueButton(title: "Continue", isEnabled: allValid, action: onNext)

                if onContinueWithGoogle != nil || onContinueWithApple != nil {
                    VStack(spacing: 12) {
                        HStack {
                            Divider()
                            Text("or continue with")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Divider()
                        }

                        if let onContinueWithApple {
                            SignInWithAppleButton(
                                .signUp,
                                onRequest: { request in
                                    request.requestedScopes = [.fullName, .email]
                                    let nonce = DriverSocialAuthService.randomNonceString()
                                    currentNonce = nonce
                                    request.nonce = DriverSocialAuthService.sha256(nonce)
                                },
                                onCompletion: { result in
                                    switch result {
                                    case .success(let authorization):
                                        guard let nonce = currentNonce else {
                                            errorMessage = "Apple sign-up could not verify this request. Please try again."
                                            return
                                        }
                                        onContinueWithApple(authorization, nonce)
                                    case .failure(let error):
                                        errorMessage = "Apple sign-up failed: \(error.localizedDescription)"
                                    }
                                }
                            )
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        if let onContinueWithGoogle {
                            Button(action: onContinueWithGoogle) {
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
                }

                SignupInfoCard(
                    icon: "lock.shield.fill",
                    title: "Your security matters",
                    message: "Your password is encrypted and never visible to anyone — including us."
                )

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
        }
        .background(Color(.systemBackground))
        .hideKeyboardOnTap()
    }

    private func passwordField(placeholder: String, text: Binding<String>, isVisible: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: "lock.fill").foregroundColor(.gray)
            Group {
                if isVisible.wrappedValue {
                    TextField(placeholder, text: text)
                } else {
                    SecureField(placeholder, text: text)
                }
            }
            Button {
                isVisible.wrappedValue.toggle()
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash.fill" : "eye.fill")
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))
    }

    private var requirementChips: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(rules, id: \.key) { rule in
                let passed = passes(rule.key)
                HStack(spacing: 5) {
                    Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                        .font(.caption2)
                        .foregroundColor(passed ? .green : .gray)
                    Text(rule.label)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(passed ? .primary : .secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(passed ? Color.green.opacity(0.1) : Color(.systemGray6)))
            }
        }
        .padding(.horizontal, 2)
    }
}
