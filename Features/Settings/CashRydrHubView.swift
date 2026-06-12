//
//  CashRydrHubView.swift
//  RydrPlayground
//
//  Community ride request marketplace. Cash Hub connections are never dispatched rides.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import MapKit

enum CashHubRole: String, CaseIterable, Identifiable {
    case rider
    case driver
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rider: return "Rider"
        case .driver: return "Driver"
        case .both: return "Rider and Driver"
        }
    }

    var canRide: Bool { self != .driver }
    var canDrive: Bool { self != .rider }
}

struct CashRydrRequest: Identifiable, Equatable {
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
    var visibility: String
    var status: String
    var driverQueueStatus: String?
    var connectedDriverUid: String?
    var connectedDriverName: String?
    var selectedOfferId: String?
    var agreedPrice: Double?
    var createdAt: Date?

    var isOpen: Bool { status == "open" }
    var isConnected: Bool { status == "connected" || status == "accepted" }
}

struct CashHubResponse: Identifiable, Equatable {
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
    var cashHubRating: Double?
    var isIdentityVerified: Bool
    var isLicenseVerified: Bool
    var isRydrVerifiedDriver: Bool
    var createdAt: Date?

    var isDriverOffer: Bool { authorRole == "driver" && (kind == "offer" || kind.isEmpty) }
}

private struct CashHubFavoriteDriver: Identifiable, Equatable {
    let id: String
    var driverUid: String
    var name: String
    var profilePhotoURL: String?
    var vehicleInfo: String
    var cashHubRating: Double?
    var isIdentityVerified: Bool
    var isLicenseVerified: Bool
    var isRydrVerifiedDriver: Bool
    var isOnline: Bool
    var addedAt: Date?
}

private enum CashHubVisibility: String, CaseIterable, Identifiable {
    case favoriteDrivers = "Favorite Drivers"
    case publicCommunity = "Public Cash Hub Community"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .favoriteDrivers:
            return "Only drivers you have favorited can see this request."
        case .publicCommunity:
            return "Any Cash Hub driver can see this request, including nearby drivers."
        }
    }

    static func normalized(_ storedValue: String?) -> CashHubVisibility {
        guard storedValue?.caseInsensitiveCompare(favoriteDrivers.rawValue) == .orderedSame else {
            return .publicCommunity
        }
        return .favoriteDrivers
    }
}

private enum CashHubScheduling {
    static let minimumLeadTime: TimeInterval = 2 * 60 * 60

    static func earliestRequestTime(from date: Date = Date()) -> Date {
        let minimum = date.addingTimeInterval(minimumLeadTime)
        let minuteStart = Calendar.current.dateInterval(of: .minute, for: minimum)?.start ?? minimum
        return minuteStart.addingTimeInterval(60)
    }

    static func isAllowed(_ date: Date) -> Bool {
        let threshold = Date().addingTimeInterval(minimumLeadTime)
        let minuteThreshold = Calendar.current.dateInterval(of: .minute, for: threshold)?.start ?? threshold
        return date >= minuteThreshold
    }
}

private func cashHubCurrencyInput(_ input: String) -> String {
    let filtered = input.filter { $0.isNumber || $0 == "." }
    let pieces = filtered.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard pieces.count == 2 else { return String(pieces[0]) }
    return String(pieces[0]) + "." + String(pieces[1].prefix(2))
}

private struct CashHubRequestDraft {
    var pickup = ""
    var destination = ""
    var scheduledTime = CashHubScheduling.earliestRequestTime()
    var passengers = 1
    var notes = ""
    var budgetRange = ""
    var rideType = "One-way"
    var visibility = CashHubVisibility.publicCommunity.rawValue

    init() {}

    init(request: CashRydrRequest) {
        pickup = request.pickup
        destination = request.destination
        scheduledTime = request.scheduledTime
        passengers = request.passengers
        notes = request.notes
        budgetRange = cashHubCurrencyInput(request.budgetRange)
        rideType = request.rideType
        visibility = CashHubVisibility.normalized(request.visibility).rawValue
    }
}

private struct CashHubOfferDraft {
    var offerAmount = ""
    var availability = ""
    var vehicleInfo = ""
    var message = ""
}

private enum CashHubRiderPanel: String, Identifiable {
    case requests
    case offers
    case messages
    case favorites

    var id: String { rawValue }
}

private enum CashHubMessageMode: String {
    case requestThread
    case directConnection

    var title: String {
        switch self {
        case .requestThread: return "Request Thread"
        case .directConnection: return "Direct Message"
        }
    }

    var responseKind: String {
        switch self {
        case .requestThread: return "message"
        case .directConnection: return "directMessage"
        }
    }
}

private struct CashHubMessageContext: Identifiable {
    let request: CashRydrRequest
    let mode: CashHubMessageMode

    var id: String { "\(request.id)-\(mode.rawValue)" }
}

@MainActor
private final class CashRydrHubVM: ObservableObject {
    @Published var requests: [CashRydrRequest] = []
    @Published var responsesByRequest: [String: [CashHubResponse]] = [:]
    @Published var favoriteDrivers: [CashHubFavoriteDriver] = []
    @Published var errorMessage: String?
    @Published var confirmationMessage: String?
    @Published var isSaving = false
    @Published var isCheckingTerms = true
    @Published var termsAccepted = false

    private let favoriteDriverLimit = 10
    private let db = Firestore.firestore()
    private var requestListener: ListenerRegistration?
    private var responseListeners: [String: ListenerRegistration] = [:]
    private var favoriteDriversListener: ListenerRegistration?
    private var favoriteProfileListeners: [String: ListenerRegistration] = [:]

    func loadAccess() {
        guard let uid = Auth.auth().currentUser?.uid else {
            isCheckingTerms = false
            errorMessage = "Please log in to use Cash Rydr Hub."
            return
        }

        db.collection("riders").document(uid).getDocument { [weak self] snap, error in
            Task { @MainActor in
                guard let self else { return }
                self.isCheckingTerms = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                let data = snap?.data() ?? [:]
                self.termsAccepted = data["cashHubTermsAccepted"] as? Bool ?? false
                if self.termsAccepted {
                    self.startMarketplace()
                    self.startFavoriteDrivers()
                }
            }
        }
    }

    func acceptTerms() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Please log in to continue."
            return
        }

        isSaving = true
        db.collection("riders").document(uid).setData([
            "cashHubTermsAccepted": true,
            "cashHubTermsAcceptedAt": FieldValue.serverTimestamp(),
            "cashHubRole": CashHubRole.rider.rawValue
        ], merge: true) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isSaving = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.termsAccepted = true
                self.startMarketplace()
                self.startFavoriteDrivers()
            }
        }
    }

    func startMarketplace() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Please log in to use Cash Rydr Hub."
            return
        }
        requestListener?.remove()
        requestListener = db.collection("cashRydrRequests")
            .whereField("riderUid", isEqualTo: uid)
            .addSnapshotListener { [weak self] snap, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    let mapped = (snap?.documents ?? []).compactMap(Self.makeRequest)
                        .sorted { $0.scheduledTime < $1.scheduledTime }
                    self.requests = mapped
                    self.syncResponseListeners(for: mapped)
                }
            }
    }

    func stop() {
        requestListener?.remove()
        requestListener = nil
        responseListeners.values.forEach { $0.remove() }
        responseListeners.removeAll()
        favoriteDriversListener?.remove()
        favoriteDriversListener = nil
        favoriteProfileListeners.values.forEach { $0.remove() }
        favoriteProfileListeners.removeAll()
    }

    func startFavoriteDrivers() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        favoriteDriversListener?.remove()
        favoriteDriversListener = db.collection("riders").document(uid)
            .collection("cashHubFavoriteDrivers")
            .addSnapshotListener { [weak self] snap, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    let favorites = (snap?.documents ?? [])
                        .map(Self.makeFavoriteDriver)
                        .sorted {
                            ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast)
                        }
                    self.favoriteDrivers = favorites
                    self.syncFavoriteProfileListeners(for: favorites)
                }
            }
    }

    func removeFavoriteDriver(_ driver: CashHubFavoriteDriver) {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Please log in to update favorite drivers."
            return
        }
        db.collection("riders").document(uid)
            .collection("cashHubFavoriteDrivers").document(driver.id)
            .delete { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = error?.localizedDescription
                    if error == nil {
                        self?.confirmationMessage = "\(driver.name) was removed from your favorite drivers."
                    }
                }
            }
    }

    func blockFavoriteDriver(_ driver: CashHubFavoriteDriver) {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Please log in to block a driver."
            return
        }
        let riderDocument = db.collection("riders").document(uid)
        riderDocument.collection("cashHubBlockedDrivers").document(driver.driverUid).setData([
            "driverUid": driver.driverUid,
            "driverName": driver.name,
            "blockedAt": FieldValue.serverTimestamp()
        ], merge: true) { [weak self] error in
            if let error {
                Task { @MainActor in self?.errorMessage = error.localizedDescription }
                return
            }
            riderDocument.collection("cashHubFavoriteDrivers").document(driver.id).delete { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.errorMessage = error?.localizedDescription
                    if error == nil {
                        self?.confirmationMessage = "\(driver.name) has been blocked."
                    }
                }
            }
        }
    }

    func addFavoriteDriver(from offer: CashHubResponse) {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Please log in to save favorite drivers."
            return
        }
        if favoriteDrivers.contains(where: { $0.driverUid == offer.authorUid }) {
            confirmationMessage = "\(offer.authorName) is already in your favorite drivers."
            return
        }
        guard favoriteDrivers.count < favoriteDriverLimit else {
            errorMessage = "You can save up to \(favoriteDriverLimit) favorite drivers. Remove one before adding another."
            return
        }
        let riderDocument = db.collection("riders").document(uid)
        riderDocument.collection("cashHubBlockedDrivers").document(offer.authorUid)
            .getDocument { [weak self] blockedSnapshot, error in
                if let error {
                    Task { @MainActor in self?.errorMessage = error.localizedDescription }
                    return
                }
                guard blockedSnapshot?.exists != true else {
                    Task { @MainActor in
                        self?.errorMessage = "This driver is blocked and cannot be added to favorites."
                    }
                    return
                }
                var data: [String: Any] = [
                    "driverUid": offer.authorUid,
                    "driverName": offer.authorName,
                    "vehicleInfo": offer.vehicleInfo,
                    "isIdentityVerified": offer.isIdentityVerified,
                    "isLicenseVerified": offer.isLicenseVerified,
                    "isRydrVerifiedDriver": offer.isRydrVerifiedDriver,
                    "addedAt": FieldValue.serverTimestamp()
                ]
                if let rating = offer.cashHubRating {
                    data["cashHubRating"] = rating
                }
                riderDocument.collection("cashHubFavoriteDrivers").document(offer.authorUid)
                    .setData(data, merge: true) { [weak self] error in
                        Task { @MainActor in
                            self?.errorMessage = error?.localizedDescription
                            if error == nil {
                                self?.confirmationMessage = "\(offer.authorName) was added to your favorite drivers."
                            }
                        }
                    }
            }
    }

    func createRequest(from draft: CashHubRequestDraft, riderName: String) -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Please log in to post a request."
            return false
        }
        guard validate(draft) else { return false }

        isSaving = true
        let data: [String: Any] = [
            "riderUid": uid,
            "riderName": displayName(riderName, fallback: "Cash Hub Rider"),
            "pickup": draft.pickup.trimmingCharacters(in: .whitespacesAndNewlines),
            "destination": draft.destination.trimmingCharacters(in: .whitespacesAndNewlines),
            "scheduledTime": Timestamp(date: draft.scheduledTime),
            "passengers": draft.passengers,
            "notes": draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            "budgetRange": draft.budgetRange.trimmingCharacters(in: .whitespacesAndNewlines),
            "rideType": draft.rideType,
            "visibility": draft.visibility,
            "status": "open",
            "createdAt": FieldValue.serverTimestamp()
        ]
        db.collection("cashRydrRequests").addDocument(data: data) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isSaving = false
                self.errorMessage = error?.localizedDescription
                if error == nil {
                    self.confirmationMessage = "Your request has been posted. Drivers may respond with availability, questions, or offers."
                }
            }
        }
        return true
    }

    func updateRequest(_ request: CashRydrRequest, from draft: CashHubRequestDraft) -> Bool {
        guard validate(draft) else { return false }

        isSaving = true
        let data: [String: Any] = [
            "pickup": draft.pickup.trimmingCharacters(in: .whitespacesAndNewlines),
            "destination": draft.destination.trimmingCharacters(in: .whitespacesAndNewlines),
            "scheduledTime": Timestamp(date: draft.scheduledTime),
            "passengers": draft.passengers,
            "notes": draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            "budgetRange": draft.budgetRange.trimmingCharacters(in: .whitespacesAndNewlines),
            "rideType": draft.rideType,
            "visibility": draft.visibility,
            "status": "open",
            "connectedDriverUid": FieldValue.delete(),
            "connectedDriverName": FieldValue.delete(),
            "selectedOfferId": FieldValue.delete(),
            "agreedPrice": FieldValue.delete()
        ]
        db.collection("cashRydrRequests").document(request.id).setData(data, merge: true) { [weak self] error in
            Task { @MainActor in
                self?.isSaving = false
                self?.errorMessage = error?.localizedDescription
            }
        }
        return true
    }

    func updateVisibility(for request: CashRydrRequest, to visibility: String) {
        guard Auth.auth().currentUser?.uid == request.riderUid else {
            errorMessage = "Only the rider who posted this request can change its visibility."
            return
        }
        let normalizedVisibility = CashHubVisibility.normalized(visibility).rawValue
        db.collection("cashRydrRequests").document(request.id)
            .setData(["visibility": normalizedVisibility], merge: true) { [weak self] error in
                Task { @MainActor in self?.errorMessage = error?.localizedDescription }
            }
    }

    func removeRequest(_ request: CashRydrRequest) {
        guard Auth.auth().currentUser?.uid == request.riderUid else {
            errorMessage = "Only the rider who posted this request can delete it."
            return
        }
        db.collection("cashRydrRequests").document(request.id).delete { [weak self] error in
            Task { @MainActor in
                self?.errorMessage = error?.localizedDescription
                if error == nil {
                    self?.confirmationMessage = "Your request has been deleted."
                }
            }
        }
    }

    func sendOffer(to request: CashRydrRequest, draft: CashHubOfferDraft, driverName: String) -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Please log in to make an offer."
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

        var data: [String: Any] = [
            "authorUid": uid,
            "authorName": displayName(driverName, fallback: "Cash Hub Driver"),
            "authorRole": "driver",
            "kind": "offer",
            "status": "pending",
            "message": draft.message.trimmingCharacters(in: .whitespacesAndNewlines),
            "availability": availability,
            "vehicleInfo": vehicleInfo,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let amount = cleanAmount(draft.offerAmount) {
            data["offerAmount"] = amount
        }
        addResponse(data, to: request)
        return true
    }

    func sendMessage(to request: CashRydrRequest, message: String, authorName: String, mode: CashHubMessageMode = .requestThread) -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Please log in to send a message."
            return false
        }
        if mode == .requestThread && request.isConnected {
            errorMessage = "This request thread is closed because a driver has accepted the request."
            return false
        }
        if mode == .directConnection && !request.isConnected {
            errorMessage = "Direct messages open after a driver accepts the request."
            return false
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a message first."
            return false
        }

        addResponse([
            "authorUid": uid,
            "authorName": displayName(authorName, fallback: "Cash Hub User"),
            "authorRole": CashHubRole.rider.rawValue,
            "kind": mode.responseKind,
            "message": trimmed,
            "createdAt": FieldValue.serverTimestamp()
        ], to: request)
        return true
    }

    func acceptOffer(_ offer: CashHubResponse, for request: CashRydrRequest) {
        guard Auth.auth().currentUser?.uid == request.riderUid else {
            errorMessage = "Only the rider who posted this request can accept an offer."
            return
        }
        guard request.isOpen else {
            errorMessage = "This request is already connected."
            return
        }

        var data: [String: Any] = [
            "status": "connected",
            "connectedDriverUid": offer.authorUid,
            "connectedDriverName": offer.authorName,
            "selectedOfferId": offer.id,
            "connectedAt": FieldValue.serverTimestamp()
        ]
        if let amount = offer.offerAmount {
            data["agreedPrice"] = amount
        }
        db.collection("cashRydrRequests").document(request.id).setData(data, merge: true) { [weak self] error in
            Task { @MainActor in
                self?.errorMessage = error?.localizedDescription
                if error == nil {
                    self?.confirmationMessage = "You and this driver are now connected for this Cash Hub request."
                }
            }
        }
    }

    func declineOffer(_ offer: CashHubResponse, for request: CashRydrRequest) {
        guard Auth.auth().currentUser?.uid == request.riderUid else {
            errorMessage = "Only the rider who posted this request can decline an offer."
            return
        }
        db.collection("cashRydrRequests").document(request.id)
            .collection("responses").document(offer.id)
            .setData(["status": "declined"], merge: true) { [weak self] error in
                Task { @MainActor in self?.errorMessage = error?.localizedDescription }
            }
    }

    func cancelConnection(for request: CashRydrRequest) {
        guard Auth.auth().currentUser?.uid == request.riderUid else { return }
        db.collection("cashRydrRequests").document(request.id).setData([
            "status": "open",
            "connectedDriverUid": FieldValue.delete(),
            "connectedDriverName": FieldValue.delete(),
            "selectedOfferId": FieldValue.delete(),
            "agreedPrice": FieldValue.delete(),
            "connectedAt": FieldValue.delete()
        ], merge: true) { [weak self] error in
            Task { @MainActor in self?.errorMessage = error?.localizedDescription }
        }
    }

    func offers(for request: CashRydrRequest) -> [CashHubResponse] {
        (responsesByRequest[request.id] ?? []).filter(\.isDriverOffer)
    }

    func selectedOffer(for request: CashRydrRequest) -> CashHubResponse? {
        guard let selectedOfferId = request.selectedOfferId else { return nil }
        return responsesByRequest[request.id]?.first { $0.id == selectedOfferId }
    }

    private func addResponse(_ data: [String: Any], to request: CashRydrRequest) {
        db.collection("cashRydrRequests")
            .document(request.id)
            .collection("responses")
            .addDocument(data: data) { [weak self] error in
                Task { @MainActor in self?.errorMessage = error?.localizedDescription }
            }
    }

    private func validate(_ draft: CashHubRequestDraft) -> Bool {
        guard !draft.pickup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Pickup location and destination are required."
            return false
        }
        guard CashHubScheduling.isAllowed(draft.scheduledTime) else {
            errorMessage = "Cash Hub requests must be scheduled at least 2 hours in advance."
            return false
        }
        let budgetAmount = draft.budgetRange.trimmingCharacters(in: .whitespacesAndNewlines)
        if !budgetAmount.isEmpty,
           (Double(budgetAmount) == nil || (Double(budgetAmount) ?? 0) <= 0) {
            errorMessage = "Enter a valid proposed payment amount or leave it blank."
            return false
        }
        return true
    }

    private func syncResponseListeners(for requests: [CashRydrRequest]) {
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
                .addSnapshotListener { [weak self] snap, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error {
                            self.errorMessage = error.localizedDescription
                            return
                        }
                        self.responsesByRequest[request.id] = (snap?.documents ?? []).compactMap(Self.makeResponse)
                    }
                }
        }
    }

    private func syncFavoriteProfileListeners(for favorites: [CashHubFavoriteDriver]) {
        let activeDriverUIDs = Set(favorites.map(\.driverUid))
        for (uid, listener) in favoriteProfileListeners where !activeDriverUIDs.contains(uid) {
            listener.remove()
            favoriteProfileListeners[uid] = nil
        }

        for driver in favorites where favoriteProfileListeners[driver.driverUid] == nil {
            favoriteProfileListeners[driver.driverUid] = db.collection("cashHubDriverProfiles")
                .document(driver.driverUid)
                .addSnapshotListener { [weak self] snap, _ in
                    Task { @MainActor in
                        guard let self,
                              let data = snap?.data(),
                              let index = self.favoriteDrivers.firstIndex(where: { $0.driverUid == driver.driverUid }) else {
                            return
                        }
                        self.favoriteDrivers[index] = Self.mergingDriverProfile(data, into: self.favoriteDrivers[index])
                    }
                }
        }
    }

    private static func makeRequest(_ doc: QueryDocumentSnapshot) -> CashRydrRequest? {
        let data = doc.data()
        guard let riderUid = data["riderUid"] as? String,
              let pickup = data["pickup"] as? String else { return nil }

        let destination = data["destination"] as? String ?? data["dropoff"] as? String ?? ""
        let scheduledTime = (data["scheduledTime"] as? Timestamp)?.dateValue()
            ?? (data["windowStart"] as? Timestamp)?.dateValue()
            ?? Date()
        var budgetRange = data["budgetRange"] as? String ?? ""
        if budgetRange.isEmpty, let legacyAmount = data["amount"] as? Double {
            budgetRange = String(format: "$%.2f", legacyAmount)
        }

        return CashRydrRequest(
            id: doc.documentID,
            riderUid: riderUid,
            riderName: data["riderName"] as? String ?? "Cash Hub Rider",
            pickup: pickup,
            destination: destination,
            scheduledTime: scheduledTime,
            passengers: data["passengers"] as? Int ?? 1,
            notes: data["notes"] as? String ?? data["note"] as? String ?? "",
            budgetRange: budgetRange,
            rideType: data["rideType"] as? String ?? "Scheduled",
            visibility: CashHubVisibility.normalized(data["visibility"] as? String).rawValue,
            status: data["status"] as? String ?? "open",
            driverQueueStatus: data["driverQueueStatus"] as? String,
            connectedDriverUid: data["connectedDriverUid"] as? String ?? data["acceptedByUid"] as? String,
            connectedDriverName: data["connectedDriverName"] as? String ?? data["acceptedByName"] as? String,
            selectedOfferId: data["selectedOfferId"] as? String,
            agreedPrice: data["agreedPrice"] as? Double,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }

    private static func makeResponse(_ doc: QueryDocumentSnapshot) -> CashHubResponse? {
        let data = doc.data()
        guard let authorUid = data["authorUid"] as? String,
              let authorName = data["authorName"] as? String,
              let authorRole = data["authorRole"] as? String else { return nil }
        return CashHubResponse(
            id: doc.documentID,
            authorUid: authorUid,
            authorName: authorName,
            authorRole: authorRole,
            kind: data["kind"] as? String ?? "",
            status: data["status"] as? String ?? "pending",
            message: data["message"] as? String ?? "",
            offerAmount: data["offerAmount"] as? Double ?? data["counterAmount"] as? Double,
            availability: data["availability"] as? String ?? "Availability provided by message",
            vehicleInfo: data["vehicleInfo"] as? String ?? "Vehicle details not provided",
            cashHubRating: data["cashHubRating"] as? Double,
            isIdentityVerified: data["isIdentityVerified"] as? Bool ?? false,
            isLicenseVerified: data["isLicenseVerified"] as? Bool ?? false,
            isRydrVerifiedDriver: data["isRydrVerifiedDriver"] as? Bool ?? false,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }

    private static func makeFavoriteDriver(_ doc: QueryDocumentSnapshot) -> CashHubFavoriteDriver {
        let data = doc.data()
        return CashHubFavoriteDriver(
            id: doc.documentID,
            driverUid: data["driverUid"] as? String ?? doc.documentID,
            name: data["driverName"] as? String ?? data["name"] as? String ?? "Cash Hub Driver",
            profilePhotoURL: data["profilePhotoURL"] as? String,
            vehicleInfo: data["vehicleInfo"] as? String ?? "Vehicle information not provided",
            cashHubRating: data["cashHubRating"] as? Double,
            isIdentityVerified: data["isIdentityVerified"] as? Bool ?? false,
            isLicenseVerified: data["isLicenseVerified"] as? Bool ?? false,
            isRydrVerifiedDriver: data["isRydrVerifiedDriver"] as? Bool ?? false,
            isOnline: data["isOnline"] as? Bool ?? false,
            addedAt: (data["addedAt"] as? Timestamp)?.dateValue()
        )
    }

    private static func mergingDriverProfile(_ data: [String: Any], into favorite: CashHubFavoriteDriver) -> CashHubFavoriteDriver {
        var merged = favorite
        merged.name = data["driverName"] as? String ?? data["name"] as? String ?? merged.name
        merged.profilePhotoURL = data["profilePhotoURL"] as? String ?? merged.profilePhotoURL
        merged.vehicleInfo = data["vehicleInfo"] as? String ?? merged.vehicleInfo
        merged.cashHubRating = data["cashHubRating"] as? Double ?? merged.cashHubRating
        merged.isIdentityVerified = data["isIdentityVerified"] as? Bool ?? merged.isIdentityVerified
        merged.isLicenseVerified = data["isLicenseVerified"] as? Bool ?? merged.isLicenseVerified
        merged.isRydrVerifiedDriver = data["isRydrVerifiedDriver"] as? Bool ?? merged.isRydrVerifiedDriver
        merged.isOnline = data["isOnline"] as? Bool ?? merged.isOnline
        return merged
    }

    private func cleanAmount(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let amount = Double(cleaned), amount > 0 else { return nil }
        return (amount * 100).rounded() / 100
    }

    private func displayName(_ name: String, fallback: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : name
    }
}

struct CashRydrHubView: View {
    @EnvironmentObject private var session: UserSessionManager
    @StateObject private var vm = CashRydrHubVM()
    @State private var acceptedTermsCheckbox = false
    @State private var showPostRequest = false
    @State private var editingRequest: CashRydrRequest?
    @State private var messagingContext: CashHubMessageContext?
    @State private var viewingConnection: CashRydrRequest?
    @State private var riderPanel: CashHubRiderPanel?
    @State private var viewingFavoriteDriver: CashHubFavoriteDriver?
    @State private var driverPendingBlock: CashHubFavoriteDriver?

    private var currentUID: String { Auth.auth().currentUser?.uid ?? "" }
    private var myRequests: [CashRydrRequest] { vm.requests.filter { $0.riderUid == currentUID } }
    var body: some View {
        Group {
            if vm.isCheckingTerms {
                ProgressView("Loading Cash Rydr Hub...")
            } else if !vm.termsAccepted {
                CashHubTermsView(
                    isConfirmed: $acceptedTermsCheckbox,
                    isSaving: vm.isSaving,
                    onContinue: { vm.acceptTerms() }
                )
            } else {
                marketplace
            }
        }
        .navigationTitle("Cash Rydr Hub")
        .navigationBarTitleDisplayMode(.inline)
        .task { vm.loadAccess() }
        .onDisappear { vm.stop() }
        .sheet(isPresented: $showPostRequest) {
            CashHubRequestForm(title: "Post Ride Request") { draft in
                if vm.createRequest(from: draft, riderName: session.userName) {
                    showPostRequest = false
                }
            }
        }
        .sheet(item: $editingRequest) { request in
            CashHubRequestForm(title: "Edit Ride Request", initialDraft: CashHubRequestDraft(request: request)) { draft in
                if vm.updateRequest(request, from: draft) {
                    editingRequest = nil
                }
            }
        }
        .sheet(item: $messagingContext) { context in
            let responses = vm.responsesByRequest[context.request.id] ?? []
            CashHubMessageForm(
                request: context.request,
                mode: context.mode,
                messages: responses.filter { $0.kind == context.mode.responseKind },
                mentionCandidates: mentionCandidates(for: context.request, responses: responses)
            ) { text in
                if vm.sendMessage(to: context.request, message: text, authorName: session.userName, mode: context.mode) {
                    messagingContext = nil
                }
            }
        }
        .sheet(item: $viewingConnection) { request in
            CashHubAcceptedRequestView(
                request: request,
                offer: vm.selectedOffer(for: request),
                onMessage: {
                    viewingConnection = nil
                    messagingContext = CashHubMessageContext(request: request, mode: .directConnection)
                },
                onCancel: {
                    vm.cancelConnection(for: request)
                    viewingConnection = nil
                }
            )
        }
        .sheet(item: $riderPanel) { panel in
            CashHubRiderPanelView(
                panel: panel,
                requests: myRequests,
                responses: vm.responsesByRequest,
                favoriteDrivers: vm.favoriteDrivers,
                onEdit: { editingRequest = $0 },
                onDelete: { vm.removeRequest($0) },
                onVisibilityChange: { request, visibility in vm.updateVisibility(for: request, to: visibility) },
                onOpenConnection: { viewingConnection = $0 },
                onMessage: { request, mode in messagingContext = CashHubMessageContext(request: request, mode: mode) },
                onFavorite: { vm.addFavoriteDriver(from: $0) },
                onViewFavoriteDriver: { viewingFavoriteDriver = $0 },
                onRemoveFavoriteDriver: { vm.removeFavoriteDriver($0) },
                onBlockFavoriteDriver: { driverPendingBlock = $0 },
                onAcceptOffer: { offer, request in vm.acceptOffer(offer, for: request) },
                onDeclineOffer: { offer, request in vm.declineOffer(offer, for: request) }
            )
        }
        .sheet(item: $viewingFavoriteDriver) { driver in
            CashHubFavoriteDriverProfileView(
                driver: vm.favoriteDrivers.first { $0.driverUid == driver.driverUid } ?? driver
            )
        }
        .confirmationDialog(
            "Block \(driverPendingBlock?.name ?? "this driver")?",
            isPresented: Binding(
                get: { driverPendingBlock != nil },
                set: { if !$0 { driverPendingBlock = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Block Driver", role: .destructive) {
                if let driverPendingBlock {
                    vm.blockFavoriteDriver(driverPendingBlock)
                }
                driverPendingBlock = nil
            }
            Button("Cancel", role: .cancel) { driverPendingBlock = nil }
        } message: {
            Text("This driver will be removed from your favorites and added to your blocked drivers.")
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

    private var marketplace: some View {
        VStack(spacing: 0) {
            CashHubHeader()

            ScrollView {
                VStack(spacing: 18) {
                    CashHubActionGrid(
                        onPost: { showPostRequest = true },
                        onRequests: { riderPanel = .requests },
                        onOffers: { riderPanel = .offers },
                        onMessages: { riderPanel = .messages },
                        onFavorites: { riderPanel = .favorites },
                        favoriteDriverCount: vm.favoriteDrivers.count
                    )

                    ForEach(myRequests.filter(\.isConnected)) { request in
                        CashHubConnectionBanner(request: request) {
                            viewingConnection = request
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func mentionCandidates(for request: CashRydrRequest, responses: [CashHubResponse]) -> [String] {
        var names = [request.riderName]
        if let driverName = request.connectedDriverName {
            names.append(driverName)
        }
        names.append(contentsOf: responses.map(\.authorName))
        return Array(Set(names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

private struct CashHubTermsView: View {
    @Binding var isConfirmed: Bool
    let isSaving: Bool
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Cash Rydr Hub Terms")
                    .font(.title.bold())

                Text("Cash Rydr Hub is a community marketplace that allows riders and independent drivers to connect directly. Cash Rydr Hub rides are not Rydr-dispatched rides.")
                VStack(alignment: .leading, spacing: 8) {
                    Label("Rydr does not dispatch Cash Hub rides.", systemImage: "checkmark.circle")
                    Label("Rydr does not set Cash Hub prices or process Cash Hub payments.", systemImage: "checkmark.circle")
                    Label("Rydr does not guarantee driver availability, ride completion, or user conduct.", systemImage: "checkmark.circle")
                }
                .font(.subheadline)
                Text("By continuing, you understand that any ride arranged through Cash Rydr Hub is coordinated directly between you and the other user. You are responsible for confirming pickup, destination, timing, payment, and safety expectations before starting the ride.")

                Toggle("I understand that Cash Rydr Hub is separate from standard Rydr rides.", isOn: $isConfirmed)
                    .toggleStyle(.switch)

                Button(isSaving ? "Saving..." : "I Understand and Continue", action: onContinue)
                    .buttonStyle(GradientButtonStyle())
                    .disabled(!isConfirmed || isSaving)
                    .opacity(isConfirmed ? 1 : 0.55)
            }
            .font(.body)
            .foregroundStyle(.primary)
            .padding(22)
        }
    }
}

private struct CashHubHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Post a ride request and manage driver replies.")
                .font(.headline)
            Text("Riders only see their own Cash Hub posts, driver offers, messages, and accepted cash ride connections.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
    }
}

private struct CashHubActionGrid: View {
    let onPost: () -> Void
    let onRequests: () -> Void
    let onOffers: () -> Void
    let onMessages: () -> Void
    let onFavorites: () -> Void
    let favoriteDriverCount: Int

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            CashHubActionCard(title: "Post Ride Request", icon: "plus.circle.fill", action: onPost)
            CashHubActionCard(title: "My Requests", icon: "list.bullet.clipboard", action: onRequests)
            CashHubActionCard(title: "Driver Offers", icon: "person.badge.plus", action: onOffers)
            CashHubActionCard(title: "Messages", icon: "bubble.left.and.bubble.right", action: onMessages)
            CashHubActionCard(
                title: "Favorite Drivers",
                icon: "star.fill",
                detail: "\(favoriteDriverCount)/10 saved",
                action: onFavorites
            )
        }
    }
}

private struct CashHubActionCard: View {
    let title: String
    let icon: String
    var detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Styles.rydrGradient)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(minHeight: 95)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct CashHubFavoriteDriversCard: View {
    let drivers: [CashHubFavoriteDriver]
    let onViewProfile: (CashHubFavoriteDriver) -> Void
    let onRemove: (CashHubFavoriteDriver) -> Void
    let onBlock: (CashHubFavoriteDriver) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Favorite Drivers", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if !drivers.isEmpty {
                    Text("\(drivers.count)/10 saved")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if drivers.isEmpty {
                Text("Drivers you favorite from offers will appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(drivers) { driver in
                    HStack(spacing: 10) {
                        CashHubDriverAvatar(driver: driver)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(driver.name)
                                .font(.subheadline.weight(.semibold))
                            CashHubOnlineStatusLabel(isOnline: driver.isOnline)
                        }

                        Spacer()

                        Button("Profile") {
                            onViewProfile(driver)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)

                        Menu {
                            Button("Remove Favorite", role: .destructive) {
                                onRemove(driver)
                            }
                            Button("Block Driver", role: .destructive) {
                                onBlock(driver)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if driver.id != drivers.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct CashHubFavoriteDriverProfileView: View {
    let driver: CashHubFavoriteDriver
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        CashHubDriverAvatar(driver: driver, size: 56)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(driver.name)
                                .font(.headline)
                            CashHubOnlineStatusLabel(isOnline: driver.isOnline)
                        }
                    }
                }
                Section("Profile") {
                    LabeledContent("Vehicle", value: driver.vehicleInfo)
                    if let rating = driver.cashHubRating {
                        LabeledContent("Cash Hub rating", value: String(format: "%.1f stars", rating))
                    }
                }
                Section("Verification") {
                    verificationRow("Identity verified", isVerified: driver.isIdentityVerified)
                    verificationRow("License verified", isVerified: driver.isLicenseVerified)
                    verificationRow("Rydr verified driver", isVerified: driver.isRydrVerifiedDriver)
                }
                Section {
                    Text("Favorite driver profiles are view-only. To discuss a ride, use an active Cash Hub request and its driver offers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Driver Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func verificationRow(_ label: String, isVerified: Bool) -> some View {
        Label(label, systemImage: isVerified ? "checkmark.seal.fill" : "minus.circle")
            .foregroundStyle(isVerified ? .green : .secondary)
    }
}

private struct CashHubDriverAvatar: View {
    let driver: CashHubFavoriteDriver
    var size: CGFloat = 38

    var body: some View {
        Group {
            if let value = driver.profilePhotoURL, let url = URL(string: value) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .foregroundStyle(.secondary)
    }
}

private struct CashHubOnlineStatusLabel: View {
    let isOnline: Bool

    var body: some View {
        HStack(spacing: 5) {
            statusIcon
            Text(isOnline ? "Online" : "Offline")
        }
        .font(.caption)
        .foregroundStyle(isOnline ? .green : .secondary)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isOnline {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
        } else {
            ZStack {
                Circle()
                    .stroke(Styles.rydrGradient, lineWidth: 1.6)
                Image(systemName: "xmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(Styles.rydrGradient)
            }
            .frame(width: 10, height: 10)
        }
    }
}

private struct CashHubConnectionBanner: View {
    let request: CashRydrRequest
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Connected with \(request.connectedDriverName ?? "driver")", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.semibold))
                Text("\(request.pickup) to \(request.destination)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("View connection details")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct CashHubRequestCard: View {
    let request: CashRydrRequest
    let offersCount: Int
    let onPrimary: () -> Void
    let onMessage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(request.riderName).font(.headline)
                    Text(request.scheduledTime.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !request.budgetRange.isEmpty {
                    Text(request.budgetRange)
                        .font(.subheadline.weight(.bold))
                }
            }

            Label(request.pickup, systemImage: "mappin.circle.fill")
            Label(request.destination, systemImage: "flag.checkered.circle.fill")
            Text("\(request.rideType) | \(request.passengers) passenger\(request.passengers == 1 ? "" : "s") | \(request.visibility)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !request.notes.isEmpty {
                Text(request.notes)
                    .font(.footnote)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text("\(offersCount) offer\(offersCount == 1 ? "" : "s") received")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Send Offer", action: onPrimary)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                Button("Message", action: onMessage)
                    .buttonStyle(.bordered)
            }
        }
        .font(.subheadline)
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct CashHubRiderPanelView: View {
    let panel: CashHubRiderPanel
    let requests: [CashRydrRequest]
    let responses: [String: [CashHubResponse]]
    let favoriteDrivers: [CashHubFavoriteDriver]
    let onEdit: (CashRydrRequest) -> Void
    let onDelete: (CashRydrRequest) -> Void
    let onVisibilityChange: (CashRydrRequest, String) -> Void
    let onOpenConnection: (CashRydrRequest) -> Void
    let onMessage: (CashRydrRequest, CashHubMessageMode) -> Void
    let onFavorite: (CashHubResponse) -> Void
    let onViewFavoriteDriver: (CashHubFavoriteDriver) -> Void
    let onRemoveFavoriteDriver: (CashHubFavoriteDriver) -> Void
    let onBlockFavoriteDriver: (CashHubFavoriteDriver) -> Void
    let onAcceptOffer: (CashHubResponse, CashRydrRequest) -> Void
    let onDeclineOffer: (CashHubResponse, CashRydrRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var requestPendingDeletion: CashRydrRequest?

    private var title: String {
        switch panel {
        case .requests: return "My Requests"
        case .offers: return "Driver Offers"
        case .messages: return "Messages"
        case .favorites: return "Favorite Drivers"
        }
    }

    private var connectedRequests: [CashRydrRequest] {
        requests.filter(\.isConnected)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    switch panel {
                    case .requests:
                        ForEach(requests) { request in
                            VStack(alignment: .leading, spacing: 10) {
                                Text("\(request.pickup) to \(request.destination)").font(.headline)
                                Text(request.scheduledTime.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Picker("Visibility", selection: Binding(
                                    get: { CashHubVisibility.normalized(request.visibility).rawValue },
                                    set: { onVisibilityChange(request, $0) }
                                )) {
                                    ForEach(CashHubVisibility.allCases) { option in
                                        Text(option.rawValue).tag(option.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                HStack {
                                    if request.isConnected {
                                        Button("View Connection") { onOpenConnection(request) }
                                            .buttonStyle(.borderedProminent).tint(.green)
                                        Text("Thread closed")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Button("Edit") { onEdit(request) }.buttonStyle(.bordered)
                                        Button("Message") { onMessage(request, .requestThread) }.buttonStyle(.bordered)
                                    }
                                    Button("Delete", role: .destructive) { requestPendingDeletion = request }
                                        .buttonStyle(.bordered)
                                }
                            }
                            .cashHubCard()
                        }
                    case .offers:
                        ForEach(requests) { request in
                            ForEach((responses[request.id] ?? []).filter(\.isDriverOffer)) { offer in
                                CashHubOfferCard(
                                    offer: offer,
                                    isConnected: request.isConnected,
                                    onMessage: { onMessage(request, request.isConnected ? .directConnection : .requestThread) },
                                    onFavorite: { onFavorite(offer) },
                                    onAccept: { onAcceptOffer(offer, request) },
                                    onDecline: { onDeclineOffer(offer, request) }
                                )
                            }
                        }
                    case .messages:
                        ForEach(connectedRequests) { request in
                            let messages = (responses[request.id] ?? []).filter { $0.kind == CashHubMessageMode.directConnection.responseKind && !$0.message.isEmpty }
                            if !messages.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(request.pickup) to \(request.destination)").font(.headline)
                                    ForEach(messages.suffix(3)) { response in
                                        Text("\(response.authorName): \(response.message)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Button("Message") { onMessage(request, .directConnection) }
                                        .buttonStyle(.bordered)
                                }
                                .cashHubCard()
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(request.pickup) to \(request.destination)").font(.headline)
                                    Text("No direct messages yet.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Button("Message") { onMessage(request, .directConnection) }
                                        .buttonStyle(.bordered)
                                }
                                .cashHubCard()
                            }
                        }
                    case .favorites:
                        CashHubFavoriteDriversCard(
                            drivers: favoriteDrivers,
                            onViewProfile: onViewFavoriteDriver,
                            onRemove: onRemoveFavoriteDriver,
                            onBlock: onBlockFavoriteDriver
                        )
                    }
                    if isPanelEmpty {
                        ContentUnavailableView(title, systemImage: "tray", description: Text("Nothing to show yet."))
                            .padding(.top, 50)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete this request?",
                isPresented: Binding(
                    get: { requestPendingDeletion != nil },
                    set: { if !$0 { requestPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Request", role: .destructive) {
                    if let requestPendingDeletion {
                        onDelete(requestPendingDeletion)
                    }
                    requestPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { requestPendingDeletion = nil }
            } message: {
                if requestPendingDeletion?.isConnected == true {
                    Text("This permanently deletes your request and removes the connected request from your Cash Hub view.")
                } else {
                    Text("This permanently deletes your request from Cash Rydr Hub.")
                }
            }
        }
    }

    private var isPanelEmpty: Bool {
        switch panel {
        case .requests, .offers:
            return requests.isEmpty
        case .messages:
            return connectedRequests.isEmpty
        case .favorites:
            return false
        }
    }
}

private struct CashHubOfferCard: View {
    let offer: CashHubResponse
    let isConnected: Bool
    let onMessage: () -> Void
    let onFavorite: () -> Void
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.crop.circle.fill").font(.title)
                VStack(alignment: .leading) {
                    Text(offer.authorName).font(.headline)
                    Text(offer.vehicleInfo).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let amount = offer.offerAmount {
                    Text(amount, format: .currency(code: "USD")).font(.headline)
                }
            }
            HStack(spacing: 6) {
                if offer.isIdentityVerified { badge("ID Verified") }
                if offer.isLicenseVerified { badge("License Verified") }
                if offer.isRydrVerifiedDriver { badge("Rydr Verified") }
                if let rating = offer.cashHubRating {
                    badge(String(format: "%.1f star", rating))
                }
            }
            Text("Available: \(offer.availability)").font(.subheadline)
            if !offer.message.isEmpty {
                Text(offer.message).font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Button("Message", action: onMessage).buttonStyle(.bordered)
                Button("Favorite", action: onFavorite).buttonStyle(.bordered)
                Button(offer.status == "declined" ? "Declined" : "Accept Offer", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isConnected || offer.status == "declined")
                Button("Decline", action: onDecline)
                    .buttonStyle(.bordered)
                    .disabled(isConnected || offer.status == "declined")
            }
        }
        .cashHubCard()
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.09))
            .clipShape(Capsule())
    }
}

private struct CashHubAcceptedRequestView: View {
    let request: CashRydrRequest
    let offer: CashHubResponse?
    let onMessage: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Driver") {
                    LabeledContent("Name", value: request.connectedDriverName ?? "Connected driver")
                    if let vehicleInfo = offer?.vehicleInfo {
                        LabeledContent("Vehicle", value: vehicleInfo)
                    }
                }
                Section("Request") {
                    LabeledContent("Pickup", value: request.pickup)
                    LabeledContent("Destination", value: request.destination)
                    LabeledContent("Scheduled time", value: request.scheduledTime.formatted(date: .abbreviated, time: .shortened))
                    if let driverQueueStatus = request.driverQueueStatus, !driverQueueStatus.isEmpty {
                        LabeledContent("Driver status", value: driverQueueStatus.capitalized)
                    }
                    if let amount = request.agreedPrice {
                        LabeledContent("Agreed price", value: amount.formatted(.currency(code: "USD")))
                    }
                }
                Section {
                    Text("This is a Cash Rydr Hub connection, not a Rydr-dispatched ride. Please confirm all details directly with the driver.")
                        .font(.footnote)
                }
                Section {
                    Button("Message Driver", action: onMessage)
                    Button("Cancel Connection", role: .destructive, action: onCancel)
                }
            }
            .navigationTitle("Connected Request")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct CashHubRequestForm: View {
    let title: String
    var initialDraft = CashHubRequestDraft()
    var onSave: (CashHubRequestDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CashHubRequestDraft
    @State private var minimumScheduledTime: Date
    @StateObject private var pickupCompleter = SearchCompleter()
    @StateObject private var destinationCompleter = SearchCompleter()
    @FocusState private var focusedAddressField: AddressField?

    private enum AddressField {
        case pickup
        case destination
    }

    init(title: String, initialDraft: CashHubRequestDraft = CashHubRequestDraft(), onSave: @escaping (CashHubRequestDraft) -> Void) {
        self.title = title
        self.initialDraft = initialDraft
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
        _minimumScheduledTime = State(initialValue: CashHubScheduling.earliestRequestTime())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") {
                    addressField(
                        title: "Pickup location",
                        text: $draft.pickup,
                        field: .pickup,
                        completer: pickupCompleter
                    )
                    addressSuggestions(for: pickupCompleter, field: .pickup)

                    addressField(
                        title: "Destination",
                        text: $draft.destination,
                        field: .destination,
                        completer: destinationCompleter
                    )
                    addressSuggestions(for: destinationCompleter, field: .destination)

                    DatePicker(
                        "Date and time",
                        selection: $draft.scheduledTime,
                        in: minimumScheduledTime...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    Text("Requests must be scheduled at least 2 hours in advance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper("Passengers: \(draft.passengers)", value: $draft.passengers, in: 1...12)
                }
                Section("Details") {
                    Picker("Ride type", selection: $draft.rideType) {
                        ForEach(["One-way", "Round trip", "Scheduled", "Flexible"], id: \.self) { Text($0) }
                    }
                    Picker("Visibility", selection: $draft.visibility) {
                        ForEach(CashHubVisibility.allCases) { option in
                            Text(option.rawValue).tag(option.rawValue)
                        }
                    }
                    if let visibility = CashHubVisibility(rawValue: draft.visibility) {
                        Text(visibility.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("$")
                        TextField("Proposed payment amount (optional)", text: Binding(
                            get: { draft.budgetRange },
                            set: { draft.budgetRange = cashHubCurrencyInput($0) }
                        ))
                        .keyboardType(.decimalPad)
                    }
                    TextField("Luggage or special notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle(title)
            .onAppear {
                minimumScheduledTime = CashHubScheduling.earliestRequestTime()
                if draft.scheduledTime < minimumScheduledTime {
                    draft.scheduledTime = minimumScheduledTime
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post Request") { onSave(draft) }
                }
            }
        }
    }

    @ViewBuilder
    private func addressField(
        title: String,
        text: Binding<String>,
        field: AddressField,
        completer: SearchCompleter
    ) -> some View {
        TextField(title, text: text)
            .textContentType(.fullStreetAddress)
            .textInputAutocapitalization(.words)
            .focused($focusedAddressField, equals: field)
            .onChange(of: text.wrappedValue) { _, value in
                completer.setQuery(value)
            }
    }

    @ViewBuilder
    private func addressSuggestions(for completer: SearchCompleter, field: AddressField) -> some View {
        if focusedAddressField == field && !addressText(for: field).isEmpty {
            ForEach(Array(completer.results.prefix(5)).indices, id: \.self) { index in
                let result = completer.results[index]
                Button {
                    selectAddress(result, for: field)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .foregroundStyle(.primary)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func addressText(for field: AddressField) -> String {
        switch field {
        case .pickup: return draft.pickup
        case .destination: return draft.destination
        }
    }

    private func selectAddress(_ completion: MKLocalSearchCompletion, for field: AddressField) {
        let fullAddress = completion.title + (completion.subtitle.isEmpty ? "" : ", \(completion.subtitle)")
        switch field {
        case .pickup:
            draft.pickup = fullAddress
            pickupCompleter.setQuery("")
        case .destination:
            draft.destination = fullAddress
            destinationCompleter.setQuery("")
        }
        focusedAddressField = nil
    }

}

private struct CashHubOfferForm: View {
    let request: CashRydrRequest
    var onSend: (CashHubOfferDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CashHubOfferDraft()

    var body: some View {
        NavigationStack {
            Form {
                Section("Request") {
                    LabeledContent("Pickup", value: request.pickup)
                    LabeledContent("Destination", value: request.destination)
                }
                Section("Your Offer") {
                    TextField("Offer amount (optional)", text: $draft.offerAmount).keyboardType(.decimalPad)
                    TextField("Estimated availability", text: $draft.availability)
                    TextField("Vehicle information", text: $draft.vehicleInfo)
                    TextField("Message", text: $draft.message, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
                Section {
                    Text("You are responding independently through Cash Rydr Hub. Confirm price, timing, and payment directly with the rider.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Send Offer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send Offer") { onSend(draft) }
                }
            }
        }
    }
}

private struct CashHubMessageForm: View {
    let request: CashRydrRequest
    let mode: CashHubMessageMode
    let messages: [CashHubResponse]
    let mentionCandidates: [String]
    var onSend: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""

    private var canSend: Bool {
        switch mode {
        case .requestThread: return !request.isConnected
        case .directConnection: return request.isConnected
        }
    }

    private var mentionSuggestions: [String] {
        guard let query = activeMentionQuery else { return [] }
        return mentionCandidates
            .filter { $0.localizedCaseInsensitiveContains(query) || query.isEmpty }
            .prefix(4)
            .map { $0 }
    }

    private var activeMentionQuery: String? {
        guard let atIndex = message.lastIndex(of: "@") else { return nil }
        let afterAt = message[message.index(after: atIndex)...]
        if afterAt.contains(where: { $0.isWhitespace || $0.isNewline }) { return nil }
        return String(afterAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Regarding") {
                    Text("\(request.pickup) to \(request.destination)")
                }
                Section(mode.title) {
                    if messages.isEmpty {
                        Text(mode == .requestThread ? "No thread messages yet." : "No direct messages yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(messages) { response in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(response.authorName)
                                    .font(.caption.weight(.semibold))
                                Text(response.message)
                                    .font(.subheadline)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                Section("Message") {
                    if canSend {
                        TextField("Use @ to mention someone by profile name", text: $message, axis: .vertical)
                            .lineLimit(5, reservesSpace: true)
                        if !mentionSuggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(mentionSuggestions, id: \.self) { name in
                                        Button("@\(name)") {
                                            insertMention(name)
                                        }
                                        .font(.caption.weight(.semibold))
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                    } else {
                        Text(mode == .requestThread
                             ? "This request thread is closed because a driver has accepted the request."
                             : "Direct messages open after a driver accepts the request.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { onSend(message) }
                        .disabled(!canSend || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func insertMention(_ name: String) {
        guard let atIndex = message.lastIndex(of: "@") else {
            message += "@\(name) "
            return
        }
        message.replaceSubrange(atIndex..<message.endIndex, with: "@\(name) ")
    }
}

private extension View {
    func cashHubCard() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
