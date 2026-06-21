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
import UIKit

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

private enum CashHubHomeTab: String, CaseIterable, Identifiable {
    case feed = "Feed"
    case myPosts = "My Posts"
    case activity = "Activity"

    var id: String { rawValue }
}

private enum CashHubActivityRange: String, CaseIterable, Identifiable {
    case days30 = "30D"
    case days90 = "90D"
    case year1 = "1Y"

    var id: String { rawValue }

    var dayCount: Int {
        switch self {
        case .days30: return 30
        case .days90: return 90
        case .year1: return 365
        }
    }
}

private struct CashHubHomeTabSelector: View {
    @Binding var selection: CashHubHomeTab
    @Namespace private var indicatorNamespace

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CashHubHomeTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        selection = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(selection == tab ? Color.white : Color.secondary)
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Styles.rydrGradient)
                                    .matchedGeometryEffect(id: "selectedHomeTab", in: indicatorNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
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

private enum CashHubFeedCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case posts = "Posts"
    case offers = "Offers"
    case messages = "Messages"
    case favorites = "Favorites"
    case trips = "Trips"

    var id: String { rawValue }
}

private enum CashHubFeedAccessory {
    case avatarInitial(String)
    case badge(String, Color)
    case none
}

private struct CashHubFeedEvent: Identifiable {
    let id: String
    let title: String
    let detail: String
    let cta: String?
    let systemImage: String
    let date: Date
    let tint: Color
    let category: CashHubFeedCategory
    var accessory: CashHubFeedAccessory = .none
    var timestampOverride: String? = nil
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
    @Published var onlineDriverCount = 0

    private let favoriteDriverLimit = 10
    private let db = Firestore.firestore()
    private var requestListener: ListenerRegistration?
    private var responseListeners: [String: ListenerRegistration] = [:]
    private var favoriteDriversListener: ListenerRegistration?
    private var favoriteProfileListeners: [String: ListenerRegistration] = [:]

    nonisolated private func logFavoriteDriversPath(uid uidBeingUsedForFirestorePath: String, operation: String) {
        if let user = Auth.auth().currentUser {
            print("🔥 AUTH UID: \(user.uid)")
        } else {
            print("🔥 AUTH UID: nil")
        }

        print("🔥 QUERY UID: \(uidBeingUsedForFirestorePath)")
        print("🔥 FULL PATH: riders/\(uidBeingUsedForFirestorePath)/cashHubFavoriteDrivers")
        print("🔥 OPERATION: \(operation)")
    }

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
        refreshOnlineDriverCount()
    }

    func refreshOnlineDriverCount() {
        db.collection("cashHubDriverProfiles")
            .whereField("isOnline", isEqualTo: true)
            .count
            .getAggregation(source: .server) { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, let snapshot, error == nil else { return }
                    self.onlineDriverCount = Int(truncating: snapshot.count)
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
        logFavoriteDriversPath(uid: uid, operation: "listen")
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
        logFavoriteDriversPath(uid: uid, operation: "delete favorite driver \(driver.id)")
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
            self?.logFavoriteDriversPath(uid: uid, operation: "delete blocked favorite driver \(driver.id)")
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
                self?.logFavoriteDriversPath(uid: uid, operation: "set favorite driver \(offer.authorUid)")
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
    @State private var requestPendingDeletion: CashRydrRequest?
    @State private var selectedHomeTab: CashHubHomeTab = .feed
    @AppStorage("cashHubSafetyFooterDismissed") private var safetyFooterDismissed = false
    private var showSafetyFooter: Bool {
        get { !safetyFooterDismissed }
        nonmutating set { safetyFooterDismissed = !newValue }
    }
    @State private var selectedFeedCategory: CashHubFeedCategory = .all
    @State private var activityRange: CashHubActivityRange = .days30

    private var currentUID: String { Auth.auth().currentUser?.uid ?? "" }
    private var myRequests: [CashRydrRequest] { vm.requests.filter { $0.riderUid == currentUID } }
    private var completedCashRideCount: Int {
        myRequests.filter { $0.status == "completed" }.count
    }

    private var cashHubFeedEvents: [CashHubFeedEvent] {
        var events: [CashHubFeedEvent] = []

        for driver in vm.favoriteDrivers where driver.isOnline {
            events.append(.init(
                id: "online-\(driver.driverUid)",
                title: "\(driver.name) is online",
                detail: "Your favorite driver is online",
                cta: "Tap to start a chat or send a request",
                systemImage: "bolt.fill",
                date: driver.addedAt ?? Date(),
                tint: .green,
                category: .favorites,
                accessory: .avatarInitial(driver.name),
                timestampOverride: "Online now"
            ))
        }

        for driver in vm.favoriteDrivers {
            events.append(.init(
                id: "favorite-\(driver.driverUid)",
                title: "You added \(driver.name) as a favorite",
                detail: "You can now easily find and request rides from \(driver.name).",
                cta: nil,
                systemImage: "heart.fill",
                date: driver.addedAt ?? .distantPast,
                tint: .pink,
                category: .favorites,
                accessory: .avatarInitial(driver.name)
            ))
        }

        for request in myRequests {
            let offers = vm.offers(for: request)
            for offer in offers where !request.isConnected {
                events.append(.init(
                    id: "offer-\(offer.id)",
                    title: "You have a new offer!",
                    detail: "\(offer.authorName) offered \(offer.offerAmount.map { $0.formatted(.currency(code: "USD")) } ?? "a price") for your ride",
                    cta: "Tap to view offer details",
                    systemImage: "bell.fill",
                    date: offer.createdAt ?? request.createdAt ?? request.scheduledTime,
                    tint: .purple,
                    category: .offers,
                    accessory: .badge(offer.offerAmount.map { $0.formatted(.currency(code: "USD")) } ?? "Offer", .purple)
                ))
            }

            let messages = (vm.responsesByRequest[request.id] ?? [])
                .filter { $0.authorUid != currentUID && !$0.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            for message in messages {
                events.append(.init(
                    id: "message-\(message.id)",
                    title: "\(message.authorName) sent you a message",
                    detail: "\u{201C}\(message.message)\u{201D}",
                    cta: nil,
                    systemImage: "bubble.left.and.bubble.right.fill",
                    date: message.createdAt ?? request.createdAt ?? request.scheduledTime,
                    tint: .orange,
                    category: .messages,
                    accessory: .avatarInitial(message.authorName)
                ))
            }

            if request.status == "completed" {
                events.append(.init(
                    id: "completed-\(request.id)",
                    title: "You completed a Cash Hub ride!",
                    detail: "Great job! You completed your ride with \(request.connectedDriverName ?? "your driver").",
                    cta: nil,
                    systemImage: "checkmark.seal.fill",
                    date: request.createdAt ?? request.scheduledTime,
                    tint: .green,
                    category: .trips,
                    accessory: .badge("Completed", .green)
                ))
            } else if request.isConnected {
                events.append(.init(
                    id: "connected-\(request.id)",
                    title: "You connected with \(request.connectedDriverName ?? "a driver")",
                    detail: cashHubTripSummary(for: request),
                    cta: nil,
                    systemImage: "person.crop.circle.badge.checkmark",
                    date: request.createdAt ?? request.scheduledTime,
                    tint: .green,
                    category: .trips,
                    accessory: .badge("Connected", .green)
                ))
            } else {
                events.append(.init(
                    id: "post-\(request.id)",
                    title: "You made a new ride request",
                    detail: cashHubTripSummary(for: request),
                    cta: nil,
                    systemImage: "paperplane.fill",
                    date: request.createdAt ?? request.scheduledTime,
                    tint: .red,
                    category: .posts
                ))
            }
        }

        if completedCashRideCount >= 10 {
            events.append(.init(
                id: "milestone-10",
                title: "You completed your 10th Cash Hub ride",
                detail: "Cash Hub milestone reached",
                cta: nil,
                systemImage: "10.circle.fill",
                date: Date(),
                tint: .red,
                category: .trips
            ))
        } else if completedCashRideCount >= 1 {
            events.append(.init(
                id: "milestone-1",
                title: "You completed your first Cash Hub ride",
                detail: "Cash Hub milestone reached",
                cta: nil,
                systemImage: "1.circle.fill",
                date: Date(),
                tint: .red,
                category: .trips
            ))
        }

        return events.sorted { $0.date > $1.date }
    }

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
                    vm.removeRequest(requestPendingDeletion)
                }
                requestPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { requestPendingDeletion = nil }
        } message: {
            if requestPendingDeletion?.isConnected == true {
                Text("This cancels the connected Cash Hub request and removes it from My Posts.")
            } else {
                Text("This cancels and removes your Cash Hub request from My Posts.")
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

    private var marketplace: some View {
        VStack(spacing: 0) {
            CashHubHeader()

            CashHubHomeTabSelector(selection: $selectedHomeTab)
                .padding(.horizontal)
                .padding(.top, 12)

            ScrollView {
                VStack(spacing: 18) {
                    switch selectedHomeTab {
                    case .feed:
                        CashHubDriversOnlineBanner(
                            onlineCount: vm.onlineDriverCount,
                            previewDrivers: vm.favoriteDrivers.filter(\.isOnline),
                            onTap: { riderPanel = .favorites }
                        )
                        CashHubQuickPostCard(onPost: { showPostRequest = true })
                        CashHubFeedTimelineCard(
                            events: cashHubFeedEvents,
                            selectedCategory: $selectedFeedCategory
                        )
                    case .myPosts:
                        CashHubMyPostsHeader(
                            postCount: myRequests.count,
                            openCount: myRequests.filter(\.isOpen).count,
                            onPost: { showPostRequest = true }
                        )
                        if myRequests.isEmpty {
                            CashHubSocialEmptyState(
                                title: "No Cash Hub posts yet",
                                message: "Create a post when you want drivers to respond with availability, questions, or offers."
                            )
                        } else {
                            ForEach(myRequests.sorted(by: recentActivitySort)) { request in
                                CashHubPostManagementCard(
                                    request: request,
                                    offers: vm.offers(for: request),
                                    responses: vm.responsesByRequest[request.id] ?? [],
                                    onEdit: { editingRequest = request },
                                    onOffers: { riderPanel = .offers },
                                    onMessage: { messagingContext = CashHubMessageContext(request: request, mode: request.isConnected ? .directConnection : .requestThread) },
                                    onConnection: { viewingConnection = request },
                                    onDelete: { requestPendingDeletion = request }
                                )
                            }
                        }
                    case .activity:
                        let completedRequests = myRequests.filter { $0.status == "completed" }
                        let rangeStart = Calendar.current.date(byAdding: .day, value: -activityRange.dayCount, to: Date()) ?? .distantPast
                        let activityRequests = completedRequests
                            .filter { $0.scheduledTime >= rangeStart }
                            .sorted(by: recentActivitySort)
                        let arrangedTotal = activityRequests
                            .compactMap(\.agreedPrice)
                            .reduce(0, +)
                        let driversMet = Set(activityRequests.compactMap(\.connectedDriverName)).count

                        CashHubActivityHeader(
                            rideCount: activityRequests.count,
                            arrangedTotal: arrangedTotal,
                            driversMet: driversMet,
                            selectedRange: $activityRange
                        )

                        if activityRequests.isEmpty {
                            CashHubSocialEmptyState(
                                title: "No completed Cash Hub rides yet",
                                message: "Ride activity appears here once a driver marks a Cash Hub ride as completed."
                            )
                        } else {
                            HStack {
                                Text("Recent Rides")
                                    .font(.headline.weight(.black))
                                Spacer()
                            }

                            ForEach(activityRequests) { request in
                                CashHubRideHistoryCard(
                                    request: request,
                                    offer: vm.selectedOffer(for: request)
                                )
                            }

                            Text("Cash Hub rides are settled directly between you and the driver — no in-app receipt is issued.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if showSafetyFooter {
                        CashHubSafetyFooter(onDismiss: { showSafetyFooter = false })
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func cashHubTripSummary(for request: CashRydrRequest) -> String {
        let price = request.agreedPrice.map { " • \($0.formatted(.currency(code: "USD")))" } ?? ""
        return "\(request.pickup) to \(request.destination)\(price)"
    }

    private func recentActivitySort(_ lhs: CashRydrRequest, _ rhs: CashRydrRequest) -> Bool {
        let lhsDate = vm.responsesByRequest[lhs.id]?.compactMap(\.createdAt).max() ?? lhs.createdAt ?? lhs.scheduledTime
        let rhsDate = vm.responsesByRequest[rhs.id]?.compactMap(\.createdAt).max() ?? rhs.createdAt ?? rhs.scheduledTime
        return lhsDate > rhsDate
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
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("RydrCash Hub")
                    .font(.title2.weight(.black))
                Text("Cash rides. Real people. Your terms.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "person.2.wave.2.fill")
                .font(.headline.weight(.black))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.red.opacity(0.08)))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
    }
}

private struct CashHubQuickPostCard: View {
    let onPost: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.black))
                    .foregroundStyle(Styles.rydrGradient)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.red.opacity(0.10)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Need a cash ride?")
                        .font(.headline.weight(.black))
                    Text("Post the trip, budget, and timing. Drivers can make offers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: onPost) {
                Label("Post a Ride", systemImage: "paperplane.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Styles.rydrGradient))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .cashHubPremiumCard()
    }
}

private struct CashHubDriversOnlineBanner: View {
    let onlineCount: Int
    let previewDrivers: [CashHubFavoriteDriver]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                HStack(spacing: -10) {
                    if previewDrivers.isEmpty {
                        ForEach(0..<min(3, max(onlineCount, 1)), id: \.self) { _ in
                            Circle()
                                .fill(Styles.rydrGradient)
                                .frame(width: 38, height: 38)
                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        }
                    } else {
                        ForEach(previewDrivers.prefix(3)) { driver in
                            CashHubDriverAvatar(driver: driver, size: 38)
                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("\(onlineCount) drivers online now")
                            .font(.subheadline.weight(.bold))
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                    }
                    Text("Find a cash ride today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .cashHubPremiumCard()
    }
}

private func cashHubRelativeTime(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}

private struct CashHubFeedTimelineCard: View {
    let events: [CashHubFeedEvent]
    @Binding var selectedCategory: CashHubFeedCategory

    private var filteredEvents: [CashHubFeedEvent] {
        guard selectedCategory != .all else { return events }
        return events.filter { $0.category == selectedCategory }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Feed")
                    .font(.headline.weight(.black))
                Spacer()
                Menu {
                    ForEach(CashHubFeedCategory.allCases) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            if category == selectedCategory {
                                Label(category.rawValue, systemImage: "checkmark")
                            } else {
                                Text(category.rawValue)
                            }
                        }
                    }
                } label: {
                    Label(selectedCategory == .all ? "Filters" : selectedCategory.rawValue, systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
                }
            }

            if filteredEvents.isEmpty {
                Text(events.isEmpty
                     ? "Your Cash Hub updates will appear here as you post rides, favorite drivers, complete trips, and update your profile."
                     : "Nothing in this category yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(filteredEvents.prefix(12))) { event in
                    CashHubFeedRow(event: event)
                    if event.id != filteredEvents.prefix(12).last?.id {
                        Divider()
                    }
                }
            }
        }
        .cashHubPremiumCard()
    }
}

private struct CashHubFeedRow: View {
    let event: CashHubFeedEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.systemImage)
                .font(.subheadline.weight(.black))
                .foregroundStyle(event.tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(event.tint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.weight(.bold))
                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let cta = event.cta {
                    Text(cta)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                trailingAccessory
                HStack(spacing: 4) {
                    Text(event.timestampOverride ?? cashHubRelativeTime(event.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        switch event.accessory {
        case .avatarInitial(let name):
            Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "R"))
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Styles.rydrGradient))
        case .badge(let text, let color):
            Text(text)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(color.opacity(0.14)))
                .foregroundStyle(color)
        case .none:
            EmptyView()
        }
    }
}

private struct CashHubMyPostsHeader: View {
    let postCount: Int
    let openCount: Int
    let onPost: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text("My Posts")
                    .font(.title2.weight(.black))
                Text("\(openCount) Open • \(postCount) Total")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
            }
            Spacer()
            Button(action: onPost) {
                Label("New Post", systemImage: "plus")
                    .font(.subheadline.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }
}

private struct CashHubPostDetailColumn: View {
    let icon: String
    let title: String
    let value: String
    var secondaryValue: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.subheadline.weight(.bold))
            if let secondaryValue {
                Text(secondaryValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CashHubPostActionButton: View {
    let icon: String
    var label: String? = nil
    var tint: Color = .primary
    var background: Color = Color(.secondarySystemGroupedBackground)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                if let label {
                    Text(label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .frame(maxWidth: label == nil ? nil : .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, label == nil ? 14 : 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(background))
        }
        .buttonStyle(.plain)
    }
}

private struct CashHubPostManagementCard: View {
    let request: CashRydrRequest
    let offers: [CashHubResponse]
    let responses: [CashHubResponse]
    let onEdit: () -> Void
    let onOffers: () -> Void
    let onMessage: () -> Void
    let onConnection: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                CashHubStatusBadge(status: request.status)
                Spacer()
                if let postedText {
                    Text(postedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Menu {
                    Button(action: onEdit) {
                        Label("Edit Post", systemImage: "pencil")
                    }
                    .disabled(request.isConnected)
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Post", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 10)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(request.pickup)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(request.destination)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(alignment: .top) {
                CashHubPostDetailColumn(icon: "calendar", title: "Date & Time", value: dateText, secondaryValue: timeText)
                Spacer()
                CashHubPostDetailColumn(icon: "person.fill", title: "Seats", value: seatsText)
                Spacer()
                CashHubPostDetailColumn(icon: "dollarsign.circle.fill", title: "Budget", value: budgetText, secondaryValue: request.budgetRange.isEmpty ? nil : "(Flexible)")
            }

            if let agreedPrice = request.agreedPrice {
                HStack {
                    Label("Agreed price: \(agreedPrice.formatted(.currency(code: "USD")))", systemImage: "banknote.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.green)
                    Spacer()
                    Button("View Details") {
                        request.isConnected ? onConnection() : onOffers()
                    }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.green.opacity(0.12)))
            }

            HStack(spacing: 14) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.red)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Offers")
                            .font(.subheadline.weight(.bold))
                        Text("\(offers.count)")
                            .font(.caption2.weight(.black))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                            .foregroundStyle(.white)
                    }
                    Text(offersSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(request.isConnected ? "Connection" : "View Offers") {
                    request.isConnected ? onConnection() : onOffers()
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.red.opacity(0.06)))

            HStack(spacing: 10) {
                CashHubPostActionButton(icon: "pencil", label: "Edit Post", action: onEdit)
                CashHubPostActionButton(icon: "bubble.left.and.bubble.right", label: "Messages", action: onMessage)
                CashHubPostActionButton(icon: "tag.fill", label: "Offers (\(offers.count))", tint: .red, action: onOffers)
                CashHubPostActionButton(icon: "trash.fill", tint: .red, background: Color.red.opacity(0.1), action: onDelete)
            }
        }
        .cashHubPremiumCard()
    }

    private var postedText: String? {
        guard let createdAt = request.createdAt else { return nil }
        return "Posted \(createdAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private var dateText: String { request.scheduledTime.formatted(date: .abbreviated, time: .omitted) }
    private var timeText: String { request.scheduledTime.formatted(date: .omitted, time: .shortened) }
    private var seatsText: String { "\(request.passengers) rider\(request.passengers == 1 ? "" : "s")" }

    private var offersSubtitle: String {
        offers.isEmpty
            ? "No offers yet. Drivers will see your post and send their offers soon."
            : "\(offers.count) offer\(offers.count == 1 ? "" : "s") waiting for your review."
    }

    private var budgetText: String {
        guard !request.budgetRange.isEmpty else { return "Open" }
        return request.budgetRange.hasPrefix("$") ? request.budgetRange : "$\(request.budgetRange)"
    }
}

private struct CashHubActivityHeader: View {
    let rideCount: Int
    let arrangedTotal: Double
    let driversMet: Int
    @Binding var selectedRange: CashHubActivityRange

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ride History")
                    .font(.title2.weight(.black))
                Text("Your completed cash rides at a glance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(CashHubActivityRange.allCases) { range in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            selectedRange = range
                        }
                    } label: {
                        Text(range.rawValue)
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(selectedRange == range ? Color.white : Color.secondary)
                            .background {
                                if selectedRange == range {
                                    Capsule().fill(Styles.rydrGradient)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))

            HStack(spacing: 10) {
                CashHubActivityStatTile(
                    icon: "car.fill",
                    tint: .red,
                    value: "\(rideCount)",
                    label: "Rides"
                )
                CashHubActivityStatTile(
                    icon: "dollarsign.circle.fill",
                    tint: .green,
                    value: arrangedTotal.formatted(.currency(code: "USD")),
                    label: "Arranged"
                )
                CashHubActivityStatTile(
                    icon: "person.2.fill",
                    tint: .purple,
                    value: "\(driversMet)",
                    label: "Drivers Met"
                )
            }
        }
        .cashHubPremiumCard()
    }
}

private struct CashHubActivityStatTile: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(tint.opacity(0.14)).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.subheadline.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private final class CashHubSnapshotCache {
    static let shared = CashHubSnapshotCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func store(_ image: UIImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
}

private func cashHubPseudoCoord(from text: String) -> CLLocationCoordinate2D {
    let base = CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880)
    let h = abs(text.hashValue)
    let lat = base.latitude + Double(h % 200 - 100) / 10000.0
    let lon = base.longitude + Double((h / 200) % 200 - 100) / 10000.0
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
}

private struct CashHubRouteThumbnail: View {
    let seed: String
    let pickupText: String
    let dropoffText: String

    @State private var snapshotImage: UIImage?

    private var pickup: CLLocationCoordinate2D { cashHubPseudoCoord(from: pickupText) }
    private var dropoff: CLLocationCoordinate2D { cashHubPseudoCoord(from: dropoffText) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))

            if let snapshotImage {
                Image(uiImage: snapshotImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .frame(width: 84, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: seed) {
            await loadSnapshot()
        }
    }

    private var fitRegion: MKCoordinateRegion {
        let minLat = min(pickup.latitude, dropoff.latitude)
        let maxLat = max(pickup.latitude, dropoff.latitude)
        let minLon = min(pickup.longitude, dropoff.longitude)
        let maxLon = max(pickup.longitude, dropoff.longitude)

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.015, (maxLat - minLat) * 1.8),
            longitudeDelta: max(0.015, (maxLon - minLon) * 1.8)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    @MainActor
    private func loadSnapshot() async {
        if let cached = CashHubSnapshotCache.shared.image(for: seed) {
            snapshotImage = cached
            return
        }

        let options = MKMapSnapshotter.Options()
        options.region = fitRegion
        options.size = CGSize(width: 168, height: 200)
        options.scale = UIScreen.main.scale
        options.showsBuildings = false
        options.pointOfInterestFilter = .excludingAll
        options.mapType = .mutedStandard

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return }

        let rendered = drawRoute(on: snapshot)
        CashHubSnapshotCache.shared.store(rendered, for: seed)
        snapshotImage = rendered
    }

    private func drawRoute(on snapshot: MKMapSnapshotter.Snapshot) -> UIImage {
        let image = snapshot.image
        let renderer = UIGraphicsImageRenderer(size: image.size)

        return renderer.image { ctx in
            image.draw(at: .zero)

            let pickupPoint = snapshot.point(for: pickup)
            let dropoffPoint = snapshot.point(for: dropoff)
            let midPoint = CGPoint(
                x: (pickupPoint.x + dropoffPoint.x) / 2,
                y: min(pickupPoint.y, dropoffPoint.y) - 14
            )

            let path = UIBezierPath()
            path.move(to: pickupPoint)
            path.addQuadCurve(to: dropoffPoint, controlPoint: midPoint)

            UIColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()

            UIColor.systemRed.setStroke()
            path.lineWidth = 3.5
            path.stroke()

            let dotRadius: CGFloat = 5
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: pickupPoint.x - dotRadius - 1.5, y: pickupPoint.y - dotRadius - 1.5, width: (dotRadius + 1.5) * 2, height: (dotRadius + 1.5) * 2))
            ctx.cgContext.fillEllipse(in: CGRect(x: dropoffPoint.x - dotRadius - 1.5, y: dropoffPoint.y - dotRadius - 1.5, width: (dotRadius + 1.5) * 2, height: (dotRadius + 1.5) * 2))

            ctx.cgContext.setFillColor(UIColor.systemRed.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: pickupPoint.x - dotRadius, y: pickupPoint.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))

            ctx.cgContext.setFillColor(UIColor.systemGreen.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: dropoffPoint.x - dotRadius, y: dropoffPoint.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
        }
    }
}

private struct CashHubRideHistoryCard: View {
    let request: CashRydrRequest
    let offer: CashHubResponse?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CashHubRouteThumbnail(seed: request.id, pickupText: request.pickup, dropoffText: request.destination)

            VStack(alignment: .leading, spacing: 6) {
                Text(request.rideType)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.red.opacity(0.1)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(request.pickup)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    Text(request.destination)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(request.scheduledTime.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(request.scheduledTime.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    CashHubAvatar(name: request.connectedDriverName ?? "Driver", size: 24)
                    Text(request.connectedDriverName ?? "Driver")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    CashHubRatingLabel(rating: offer?.cashHubRating)
                }
            }

            Spacer(minLength: 8)

            Text(priceText)
                .font(.headline.weight(.black))
        }
        .padding(14)
        .cashHubPremiumCard()
    }

    private var priceText: String {
        if let agreedPrice = request.agreedPrice {
            return agreedPrice.formatted(.currency(code: "USD"))
        }
        return "—"
    }
}

private struct CashHubSafetyFooter: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Label("Cash rides are arranged directly between rider and driver.", systemImage: "shield.checkered")
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            Label("Confirm details before meeting.", systemImage: "checkmark.seal")
            Label("Never share sensitive personal information in chat.", systemImage: "lock.shield")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .cashHubPremiumCard()
    }
}

private struct CashHubSocialEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.title2)
                .foregroundStyle(Styles.rydrGradient)
            Text(title)
                .font(.headline.weight(.black))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .cashHubPremiumCard()
    }
}

private struct CashHubAvatar: View {
    let name: String
    var size: CGFloat = 42

    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "R"))
            .font(.system(size: size * 0.38, weight: .black))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Styles.rydrGradient))
    }
}

private struct CashHubStatusBadge: View {
    let status: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.black))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.12)))
            .foregroundStyle(color)
    }

    private var label: String {
        switch status {
        case "connected", "accepted": return "Accepted"
        case "completed": return "Completed"
        case "cancelled", "canceled": return "Canceled"
        case "expired": return "Expired"
        default: return "Open"
        }
    }

    private var color: Color {
        switch status {
        case "connected", "accepted", "completed": return .green
        case "cancelled", "canceled", "expired": return .secondary
        default: return .red
        }
    }
}

private struct CashHubRouteRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
        }
    }
}

private struct CashHubInfoChip: View {
    let systemName: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemName)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
            .foregroundStyle(.secondary)
    }
}

private struct CashHubOfferAvatarStack: View {
    let offers: [CashHubResponse]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(offers.prefix(3))) { offer in
                CashHubAvatar(name: offer.authorName, size: 28)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
        }
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
    var showOnlineDot: Bool = false

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
        .overlay(alignment: .bottomTrailing) {
            if showOnlineDot && driver.isOnline {
                Circle()
                    .fill(Color.green)
                    .frame(width: size * 0.32, height: size * 0.32)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
        }
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .foregroundStyle(.secondary)
    }
}

private struct CashHubRatingLabel: View {
    let rating: Double?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.orange)
            Text(rating.map { String(format: "%.1f", $0) } ?? "New")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
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

    func cashHubPremiumCard() -> some View {
        self
            .padding()
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
