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

    @State private var isSaving = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                DriverOnboardingStepIndicator(currentStep: currentStep, totalSteps: totalSteps, stepTitle: "Background Check")

                heroIllustration

                VStack(spacing: 8) {
                    Text("Background Check (Beta)")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Styles.rydrGradient)
                    Text("Background checks are required for all Rydr drivers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                infoCard
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

            Text("All drivers are normally required to complete a background check before becoming eligible to accept rides.")
            Text("As part of this closed beta program, background checks are temporarily deferred for approved beta participants while we complete integration with our background screening provider.")
            Text("Participation in the beta does not waive this requirement. A successful background check will be required before public launch or continued access to the Rydr Driver platform.")
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
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

                Text("I understand that a background check is required to drive on the Rydr platform. I acknowledge that this requirement is temporarily deferred only for the beta program, and I agree to complete a background check when required. I also understand that misconduct during beta may result in immediate removal from testing and may affect my future eligibility to drive with Rydr.")
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
            let status = (data["backgroundCheckStatus"] as? String)?.lowercased()
            let alreadyAcknowledged = data["backgroundCheckAcknowledged"] as? Bool ?? false
            if alreadyAcknowledged && status == "beta_deferred" {
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
            "backgroundCheckStatus": "beta_deferred",
            "backgroundAcknowledgedAt": FieldValue.serverTimestamp(),
            "backgroundAcknowledgementVersion": 1
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
