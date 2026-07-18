//
//  IdentityVerificationView.swift
//  Rydr Driver
//
//  Step 6 of driver signup: Identity Verification intro. Extracted out of
//  DriverSignupCoordinator.swift and restyled to match the premium
//  onboarding mockup (feature checklist, "Powered by Stripe Identity" badge,
//  shared step indicator). The hosted Stripe Identity integration itself is
//  untouched — this only restyles the launch screen around it.
//

import SwiftUI
import StripeIdentity
import FirebaseAuth
import FirebaseFirestore

struct IdentityVerificationView: View {
    @Binding var isVerified: Bool

    var currentStep: Int = 6
    var totalSteps: Int = 8

    var onNext: () -> Void

    @State private var isLoading = false
    @State private var message: String?
    @State private var isError = false

    private let features: [(icon: String, text: String)] = [
        ("doc.text.viewfinder", "Government-issued ID"),
        ("camera.fill", "Selfie verification"),
        ("lock.shield.fill", "Secure & encrypted"),
        ("clock.fill", "Takes about 2 minutes")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                DriverOnboardingStepIndicator(currentStep: currentStep, totalSteps: totalSteps, stepTitle: "Identity Verification")

                heroIllustration

                VStack(spacing: 8) {
                    Text("Verify Your Identity")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Styles.rydrGradient)
                    Text("You'll be redirected to a secure flow to scan your ID and take a quick selfie.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    ForEach(features, id: \.text) { feature in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.red.opacity(0.1)).frame(width: 36, height: 36)
                                Image(systemName: feature.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Styles.rydrGradient)
                            }
                            Text(feature.text)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))

                poweredByBadge

                SignupContinueButton(
                    title: isVerified ? "Identity Verified" : "Start Verification",
                    systemImage: isVerified ? "checkmark.seal.fill" : "shield.lefthalf.filled",
                    isEnabled: !isLoading && !isVerified,
                    isLoading: isLoading,
                    action: { Task { await startVerification() } }
                )
                .disabled(isVerified)
                .opacity(isVerified ? 0.55 : 1)

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(isError ? .orange : .secondary)
                        .multilineTextAlignment(.center)
                }

                if isVerified {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                        Text("Identity verified")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.green)
                    }
                }

                SignupContinueButton(title: "Continue", isEnabled: isVerified, action: onNext)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
        }
        .background(Color(.systemBackground))
    }

    private var heroIllustration: some View {
        ZStack {
            Circle().fill(Color.red.opacity(0.08)).frame(width: 110, height: 110)
            Image(systemName: "person.text.rectangle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Styles.rydrGradient)
        }
    }

    private var poweredByBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(Styles.rydrGradient)
            Text("Powered by Stripe Identity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
    }

    @MainActor
    private func startVerification() async {
        isLoading = true
        isError = false
        message = nil
        defer { isLoading = false }

        do {
            let clientSecret = try await DriverIdentityVerificationService.shared.createSession()
            let result = try await DriverIdentityVerificationService.shared.presentVerification(clientSecret: clientSecret)

            switch result {
            case .flowCompleted:
                message = "Verification submitted. Confirming with Stripe..."
                try await confirmVerifiedStatus()
            case .flowCanceled:
                isError = true
                message = "Verification was canceled. Please complete identity verification to continue."
            case .flowFailed(let error):
                isError = true
                message = error.localizedDescription
            }
        } catch {
            isError = true
            message = error.localizedDescription
        }
    }

    @MainActor
    private func confirmVerifiedStatus() async throws {
        for _ in 0..<8 {
            let status = try await DriverIdentityVerificationService.shared.fetchStatus()
            if status.identityVerified || status.identityStatus == "verified" {
                isVerified = true
                isError = false
                message = "Identity Verified"
                markIdentityStepCompleted()
                return
            }
            if status.identityStatus == "requires_input" || status.identityStatus == "canceled" {
                isError = true
                message = "Stripe needs more information before identity verification can be completed."
                return
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }

        isError = false
        message = "Stripe is still processing your verification. Please try Continue again in a moment."
    }

    private func markIdentityStepCompleted() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("drivers").document(uid).setData([
            "identityVerificationStepCompleted": true,
            "identityVerificationStepCompletedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
}
