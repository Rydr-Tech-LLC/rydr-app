//
//  PhoneVerificationView.swift
//  RydrSignupFlow
//
import SwiftUI
import FirebaseAuth

struct PhoneVerificationView: View {
    var initialPhoneNumber: String = ""
    var linkToCurrentUser = false
    var onVerified: (String) -> Void

    @State private var nationalNumber: String = ""

    @State private var sending = false
    @State private var errorMessage = ""
    @State private var verificationSession: PhoneVerificationSession?

    private var formattedPhoneNumber: String {
        let digits = nationalNumber.filter { $0.isNumber }.prefix(10)
        return "+1" + digits
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Enter your phone").font(.title).bold()

            HStack {
                Text("🇺🇸 +1")
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                TextField("Phone number", text: Binding(
                    get: { nationalNumber },
                    set: { nationalNumber = String($0.filter { $0.isNumber }.prefix(10)) }
                ))
                .keyboardType(.numberPad)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .accessibilityLabel("US Phone Number Field")
            }
            .padding(.bottom, 4)

            Text("US numbers only. Enter your 10-digit number.")
                .font(.caption)
                .foregroundColor(.secondary)

            if !errorMessage.isEmpty {
                Text(errorMessage).foregroundColor(.red).font(.footnote)
            }

            Button {
                sendCode()
            } label: {
                Text(sending ? "Sending..." : "Send Code")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(sending ? Color.gray : Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(sending || nationalNumber.count != 10)

            Spacer()
        }
        .padding()
        .onAppear(perform: applyInitialPhoneNumber)
        .onChange(of: initialPhoneNumber) { _, _ in
            applyInitialPhoneNumber()
        }
        .navigationDestination(item: $verificationSession) { verificationSession in
            VerificationCodeView(
                verificationID: verificationSession.verificationID,
                phoneNumber: verificationSession.phoneNumber,
                linkToCurrentUser: linkToCurrentUser,
                onSuccess: { user in
                    onVerified(user.phoneNumber ?? "")
                },
                onResendCode: { sendCode(resend: true) }
            )
        }
    }

    private func applyInitialPhoneNumber() {
        guard nationalNumber.isEmpty else { return }
        let digits = initialPhoneNumber.filter { $0.isNumber }
        nationalNumber = String(digits.suffix(10))
    }

    private func sendCode(resend: Bool = false) {
        errorMessage = ""
        sending = true
        let e164 = formattedPhoneNumber

        if linkToCurrentUser, Auth.auth().currentUser?.phoneNumber == e164 {
            sending = false
            onVerified(e164)
            return
        }

        // DEBUG/testing on simulator (don’t ship enabled):
        // Auth.auth().settings?.isAppVerificationDisabledForTesting = true

        PhoneAuthProvider.provider().verifyPhoneNumber(e164, uiDelegate: nil) { id, error in
            Task { @MainActor in
                sending = false
                if let error = error {
                    errorMessage = "Failed to send code: \(error.localizedDescription)"
                    return
                }

                guard let id, !id.isEmpty else {
                    errorMessage = "Firebase did not return a verification session. Please resend the code."
                    return
                }

                verificationSession = PhoneVerificationSession(
                    verificationID: id,
                    phoneNumber: e164
                )
            }
        }
    }
}
