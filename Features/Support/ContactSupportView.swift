//
//  ContactSupportView.swift
//  RydrPlayground
//
//  General support contact and ticket creation flow.
//

import SwiftUI
import FirebaseAuth
import MessageUI

struct ContactSupportView: View {
    var prefilledSubject: String = ""
    var prefilledCategory: String = "General support"
    var prefilledIssueType: String = "Other issue"
    var prefilledRideId: String = ""
    var prefilledDescription: String = ""

    @Environment(\.openURL) private var openURL
    @State private var category: String
    @State private var issueType: String
    @State private var subject: String
    @State private var rideId: String
    @State private var description: String
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var createdTicket: SupportTicket?
    @State private var showMailComposer = false

    private let service = SupportTicketService()
    private let categories = [
        "General support",
        "Ride help",
        "Payments & Charges",
        "Cancellations & Refunds",
        "RydrBank Rewards",
        "SafeRydr",
        "Cash Rydr Hub",
        "Account & Profile",
        "Safety"
    ]
    private let issueTypes = [
        "I was charged incorrectly",
        "Driver cancelled",
        "Driver did not arrive",
        "I was charged a cancellation fee",
        "I left an item in the vehicle",
        "Safety concern",
        "Other issue"
    ]

    init(
        prefilledSubject: String = "",
        prefilledCategory: String = "General support",
        prefilledIssueType: String = "Other issue",
        prefilledRideId: String = "",
        prefilledDescription: String = ""
    ) {
        self.prefilledSubject = prefilledSubject
        self.prefilledCategory = prefilledCategory
        self.prefilledIssueType = prefilledIssueType
        self.prefilledRideId = prefilledRideId
        self.prefilledDescription = prefilledDescription
        _category = State(initialValue: prefilledCategory)
        _issueType = State(initialValue: prefilledIssueType)
        _subject = State(initialValue: prefilledSubject)
        _rideId = State(initialValue: prefilledRideId)
        _description = State(initialValue: prefilledDescription)
    }

    var body: some View {
        Form {
            Section {
                Text("Tell us what happened. We'll review your request and follow up.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if issueType == "Safety concern" || category == "Safety" {
                Section {
                    Label(
                        "Call 911 or local emergency services immediately if you are in danger.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                }
            }

            Section("Request details") {
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }

                Picker("Issue", selection: $issueType) {
                    ForEach(issueTypes, id: \.self) { Text($0).tag($0) }
                }

                TextField("Subject", text: $subject)
                TextField("Ride reference optional", text: $rideId)
                    .textInputAutocapitalization(.never)

                TextField("Tell us what happened", text: $description, axis: .vertical)
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
                    createChatTicket()
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Label("Start a support chat", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                }
                .disabled(isSubmitting)

                Button {
                    openEmailSupport()
                } label: {
                    Label("Email support", systemImage: "envelope.fill")
                }

                NavigationLink {
                    ScheduleCallRequestView(prefilledRideId: rideId, prefilledTopic: subject.isEmpty ? issueType : subject)
                } label: {
                    Label("Schedule a callback", systemImage: "phone.badge.clock.fill")
                }
            }
        }
        .navigationTitle("Contact support")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $createdTicket) { ticket in
            SupportChatView(ticketId: ticket.ticketId, subject: ticket.subject)
        }
        .sheet(isPresented: $showMailComposer) {
            MailComposerView(draft: emailDraft) {
                showMailComposer = false
            }
        }
    }

    private var emailDraft: SupportEmailDraft {
        let uid = Auth.auth().currentUser?.uid ?? "Not signed in"
        let rideLine = rideId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Ride ID: Not provided" : "Ride ID: \(rideId)"
        let body = """
        User ID: \(uid)
        \(rideLine)
        Category: \(category)
        Issue: \(issueType)

        \(description)
        """

        return SupportEmailDraft(
            subject: subject.isEmpty ? "Rydr Support - \(issueType)" : subject,
            body: body
        )
    }

    private func createChatTicket() {
        isSubmitting = true
        errorMessage = nil

        let draft = SupportTicketDraft(
            rideId: rideId,
            category: category,
            issueType: issueType,
            subject: subject.isEmpty ? issueType : subject,
            description: description,
            priority: issueType == "Safety concern" ? "urgent" : "normal",
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

    private func openEmailSupport() {
        if MFMailComposeViewController.canSendMail() {
            showMailComposer = true
        } else if let url = emailDraft.mailtoURL {
            openURL(url)
        }
    }
}
