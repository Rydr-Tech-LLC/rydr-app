//
//  EmailPasswordView.swift
//  RydrSignupFlow
//

import SwiftUI
import FirebaseAuth


struct EmailAndPasswordView: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var confirmPassword: String
    var onNext: () -> Void
    
    @State private var errorMessage = ""

    @State private var passwordValidations: [String: Bool] = [
        "At least 8 characters": false,
        "1 uppercase letter": false,
        "1 number": false,
        "1 special character": false
    ]

    private var allValid: Bool {
        passwordValidations.values.allSatisfy { $0 } && !confirmPassword.isEmpty && password == confirmPassword
    }

    var body: some View {
        VStack(spacing: 25) {
            // Header & Email Field
            Text("Set Up Your Login")
                .font(.title).bold()
                .foregroundStyle(LinearGradient(
                    colors: [Color.red, Color(red: 0.5, green: 0, blue: 0.13).opacity(0.7)],
                    startPoint: .leading, endPoint: .trailing
                ))

            HStack {
                Image(systemName: "envelope").foregroundColor(.gray)
                TextField("Email Address", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )

            // Password Field
            HStack {
                Image(systemName: "lock").foregroundColor(.gray)
                SecureField("Create Password", text: $password)
                    .onChange(of: password) {
                        validatePassword(password)
                    }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )

            // Password Rules – always displayed
            VStack(alignment: .leading, spacing: 6) {
                ForEach(passwordValidations.sorted(by: { $0.key < $1.key }), id: \.key) { rule, passed in
                    HStack {
                        Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(passed ? .green : .gray)
                        Text(rule).font(.caption)
                    }
                }
            }.padding(.horizontal)

            // Confirm Password Field
            HStack {
                Image(systemName: "lock.rotation").foregroundColor(.gray)
                SecureField("Confirm Password", text: $confirmPassword)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )

            // Password match feedback
            if !confirmPassword.isEmpty && password != confirmPassword {
                Text("Passwords do not match.")
                    .foregroundColor(.red)
                    .font(.caption)
                    .transition(.opacity)
            }

            // Continue Button
            Button("Continue") {
                onNext()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!allValid)
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Spacer()
        }
        .padding()
    }

    private func validatePassword(_ text: String) {
        passwordValidations["At least 8 characters"] = text.count >= 8
        passwordValidations["1 uppercase letter"] = text.rangeOfCharacter(from: .uppercaseLetters) != nil
        passwordValidations["1 number"] = text.rangeOfCharacter(from: .decimalDigits) != nil
        passwordValidations["1 special character"] = text.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+{}|:<>?-=[];,./")) != nil
    }
}

