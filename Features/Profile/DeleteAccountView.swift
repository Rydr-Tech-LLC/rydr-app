//
//  DeleteAccountView.swift
//  RydrPlayground
//
//  Rider-side entry point into the production account-deletion workflow
//  (Part 12 of the beta hardening sprint):
//
//    Rider -> Deletion Request -> Firestore queue (`accountDeletionRequests`)
//    -> Mission Control review -> backend deletion -> Stripe cleanup
//    -> Firebase cleanup -> GDPR-safe anonymization
//
//  This screen only performs the first step: it writes a signed,
//  self-attested request into the queue. Firestore rules
//  (`accountDeletionRequests/{requestId}`) only allow a rider to create a
//  request keyed by their own uid and only an admin (Mission Control, via
//  the Admin SDK) to update/delete it — so the actual account/Stripe/Auth
//  deletion can only ever happen server-side, never directly from the app.
//  This is intentional: it gives support a chance to catch fraud disputes,
//  in-progress rides, or pending payouts before data is destroyed.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct DeleteAccountView: View {
    @EnvironmentObject var session: UserSessionManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var reason: String = ""
    @State private var hasConfirmedUnderstanding = false
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @State private var existingRequestStatus: String?
    @State private var isCheckingExistingRequest = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if isCheckingExistingRequest {
                    ProgressView().padding(.top, 8)
                } else if let existingRequestStatus {
                    pendingRequestCard(status: existingRequestStatus)
                } else {
                    consequencesCard
                    reasonField
                    confirmationToggle

                    if let submissionError {
                        Text(submissionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    submitButton
                }
            }
            .padding(20)
        }
        .background(background.ignoresSafeArea())
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadExistingRequest() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Delete your Rydr account")
                .font(.title3.weight(.bold))
                .foregroundStyle(primaryText)
            Text("This permanently removes access to your Rydr rider account. A Rydr team member reviews every request before it's processed.")
                .font(.subheadline)
                .foregroundStyle(secondaryText)
        }
    }

    private var consequencesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            consequenceRow(icon: "person.crop.circle.badge.xmark", text: "Your profile, saved places, and ride history will be removed or anonymized.")
            consequenceRow(icon: "creditcard", text: "Saved payment methods will be detached and your Stripe customer record deleted.")
            consequenceRow(icon: "clock.arrow.circlepath", text: "Rydr may retain anonymized records required for tax, fraud, or legal compliance.")
            consequenceRow(icon: "hourglass", text: "Processing can take a few business days while support confirms there are no pending rides, disputes, or payments.")
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func consequenceRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(primaryText)
        }
    }

    private var reasonField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why are you leaving? (optional)")
                .font(.caption.weight(.bold))
                .foregroundStyle(secondaryText)
            TextField("Tell us what we could have done better", text: $reason, axis: .vertical)
                .lineLimit(3...5)
                .padding(12)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var confirmationToggle: some View {
        Toggle(isOn: $hasConfirmedUnderstanding) {
            Text("I understand this request is permanent and cannot be undone once processed.")
                .font(.subheadline)
                .foregroundStyle(primaryText)
        }
        .tint(.red)
    }

    private var submitButton: some View {
        Button {
            Task { await submitDeletionRequest() }
        } label: {
            HStack {
                if isSubmitting { ProgressView().tint(.white) }
                Text(isSubmitting ? "Submitting…" : "Request Account Deletion")
                    .font(.headline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(hasConfirmedUnderstanding ? Color.red : Color.red.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!hasConfirmedUnderstanding || isSubmitting)
    }

    private func pendingRequestCard(status: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Deletion request received")
                .font(.headline.weight(.bold))
                .foregroundStyle(primaryText)
            Text("Status: \(status.replacingOccurrences(of: "_", with: " ").capitalized)")
                .font(.subheadline)
                .foregroundStyle(secondaryText)
            Text("Our support team is reviewing your request. You'll receive an email once it's processed. Contact support if you need to cancel this request.")
                .font(.footnote)
                .foregroundStyle(secondaryText)
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @MainActor
    private func loadExistingRequest() async {
        defer { isCheckingExistingRequest = false }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snapshot = try await Firestore.firestore()
                .collection("accountDeletionRequests")
                .document(uid)
                .get()
            if snapshot.exists, let status = snapshot.data()?["status"] as? String, status != "rejected" {
                existingRequestStatus = status
            }
        } catch {
            // Non-fatal: worst case the rider can submit a duplicate request,
            // which Mission Control will simply see as a re-affirmation.
        }
    }

    @MainActor
    private func submitDeletionRequest() async {
        guard let user = Auth.auth().currentUser else {
            submissionError = "You need to be signed in to request account deletion."
            return
        }

        isSubmitting = true
        submissionError = nil

        let payload: [String: Any] = [
            "uid": user.uid,
            "userId": user.uid,
            "role": "rider",
            "email": user.email ?? session.userEmail,
            "reason": reason.trimmingCharacters(in: .whitespacesAndNewlines),
            "status": "requested",
            "source": "ios_rider_app",
            "clientRequestedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        do {
            try await Firestore.firestore()
                .collection("accountDeletionRequests")
                .document(user.uid)
                .set(payload, merge: true)
            existingRequestStatus = "requested"
        } catch {
            submissionError = "We couldn't submit your request: \(error.localizedDescription). Please try again or contact support."
        }

        isSubmitting = false
    }

    private var background: Color {
        colorScheme == .dark ? .black : Color(.systemGroupedBackground)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : Color(red: 0.05, green: 0.08, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.66) : Color(red: 0.38, green: 0.40, blue: 0.48)
    }
}
