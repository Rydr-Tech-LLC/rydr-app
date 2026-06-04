//
//  RideHelpView.swift
//  RydrPlayground
//
//  Recent ride and manual ride-reference help flow.
//

import SwiftUI

struct RideHelpView: View {
    @EnvironmentObject private var rideManager: RideManager

    var prefilledRideId: String = ""

    @State private var rideReference = ""
    @State private var selectedReason = "I was charged incorrectly"
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var createdTicket: SupportTicket?

    private let service = SupportTicketService()
    private let reasons = [
        "I was charged incorrectly",
        "Driver cancelled",
        "Driver did not arrive",
        "I was charged a cancellation fee",
        "I left an item in the vehicle",
        "Safety concern",
        "Other issue"
    ]

    private var recentRides: [Receipt] {
        Array(rideManager.history.prefix(5))
    }

    init(prefilledRideId: String = "") {
        self.prefilledRideId = prefilledRideId
        _rideReference = State(initialValue: prefilledRideId)
    }

    var body: some View {
        Form {
            Section {
                Text("Get help with a recent ride or enter a ride reference manually.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !recentRides.isEmpty {
                Section("Recent rides") {
                    ForEach(recentRides) { receipt in
                        Button {
                            rideReference = receipt.rideId.uuidString
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "car.fill")
                                    .foregroundStyle(Styles.rydrGradient)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(short(receipt.pickup) + " to " + short(receipt.dropoff))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(receipt.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("$" + String(format: "%.2f", receipt.fare))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if rideReference == receipt.rideId.uuidString {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Styles.rydrGradient)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Section("Recent rides") {
                    ContentUnavailableView(
                        "No recent rides available",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Enter a ride reference if you have one.")
                    )
                }
            }

            Section("Tell us what happened") {
                TextField("Ride reference optional", text: $rideReference)
                    .textInputAutocapitalization(.never)

                Picker("Reason", selection: $selectedReason) {
                    ForEach(reasons, id: \.self) { Text($0).tag($0) }
                }

                if selectedReason == "Safety concern" {
                    Label(
                        "Call 911 or local emergency services immediately if you are in danger.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                }

                TextField("Tell us what happened", text: $details, axis: .vertical)
                    .lineLimit(5...8)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    submitRideHelp()
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Label("Submit ride help request", systemImage: "questionmark.circle.fill")
                    }
                }
                .disabled(isSubmitting)

                NavigationLink {
                    RideDisputeView(prefilledRideId: rideReference)
                } label: {
                    Label("Dispute this charge", systemImage: "creditcard.trianglebadge.exclamationmark")
                }
            }
        }
        .navigationTitle("Ride help")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $createdTicket) { ticket in
            SupportChatView(ticketId: ticket.ticketId, subject: ticket.subject)
        }
    }

    private func submitRideHelp() {
        isSubmitting = true
        errorMessage = nil

        let draft = SupportTicketDraft(
            rideId: rideReference,
            category: selectedReason == "Safety concern" ? "Safety" : "Ride help",
            issueType: selectedReason,
            subject: "Ride help - \(selectedReason)",
            description: details,
            priority: selectedReason == "Safety concern" ? "urgent" : "normal",
            contactPreference: "chat"
        )

        Task {
            do {
                let ticket = try await service.createTicket(draft)
                await MainActor.run {
                    createdTicket = ticket
                    isSubmitting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }

    private func short(_ value: String) -> String {
        value.split(separator: ",").first.map(String.init) ?? value
    }
}
