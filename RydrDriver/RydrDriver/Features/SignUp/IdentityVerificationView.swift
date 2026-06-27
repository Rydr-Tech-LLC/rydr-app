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

struct IdentityVerificationView: View {
    @Binding var isVerified: Bool

    var currentStep: Int = 6
    var totalSteps: Int = 8

    var onNext: () -> Void

    @State private var isPresenting = false
    @State private var url: URL?
    @State private var message: String?

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

                SignupContinueButton(title: "Start Verification", systemImage: "shield.lefthalf.filled", isEnabled: true, action: startVerification)
                    .sheet(isPresented: $isPresenting) {
                        if let url { SafariView(url: url) }
                    }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if isVerified {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                        Text("Identity verified")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.green)
                    }
                } else {
                    Toggle("I completed verification", isOn: $isVerified)
                        .toggleStyle(SwitchToggleStyle(tint: .red))
                        .font(.subheadline)
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

    private func startVerification() {
        // TODO: Call backend to create Stripe Identity verification session and return hosted link URL
        #if DEBUG
        url = URL(string: "https://verify.stripe.com/demo")
        isPresenting = true
        #else
        message = "Stripe Identity is waiting on backend configuration. For beta testing, an admin can mark this account as manually reviewed."
        #endif
    }
}
