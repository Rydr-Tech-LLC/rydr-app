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
    var releasedByUid: String?
    var agreedPrice: Double?
    var createdAt: Date?
    var pickupCoordinate: CLLocationCoordinate2D?
    var destinationCoordinate: CLLocationCoordinate2D?

    var isOpenForCurrentDriver: Bool {
        guard status == "open", connectedDriverUid == nil else { return false }
        if releasedByUid == Auth.auth().currentUser?.uid { return false }
        return !["scheduled", "confirmed", "arrived", "started"].contains(driverQueueStatus)
    }

    var isScheduledForCurrentDriver: Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return connectedDriverUid == uid
            && (status == "connected" || status == "accepted")
            && ["scheduled", "confirmed", "arrived", "started"].contains(driverQueueStatus)
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
    @Published var isCheckingTerms = true
    @Published var termsAccepted = false
    @Published var termsAcceptanceEnabled = false
    @Published var isSavingTerms = false

    private let db = Firestore.firestore()
    private var openRequestListener: ListenerRegistration?
    private var scheduledRequestListener: ListenerRegistration?
    private var responseListeners: [String: ListenerRegistration] = [:]
    private var publicOpenRequestBuffer: [DriverCashRideRequest] = []
    private var driverScheduledRequestBuffer: [DriverCashRideRequest] = []

    func loadAccess() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Sign in before using Cash Rydr Hub."
            isCheckingTerms = false
            isLoading = false
            return
        }

        let configRef = db.collection("platformConfig").document("cashRydrHub")
        let driverRef = db.collection("drivers").document(uid)

        configRef.getDocument { [weak self] configSnapshot, _ in
            driverRef.getDocument { snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isCheckingTerms = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                        return
                    }

                    let config = configSnapshot?.data() ?? [:]
                    self.termsAcceptanceEnabled = config["termsAcceptanceEnabled"] as? Bool ?? false

                    let data = snapshot?.data() ?? [:]
                    self.termsAccepted = data["cashHubTermsAccepted"] as? Bool ?? false
                    if self.termsAcceptanceEnabled && self.termsAccepted {
                        self.start()
                    } else {
                        self.isLoading = false
                    }
                }
            }
        }
    }

    func acceptTerms() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Sign in before continuing."
            return
        }

        guard termsAcceptanceEnabled else {
            errorMessage = "Cash Rydr Hub is not available during the live beta."
            return
        }

        isSavingTerms = true
        db.collection("drivers").document(uid).setData([
            "cashHubTermsAccepted": true,
            "cashHubTermsAcceptedAt": FieldValue.serverTimestamp(),
            "cashHubRole": "driver"
        ], merge: true) { error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSavingTerms = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.termsAccepted = true
                self.start()
            }
        }
    }

    func start() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Sign in before using Cash Rydr Hub."
            isLoading = false
            return
        }
        openRequestListener?.remove()
        scheduledRequestListener?.remove()
        isLoading = true
        openRequestListener = db.collection("cashRydrRequests")
            .whereField("status", isEqualTo: "open")
            .whereField("visibility", isEqualTo: "public")
            .addSnapshotListener { snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.isLoading = false
                        self.errorMessage = error.localizedDescription
                        return
                    }

                    self.publicOpenRequestBuffer = (snapshot?.documents ?? [])
                        .compactMap(Self.makeRequest)
                        .sorted { $0.scheduledTime < $1.scheduledTime }
                    self.applyRequestBuffers()
                }
            }

        scheduledRequestListener = db.collection("cashRydrRequests")
            .whereField("connectedDriverUid", isEqualTo: uid)
            .addSnapshotListener { snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.isLoading = false
                        self.errorMessage = error.localizedDescription
                        return
                    }

                    self.driverScheduledRequestBuffer = (snapshot?.documents ?? [])
                        .compactMap(Self.makeRequest)
                        .sorted { $0.scheduledTime < $1.scheduledTime }
                    self.applyRequestBuffers()
                }
            }
    }

    func stop() {
        openRequestListener?.remove()
        openRequestListener = nil
        scheduledRequestListener?.remove()
        scheduledRequestListener = nil
        responseListeners.values.forEach { $0.remove() }
        responseListeners.removeAll()
        publicOpenRequestBuffer = []
        driverScheduledRequestBuffer = []
    }

    private func applyRequestBuffers() {
        var mergedById: [String: DriverCashRideRequest] = [:]
        for request in publicOpenRequestBuffer + driverScheduledRequestBuffer {
            mergedById[request.id] = request
        }
        let requests = mergedById.values.sorted { $0.scheduledTime < $1.scheduledTime }
        openRequests = requests.filter(\.isOpenForCurrentDriver)
        scheduledRequests = requests.filter(\.isScheduledForCurrentDriver)
        syncResponseListeners(for: openRequests + scheduledRequests)
        isLoading = false
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
            "kind": request.status == "open" ? "message" : "directMessage",
            "message": trimmed,
            "createdAt": FieldValue.serverTimestamp()
        ], to: request)
        return true
    }

    func sendOffer(to request: DriverCashRideRequest, draft: DriverCashOfferDraft, driverName: String) -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Sign in before starting a negotiation."
            return false
        }
        guard request.isOpenForCurrentDriver else {
            errorMessage = "This request is no longer accepting negotiations."
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
        confirmationMessage = "Negotiation sent to \(request.riderName)."
        return true
    }

    func accept(_ request: DriverCashRideRequest, driverName: String) {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Sign in before accepting a cash ride."
            return
        }
        guard request.isOpenForCurrentDriver else {
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
        case "arrived":
            payload["driverArrivedAt"] = FieldValue.serverTimestamp()
        case "started":
            payload["cashRideStartedAt"] = FieldValue.serverTimestamp()
        case "completed":
            payload["cashCompletedAt"] = FieldValue.serverTimestamp()
            // Rider-side history/activity filtering reads the top-level "status" field,
            // not "driverQueueStatus" — both must flip to "completed" so the ride
            // actually surfaces in the rider's Cash Hub Ride History.
            payload["status"] = "completed"
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
                    self.confirmationMessage = "Ride released. This release was flagged for admin review because it was within 1 hour of pickup."
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
            driverQueueStatus: data["driverQueueStatus"] as? String ?? "open",
            connectedDriverUid: data["connectedDriverUid"] as? String ?? data["acceptedByUid"] as? String,
            connectedDriverName: data["connectedDriverName"] as? String ?? data["acceptedByName"] as? String,
            releasedByUid: data["releasedByUid"] as? String,
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
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: DriverSessionManager
    @StateObject private var vm = DriverCashRydrHubVM()
    @State private var selectedTab: DriverCashHubTab = .newPosts
    @State private var messagingRequest: DriverCashRideRequest?
    @State private var offeringRequest: DriverCashRideRequest?
    @State private var acceptingRequest: DriverCashRideRequest?
    @State private var activeRideRequest: DriverCashRideRequest?
    @State private var acceptedRideRequest: DriverCashRideRequest?
    @State private var selectedScheduledRide: DriverCashRideRequest?
    @State private var releasingRequest: DriverCashRideRequest?
    @State private var hiddenRequestIDs: Set<String> = []
    @State private var showsSafetyNotice = true
    @State private var acceptedTermsCheckbox = false

    var body: some View {
        VStack(spacing: 0) {
            if vm.isCheckingTerms {
                Spacer()
                ProgressView("Loading Cash Hub...")
                Spacer()
            } else if !vm.termsAcceptanceEnabled || !vm.termsAccepted {
                DriverCashHubTermsView(
                    isConfirmed: $acceptedTermsCheckbox,
                    isSaving: vm.isSavingTerms,
                    canAcceptTerms: vm.termsAcceptanceEnabled,
                    onContinue: { vm.acceptTerms() }
                )
                .safeAreaInset(edge: .top) {
                    DriverCashHubGrabber(onClose: { dismiss() })
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            } else if vm.isLoading {
                Spacer()
                ProgressView("Loading Cash Hub...")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        DriverCashHubGrabber(onClose: { dismiss() })
                        header
                        DriverCashHubSegmentedTabs(selectedTab: $selectedTab)
                        switch selectedTab {
                        case .newPosts:
                            requestList(vm.openRequests.filter { !hiddenRequestIDs.contains($0.id) })
                        case .nearby:
                            requestList(vm.openRequests.filter { !hiddenRequestIDs.contains($0.id) })
                        case .scheduled:
                            scheduledList
                        case .myOffers:
                            requestList(
                                vm.openRequests.filter { !hiddenRequestIDs.contains($0.id) && hasPendingNegotiation(for: $0) },
                                emptyTitle: "No pending negotiations",
                                emptyMessage: "Posts you negotiate on will live here until the rider accepts or the request closes."
                            )
                        }
                        if showsSafetyNotice {
                            DriverCashSafetyNotice {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    showsSafetyNotice = false
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .background(
            LinearGradient(
                colors: [Color(.systemGroupedBackground), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .onAppear { vm.loadAccess() }
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
            DriverCashOfferSheet(
                request: request,
                messages: vm.responsesByRequest[request.id] ?? []
            ) { draft in
                if vm.sendOffer(to: request, draft: draft, driverName: session.driverName) {
                    offeringRequest = nil
                }
            }
        }
        .fullScreenCover(item: $activeRideRequest) { request in
            DriverCashRydrNavigationView(
                request: request,
                onMessage: { messagingRequest = request },
                onArrived: { vm.updateQueueStatus(request, status: "arrived") },
                onStartRide: { vm.updateQueueStatus(request, status: "started") },
                onComplete: {
                    vm.updateQueueStatus(request, status: "completed")
                    activeRideRequest = nil
                }
            )
        }
        .fullScreenCover(item: $acceptedRideRequest) { request in
            DriverCashAcceptedRideView(
                request: request,
                onViewDetails: {
                    acceptedRideRequest = nil
                    selectedTab = .scheduled
                },
                onMessage: {
                    acceptedRideRequest = nil
                    messagingRequest = request
                }
            )
        }
        .fullScreenCover(item: $selectedScheduledRide) { request in
            DriverCashScheduledDetailView(
                request: request,
                onBack: { selectedScheduledRide = nil },
                onMessage: { messagingRequest = request },
                onStartRide: {
                    selectedScheduledRide = nil
                    activeRideRequest = request
                },
                onArrived: { vm.updateQueueStatus(request, status: "arrived") },
                onComplete: {
                    vm.updateQueueStatus(request, status: "completed")
                    selectedScheduledRide = nil
                },
                onCancel: {
                    selectedScheduledRide = nil
                    releasingRequest = request
                }
            )
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
                    acceptedRideRequest = acceptingRequest
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
        VStack(spacing: 14) {
            DriverCashHeroCard()
            DriverCashStatsCard(
                openCount: vm.openRequests.count,
                scheduledCount: vm.scheduledRequests.count,
                negotiatingCount: pendingNegotiationCount
            )
        }
    }

    @ViewBuilder
    private func requestList(
        _ requests: [DriverCashRideRequest],
        emptyTitle: String = "No open requests",
        emptyMessage: String = "New Cash Hub rider posts will appear here when riders request independent scheduled rides."
    ) -> some View {
        if requests.isEmpty {
            DriverCashEmptyState(
                title: emptyTitle,
                message: emptyMessage,
                onRefresh: { vm.start() }
            )
        } else {
            ForEach(requests) { request in
                DriverCashRequestCard(
                    request: request,
                    responses: vm.responsesByRequest[request.id] ?? [],
                    onOffer: { offeringRequest = request },
                    onAccept: { acceptingRequest = request },
                    onHide: { hiddenRequestIDs.insert(request.id) }
                )
            }
        }
    }

    @ViewBuilder
    private var scheduledList: some View {
        if vm.scheduledRequests.isEmpty {
            DriverCashEmptyState(
                title: "No scheduled cash rides",
                message: "Accepted Cash Hub rides will live here so you can confirm, navigate, and manage reminders.",
                onRefresh: { vm.start() }
            )
        } else {
            ForEach(vm.scheduledRequests) { request in
                DriverCashScheduledCard(
                    request: request,
                    responses: vm.responsesByRequest[request.id] ?? [],
                    onViewDetails: { selectedScheduledRide = request },
                    onRelease: { releasingRequest = request }
                )
            }
        }
    }

    private var pendingNegotiationCount: Int {
        vm.openRequests.filter { hasPendingNegotiation(for: $0) }.count
    }

    private func hasPendingNegotiation(for request: DriverCashRideRequest) -> Bool {
        (vm.responsesByRequest[request.id] ?? []).contains {
            $0.isDriverAuthored
                && $0.kind == "offer"
                && ["pending", "countered"].contains($0.status)
        }
    }
}

private struct DriverCashHubTermsView: View {
    @Binding var isConfirmed: Bool
    let isSaving: Bool
    let canAcceptTerms: Bool
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            DriverCashHubTermsBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    DriverCashHubTermsHero()
                        .padding(.top, 30)

                    DriverCashHubTermsKnowledgeCard()

                    DriverCashHubResponsibilityCard()

                    if !canAcceptTerms {
                        DriverCashHubBetaLockedNotice()
                    }

                    DriverCashHubConfirmationToggle(
                        isConfirmed: $isConfirmed,
                        isEnabled: canAcceptTerms
                    )

                    Button(action: onContinue) {
                        HStack(spacing: 12) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "shield.checkered")
                                    .font(.title3.weight(.bold))
                            }
                            Text(isSaving ? "Saving..." : canAcceptTerms ? "I Understand and Continue" : "Unavailable During Live Beta")
                                .font(.headline.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(canAcceptTerms && isConfirmed && !isSaving ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color.gray.opacity(0.45)))
                        )
                        .shadow(color: Color.red.opacity(canAcceptTerms && isConfirmed ? 0.24 : 0), radius: 18, y: 10)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAcceptTerms || !isConfirmed || isSaving)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
            }
        }
    }
}

private struct DriverCashHubBetaLockedNotice: View {
    var body: some View {
        Label {
            Text("Cash Rydr Hub terms acceptance is paused for the live beta.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(Styles.rydrGradient)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.red.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct DriverCashHubTermsBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(red: 1.0, green: 0.965, blue: 0.97),
                Color(.secondarySystemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            Circle()
                .fill(Color.red.opacity(0.09))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(y: 120)
                .accessibilityHidden(true)
        }
    }
}

private struct DriverCashHubTermsHero: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                DriverCashHubTermsArc()
                    .stroke(Color.red.opacity(0.26), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 8]))
                    .frame(height: 88)
                    .offset(y: 24)
                    .accessibilityHidden(true)

                HStack {
                    DriverCashHubHeroBubble(systemImage: "car.fill")
                    Spacer()
                    DriverCashHubHeroBubble(systemImage: "person.fill")
                }
                .padding(.horizontal, 34)
                .offset(y: 28)

                ZStack {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 96, weight: .black))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.red.opacity(0.70), Color(red: 0.78, green: 0.04, blue: 0.13)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.red.opacity(0.20), radius: 18, y: 10)
                    Image(systemName: "person.2.fill")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .offset(y: -5)
                }
            }
            .frame(height: 150)

            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    Text("Cash ")
                        .foregroundStyle(.primary)
                    Text("Rydr")
                        .foregroundStyle(Styles.rydrGradient)
                    Text(" Hub Terms")
                        .foregroundStyle(.primary)
                }
                .font(.system(size: 36, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

                Text("Cash Rydr Hub is a community marketplace that allows riders and independent drivers to connect directly. Cash Rydr Hub rides are not Rydr-dispatched rides.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 8)
            }
        }
    }
}

private struct DriverCashHubHeroBubble: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.title2.weight(.black))
            .foregroundStyle(Styles.rydrGradient)
            .frame(width: 70, height: 70)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.82), lineWidth: 2))
            .shadow(color: Color.black.opacity(0.07), radius: 16, y: 9)
            .accessibilityHidden(true)
    }
}

private struct DriverCashHubTermsArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        return path
    }
}

private struct DriverCashHubTermsKnowledgeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label {
                Text("What You Should Know")
                    .font(.title3.weight(.black))
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "shield.checkered")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Styles.rydrGradient)
            }

            VStack(spacing: 0) {
                DriverCashHubTermsFactRow(systemImage: "paperplane.fill", text: "Rydr does not dispatch Cash Hub rides.")
                Divider().padding(.leading, 82)
                DriverCashHubTermsFactRow(systemImage: "dollarsign.circle", text: "Rydr does not set Cash Hub prices or process Cash Hub payments.")
                Divider().padding(.leading, 82)
                DriverCashHubTermsFactRow(systemImage: "shield", text: "Rydr does not guarantee rider availability, ride completion, or user conduct.")
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)
    }
}

private struct DriverCashHubTermsFactRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 62, height: 62)
                .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(text)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
    }
}

private struct DriverCashHubResponsibilityCard: View {
    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.red.opacity(0.08), Color(.systemBackground)],
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.red.opacity(0.12), lineWidth: 1)
                )

            Image(systemName: "hands.sparkles")
                .font(.system(size: 86, weight: .light))
                .foregroundStyle(Color.red.opacity(0.16))
                .padding(.trailing, 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 14) {
                Label {
                    Text("Your Responsibility")
                        .font(.title3.weight(.black))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Styles.rydrGradient)
                }

                Text("By continuing, you understand that any ride arranged through Cash Rydr Hub is coordinated directly between you and the rider. You are responsible for confirming pickup, destination, timing, payment, and safety expectations before starting the ride.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .shadow(color: Color.red.opacity(0.06), radius: 14, y: 8)
    }
}

private struct DriverCashHubConfirmationToggle: View {
    @Binding var isConfirmed: Bool
    let isEnabled: Bool

    var body: some View {
        Button {
            guard isEnabled else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isConfirmed.toggle()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isConfirmed ? "checkmark.circle.fill" : "circle")
                    .font(.title.weight(.bold))
                    .foregroundStyle(isConfirmed ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color.secondary.opacity(0.45)))

                Text("I understand that Cash Rydr Hub is separate from standard Rydr rides.")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: $isConfirmed)
                    .labelsHidden()
                    .tint(.red)
                    .disabled(!isEnabled)
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("I understand that Cash Rydr Hub is separate from standard Rydr rides")
        .accessibilityValue(isConfirmed ? "Confirmed" : "Not confirmed")
    }
}

private enum DriverCashHubTab: String, CaseIterable, Identifiable {
    case newPosts
    case nearby
    case scheduled
    case myOffers

    var id: String { rawValue }
    var title: String {
        switch self {
        case .newPosts: return "New Posts"
        case .nearby: return "Nearby"
        case .scheduled: return "Scheduled"
        case .myOffers: return "My Offers"
        }
    }
}

private struct DriverCashHubGrabber: View {
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 42, height: 5)

            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Cash Rydr Hub")
            }
        }
        .frame(height: 36)
    }
}

private struct DriverCashHeroCard: View {
    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Styles.rydrGradient)

            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: CGFloat(10 + index * 2), height: CGFloat(36 + (index % 3) * 16))
                }
            }
            .offset(x: -72, y: -2)

            Image(systemName: "car.side.fill")
                .font(.system(size: 60, weight: .black))
                .foregroundStyle(Color.white.opacity(0.28))
                .rotationEffect(.degrees(-2))
                .offset(x: -18, y: 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("Cash Rydr Hub")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                Text("See posts. Connect. Negotiate.\nGet paid.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .frame(minHeight: 122)
        .shadow(color: Color.red.opacity(0.24), radius: 18, y: 9)
    }
}

private struct DriverCashStatsCard: View {
    let openCount: Int
    let scheduledCount: Int
    let negotiatingCount: Int

    var body: some View {
        HStack(spacing: 0) {
            DriverCashStatColumn(value: openCount, title: "Open", systemImage: "calendar.badge.plus")
            Divider().frame(height: 54)
            DriverCashStatColumn(value: scheduledCount, title: "Scheduled", systemImage: "calendar")
            Divider().frame(height: 54)
            DriverCashStatColumn(value: negotiatingCount, title: "Negotiating", systemImage: "message.badge")
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)
        )
    }
}

private struct DriverCashStatColumn: View {
    let value: Int
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 7) {
            Text("\(value)")
                .font(.title3.weight(.black))
                .foregroundStyle(value > 0 ? Color.red : Color.primary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(value > 0 ? Color.red : Color.secondary.opacity(0.6))
                .frame(width: 24, height: 24)
                .background(Circle().fill(value > 0 ? Color.red.opacity(0.10) : Color(.secondarySystemGroupedBackground)))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DriverCashHubSegmentedTabs: View {
    @Binding var selectedTab: DriverCashHubTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DriverCashHubTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.caption.weight(.black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
                        .background(
                            Capsule()
                                .fill(selectedTab == tab ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color.clear))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
    }
}

private struct DriverCashRequestCard: View {
    let request: DriverCashRideRequest
    let responses: [DriverCashHubResponse]
    let onOffer: () -> Void
    let onAccept: () -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DriverCashRideSummary(request: request)

            Text(cardDetailLine)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !request.notes.isEmpty {
                Text(request.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
            }

            HStack(spacing: 10) {
                Button("Accept", action: onAccept)
                    .buttonStyle(.bordered)
                Button("Negotiate", action: onOffer)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                Menu {
                    Button("Hide", role: .destructive, action: onHide)
                    Button("Report Post", role: .destructive) {}
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
            }
        }
        .driverCashPremiumCard()
    }

    private var cardDetailLine: String {
        let offerCount = responses.filter { $0.kind == "offer" }.count
        let offerText = "\(offerCount) Offer\(offerCount == 1 ? "" : "s")"
        let passengerText = "\(request.passengers) Passenger\(request.passengers == 1 ? "" : "s")"
        return "\(offerText) -> No Luggage, \(request.rideType) -> \(passengerText)"
    }

}

private struct DriverCashScheduledCard: View {
    let request: DriverCashRideRequest
    let responses: [DriverCashHubResponse]
    let onViewDetails: () -> Void
    let onRelease: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DriverCashRideSummary(request: request)

            Label("Queue status: \(request.driverQueueStatus.capitalized)", systemImage: "calendar.badge.clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                Button("View Details", action: onViewDetails)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                Button("Release/Cancel", role: .destructive, action: onRelease)
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
        .driverCashPremiumCard()
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

private struct DriverCashAcceptedRideView: View {
    let request: DriverCashRideRequest
    var onViewDetails: () -> Void
    var onMessage: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color.red.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ForEach(0..<18, id: \.self) { index in
                Capsule()
                    .fill(Color.red.opacity(0.65))
                    .frame(width: 4, height: 14)
                    .offset(y: animate ? -CGFloat(120 + (index % 6) * 28) : -20)
                    .rotationEffect(.degrees(Double(index * 21)))
                    .opacity(animate ? 0 : 1)
                    .animation(.easeOut(duration: 1.15).delay(Double(index) * 0.025), value: animate)
            }

            VStack(spacing: 22) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Styles.rydrGradient)
                        .frame(width: 104, height: 104)
                        .shadow(color: Color.red.opacity(0.35), radius: 28, y: 12)
                        .scaleEffect(animate ? 1.04 : 0.84)
                    Image(systemName: "checkmark")
                        .font(.system(size: 46, weight: .black))
                        .foregroundStyle(.white)
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.72), value: animate)

                VStack(spacing: 8) {
                    Text("Ride Accepted")
                        .font(.largeTitle.weight(.black))
                    Text("You'll pick up \(request.riderName).")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    DriverCashNavigationSummaryRow(
                        title: "Pickup",
                        address: request.pickup,
                        systemImage: "mappin.circle.fill",
                        label: request.scheduledTime.formatted(date: .omitted, time: .shortened)
                    )
                    DriverCashNavigationSummaryRow(
                        title: "Drop-off",
                        address: request.destination,
                        systemImage: "flag.checkered.circle.fill",
                        label: "Cash"
                    )
                    Divider()
                    HStack {
                        Text("Agreed Price")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(agreedPriceText)
                            .font(.title3.weight(.black))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemGroupedBackground)))

                Button("View Details") {
                    onViewDetails()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button("Message \(request.riderName)") {
                    onMessage()
                    dismiss()
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(.red)

                Spacer()
            }
            .padding(24)
        }
        .onAppear { animate = true }
    }

    private var agreedPriceText: String {
        if let agreedPrice = request.agreedPrice {
            return agreedPrice.formatted(.currency(code: "USD"))
        }
        guard !request.budgetRange.isEmpty else { return "Cash" }
        return request.budgetRange.hasPrefix("$") ? request.budgetRange : "$\(request.budgetRange)"
    }
}

private struct DriverCashScheduledDetailView: View {
    let request: DriverCashRideRequest
    var onBack: () -> Void
    var onMessage: () -> Void
    var onStartRide: () -> Void
    var onArrived: () -> Void
    var onComplete: () -> Void
    var onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    riderHeader
                    routeCard
                    actionCard

                    Button("Cancel Ride", role: .destructive) {
                        onCancel()
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .padding(.top, 4)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Scheduled Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onBack()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.bold))
                    }
                }
            }
        }
    }

    private var riderHeader: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Styles.rydrGradient)
                .frame(width: 54, height: 54)
                .overlay(
                    Text(initials)
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(request.riderName)
                    .font(.title3.weight(.black))
                Text("Cash ride • \(request.scheduledTime.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onMessage()
            } label: {
                Image(systemName: "message.fill")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                    .foregroundStyle(.red)
            }
        }
        .driverCashPremiumCard()
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            DriverCashNavigationSummaryRow(
                title: "Pickup",
                address: request.pickup,
                systemImage: "mappin.circle.fill",
                label: "Pickup"
            )
            DriverCashNavigationSummaryRow(
                title: "Drop-off",
                address: request.destination,
                systemImage: "flag.checkered.circle.fill",
                label: "Drop-off"
            )
            if !request.notes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rider Note")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(request.notes)
                        .font(.subheadline)
                }
            }
            Divider()
            HStack {
                Text("Agreed Price")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(agreedPriceText)
                    .font(.title3.weight(.black))
                    .foregroundStyle(.primary)
            }
        }
        .driverCashPremiumCard()
    }

    private var actionCard: some View {
        VStack(spacing: 12) {
            Button {
                onStartRide()
                dismiss()
            } label: {
                Text("Start Ride")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Button {
                onArrived()
            } label: {
                Text("I've Arrived")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)

            Button {
                onComplete()
                dismiss()
            } label: {
                Text("Complete Ride")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.black)
        }
        .driverCashPremiumCard()
    }

    private var initials: String {
        request.riderName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    private var agreedPriceText: String {
        if let agreedPrice = request.agreedPrice {
            return agreedPrice.formatted(.currency(code: "USD"))
        }
        guard !request.budgetRange.isEmpty else { return "Cash" }
        return request.budgetRange.hasPrefix("$") ? request.budgetRange : "$\(request.budgetRange)"
    }
}

private struct DriverCashRydrNavigationView: View {
    let request: DriverCashRideRequest
    var onMessage: () -> Void
    var onArrived: () -> Void
    var onStartRide: () -> Void
    var onComplete: () -> Void

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
    @State private var didArrive = false
    @State private var isNavigationStarted = false
    @State private var isRouteTrayExpanded = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            RydrDriverNavigationMapView(
                position: $camera,
                driverCoordinate: driverCoordinate,
                pickupCoordinate: pickupCoordinate,
                dropoffCoordinate: destinationCoordinate,
                routeCoordinates: routeCoordinates,
                isPickupStage: isPickupStage,
                heading: routeHeading,
                onRecenter: { startNavigation() }
            )
            .ignoresSafeArea()

            cashInstructionCard
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            cashRouteTray
            .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .task {
            await resolveCoordinates()
            await calculateRoute()
        }
    }

    private var cashInstructionCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: instructionIcon)
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text(navigationInstruction)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.70)

                    Text("Cash Rydr Hub navigation")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)

                    if !isNavigationStarted {
                        Button {
                            startNavigation()
                        } label: {
                            Label("Start Navigation", systemImage: "location.north.line.fill")
                                .font(.caption.weight(.black))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Styles.rydrGradient))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 5)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.66))
            )

            HStack(spacing: 16) {
                Image(systemName: "arrow.turn.up.right")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.70))
                    .frame(width: 54)

                Text(upcomingInstruction)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.48))
            )
            .offset(y: -1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 24, y: 12)
    }

    private var cashRouteTray: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.black.opacity(0.28))
                .frame(width: 54, height: 5)
                .padding(.top, 8)

            HStack(spacing: 8) {
                DriverCashNavigationMetric(value: arrivalTimeText, label: "arrival")
                DriverCashNavigationMetric(value: travelTimeText, label: "min")
                DriverCashNavigationMetric(value: distanceText, label: "mi")
            }

            if isRouteTrayExpanded {
                expandedCashRouteActions
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, isRouteTrayExpanded ? 18 : 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Color.white.opacity(0.76)))
                .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).stroke(Color.white.opacity(0.80), lineWidth: 1))
        )
        .shadow(color: Color.black.opacity(0.22), radius: 22, y: 10)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        if value.translation.height < -24 {
                            isRouteTrayExpanded = true
                        } else if value.translation.height > 24 {
                            isRouteTrayExpanded = false
                        } else {
                            isRouteTrayExpanded.toggle()
                        }
                    }
                }
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isRouteTrayExpanded.toggle()
            }
        }
    }

    private var expandedCashRouteActions: some View {
        VStack(spacing: 12) {
            DriverCashNavigationSummaryRow(
                title: isPickupStage ? "Pickup" : "Drop-off",
                address: activeAddress,
                systemImage: isPickupStage ? "mappin.circle.fill" : "flag.checkered.circle.fill",
                label: isPickupStage ? "Cash pickup" : "Cash drop-off"
            )

            DriverCashNavigationDetailRow(icon: "person.crop.circle.fill", title: request.riderName, subtitle: request.rideType)
            DriverCashNavigationDetailRow(icon: "banknote.fill", title: agreedPriceText, subtitle: "Cash Hub agreed price")

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.10)))
            }

            VStack(spacing: 0) {
                cashNavigationOption("Message Rider", icon: "message.fill", action: onMessage)
                Divider().padding(.leading, 58)
                cashNavigationOption("Recenter Navigation", icon: "location.fill") {
                    startNavigation()
                }
                Divider().padding(.leading, 58)
                cashNavigationOption("Close Cash Navigation", icon: "xmark.circle.fill", color: .red) {
                    dismiss()
                }
            }
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.05)))

            primaryAction

            Button {
                onComplete()
                dismiss()
            } label: {
                Text("Cash Ride Completed")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.08)))
                    .foregroundStyle(isPickupStage ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
            }
            .disabled(isPickupStage)

            Text("Cash Rydr Hub is a driver-managed cash ride flow. Rydr Map is provided for navigation support.")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if isPickupStage && !didArrive {
            Button {
                didArrive = true
                if let pickupCoordinate {
                    driverCoordinate = pickupCoordinate
                }
                onArrived()
            } label: {
                Text("I've Arrived")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Styles.rydrGradient))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(pickupCoordinate == nil)
        } else if isPickupStage {
            Button {
                isPickupStage = false
                onStartRide()
                Task {
                    await calculateRoute()
                    startNavigation()
                }
            } label: {
                Text("Start Ride")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Styles.rydrGradient))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(destinationCoordinate == nil)
        } else {
            Button {
                onComplete()
                dismiss()
            } label: {
                Text("Complete Ride")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Styles.rydrGradient))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private var activeDestination: CLLocationCoordinate2D? {
        isPickupStage ? pickupCoordinate : destinationCoordinate
    }

    private var navigationInstruction: String {
        if !isNavigationStarted {
            return "Tap Start Navigation for Rydr Map guidance."
        }
        if let first = routeSteps.first, !first.isEmpty {
            return first
        }
        return "Calculating Rydr route."
    }

    private var upcomingInstruction: String {
        routeSteps.dropFirst().first ?? activeAddress
    }

    private var activeAddress: String {
        isPickupStage ? request.pickup : request.destination
    }

    private var agreedPriceText: String {
        if let agreedPrice = request.agreedPrice {
            return agreedPrice.formatted(.currency(code: "USD"))
        }
        guard !request.budgetRange.isEmpty else { return "Cash" }
        return request.budgetRange.hasPrefix("$") ? request.budgetRange : "$\(request.budgetRange)"
    }

    private var instructionIcon: String {
        let instruction = navigationInstruction.lowercased()
        if instruction.contains("left") { return "arrow.turn.up.left" }
        if instruction.contains("right") { return "arrow.turn.up.right" }
        if instruction.contains("pickup") || instruction.contains("arrived") {
            return isPickupStage ? "mappin.circle.fill" : "flag.checkered.circle.fill"
        }
        return "arrow.up"
    }

    private var arrivalTimeText: String {
        guard let routeTravelTime else { return "--" }
        return Date.now.addingTimeInterval(routeTravelTime).formatted(date: .omitted, time: .shortened)
    }

    private var travelTimeText: String {
        guard let routeTravelTime else { return "--" }
        let minutes = max(1, Int((routeTravelTime / 60).rounded()))
        return "\(minutes)"
    }

    private var distanceText: String {
        guard let routeDistanceMeters else { return "--" }
        return String(format: "%.1f", routeDistanceMeters / 1609.344)
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

    private var navigationCamera: MapCamera {
        MapCamera(
            centerCoordinate: driverCoordinate,
            distance: 720,
            heading: routeHeading,
            pitch: 68
        )
    }

    private var routeHeading: CLLocationDirection {
        let coordinates = routeCoordinates
        guard coordinates.count >= 2 else { return 0 }
        let origin = driverCoordinate
        let target = coordinates.dropFirst().first ?? coordinates[1]
        return bearing(from: origin, to: target)
    }

    private func startNavigation() {
        isNavigationStarted = true
        withAnimation(.easeInOut(duration: 0.28)) {
            camera = .camera(navigationCamera)
        }
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
        if isNavigationStarted {
            camera = .camera(navigationCamera)
        } else {
            camera = .region(region)
        }
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
            camera = isNavigationStarted ? .camera(navigationCamera) : .region(region)
        } catch {
            routeCoordinates = [driverCoordinate, destination]
            routeSteps = []
            routeDistanceMeters = nil
            routeTravelTime = nil
            errorMessage = "Rydr route preview is using a direct line until routing is available."
            camera = isNavigationStarted ? .camera(navigationCamera) : .region(region)
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

    private func cashNavigationOption(
        _ title: String,
        icon: String,
        color: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(color == .primary ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(color))
                    .frame(width: 34, height: 34)
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
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

private struct DriverCashNavigationMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 31, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DriverCashNavigationDetailRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Styles.rydrGradient))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.05)))
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
    let messages: [DriverCashHubResponse]
    var onSend: (DriverCashOfferDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = DriverCashOfferDraft()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(request.pickup) -> \(request.destination)")
                            .font(.headline.weight(.black))
                        Text(request.scheduledTime.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Budget \(budgetText)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Styles.rydrGradient)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Thread")
                            .font(.headline.weight(.black))
                        if messages.isEmpty {
                            Text("Start the negotiation with your price, availability, and pickup details.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(messages.sorted(by: messageSort)) { message in
                                DriverCashThreadBubble(message: message)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Negotiation")
                            .font(.headline.weight(.black))
                        TextField("Your price", text: $draft.amount)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        TextField("Availability", text: $draft.availability)
                            .textFieldStyle(.roundedBorder)
                        TextField("Vehicle", text: $draft.vehicleInfo)
                            .textFieldStyle(.roundedBorder)
                        TextField("Message", text: $draft.message, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("I can do that") { draft.message = "I can do that." }
                            Button("On my way") { draft.message = "On my way." }
                            Button("Meet outside?") { draft.message = "Can you meet outside?" }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))

                    Text("Cash Hub prices and pickup coordination are handled directly between you and the rider.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Negotiate")
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

    private var budgetText: String {
        guard !request.budgetRange.isEmpty else { return "open" }
        return request.budgetRange.hasPrefix("$") ? request.budgetRange : "$\(request.budgetRange)"
    }

    private func messageSort(_ lhs: DriverCashHubResponse, _ rhs: DriverCashHubResponse) -> Bool {
        (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
    }
}

private struct DriverCashThreadBubble: View {
    let message: DriverCashHubResponse

    var body: some View {
        HStack {
            if message.isDriverAuthored { Spacer(minLength: 32) }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(message.isDriverAuthored ? "You" : message.authorName)
                        .font(.caption.weight(.bold))
                    if let amount = message.offerAmount {
                        Text(amount, format: .currency(code: "USD"))
                            .font(.caption.weight(.black))
                            .foregroundStyle(message.isDriverAuthored ? .white : .red)
                    }
                }
                if !message.message.isEmpty {
                    Text(message.message)
                        .font(.subheadline)
                } else if message.kind == "offer" {
                    Text("Sent a negotiation.")
                        .font(.subheadline)
                }
            }
            .padding(12)
            .foregroundStyle(message.isDriverAuthored ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(message.isDriverAuthored ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            )
            if !message.isDriverAuthored { Spacer(minLength: 32) }
        }
    }
}

private struct DriverCashStatChip: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.headline.weight(.black))
            Text(subtitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

private struct DriverCashSafetyNotice: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.08))
                    .frame(width: 90, height: 90)
                Image(systemName: "shield.checkered")
                    .font(.system(size: 38, weight: .black))
                    .foregroundStyle(Styles.rydrGradient)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text("Safety First")
                        .font(.headline.weight(.black))
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss safety notice")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cash rides are arranged directly between rider and driver.")
                    Text("Confirm pickup, drop-off, price, and timing before meeting.")
                    Text("Report suspicious activity or unsafe behavior.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button(action: onDismiss) {
                    Text("Got it")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Styles.rydrGradient))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemBackground), Color.red.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.red.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct DriverCashEmptyState: View {
    let title: String
    let message: String
    var onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.08))
                    .frame(width: 74, height: 74)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 31, weight: .bold))
                    .foregroundStyle(Color.red)
            }

            Text(title)
                .font(.headline.weight(.black))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Styles.rydrGradient))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)
        )
    }
}

private extension View {
    func driverCashCard() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground)))
    }

    func driverCashPremiumCard() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
    }
}
