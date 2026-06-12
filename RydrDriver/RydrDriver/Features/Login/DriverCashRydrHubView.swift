//
//  DriverCashRydrHubView.swift
//  Rydr Driver
//
//  Driver-facing Cash Rydr Hub marketplace and scheduled cash ride queue.
//

import Combine
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import MapKit
import UIKit

private struct DriverCashRideRequest: Identifiable, Equatable {
    let id: String
    var riderUid: String
    var riderName: String
    var pickup: String
    var destination: String
    var scheduledTime: Date
    var passengers: Int
    var notes: String
    var budgetRange: String
    var rideType: String
    var status: String
    var driverQueueStatus: String
    var connectedDriverUid: String?
    var connectedDriverName: String?
    var agreedPrice: Double?
    var createdAt: Date?

    var isOpen: Bool { status == "open" }
    var isScheduledForCurrentDriver: Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return connectedDriverUid == uid
            && (status == "connected" || status == "accepted")
            && driverQueueStatus != "completed"
            && driverQueueStatus != "missed"
            && driverQueueStatus != "cancelled"
    }
}

private struct DriverCashHubResponse: Identifiable, Equatable {
    let id: String
    var authorUid: String
    var authorName: String
    var authorRole: String
    var kind: String
    var status: String
    var message: String
    var offerAmount: Double?
    var availability: String
    var vehicleInfo: String
    var createdAt: Date?

    var isDriverAuthored: Bool {
        authorUid == Auth.auth().currentUser?.uid
    }
}

private struct DriverCashOfferDraft {
    var amount = ""
    var availability = ""
    var vehicleInfo = ""
    var message = ""
}

@MainActor
private final class DriverCashRydrHubVM: ObservableObject {
    @Published var openRequests: [DriverCashRideRequest] = []
    @Published var scheduledRequests: [DriverCashRideRequest] = []
    @Published var responsesByRequest: [String: [DriverCashHubResponse]] = [:]
    @Published var errorMessage: String?
    @Published var confirmationMessage: String?
    @Published var isLoading = true

    private let db = Firestore.firestore()
    private var requestListener: ListenerRegistration?
    private var responseListeners: [String: ListenerRegistration] = [:]

    func start() {
        requestListener?.remove()
        isLoading = true
        requestListener = db.collection("cashRydrRequests")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }

                    let requests = (snapshot?.documents ?? [])
                        .compactMap(Self.makeRequest)
                        .sorted { $0.scheduledTime < $1.scheduledTime }

                    self.openRequests = requests.filter(\.isOpen)
                    self.scheduledRequests = requests.filter(\.isScheduledForCurrentDriver)
                    self.syncResponseListeners(for: self.openRequests + self.scheduledRequests)
                }
            }
    }

    func stop() {
        requestListener?.remove()
        requestListener = nil
        responseListeners.values.forEach { $0.remove() }
        responseListeners.removeAll()
    }

    func sendMessage(to request: DriverCashRideRequest, text: String, driverName: String) -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Sign in before messaging a rider."
            return false
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a message first."
            return false
        }
        addResponse([
            "authorUid": uid,
            "authorName": displayName(driverName),
            "authorRole": "driver",
            "kind": request.isOpen ? "message" : "directMessage",
            "message": trimmed,
            "createdAt": FieldValue.serverTimestamp()
        ], to: request)
        return true
    }

    func sendOffer(to request: DriverCashRideRequest, draft: DriverCashOfferDraft, driverName: String) -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Sign in before sending an offer."
            return false
        }
        guard request.isOpen else {
            errorMessage = "This request is no longer accepting offers."
            return false
        }

        let availability = draft.availability.trimmingCharacters(in: .whitespacesAndNewlines)
        let vehicleInfo = draft.vehicleInfo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !availability.isEmpty, !vehicleInfo.isEmpty else {
            errorMessage = "Add your availability and vehicle information."
            return false
        }

        var payload: [String: Any] = [
            "authorUid": uid,
            "authorName": displayName(driverName),
            "authorRole": "driver",
            "kind": "offer",
            "status": "pending",
            "message": draft.message.trimmingCharacters(in: .whitespacesAndNewlines),
            "availability": availability,
            "vehicleInfo": vehicleInfo,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let amount = cleanAmount(draft.amount) {
            payload["offerAmount"] = amount
        }
        addResponse(payload, to: request)
        confirmationMessage = "Offer sent to \(request.riderName)."
        return true
    }

    func accept(_ request: DriverCashRideRequest, driverName: String) {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Sign in before accepting a cash ride."
            return
        }
        guard request.isOpen else {
            errorMessage = "This request has already been accepted."
            return
        }

        var payload: [String: Any] = [
            "status": "connected",
            "driverQueueStatus": "scheduled",
            "connectedDriverUid": uid,
            "connectedDriverName": displayName(driverName),
            "acceptedByUid": uid,
            "acceptedByName": displayName(driverName),
            "connectedAt": FieldValue.serverTimestamp(),
            "acceptedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let amount = cleanAmount(request.budgetRange) {
            payload["agreedPrice"] = amount
        }

        db.collection("cashRydrRequests").document(request.id).setData(payload, merge: true) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                self?.confirmationMessage = "Cash ride accepted and added to your scheduled queue."
                self?.addResponse([
                    "authorUid": uid,
                    "authorName": self?.displayName(driverName) ?? "Cash Hub Driver",
                    "authorRole": "driver",
                    "kind": "directMessage",
                    "message": "I accepted this cash ride. Please confirm any final pickup details before the scheduled time.",
                    "createdAt": FieldValue.serverTimestamp()
                ], to: request)
            }
        }
    }

    func updateQueueStatus(_ request: DriverCashRideRequest, status: String) {
        guard request.connectedDriverUid == Auth.auth().currentUser?.uid else {
            errorMessage = "Only the accepting driver can update this cash ride."
            return
        }

        var payload: [String: Any] = [
            "driverQueueStatus": status,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        switch status {
        case "confirmed":
            payload["driverConfirmedAt"] = FieldValue.serverTimestamp()
        case "completed":
            payload["cashCompletedAt"] = FieldValue.serverTimestamp()
        case "missed":
            payload["driverMarkedMissedAt"] = FieldValue.serverTimestamp()
        default:
            break
        }

        db.collection("cashRydrRequests").document(request.id).setData(payload, merge: true) { [weak self] error in
            Task { @MainActor in
                self?.errorMessage = error?.localizedDescription
                if error == nil {
                    self?.confirmationMessage = "Cash ride marked \(status)."
                }
            }
        }
    }

    private func addResponse(_ data: [String: Any], to request: DriverCashRideRequest) {
        db.collection("cashRydrRequests")
            .document(request.id)
            .collection("responses")
            .addDocument(data: data) { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = error?.localizedDescription
                }
            }
    }

    private func syncResponseListeners(for requests: [DriverCashRideRequest]) {
        let activeIDs = Set(requests.map(\.id))
        for (id, listener) in responseListeners where !activeIDs.contains(id) {
            listener.remove()
            responseListeners[id] = nil
            responsesByRequest[id] = nil
        }

        for request in requests where responseListeners[request.id] == nil {
            responseListeners[request.id] = db.collection("cashRydrRequests")
                .document(request.id)
                .collection("responses")
                .order(by: "createdAt", descending: false)
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error {
                            self.errorMessage = error.localizedDescription
                            return
                        }
                        self.responsesByRequest[request.id] = (snapshot?.documents ?? []).compactMap(Self.makeResponse)
                    }
                }
        }
    }

    private static func makeRequest(_ document: QueryDocumentSnapshot) -> DriverCashRideRequest? {
        let data = document.data()
        guard let riderUid = data["riderUid"] as? String,
              let pickup = data["pickup"] as? String else { return nil }
        let scheduledTime = (data["scheduledTime"] as? Timestamp)?.dateValue()
            ?? (data["windowStart"] as? Timestamp)?.dateValue()
            ?? Date()
        var budgetRange = data["budgetRange"] as? String ?? ""
        if budgetRange.isEmpty, let amount = data["amount"] as? Double {
            budgetRange = String(format: "%.2f", amount)
        }

        return DriverCashRideRequest(
            id: document.documentID,
            riderUid: riderUid,
            riderName: data["riderName"] as? String ?? "Cash Hub Rider",
            pickup: pickup,
            destination: data["destination"] as? String ?? data["dropoff"] as? String ?? "",
            scheduledTime: scheduledTime,
            passengers: data["passengers"] as? Int ?? 1,
            notes: data["notes"] as? String ?? data["note"] as? String ?? "",
            budgetRange: budgetRange,
            rideType: data["rideType"] as? String ?? "Scheduled",
            status: data["status"] as? String ?? "open",
            driverQueueStatus: data["driverQueueStatus"] as? String ?? "scheduled",
            connectedDriverUid: data["connectedDriverUid"] as? String ?? data["acceptedByUid"] as? String,
            connectedDriverName: data["connectedDriverName"] as? String ?? data["acceptedByName"] as? String,
            agreedPrice: data["agreedPrice"] as? Double,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }

    private static func makeResponse(_ document: QueryDocumentSnapshot) -> DriverCashHubResponse? {
        let data = document.data()
        guard let authorUid = data["authorUid"] as? String,
              let authorName = data["authorName"] as? String,
              let authorRole = data["authorRole"] as? String else { return nil }
        return DriverCashHubResponse(
            id: document.documentID,
            authorUid: authorUid,
            authorName: authorName,
            authorRole: authorRole,
            kind: data["kind"] as? String ?? "",
            status: data["status"] as? String ?? "pending",
            message: data["message"] as? String ?? "",
            offerAmount: data["offerAmount"] as? Double ?? data["counterAmount"] as? Double,
            availability: data["availability"] as? String ?? "",
            vehicleInfo: data["vehicleInfo"] as? String ?? "",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }

    private func cleanAmount(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let amount = Double(cleaned), amount > 0 else { return nil }
        return (amount * 100).rounded() / 100
    }

    private func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Cash Hub Driver" : trimmed
    }
}

struct DriverCashRydrHubView: View {
    @EnvironmentObject private var session: DriverSessionManager
    @StateObject private var vm = DriverCashRydrHubVM()
    @State private var selectedTab: DriverCashHubTab = .requests
    @State private var messagingRequest: DriverCashRideRequest?
    @State private var offeringRequest: DriverCashRideRequest?
    @State private var acceptingRequest: DriverCashRideRequest?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Cash Hub", selection: $selectedTab) {
                ForEach(DriverCashHubTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if vm.isLoading {
                Spacer()
                ProgressView("Loading Cash Hub...")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        header
                        switch selectedTab {
                        case .requests:
                            requestList
                        case .scheduled:
                            scheduledList
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Cash Rydr Hub")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .sheet(item: $messagingRequest) { request in
            DriverCashMessageSheet(
                request: request,
                messages: vm.responsesByRequest[request.id] ?? []
            ) { text in
                if vm.sendMessage(to: request, text: text, driverName: session.driverName) {
                    messagingRequest = nil
                }
            }
        }
        .sheet(item: $offeringRequest) { request in
            DriverCashOfferSheet(request: request) { draft in
                if vm.sendOffer(to: request, draft: draft, driverName: session.driverName) {
                    offeringRequest = nil
                }
            }
        }
        .confirmationDialog(
            "Accept this cash ride?",
            isPresented: Binding(
                get: { acceptingRequest != nil },
                set: { if !$0 { acceptingRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Accept and Schedule") {
                if let acceptingRequest {
                    vm.accept(acceptingRequest, driverName: session.driverName)
                }
                acceptingRequest = nil
                selectedTab = .scheduled
            }
            Button("Cancel", role: .cancel) { acceptingRequest = nil }
        } message: {
            Text("Cash Hub rides are managed by the driver. Rydr can help you track the request, but getting to pickup on time is your responsibility.")
        }
        .alert("Cash Rydr Hub", isPresented: Binding(
            get: { vm.errorMessage != nil || vm.confirmationMessage != nil },
            set: {
                if !$0 {
                    vm.errorMessage = nil
                    vm.confirmationMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? vm.confirmationMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Independent cash ride marketplace", systemImage: "person.3.fill")
                .font(.headline)
            Text("Browse rider requests, message or negotiate price, then manage accepted cash rides from your scheduled queue.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .driverCashCard()
    }

    @ViewBuilder
    private var requestList: some View {
        if vm.openRequests.isEmpty {
            DriverCashEmptyState(
                title: "No open requests",
                message: "New Cash Hub rider posts will appear here when riders request independent scheduled rides."
            )
        } else {
            ForEach(vm.openRequests) { request in
                DriverCashRequestCard(
                    request: request,
                    responses: vm.responsesByRequest[request.id] ?? [],
                    onMessage: { messagingRequest = request },
                    onOffer: { offeringRequest = request },
                    onAccept: { acceptingRequest = request }
                )
            }
        }
    }

    @ViewBuilder
    private var scheduledList: some View {
        if vm.scheduledRequests.isEmpty {
            DriverCashEmptyState(
                title: "No scheduled cash rides",
                message: "Accepted Cash Hub rides will live here so you can confirm, navigate, and manage reminders."
            )
        } else {
            ForEach(vm.scheduledRequests) { request in
                DriverCashScheduledCard(
                    request: request,
                    responses: vm.responsesByRequest[request.id] ?? [],
                    onMessage: { messagingRequest = request },
                    onConfirm: { vm.updateQueueStatus(request, status: "confirmed") },
                    onComplete: { vm.updateQueueStatus(request, status: "completed") },
                    onMissed: { vm.updateQueueStatus(request, status: "missed") }
                )
            }
        }
    }
}

private enum DriverCashHubTab: String, CaseIterable, Identifiable {
    case requests
    case scheduled

    var id: String { rawValue }
    var title: String {
        switch self {
        case .requests: return "Requests"
        case .scheduled: return "Scheduled"
        }
    }
}

private struct DriverCashRequestCard: View {
    let request: DriverCashRideRequest
    let responses: [DriverCashHubResponse]
    let onMessage: () -> Void
    let onOffer: () -> Void
    let onAccept: () -> Void

    private var driverResponses: [DriverCashHubResponse] {
        responses.filter(\.isDriverAuthored)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DriverCashRideSummary(request: request)

            if !driverResponses.isEmpty {
                Text("You have \(driverResponses.count) reply\(driverResponses.count == 1 ? "" : "ies") on this request.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Message", action: onMessage)
                    .buttonStyle(.bordered)
                Button("Send Offer", action: onOffer)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Accept", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
        }
        .driverCashCard()
    }
}

private struct DriverCashScheduledCard: View {
    let request: DriverCashRideRequest
    let responses: [DriverCashHubResponse]
    let onMessage: () -> Void
    let onConfirm: () -> Void
    let onComplete: () -> Void
    let onMissed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DriverCashRideSummary(request: request)

            Label("Queue status: \(request.driverQueueStatus.capitalized)", systemImage: "calendar.badge.clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                Button("Message", action: onMessage)
                    .buttonStyle(.bordered)
                Button("Confirm", action: onConfirm)
                    .buttonStyle(.bordered)
                Button("Navigate") {
                    openMaps(to: request.pickup)
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Button("Complete", action: onComplete)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                Button("Missed", role: .destructive, action: onMissed)
                    .buttonStyle(.bordered)
            }

            if responses.contains(where: { $0.kind == "directMessage" }) {
                Text("Direct messages are available for this accepted cash ride.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .driverCashCard()
    }

    private func openMaps(to address: String) {
        let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? address
        if let url = URL(string: "maps://?daddr=\(encoded)&dirflg=d") {
            UIApplication.shared.open(url)
        }
    }
}

private struct DriverCashRideSummary: View {
    let request: DriverCashRideRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.riderName)
                        .font(.headline)
                    Text(request.scheduledTime.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !request.budgetRange.isEmpty {
                    Text(budgetText)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Styles.rydrGradient)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(request.pickup, systemImage: "mappin.circle.fill")
                Label(request.destination, systemImage: "flag.checkered.circle.fill")
            }
            .font(.subheadline)

            HStack(spacing: 8) {
                DriverCashBadge(text: request.rideType)
                DriverCashBadge(text: "\(request.passengers) passenger\(request.passengers == 1 ? "" : "s")")
            }

            if !request.notes.isEmpty {
                Text(request.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var budgetText: String {
        if request.budgetRange.hasPrefix("$") { return request.budgetRange }
        return "$\(request.budgetRange)"
    }
}

private struct DriverCashMessageSheet: View {
    let request: DriverCashRideRequest
    let messages: [DriverCashHubResponse]
    var onSend: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Ride") {
                    Text("\(request.pickup) to \(request.destination)")
                    Text(request.scheduledTime.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }

                Section("Conversation") {
                    if messages.isEmpty {
                        Text("No messages yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(messages) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.authorName)
                                    .font(.caption.weight(.semibold))
                                if let amount = message.offerAmount {
                                    Text(amount, format: .currency(code: "USD"))
                                        .font(.caption)
                                        .foregroundStyle(Styles.rydrGradient)
                                }
                                if !message.message.isEmpty {
                                    Text(message.message)
                                }
                            }
                        }
                    }
                }

                Section("Message Rider") {
                    TextField("Message", text: $text, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                }
            }
            .navigationTitle("Message Rider")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { onSend(text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct DriverCashOfferSheet: View {
    let request: DriverCashRideRequest
    var onSend: (DriverCashOfferDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = DriverCashOfferDraft()

    var body: some View {
        NavigationStack {
            Form {
                Section("Request") {
                    LabeledContent("Pickup", value: request.pickup)
                    LabeledContent("Destination", value: request.destination)
                    LabeledContent("Scheduled", value: request.scheduledTime.formatted(date: .abbreviated, time: .shortened))
                }

                Section("Your Offer") {
                    TextField("Offer amount", text: $draft.amount)
                        .keyboardType(.decimalPad)
                    TextField("Availability", text: $draft.availability)
                    TextField("Vehicle", text: $draft.vehicleInfo)
                    TextField("Message", text: $draft.message, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                Section {
                    Text("Cash Hub prices and pickup coordination are handled directly between you and the rider.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Send Offer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { onSend(draft) }
                        .disabled(draft.availability.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.vehicleInfo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct DriverCashBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.red.opacity(0.1)))
    }
}

private struct DriverCashEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .driverCashCard()
    }
}

private extension View {
    func driverCashCard() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground)))
    }
}
