//
//  CashRydrHubView.swift
//  RydrPlayground
//
//  Cash ride request board.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct CashRydrRequest: Identifiable, Equatable {
    let id: String
    var riderUid: String
    var riderName: String
    var pickup: String
    var dropoff: String
    var amount: Double
    var note: String
    var windowStart: Date
    var windowEnd: Date
    var status: String
    var acceptedByUid: String?
    var acceptedByName: String?
    var createdAt: Date?

    var isOpen: Bool { status == "open" }
}

struct CashRydrReply: Identifiable, Equatable {
    let id: String
    var authorUid: String
    var authorName: String
    var authorRole: String
    var message: String
    var counterAmount: Double?
    var createdAt: Date?
}

private struct CashRydrDraft {
    var pickup = ""
    var dropoff = ""
    var amount = ""
    var note = ""
    var windowStart = Date().addingTimeInterval(3 * 60 * 60)
    var windowEnd = Date().addingTimeInterval(4 * 60 * 60)

    init() {}

    init(request: CashRydrRequest) {
        pickup = request.pickup
        dropoff = request.dropoff
        amount = String(format: "%.2f", request.amount)
        note = request.note
        windowStart = request.windowStart
        windowEnd = request.windowEnd
    }
}

private enum CashRydrMode: String, CaseIterable, Identifiable {
    case rider = "Rider"
    case driver = "Driver"

    var id: String { rawValue }
}

private final class CashRydrHubVM: ObservableObject {
    @Published var requests: [CashRydrRequest] = []
    @Published var repliesByRequest: [String: [CashRydrReply]] = [:]
    @Published var errorMessage: String?
    @Published var isSaving = false

    private let db = Firestore.firestore()
    private var requestListener: ListenerRegistration?
    private var replyListeners: [String: ListenerRegistration] = [:]

    func start() {
        requestListener?.remove()
        requestListener = db.collection("cashRydrRequests")
            .order(by: "windowStart", descending: false)
            .addSnapshotListener { [weak self] snap, error in
                guard let self = self else { return }
                if let error = error {
                    DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                    return
                }

                let mapped = (snap?.documents ?? []).compactMap(Self.makeRequest)
                DispatchQueue.main.async {
                    self.requests = mapped
                    self.syncReplyListeners(for: mapped)
                }
            }
    }

    func stop() {
        requestListener?.remove()
        requestListener = nil
        replyListeners.values.forEach { $0.remove() }
        replyListeners.removeAll()
    }

    func create(from draft: CashRydrDraft, riderName: String) -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Please log in to post a cash ride request."
            return false
        }
        guard let amount = cleanAmount(draft.amount) else {
            errorMessage = "Enter a valid cash amount."
            return false
        }
        guard validate(draft: draft) else { return false }

        isSaving = true
        let data: [String: Any] = [
            "riderUid": uid,
            "riderName": riderName.isEmpty ? "Rydr Rider" : riderName,
            "pickup": draft.pickup.trimmingCharacters(in: .whitespacesAndNewlines),
            "dropoff": draft.dropoff.trimmingCharacters(in: .whitespacesAndNewlines),
            "amount": amount,
            "note": draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
            "windowStart": Timestamp(date: draft.windowStart),
            "windowEnd": Timestamp(date: draft.windowEnd),
            "status": "open",
            "createdAt": FieldValue.serverTimestamp()
        ]

        db.collection("cashRydrRequests").addDocument(data: data) { [weak self] error in
            DispatchQueue.main.async {
                self?.isSaving = false
                self?.errorMessage = error?.localizedDescription
            }
        }
        return true
    }

    func update(_ request: CashRydrRequest, from draft: CashRydrDraft) -> Bool {
        guard let amount = cleanAmount(draft.amount) else {
            errorMessage = "Enter a valid cash amount."
            return false
        }
        guard validate(draft: draft) else { return false }

        isSaving = true
        let data: [String: Any] = [
            "pickup": draft.pickup.trimmingCharacters(in: .whitespacesAndNewlines),
            "dropoff": draft.dropoff.trimmingCharacters(in: .whitespacesAndNewlines),
            "amount": amount,
            "note": draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
            "windowStart": Timestamp(date: draft.windowStart),
            "windowEnd": Timestamp(date: draft.windowEnd),
            "status": "open",
            "acceptedByUid": FieldValue.delete(),
            "acceptedByName": FieldValue.delete()
        ]

        db.collection("cashRydrRequests").document(request.id).setData(data, merge: true) { [weak self] error in
            DispatchQueue.main.async {
                self?.isSaving = false
                self?.errorMessage = error?.localizedDescription
            }
        }
        return true
    }

    func delete(_ request: CashRydrRequest) {
        db.collection("cashRydrRequests").document(request.id).delete { [weak self] error in
            DispatchQueue.main.async { self?.errorMessage = error?.localizedDescription }
        }
    }

    func accept(_ request: CashRydrRequest, driverName: String) {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Please log in to accept a request."
            return
        }
        guard request.isOpen else {
            errorMessage = "This request has already been accepted."
            return
        }

        db.collection("cashRydrRequests").document(request.id).setData([
            "status": "accepted",
            "acceptedByUid": uid,
            "acceptedByName": driverName.isEmpty ? "Rydr Driver" : driverName,
            "acceptedAt": FieldValue.serverTimestamp()
        ], merge: true) { [weak self] error in
            DispatchQueue.main.async { self?.errorMessage = error?.localizedDescription }
        }
    }

    func reply(to request: CashRydrRequest, role: CashRydrMode, message: String, counterAmount: String, authorName: String) -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Please log in to reply."
            return false
        }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = cleanAmount(counterAmount)
        guard !trimmedMessage.isEmpty || amount != nil else {
            errorMessage = "Add a reply or a counter amount."
            return false
        }

        var data: [String: Any] = [
            "authorUid": uid,
            "authorName": authorName.isEmpty ? "Rydr User" : authorName,
            "authorRole": role.rawValue.lowercased(),
            "message": trimmedMessage,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let amount = amount {
            data["counterAmount"] = amount
        }

        db.collection("cashRydrRequests")
            .document(request.id)
            .collection("replies")
            .addDocument(data: data) { [weak self] error in
                DispatchQueue.main.async { self?.errorMessage = error?.localizedDescription }
            }
        return true
    }

    private func validate(draft: CashRydrDraft) -> Bool {
        let pickup = draft.pickup.trimmingCharacters(in: .whitespacesAndNewlines)
        let dropoff = draft.dropoff.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !pickup.isEmpty, !dropoff.isEmpty else {
            errorMessage = "Pickup and drop-off are required."
            return false
        }
        guard draft.windowStart >= Date().addingTimeInterval(2 * 60 * 60) else {
            errorMessage = "Cash ride requests must be at least 2 hours from now."
            return false
        }
        guard draft.windowEnd > draft.windowStart else {
            errorMessage = "Choose an end time after the start time."
            return false
        }
        return true
    }

    private func cleanAmount(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return (value * 100).rounded() / 100
    }

    private func syncReplyListeners(for requests: [CashRydrRequest]) {
        let activeIds = Set(requests.map(\.id))
        for (id, listener) in replyListeners where !activeIds.contains(id) {
            listener.remove()
            replyListeners[id] = nil
            repliesByRequest[id] = nil
        }

        for request in requests where replyListeners[request.id] == nil {
            replyListeners[request.id] = db.collection("cashRydrRequests")
                .document(request.id)
                .collection("replies")
                .order(by: "createdAt", descending: false)
                .addSnapshotListener { [weak self] snap, error in
                    guard let self = self else { return }
                    if let error = error {
                        DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                        return
                    }
                    let replies = (snap?.documents ?? []).compactMap(Self.makeReply)
                    DispatchQueue.main.async {
                        self.repliesByRequest[request.id] = replies
                    }
                }
        }
    }

    private static func makeRequest(_ doc: QueryDocumentSnapshot) -> CashRydrRequest? {
        let data = doc.data()
        guard
            let riderUid = data["riderUid"] as? String,
            let pickup = data["pickup"] as? String,
            let dropoff = data["dropoff"] as? String,
            let amount = data["amount"] as? Double,
            let windowStart = data["windowStart"] as? Timestamp,
            let windowEnd = data["windowEnd"] as? Timestamp
        else { return nil }

        return CashRydrRequest(
            id: doc.documentID,
            riderUid: riderUid,
            riderName: data["riderName"] as? String ?? "Rydr Rider",
            pickup: pickup,
            dropoff: dropoff,
            amount: amount,
            note: data["note"] as? String ?? "",
            windowStart: windowStart.dateValue(),
            windowEnd: windowEnd.dateValue(),
            status: data["status"] as? String ?? "open",
            acceptedByUid: data["acceptedByUid"] as? String,
            acceptedByName: data["acceptedByName"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }

    private static func makeReply(_ doc: QueryDocumentSnapshot) -> CashRydrReply? {
        let data = doc.data()
        guard
            let authorUid = data["authorUid"] as? String,
            let authorName = data["authorName"] as? String,
            let authorRole = data["authorRole"] as? String
        else { return nil }

        return CashRydrReply(
            id: doc.documentID,
            authorUid: authorUid,
            authorName: authorName,
            authorRole: authorRole,
            message: data["message"] as? String ?? "",
            counterAmount: data["counterAmount"] as? Double,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }
}

struct CashRydrHubView: View {
    @EnvironmentObject private var session: UserSessionManager
    @StateObject private var vm = CashRydrHubVM()

    @State private var mode: CashRydrMode = .rider
    @State private var showRequestForm = false
    @State private var editingRequest: CashRydrRequest?
    @State private var respondingTo: CashRydrRequest?

    private var currentUid: String { Auth.auth().currentUser?.uid ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(vm.requests) { request in
                        CashRydrRequestCard(
                            request: request,
                            replies: vm.repliesByRequest[request.id] ?? [],
                            mode: mode,
                            isMine: request.riderUid == currentUid,
                            onAccept: { vm.accept(request, driverName: session.userName) },
                            onReply: { respondingTo = request },
                            onEdit: { editingRequest = request },
                            onDelete: { vm.delete(request) }
                        )
                    }

                    if vm.requests.isEmpty {
                        ContentUnavailableView(
                            "No cash ride requests",
                            systemImage: "rectangle.on.rectangle.angled",
                            description: Text("New requests will show up here.")
                        )
                        .padding(.top, 60)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Cash Rydr Hub")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showRequestForm = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("New cash ride request")
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .sheet(isPresented: $showRequestForm) {
            CashRydrRequestForm(title: "New Request") { draft in
                if vm.create(from: draft, riderName: session.userName) {
                    showRequestForm = false
                }
            }
        }
        .sheet(item: $editingRequest) { request in
            CashRydrRequestForm(title: "Edit Request", initialDraft: CashRydrDraft(request: request)) { draft in
                if vm.update(request, from: draft) {
                    editingRequest = nil
                }
            }
        }
        .sheet(item: $respondingTo) { request in
            CashRydrReplyForm(request: request, mode: mode) { message, counterAmount in
                if vm.reply(
                    to: request,
                    role: mode,
                    message: message,
                    counterAmount: counterAmount,
                    authorName: session.userName
                ) {
                    respondingTo = nil
                }
            }
        }
        .alert("Cash Rydr Hub", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cash ride board")
                        .font(.title2.bold())
                    Text("Post, accept, or negotiate upcoming cash rides.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Picker("Hub mode", selection: $mode) {
                ForEach(CashRydrMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

private struct CashRydrRequestCard: View {
    let request: CashRydrRequest
    let replies: [CashRydrReply]
    let mode: CashRydrMode
    let isMine: Bool
    var onAccept: () -> Void
    var onReply: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.riderName)
                        .font(.headline)
                    Text(timeWindow)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(request.amount, format: .currency(code: "USD"))
                        .font(.title3.bold())
                    statusPill
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                routeRow(icon: "mappin.circle.fill", title: "Pickup", text: request.pickup)
                routeRow(icon: "flag.checkered.circle.fill", title: "Drop-off", text: request.dropoff)
            }

            if !request.note.isEmpty {
                Text(request.note)
                    .font(.body)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let acceptedByName = request.acceptedByName, request.status == "accepted" {
                Label("Accepted by \(acceptedByName)", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }

            if !replies.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(replies.suffix(3)) { reply in
                        CashRydrReplyRow(reply: reply)
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                if isMine {
                    Button("Edit", action: onEdit)
                        .buttonStyle(.bordered)
                    Button("Remove", role: .destructive, action: onDelete)
                        .buttonStyle(.bordered)
                } else if mode == .driver, request.isOpen {
                    Button("Accept", action: onAccept)
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    Button("Respond", action: onReply)
                        .buttonStyle(.bordered)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var statusPill: some View {
        Text(request.status.capitalized)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(request.status == "accepted" ? Color.green.opacity(0.14) : Color.orange.opacity(0.16))
            .foregroundStyle(request.status == "accepted" ? .green : .orange)
            .clipShape(Capsule())
    }

    private var timeWindow: String {
        let start = request.windowStart.formatted(date: .abbreviated, time: .shortened)
        let end = request.windowEnd.formatted(date: .omitted, time: .shortened)
        return "\(start) - \(end)"
    }

    private func routeRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

private struct CashRydrReplyRow: View {
    let reply: CashRydrReply

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(reply.authorName)
                    .font(.caption.weight(.semibold))
                Text(reply.authorRole.capitalized)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
                Spacer()
                if let counterAmount = reply.counterAmount {
                    Text(counterAmount, format: .currency(code: "USD"))
                        .font(.caption.weight(.bold))
                }
            }
            if !reply.message.isEmpty {
                Text(reply.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct CashRydrRequestForm: View {
    let title: String
    var initialDraft = CashRydrDraft()
    var onSave: (CashRydrDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CashRydrDraft

    init(title: String, initialDraft: CashRydrDraft = CashRydrDraft(), onSave: @escaping (CashRydrDraft) -> Void) {
        self.title = title
        self.initialDraft = initialDraft
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    TextField("Pickup location", text: $draft.pickup, axis: .vertical)
                    TextField("Drop-off location", text: $draft.dropoff, axis: .vertical)
                }

                Section("Cash offer") {
                    TextField("Amount", text: $draft.amount)
                        .keyboardType(.decimalPad)
                }

                Section("Time window") {
                    DatePicker("Start", selection: $draft.windowStart, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: $draft.windowEnd, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Post") {
                    TextField("Add details for drivers", text: $draft.note, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { onSave(draft) }
                }
            }
        }
    }
}

private struct CashRydrReplyForm: View {
    let request: CashRydrRequest
    let mode: CashRydrMode
    var onSend: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var counterAmount = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Request") {
                    LabeledContent("Offer", value: request.amount.formatted(.currency(code: "USD")))
                    LabeledContent("Pickup", value: request.pickup)
                    LabeledContent("Drop-off", value: request.dropoff)
                }

                Section(mode == .driver ? "Response" : "Reply") {
                    TextField("Message", text: $message, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                    TextField("Counter amount", text: $counterAmount)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle(mode == .driver ? "Respond" : "Reply")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { onSend(message, counterAmount) }
                }
            }
        }
    }
}
