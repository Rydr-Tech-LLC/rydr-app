//
//  DeleteAccountView.swift
//  RydrPlayground
//
//  Rider-side entry point into the production account-deletion workflow
//  (Part 12 of the beta hardening sprint):
//
//    Rider -> authenticated backend -> Firestore queue (`accountDeletionRequests`)
//    -> Mission Control review -> backend deletion -> Stripe cleanup
//    -> Firebase cleanup -> GDPR-safe anonymization
//
//  This screen only performs the first step: it asks the backend to create
//  the request. The backend derives identity and account roles from the
//  verified Firebase token; mobile clients cannot write this queue directly.
//  This is intentional: it gives support a chance to catch fraud disputes,
//  in-progress rides, or pending payouts before data is destroyed.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct DeleteAccountView: View {
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
                .getDocument()
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

        do {
            guard let rawBase = Bundle.main.object(forInfoDictionaryKey: "RYDR_BACKEND_BASE_URL") as? String,
                  let base = URL(string: rawBase),
                  let url = URL(string: "/account/deletion-requests", relativeTo: base) else {
                throw URLError(.badURL)
            }
            let token = try await user.getIDToken()
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "reason": reason.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let message = payload?["error"] as? String ?? "Account deletion request failed."
                throw NSError(
                    domain: "RydrAccountDeletion",
                    code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }
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
