//
//  BackgroundCheckView.swift
//  Rydr Driver
//
//  Step 7 of driver signup: Background Check intro. Extracted out of
//  DriverSignupCoordinator.swift and restyled to match the premium
//  onboarding mockup (feature checklist, "Powered by checkr" badge, shared
//  step indicator). The hosted Checkr integration itself is untouched —
//  this only restyles the launch screen around it.
//

import SwiftUI

struct BackgroundCheckView: View {
    let firstName: String
    let lastName: String
    let email: String
    let phone: String
    let dob: Date
    let licenseNumber: String
    let licenseState: String

    @Binding var started: Bool

    var currentStep: Int = 7
    var totalSteps: Int = 8

    var onNext: () -> Void

    @State private var showConsent = false
    @State private var presentingApply = false
    @State private var applyURL: URL?
    @State private var message: String?

    private let features: [(icon: String, text: String)] = [
        ("lock.shield.fill", "Secure & confidential"),
        ("checkmark.seal.fill", "FCRA compliant"),
        ("clock.fill", "Takes about 5-10 minutes"),
        ("shield.lefthalf.filled", "Used for safety")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                DriverOnboardingStepIndicator(currentStep: currentStep, totalSteps: totalSteps, stepTitle: "Background Check")

                heroIllustration

                VStack(spacing: 8) {
                    Text("Background Check")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Styles.rydrGradient)
                    Text("We use a secure partner to run a criminal and driving record screen.")
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

                Toggle("I consent to a background check (FCRA)", isOn: $showConsent)
                    .toggleStyle(SwitchToggleStyle(tint: .red))
                    .font(.subheadline)

                SignupContinueButton(
                    title: started ? "Background Check Started" : "Start Background Check",
                    systemImage: "shield.lefthalf.filled",
                    isEnabled: showConsent,
                    action: startCheck
                )
                .sheet(isPresented: $presentingApply) {
                    if let url = applyURL { SafariView(url: url) }
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                SignupContinueButton(title: "Continue", isEnabled: started, action: onNext)

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
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Styles.rydrGradient)
        }
    }

    private var poweredByBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(Styles.rydrGradient)
            Text("Powered by checkr")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
    }

    private func startCheck() {
        guard showConsent else { return }
        // TODO: Call backend to create Checkr Candidate + Invitation, return hosted Apply URL.
        #if DEBUG
        applyURL = URL(string: "https://apply.checkr.com/apply/demo")
        presentingApply = true
        #else
        message = "Background checks are manually bypassed only for approved beta testers. No production Checkr invitation was created."
        #endif
        started = true
    }
}
