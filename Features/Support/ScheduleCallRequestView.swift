//
//  ScheduleCallRequestView.swift
//  RydrPlayground
//
//  Support callback request form.
//

import SwiftUI

struct ScheduleCallRequestView: View {
    var prefilledRideId: String = ""
    var prefilledTopic: String = ""

    @State private var topic: String
    @State private var rideId: String
    @State private var preferredDate = Date()
    @State private var preferredTimeWindow = "Morning"
    @State private var phoneNumber = ""
    @State private var notes = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var confirmationMessage: String?

    private let service = SupportTicketService()
    private let timeWindows = ["Morning", "Afternoon", "Evening"]

    init(prefilledRideId: String = "", prefilledTopic: String = "") {
        self.prefilledRideId = prefilledRideId
        self.prefilledTopic = prefilledTopic
        _rideId = State(initialValue: prefilledRideId)
        _topic = State(initialValue: prefilledTopic)
    }

    var body: some View {
        Form {
            Section {
                Text("Request a callback from Rydr support. We'll use your preferred date and time window when reviewing availability.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Callback details") {
                TextField("Topic", text: $topic)
                TextField("Ride reference optional", text: $rideId)
                    .textInputAutocapitalization(.never)
                DatePicker("Preferred date", selection: $preferredDate, displayedComponents: .date)
                Picker("Time window", selection: $preferredTimeWindow) {
                    ForEach(timeWindows, id: \.self) { Text($0).tag($0) }
                }
                TextField("Phone number", text: $phoneNumber)
                    .keyboardType(.phonePad)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(4...7)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let confirmationMessage {
                Section {
                    Text(confirmationMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    submitRequest()
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Label("Schedule a callback", systemImage: "phone.badge.clock.fill")
                    }
                }
                .disabled(isSubmitting)
            }
        }
        .navigationTitle("Schedule a call")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submitRequest() {
        isSubmitting = true
        errorMessage = nil
        confirmationMessage = nil

        let draft = SupportCallRequestDraft(
            rideId: rideId,
            topic: topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Support callback" : topic,
            preferredDate: preferredDate,
            preferredTimeWindow: preferredTimeWindow,
            phoneNumber: phoneNumber,
            notes: notes
        )

        Task {
            do {
                _ = try await service.createCallRequest(draft)
                await MainActor.run {
                    confirmationMessage = "Your callback request was submitted. We'll review your request and follow up."
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
}
