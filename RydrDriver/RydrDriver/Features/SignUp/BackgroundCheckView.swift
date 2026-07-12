//
//  BackgroundCheckView.swift
//  Rydr Driver
//
//  Step 7 of driver signup: Background Check beta acknowledgement. This
//  screen is intentionally isolated so the real Checkr flow can replace the
//  beta acknowledgement without reshaping the signup coordinator.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct BackgroundCheckView: View {
    let firstName: String
    let lastName: String
    let email: String
    let phone: String
    let dob: Date
    let licenseNumber: String
    let licenseState: String

    @Binding var acknowledged: Bool

    var currentStep: Int = 7
    var totalSteps: Int = 8

    var onNext: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var isSaving = false
    @State private var message: String?
    @State private var messageIsError = false

    private let checkrURL = URL(string: "https://candidate.checkr.com/")!

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                DriverOnboardingStepIndicator(currentStep: currentStep, totalSteps: totalSteps, stepTitle: "Background Check")

                heroIllustration

                VStack(spacing: 8) {
                    Text("Background Check")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Styles.rydrGradient)
                    Text("Background checks are required for all Rydr drivers. Use your legal name exactly as it appears on your driver license.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                infoCard
                checkrRedirectButton
                warningCard
                acknowledgementCheckbox

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(messageIsError ? .red : .secondary)
                        .multilineTextAlignment(.center)
                }

                SignupContinueButton(
                    title: acknowledged ? "Continue" : "Accept & Continue",
                    systemImage: "checkmark.shield.fill",
                    isEnabled: acknowledged,
                    isLoading: isSaving,
                    action: saveAcknowledgement
                )

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
        }
        .background(Color(.systemBackground))
        .task {
            await loadExistingAcknowledgement()
        }
    }

    private var heroIllustration: some View {
        ZStack {
            Circle().fill(Color.red.opacity(0.08)).frame(width: 110, height: 110)
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Styles.rydrGradient)
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rydr is committed to rider and driver safety.")
                .font(.headline.weight(.bold))

            Text("For this beta, Rydr is using an external Checkr flow and manual review instead of an in-app Checkr API integration.")
            Text("Your legal name, date of birth, license details, email, and phone number are saved to your driver profile so Mission Control can monitor background-check readiness.")
            Text("After you continue, your background-check status will be marked as manual pending until Rydr reviews the external Checkr result.")
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private var checkrRedirectButton: some View {
        Button(action: openCheckr) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.forward.app.fill")
                Text("Open Checkr")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "safari.fill")
                    .font(.caption.weight(.bold))
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
        }
        .foregroundColor(.white)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Styles.rydrGradient)
        )
        .buttonStyle(.plain)
        .accessibilityLabel("Open Checkr background check")
    }

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Important")
                    .font(.headline.weight(.heavy))
            }

            Text("Because this beta involves real interactions between riders and drivers, Rydr maintains a zero-tolerance policy for misconduct.")

            Text("Any reports of unsafe behavior, harassment, fraud, violence, illegal activity, or violations of the Rydr Community Standards may result in:")

            VStack(alignment: .leading, spacing: 7) {
                bullet("Immediate removal from beta testing")
                bullet("Suspension of your account")
                bullet("Permanent ineligibility to drive on the Rydr platform")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.orange.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private var acknowledgementCheckbox: some View {
        Button {
            acknowledged.toggle()
            message = nil
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: acknowledged ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(acknowledged ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color.secondary))
                    .frame(width: 28)

                Text("I understand that a background check is required to drive on the Rydr platform. I acknowledge that Rydr is using an external Checkr/manual review flow during beta, and I agree to complete any requested background screening steps. I also understand that misconduct during beta may result in immediate removal from testing and may affect my future eligibility to drive with Rydr.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(acknowledged ? Color.red.opacity(0.06) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(acknowledged ? Color.red.opacity(0.28) : Color.gray.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func openCheckr() {
        recordCheckrRedirect()
        openURL(checkrURL)
    }

    private func recordCheckrRedirect() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("drivers").document(uid).setData([
            "backgroundCheckProvider": "checkr",
            "backgroundCheckFlow": "external_redirect",
            "backgroundCheckStatus": "manual_pending",
            "backgroundCheckRedirectURL": checkrURL.absoluteString,
            "backgroundCheckRedirectedAt": FieldValue.serverTimestamp(),
            "backgroundCheckLegalFirstName": firstName,
            "backgroundCheckLegalLastName": lastName,
            "backgroundCheckEmail": email,
            "backgroundCheckPhone": phone,
            "backgroundCheckLicenseState": licenseState,
            "backgroundCheckSource": "driver-ios-signup"
        ], merge: true)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.subheadline.weight(.bold))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor
    private func loadExistingAcknowledgement() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let snapshot = try await Firestore.firestore().collection("drivers").document(uid).getDocument()
            let data = snapshot.data() ?? [:]
            let alreadyAcknowledged = data["backgroundCheckAcknowledged"] as? Bool ?? false
            if alreadyAcknowledged {
                acknowledged = true
            }
        } catch {
            message = "We couldn't confirm your saved background check acknowledgement. Please try again."
            messageIsError = true
        }
    }

    private func saveAcknowledgement() {
        guard acknowledged else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            message = "Your session expired. Please sign in again."
            messageIsError = true
            return
        }

        isSaving = true
        message = nil
        messageIsError = false

        Firestore.firestore().collection("drivers").document(uid).setData([
            "backgroundCheckAcknowledged": true,
            "backgroundCheckAcknowledgedAt": FieldValue.serverTimestamp(),
            "backgroundAcknowledgementVersion": 1,
            "backgroundCheckProvider": "checkr",
            "backgroundCheckFlow": "external_redirect",
            "backgroundCheckStatus": "manual_pending",
            "backgroundCheckManualReviewRequired": true,
            "backgroundCheckLegalFirstName": firstName,
            "backgroundCheckLegalLastName": lastName,
            "backgroundCheckEmail": email,
            "backgroundCheckPhone": phone,
            "backgroundCheckDob": Timestamp(date: dob),
            "backgroundCheckLicenseNumberLast4": String(licenseNumber.suffix(4)),
            "backgroundCheckLicenseState": licenseState,
            "backgroundCheckSource": "driver-ios-signup",
            "backgroundCheckStepCompleted": true,
            "betaAgreementAccepted": true,
            "betaAgreementAcceptedAt": FieldValue.serverTimestamp()
        ], merge: true) { error in
            isSaving = false
            if let error {
                message = "We couldn't save your acknowledgement: \(error.localizedDescription)"
                messageIsError = true
                return
            }
            onNext()
        }
    }
}
