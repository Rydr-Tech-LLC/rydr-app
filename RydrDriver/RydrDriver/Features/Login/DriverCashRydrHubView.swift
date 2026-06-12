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
    var pickupCoordinate: CLLocationCoordinate2D?
    var destinationCoordinate: CLLocationCoordinate2D?

    var isOpen: Bool { status == "open" }
    var isScheduledForCurrentDriver: Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return connectedDriverUid == uid
            && (status == "connected" || status == "accepted")
            && driverQueueStatus != "completed"
            && driverQueueStatus != "missed"
            && driverQueueStatus != "cancelled"
    }

    static func == (lhs: DriverCashRideRequest, rhs: DriverCashRideRequest) -> Bool {
        lhs.id == rhs.id
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
            .addSnapshotListener { snapshot, error in
                Task { @MainActor [weak self] in
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
        let authorName = displayName(driverName)

        db.collection("cashRydrRequests").document(request.id).setData(payload, merge: true) { error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.confirmationMessage = "Cash ride accepted and added to your scheduled queue."
                self.addResponse([
                    "authorUid": uid,
                    "authorName": authorName,
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

        db.collection("cashRydrRequests").document(request.id).setData(payload, merge: true) { error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.errorMessage = error?.localizedDescription
                if error == nil {
                    self.confirmationMessage = "Cash ride marked \(status)."
                }
            }
        }
    }

    func releaseScheduledRide(_ request: DriverCashRideRequest, driverName: String) {
        guard let uid = Auth.auth().currentUser?.uid,
              request.connectedDriverUid == uid else {
            errorMessage = "Only the accepting driver can release this cash ride."
            return
        }

        let isLateRelease = request.scheduledTime.timeIntervalSince(Date()) <= 3600
        var payload: [String: Any] = [
            "status": "open",
            "driverQueueStatus": "released",
            "releasedByUid": uid,
            "releasedByName": displayName(driverName),
            "releasedAt": FieldValue.serverTimestamp(),
            "lateReleasePenalty": isLateRelease,
            "connectedDriverUid": FieldValue.delete(),
            "connectedDriverName": FieldValue.delete(),
            "acceptedByUid": FieldValue.delete(),
            "acceptedByName": FieldValue.delete(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if isLateRelease {
            payload["lateReleasePenaltyReason"] = "Released within 1 hour of scheduled pickup."
        }

        let requestRef = db.collection("cashRydrRequests").document(request.id)
        requestRef.setData(payload, merge: true) { error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                if isLateRelease {
                    self.recordLateReleasePenalty(driverUid: uid, request: request)
                    self.confirmationMessage = "Ride released. Late release marker added because this was within 1 hour of pickup."
                } else {
                    self.confirmationMessage = "Ride released back to Cash Hub."
                }
            }
        }
    }

    private func addResponse(_ data: [String: Any], to request: DriverCashRideRequest) {
        db.collection("cashRydrRequests")
            .document(request.id)
            .collection("responses")
            .addDocument(data: data) { error in
                Task { @MainActor [weak self] in
                    self?.errorMessage = error?.localizedDescription
                }
            }
    }

    private func recordLateReleasePenalty(driverUid: String, request: DriverCashRideRequest) {
        let driverRef = db.collection("drivers").document(driverUid)
        driverRef.setData([
            "cashHubLateReleaseCount": FieldValue.increment(Int64(1)),
            "cashHubLastLateReleaseAt": FieldValue.serverTimestamp(),
            "cashHubLastLateReleaseRequestId": request.id,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        driverRef.collection("cashHubPenaltyMarkers").addDocument(data: [
            "requestId": request.id,
            "scheduledTime": Timestamp(date: request.scheduledTime),
            "reason": "Released within 1 hour of scheduled pickup.",
            "createdAt": FieldValue.serverTimestamp()
        ])
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
                .addSnapshotListener { snapshot, error in
                    Task { @MainActor [weak self] in
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
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            pickupCoordinate: coordinate(from: data["pickupCoordinate"] ?? data["pickupLocation"] ?? data["pickupGeoPoint"]),
            destinationCoordinate: coordinate(from: data["destinationCoordinate"] ?? data["dropoffCoordinate"] ?? data["dropoffLocation"] ?? data["dropoffGeoPoint"])
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

    private static func coordinate(from value: Any?) -> CLLocationCoordinate2D? {
        if let point = value as? GeoPoint {
            return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        }
        guard let data = value as? [String: Any] else { return nil }
        let lat = doubleValue(data["lat"] ?? data["latitude"])
        let lng = doubleValue(data["lng"] ?? data["longitude"])
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }
}

struct DriverCashRydrHubView: View {
    @EnvironmentObject private var session: DriverSessionManager
    @StateObject private var vm = DriverCashRydrHubVM()
    @State private var selectedTab: DriverCashHubTab = .requests
    @State private var messagingRequest: DriverCashRideRequest?
    @State private var offeringRequest: DriverCashRideRequest?
    @State private var acceptingRequest: DriverCashRideRequest?
    @State private var navigatingRequest: DriverCashRideRequest?
    @State private var releasingRequest: DriverCashRideRequest?

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
        .fullScreenCover(item: $navigatingRequest) { request in
            DriverCashRydrNavigationView(request: request)
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
        .confirmationDialog(
            "Release this scheduled ride?",
            isPresented: Binding(
                get: { releasingRequest != nil },
                set: { if !$0 { releasingRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Release Ride", role: .destructive) {
                if let releasingRequest {
                    vm.releaseScheduledRide(releasingRequest, driverName: session.driverName)
                }
                releasingRequest = nil
            }
            Button("Keep Ride", role: .cancel) { releasingRequest = nil }
        } message: {
            if let releasingRequest, releasingRequest.scheduledTime.timeIntervalSince(Date()) <= 3600 {
                Text("This ride is within 1 hour of pickup. Releasing it now will add a late-release marker to your Cash Hub record. Continued late releases could remove your Cash Rydr Hub access.")
            } else {
                Text("The rider will need another driver. Release only if you can no longer complete this scheduled ride.")
            }
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
                    onNavigate: { navigatingRequest = request },
                    onConfirm: { vm.updateQueueStatus(request, status: "confirmed") },
                    onComplete: { vm.updateQueueStatus(request, status: "completed") },
                    onMissed: { vm.updateQueueStatus(request, status: "missed") },
                    onRelease: { releasingRequest = request }
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
    let onNavigate: () -> Void
    let onConfirm: () -> Void
    let onComplete: () -> Void
    let onMissed: () -> Void
    let onRelease: () -> Void

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
                Button("Navigate with Rydr Map", action: onNavigate)
                .buttonStyle(.bordered)
            }

            HStack {
                Button("Complete", action: onComplete)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                Button("Missed", role: .destructive, action: onMissed)
                    .buttonStyle(.bordered)
                Button("Release Ride", role: .destructive, action: onRelease)
                    .buttonStyle(.bordered)
            }

            if request.scheduledTime.timeIntervalSince(Date()) <= 3600 {
                Label("Releasing now will add a late-release marker.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            if responses.contains(where: { $0.kind == "directMessage" }) {
                Text("Direct messages are available for this accepted cash ride.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .driverCashCard()
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

private struct DriverCashRydrNavigationView: View {
    let request: DriverCashRideRequest

    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .region(DriverMapDefaults.pilotRegion)
    @State private var driverCoordinate = DriverMapDefaults.pilotCoordinate
    @State private var pickupCoordinate: CLLocationCoordinate2D?
    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var routeSteps: [String] = []
    @State private var routeDistanceMeters: CLLocationDistance?
    @State private var routeTravelTime: TimeInterval?
    @State private var isPickupStage = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            RydrDriverNavigationMapView(
                position: $camera,
                driverCoordinate: driverCoordinate,
                pickupCoordinate: pickupCoordinate,
                dropoffCoordinate: destinationCoordinate,
                routeCoordinates: routeCoordinates,
                isPickupStage: isPickupStage,
                onRecenter: { camera = .region(region) }
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isPickupStage ? "Navigate to pickup" : "Navigate to drop-off")
                            .font(.headline.weight(.black))
                        Text(request.riderName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(Color(.systemGray5)))
                            .foregroundStyle(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    DriverCashNavigationSummaryRow(
                        title: isPickupStage ? "Pickup" : "Drop-off",
                        address: isPickupStage ? request.pickup : request.destination,
                        systemImage: isPickupStage ? "mappin.circle.fill" : "flag.checkered.circle.fill",
                        label: isPickupStage ? "En route to pickup" : "En route to drop-off"
                    )

                    Label(navigationInstruction, systemImage: "location.north.line.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if let routeSummary {
                        Text(routeSummary)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Button {
                            isPickupStage = false
                            if let pickupCoordinate {
                                driverCoordinate = pickupCoordinate
                            }
                            Task { await calculateRoute() }
                        } label: {
                            Text("Start Drop-off Route")
                                .font(.headline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(!isPickupStage || destinationCoordinate == nil)

                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.22), lineWidth: 1))
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .task {
            await resolveCoordinates()
            await calculateRoute()
        }
    }

    private var activeDestination: CLLocationCoordinate2D? {
        isPickupStage ? pickupCoordinate : destinationCoordinate
    }

    private var navigationInstruction: String {
        if let first = routeSteps.first, !first.isEmpty {
            return first
        }
        return "Calculating Rydr route."
    }

    private var routeSummary: String? {
        guard let routeDistanceMeters, let routeTravelTime else { return nil }
        let miles = routeDistanceMeters / 1609.344
        let minutes = max(1, Int((routeTravelTime / 60).rounded()))
        return String(format: "%.1f mi • %d min", miles, minutes)
    }

    private var region: MKCoordinateRegion {
        let coordinates = [driverCoordinate, pickupCoordinate, destinationCoordinate].compactMap { $0 }
        guard !coordinates.isEmpty else { return DriverMapDefaults.pilotRegion }
        let minLat = coordinates.map(\.latitude).min() ?? DriverMapDefaults.pilotCoordinate.latitude
        let maxLat = coordinates.map(\.latitude).max() ?? DriverMapDefaults.pilotCoordinate.latitude
        let minLng = coordinates.map(\.longitude).min() ?? DriverMapDefaults.pilotCoordinate.longitude
        let maxLng = coordinates.map(\.longitude).max() ?? DriverMapDefaults.pilotCoordinate.longitude
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.025, (maxLat - minLat) * 1.8),
                longitudeDelta: max(0.025, (maxLng - minLng) * 1.8)
            )
        )
    }

    @MainActor
    private func resolveCoordinates() async {
        if let requestPickupCoordinate = request.pickupCoordinate {
            pickupCoordinate = requestPickupCoordinate
        } else {
            pickupCoordinate = await geocode(request.pickup)
        }

        if let requestDestinationCoordinate = request.destinationCoordinate {
            destinationCoordinate = requestDestinationCoordinate
        } else {
            destinationCoordinate = await geocode(request.destination)
        }
        camera = .region(region)
    }

    @MainActor
    private func calculateRoute() async {
        guard let destination = activeDestination else {
            routeCoordinates = []
            routeSteps = []
            routeDistanceMeters = nil
            routeTravelTime = nil
            errorMessage = "Could not resolve this route yet."
            return
        }

        let routeRequest = MKDirections.Request()
        routeRequest.source = MKMapItem(location: CLLocation(latitude: driverCoordinate.latitude, longitude: driverCoordinate.longitude), address: nil)
        routeRequest.destination = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        routeRequest.transportType = .automobile

        do {
            let response = try await MKDirections(request: routeRequest).calculate()
            guard let route = response.routes.first else {
                errorMessage = "No route found."
                return
            }
            routeCoordinates = route.polyline.cashHubCoordinates
            routeSteps = route.steps
                .map(\.instructions)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            routeDistanceMeters = route.distance
            routeTravelTime = route.expectedTravelTime
            errorMessage = nil
            camera = .region(region)
        } catch {
            routeCoordinates = [driverCoordinate, destination]
            routeSteps = []
            routeDistanceMeters = nil
            routeTravelTime = nil
            errorMessage = "Rydr route preview is using a direct line until routing is available."
        }
    }

    private func geocode(_ address: String) async -> CLLocationCoordinate2D? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            request.region = DriverMapDefaults.pilotRegion
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.first?.location.coordinate
        } catch {
            return nil
        }
    }
}

private extension MKPolyline {
    var cashHubCoordinates: [CLLocationCoordinate2D] {
        var coordinates = Array(repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}

private struct DriverCashNavigationSummaryRow: View {
    let title: String
    let address: String
    let systemImage: String
    let label: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label(label, systemImage: "location.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Text(address)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
