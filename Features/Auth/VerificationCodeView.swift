//
//  VerificationCodeView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/15/25.
//
import SwiftUI
import FirebaseAuth

struct VerificationCodeView: View {
    let verificationID: String
    let phoneNumber: String
    var linkToCurrentUser = false
    var onSuccess: (User) -> Void
    var onResendCode: () -> Void

    @State private var verificationCode = ""
    @State private var isVerifying = false
    @State private var errorMessage = ""
    @FocusState private var isFocused: Bool

    @State private var canResend = false
    @State private var countdown = 30
    @State private var progress: CGFloat = 1.0
    @State private var timer: Timer?

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

            TextField("Enter 6-digit code", text: $verificationCode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onAppear {
                    isFocused = true
                    startCountdown()
                }

            // 🔵 Animated Countdown Bar
            if !canResend {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)

                    Capsule()
                        .fill(Color.red)
                        .frame(width: progress * UIScreen.main.bounds.width * 0.8, height: 6)
                        .animation(.linear(duration: 1), value: progress)
                }
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
                    .background(verificationCode.count == 6 ? Color.red : Color.gray)
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
        .navigationBarBackButtonHidden(isVerifying)
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func verifyCode() {
        isVerifying = true
        errorMessage = ""

        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: verificationCode
        )

        let completion: (AuthDataResult?, Error?) -> Void = { result, error in
            isVerifying = false
            if let error = error {
                errorMessage = "Verification failed: \(error.localizedDescription)"
            } else if let user = result?.user {
                print("✅ Phone verified and signed in")
                onSuccess(user)
            }
        }

        if linkToCurrentUser, let user = Auth.auth().currentUser {
            user.link(with: credential, completion: completion)
        } else {
            Auth.auth().signIn(with: credential, completion: completion)
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
