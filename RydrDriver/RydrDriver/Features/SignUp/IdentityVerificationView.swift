//
//  IdentityVerificationView.swift
//  Rydr Driver
//
//  Backend-confirmed submission permits onboarding; only verification permits approval.
//

import SwiftUI
import StripeIdentity
import FirebaseAuth

struct IdentityVerificationView: View {
    @Binding var isVerified: Bool
    @Binding var isSubmitted: Bool

    var currentStep: Int = 6
    var totalSteps: Int = 8

    var onNext: () -> Void
    var launchVerification: () async throws -> IdentityVerificationSheet.VerificationFlowResult = {
        let service = DriverIdentityVerificationService.shared
        let secret = try await service.createSession()
        return try await service.presentVerification(clientSecret: secret)
    }
    var loadStatus: () async throws -> DriverIdentityStatus = {
        try await DriverIdentityVerificationService.shared.fetchStatus()
    }
    var pollDelay: UInt64 = 2_000_000_000

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
                    title: isVerified ? "Identity Verified" : (isSubmitted ? "Check Verification Status" : "Start Verification"),
                    systemImage: isVerified ? "checkmark.seal.fill" : "shield.lefthalf.filled",
                    isEnabled: !isLoading && !isVerified,
                    isLoading: isLoading,
                    action: { Task { if isSubmitted { await refreshStatus() } else { await startVerification() } } }
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

                if isSubmitted && !isVerified {
                    Label("Verification pending. You can finish onboarding, but you cannot drive until verification and account approval are complete.", systemImage: "clock.badge.checkmark")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("identityPendingNotice")
                }
                SignupContinueButton(title: "Continue", isEnabled: !isLoading && (isVerified || isSubmitted), action: onNext)
                    .accessibilityIdentifier("identityContinue")

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
        }
        .background(Color(.systemBackground))
        .task { await refreshStatus() }
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
            let result = try await launchVerification()

            switch result {
            case .flowCompleted:
                message = "Verification submitted. Confirming with Stripe..."
                try await confirmSubmittedStatus()
            case .flowCanceled:
                await recoverSubmission(or: "Verification was canceled. Please complete identity verification to continue.")
            case .flowFailed(let error):
                await recoverSubmission(or: error.localizedDescription)
            }
        } catch {
            await recoverSubmission(or: error.localizedDescription)
        }
    }

    @MainActor
    private func apply(_ status: DriverIdentityStatus) -> Bool {
        isVerified = status.isVerified
        isSubmitted = status.canContinueOnboarding
        isError = false
        message = nil
        if status.isVerified { message = "Identity Verified" }
        else if status.canContinueOnboarding { message = "Verification submitted. Stripe is reviewing your identity." }
        else if ["requires_input", "canceled"].contains(status.identityStatus) {
            isError = true
            message = "Stripe needs more information. Complete identity verification to continue."
        }
        return status.canContinueOnboarding
    }

    @MainActor
    private func refreshStatus() async {
        isLoading = true
        defer { isLoading = false }
        do { _ = apply(try await loadStatus()) }
        catch { isError = true; message = "Unable to check verification status. Please try again. " + error.localizedDescription }
    }

    @MainActor
    private func recoverSubmission(or failureMessage: String) async {
        // Stripe can return a URL/presentation error after accepting the documents.
        // Recover only from authenticated backend confirmation, never the SDK result.
        for attempt in 0..<8 {
            guard let status = try? await loadStatus() else { break }
            if apply(status) { return }
            if ["requires_input", "canceled"].contains(status.identityStatus) { return }
            if attempt < 7 {
                do { try await Task.sleep(nanoseconds: pollDelay) }
                catch { return }
            }
        }
        isError = true
        message = failureMessage
    }

    @MainActor
    private func confirmSubmittedStatus() async throws {
        for attempt in 0..<8 {
            let status = try await loadStatus()
            if apply(status) { return }
            if ["requires_input", "canceled"].contains(status.identityStatus) { return }
            if attempt < 7 { try await Task.sleep(nanoseconds: pollDelay) }
        }
        isError = false
        message = "Waiting for submission confirmation. Check verification again before continuing."
    }
}

#if DEBUG && targetEnvironment(simulator)
struct DriverIdentityUITestFixture: View {
    @State private var verified = false
    @State private var submitted = false
    @State private var didSubmit = false
    @State private var statusReads = 0
    @State private var next = false
    private var args: [String] { ProcessInfo.processInfo.arguments }
    var body: some View {
        if next {
            VStack {
                Text("Background Check").accessibilityIdentifier("identityNextStep")
                Text(verified ? "verified" : "unverified").accessibilityIdentifier("identityVerificationValue")
            }
        } else {
            IdentityVerificationView(isVerified: $verified, isSubmitted: $submitted, onNext: {
                if verified || submitted { next = true }
            }, launchVerification: {
                didSubmit = true
                if args.contains("-IdentityURLFailure") { return .flowFailed(error: URLError(.unsupportedURL)) }
                if args.contains("-IdentityCanceled") { return .flowCanceled }
                return .flowCompleted
            }, loadStatus: {
                statusReads += 1
                if args.contains("-IdentityUnavailable") { throw URLError(.notConnectedToInternet) }
                let status: String
                if !(didSubmit || args.contains("-IdentityResume")) { status = "not_started" }
                else if args.contains("-IdentityURLFailure") && statusReads < 4 { status = "not_started" }
                else if args.contains("-IdentityRequiresInput") { status = "requires_input" }
                else if args.contains("-IdentityVerified") { status = "verified" }
                else if args.contains("-IdentityCanceled") || args.contains("-IdentityUnconfirmed") { status = "not_started" }
                else { status = "processing" }
                return DriverIdentityStatus(identityVerified: status == "verified", identityStatus: status)
            }, pollDelay: 1_000_000)
        }
    }
}
#endif
