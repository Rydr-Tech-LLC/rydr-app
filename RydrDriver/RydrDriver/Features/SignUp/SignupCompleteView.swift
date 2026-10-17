//
//  SignupCompleteView.swift
//  Rydr Driver
//
//  Final screen of driver signup, shown once all onboarding steps are
//  submitted. Extracted out of DriverSignupCoordinator.swift and lightly
//  restyled to match the premium onboarding design language.
//

import SwiftUI

struct SignupCompleteView: View {
    var verifyCompletion: () async throws -> Bool = { try await RydrBackendService.onboardingStatus().completed }
    var onFinish: () -> Void
    @State private var finishing = false
    @State private var finishError: String?

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle().fill(Color.green.opacity(0.12)).frame(width: 120, height: 120)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { appeared = true }
            }

            VStack(spacing: 10) {
                Text("Application Submitted")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Styles.rydrGradient)

                Text("Your application is submitted. You can explore your Dashboard while your account is reviewed. Going online unlocks after all required checks are approved.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }

            if let finishError { Text(finishError).foregroundStyle(.red).accessibilityIdentifier("signupFinishError") }
            SignupContinueButton(title: "Go to Dashboard", isLoading: finishing) {
                guard !finishing else { return }
                finishing = true; finishError = nil
                Task { @MainActor in
                    defer { finishing = false }
                    do {
                        guard try await verifyCompletion() else {
                            finishError = "Your setup has not finished saving. Please try again."
                            return
                        }
                        onFinish()
                    } catch { finishError = "We couldn’t confirm your submitted application. Check your connection and try again." }
                }
            }.accessibilityIdentifier("signupDashboard")
                .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color(.systemBackground))
    }
}
