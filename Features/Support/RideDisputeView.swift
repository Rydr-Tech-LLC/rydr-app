//
//  RideDisputeView.swift
//  RydrPlayground
//
//  Charge dispute support flow.
//

import SwiftUI

struct RideDisputeView: View {
    var prefilledRideId: String = ""

    @State private var rideId: String
    @State private var issueType = "I was charged incorrectly"
    @State private var explanation = ""
    @State private var amountDisputed = ""
    @State private var contactPreference = "chat"
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var createdTicket: SupportTicket?
    @State private var submittedMessage: String?

    private let service = SupportTicketService()
    private let issueTypes = [
        "I was charged incorrectly",
        "I was charged a cancellation fee",
        "Minimum fare question",
        "Booking fee question",
        "Refund request",
        "Other charge issue"
    ]

    init(prefilledRideId: String = "") {
        self.prefilledRideId = prefilledRideId
        _rideId = State(initialValue: prefilledRideId)
    }

    var body: some View {
        Form {
            Section {
                Text("Tell us what happened with the charge. We'll review your request.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Ride and charge") {
                TextField("Ride reference optional", text: $rideId)
                    .textInputAutocapitalization(.never)

                Picker("Issue type", selection: $issueType) {
                    ForEach(issueTypes, id: \.self) { Text($0).tag($0) }
                }

                TextField("Amount disputed optional", text: $amountDisputed)
                    .keyboardType(.decimalPad)

                TextField("Tell us what happened", text: $explanation, axis: .vertical)
                    .lineLimit(5...8)
            }

            Section("Contact preference") {
                Picker("Contact preference", selection: $contactPreference) {
                    Text("Chat").tag("chat")
                    Text("Email").tag("email")
                    Text("Scheduled call").tag("scheduledCall")
                }
                .pickerStyle(.segmented)
            }

            Section("Attachments") {
                Text("Attachment uploads will be available later. For now, include key details in your explanation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let submittedMessage {
                Section {
                    Text(submittedMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    submitDispute()
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Label("Submit dispute", systemImage: "doc.text.magnifyingglass")
                    }
                }
                .disabled(isSubmitting)
            }
        }
        .navigationTitle("Dispute a charge")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $createdTicket) { ticket in
            SupportChatView(ticketId: ticket.ticketId, subject: ticket.subject)
        }
    }

    private func submitDispute() {
        isSubmitting = true
        errorMessage = nil
        submittedMessage = nil

        let amountLine = amountDisputed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "\nAmount disputed: \(amountDisputed)"
        let description = explanation + amountLine

        let draft = SupportTicketDraft(
            rideId: rideId,
            category: "Payments & Charges",
            issueType: issueType,
            subject: "Charge dispute - \(issueType)",
            description: description,
            priority: "normal",
            contactPreference: contactPreference
        )

        Task {
            do {
                let ticket = try await service.createTicket(draft)
                await MainActor.run {
                    isSubmitting = false
                    if contactPreference == "chat" {
                        createdTicket = ticket
                    } else if contactPreference == "scheduledCall" {
                        submittedMessage = "Your dispute was submitted. You can also schedule a callback from Help & Support."
                    } else {
                        submittedMessage = "Your dispute was submitted. Rydr support will follow up by email."
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}
