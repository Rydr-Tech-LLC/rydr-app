//
//  CashRydrHubView.swift
//  RydrPlayground
//
//  Community ride request marketplace. Cash Hub connections are never dispatched rides.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CoreLocation
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
    var tripFormat: String
    var visibility: String
    var status: String
    var driverQueueStatus: String?
    var connectedDriverUid: String?
    var connectedDriverName: String?
    var selectedOfferId: String?
    var agreedPrice: Double?
    var createdAt: Date?
    var isHiddenFromMyPosts: Bool

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

private func cashHubConversationId(requestId: String, driverUid: String) -> String {
    "\(requestId)_\(driverUid)"
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
    var addedAt: Date?
}

private enum CashHubVisibility: String, CaseIterable, Identifiable {
    case favoriteDrivers = "Favorite Drivers"
    case publicCommunity = "Public CashRydr Hub Community"

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
    static let submissionBuffer: TimeInterval = 5 * 60

    static func earliestRequestTime(from date: Date = Date()) -> Date {
        // Give the rider enough time to finish and submit the form without a
        // value that was valid when the sheet opened falling below the
        // backend's two-hour minimum while the request is in flight.
        let minimum = date.addingTimeInterval(minimumLeadTime + submissionBuffer)
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
    var tripFormat = "One-way"
    var visibility = CashHubVisibility.publicCommunity.rawValue
    var pickupLatitude: Double?
    var pickupLongitude: Double?
    var destinationLatitude: Double?
    var destinationLongitude: Double?

    init() {}

    init(request: CashRydrRequest) {
        pickup = request.pickup
        destination = request.destination
        scheduledTime = request.scheduledTime
        passengers = request.passengers
        notes = request.notes
        budgetRange = cashHubCurrencyInput(request.budgetRange)
        tripFormat = request.tripFormat
        visibility = CashHubVisibility.normalized(request.visibility).rawValue
    }

    var coordinatePayload: [String: Any] {
        var payload: [String: Any] = [:]
        if let pickupLatitude, let pickupLongitude {
            payload["pickupCoordinate"] = ["latitude": pickupLatitude, "longitude": pickupLongitude]
        }
        if let destinationLatitude, let destinationLongitude {
            payload["destinationCoordinate"] = ["latitude": destinationLatitude, "longitude": destinationLongitude]
        }
        return payload
    }
}

private struct CashHubOfferDraft {
    var offerAmount = ""
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
        case .requestThread: return "Offer Conversation"
        case .directConnection: return "Trip Chat"
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
    let conversationId: String?
    let driverUid: String?
    let driverName: String?

    init(request: CashRydrRequest, mode: CashHubMessageMode, offer: CashHubResponse? = nil) {
        self.request = request
        self.mode = mode
        let resolvedDriverUid = offer?.authorUid ?? request.connectedDriverUid
        self.driverUid = resolvedDriverUid
        self.driverName = offer?.authorName ?? request.connectedDriverName
        self.conversationId = resolvedDriverUid.map { cashHubConversationId(requestId: request.id, driverUid: $0) }
    }

    var id: String { "\(request.id)-\(mode.rawValue)-\(conversationId ?? "none")" }
}

private enum CashHubFeedCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case posts = "Posts"
    case offers = "Offers"
    case messages = "Chats"
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
    var requestId: String? = nil
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
    @Published var termsAcceptanceEnabled = false

    private var cashHubTermsVersion = "legacy"
    private let favoriteDriverLimit = 10
    private let db = Firestore.firestore()
    private var requestListener: ListenerRegistration?
    private var responseListeners: [String: ListenerRegistration] = [:]
    private var messageListeners: [String: ListenerRegistration] = [:]
    private var messagesByConversation: [String: [CashHubResponse]] = [:]
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

        let configRef = db.collection("platformConfig").document("cashRydrHub")
        let riderRef = db.collection("riders").document(uid)

        configRef.getDocument { [weak self] configSnap, _ in
            guard self != nil else { return }
            riderRef.getDocument { [weak self] snap, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isCheckingTerms = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }

                    let config = configSnap?.data() ?? [:]
                    self.termsAcceptanceEnabled = config["termsAcceptanceEnabled"] as? Bool ?? false
                    self.cashHubTermsVersion = config["cashHubTermsVersion"] as? String ?? "legacy"

                    let data = snap?.data() ?? [:]
                    let acceptedVersion = data["cashHubTermsVersion"] as? String
                    let acceptedCurrentTerms = acceptedVersion == self.cashHubTermsVersion || (acceptedVersion == nil && self.cashHubTermsVersion == "legacy")
                    self.termsAccepted = (data["cashHubTermsAccepted"] as? Bool ?? false) && acceptedCurrentTerms
                    if self.termsAcceptanceEnabled && self.termsAccepted {
                        self.startMarketplace()
                        self.startFavoriteDrivers()
                    }
                }
            }
        }
    }

    func acceptTerms() {
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Please log in to continue."
            return
        }

        guard termsAcceptanceEnabled else {
            errorMessage = "Cash Rydr Hub is not available during the live beta."
            return
        }

        isSaving = true
        Task { [weak self] in
            do {
                try await RiderCashHubBackend.acceptTerms()
                await MainActor.run {
                    guard let self else { return }
                    self.isSaving = false
                    self.termsAccepted = true
                    self.startMarketplace()
                    self.startFavoriteDrivers()
                }
            } catch {
                await MainActor.run {
                    self?.isSaving = false
                    self?.errorMessage = error.localizedDescription
                }
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
        messageListeners.values.forEach { $0.remove() }
        messageListeners.removeAll()
        messagesByConversation.removeAll()
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
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Please log in to update favorite drivers."
            return
        }
        Task { [weak self] in do { try await RiderCashHubBackend.relationship(action:"remove_favorite_driver",targetUid:driver.driverUid);await MainActor.run{self?.confirmationMessage="\(driver.name) was removed from your favorite drivers."} } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
    }

    func blockFavoriteDriver(_ driver: CashHubFavoriteDriver) {
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Please log in to block a driver."
            return
        }
        Task { [weak self] in do { try await RiderCashHubBackend.relationship(action:"block_driver",targetUid:driver.driverUid);await MainActor.run{self?.confirmationMessage="\(driver.name) has been blocked."} } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
    }

    func blockDriver(_ offer: CashHubResponse) {
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Please log in to block a driver."
            return
        }
        Task { [weak self] in do { try await RiderCashHubBackend.relationship(action:"block_driver",targetUid:offer.authorUid,conversationId:offer.id);await MainActor.run{self?.confirmationMessage="\(offer.authorName) has been blocked."} } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
    }

    func reportDriver(_ offer: CashHubResponse, for request: CashRydrRequest) {
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Please log in to report a driver."
            return
        }
        let payload: [String: Any] = [
            "reportType": "Cash Hub driver report",
            "cashHubRequestId": request.id,
            "cashHubConversationId": offer.id,
            "description": "Rider reported a Cash Hub driver conversation for review."
        ]
        Task { [weak self] in do { try await RiderSafetyBackend.submit(payload);await MainActor.run{self?.confirmationMessage="Driver reported to Rydr safety support."} } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
    }

    func reportConnectedListingProblem(_ request: CashRydrRequest) {
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Please log in to report a problem."
            return
        }
        let payload: [String: Any] = [
            "reportType": "Cash Hub connected listing problem",
            "cashHubRequestId": request.id,
            "description": "Rider reported a problem with a connected Cash Hub listing."
        ]
        Task { [weak self] in do { try await RiderSafetyBackend.submit(payload);await MainActor.run{self?.confirmationMessage="Problem reported to Rydr safety support."} } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
    }

    func addFavoriteDriver(from offer: CashHubResponse) {
        guard Auth.auth().currentUser != nil else {
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
        Task { [weak self] in do { try await RiderCashHubBackend.relationship(action:"add_favorite_driver",targetUid:offer.authorUid);await MainActor.run{self?.confirmationMessage="\(offer.authorName) was added to your favorite drivers."} } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
    }

    func createRequest(from draft: CashHubRequestDraft, riderName: String, completion: @escaping (Bool) -> Void) {
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Please log in to post a request."
            completion(false)
            return
        }
        guard validate(draft) else {
            completion(false)
            return
        }

        isSaving = true
        let data: [String: Any] = [
            "riderName": displayName(riderName, fallback: "Cash Hub Rider"),
            "pickup": draft.pickup.trimmingCharacters(in: .whitespacesAndNewlines),
            "destination": draft.destination.trimmingCharacters(in: .whitespacesAndNewlines),
            "scheduledTime": ISO8601DateFormatter().string(from: draft.scheduledTime),
            "passengers": draft.passengers,
            "notes": draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            "budgetRange": draft.budgetRange.trimmingCharacters(in: .whitespacesAndNewlines),
            "tripFormat": draft.tripFormat,
            "visibility": draft.visibility
        ].merging(draft.coordinatePayload) { _, new in new }
        Task { [weak self] in
            do { try await RiderCashHubBackend.create(data); await MainActor.run { self?.isSaving=false;self?.confirmationMessage="Your request has been posted. Drivers may respond with price offers and messages."; completion(true) } }
            catch { await MainActor.run { self?.isSaving=false;self?.errorMessage=error.localizedDescription; completion(false) } }
        }
    }

    func updateRequest(_ request: CashRydrRequest, from draft: CashHubRequestDraft, completion: @escaping (Bool) -> Void) {
        guard validate(draft) else {
            completion(false)
            return
        }

        isSaving = true
        let data: [String: Any] = [
            "pickup": draft.pickup.trimmingCharacters(in: .whitespacesAndNewlines),
            "destination": draft.destination.trimmingCharacters(in: .whitespacesAndNewlines),
            "scheduledTime": ISO8601DateFormatter().string(from: draft.scheduledTime),
            "passengers": draft.passengers,
            "notes": draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            "budgetRange": draft.budgetRange.trimmingCharacters(in: .whitespacesAndNewlines),
            "tripFormat": draft.tripFormat,
            "visibility": draft.visibility
        ].merging(draft.coordinatePayload) { _, new in new }
        Task { [weak self] in do { try await RiderCashHubBackend.command(requestId:request.id,action:"edit",body:data);await MainActor.run{self?.isSaving=false;completion(true)} } catch { await MainActor.run{self?.isSaving=false;self?.errorMessage=error.localizedDescription;completion(false)} } }
    }

    func updateVisibility(for request: CashRydrRequest, to visibility: String) {
        guard Auth.auth().currentUser?.uid == request.riderUid else {
            errorMessage = "Only the rider who posted this request can change its visibility."
            return
        }
        let normalizedVisibility = CashHubVisibility.normalized(visibility).rawValue
        Task { [weak self] in do { try await RiderCashHubBackend.command(requestId:request.id,action:"visibility",body:["visibility":normalizedVisibility]) } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
    }

    func removeRequest(_ request: CashRydrRequest) {
        guard Auth.auth().currentUser?.uid == request.riderUid else {
            errorMessage = "Only the rider who posted this request can delete it."
            return
        }
        Task { [weak self] in do { try await RiderCashHubBackend.command(requestId:request.id,action:"remove");await MainActor.run{self?.confirmationMessage="Your request was removed from My Posts. Accepted ride history remains in Activity."} } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
    }

    func sendOffer(to request: CashRydrRequest, draft: CashHubOfferDraft, driverName: String) -> Bool {
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Please log in to make an offer."
            return false
        }
        guard request.isOpen else {
            errorMessage = "This request is no longer accepting offers."
            return false
        }

        let message = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let offerAmount = cleanAmount(draft.offerAmount) else {
            errorMessage = "Enter a valid offer amount."
            return false
        }

        var offerData: [String: Any] = [
            "offerAmount": offerAmount
        ]
        if !message.isEmpty {
            offerData["message"] = message
        }
        Task { [weak self] in do { try await RiderCashHubBackend.offer(requestId:request.id,body:offerData) } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
        return true
    }

    func sendMessage(to context: CashHubMessageContext, message: String, authorName: String) -> Bool {
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Please log in to send a message."
            return false
        }
        let request = context.request
        if context.mode == .requestThread && request.isConnected {
            errorMessage = "Offer conversations close after you connect with a driver."
            return false
        }
        if context.mode == .directConnection && !request.isConnected {
            errorMessage = "Trip Chat opens after you connect with a driver."
            return false
        }
        guard let conversationId = context.conversationId, context.driverUid != nil else {
            errorMessage = "Choose a driver conversation first."
            return false
        }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a message first."
            return false
        }

        Task { [weak self] in do { try await RiderCashHubBackend.message(conversationId:conversationId,text:trimmed,kind:context.mode.responseKind) } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
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

        Task { [weak self] in do { try await RiderCashHubBackend.command(requestId:request.id,action:"accept_offer",body:["offerId":offer.id]);await MainActor.run{self?.confirmationMessage="You and this driver are now connected for this Cash Hub request."} } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
    }

    func declineOffer(_ offer: CashHubResponse, for request: CashRydrRequest) {
        guard Auth.auth().currentUser?.uid == request.riderUid else {
            errorMessage = "Only the rider who posted this request can decline an offer."
            return
        }
        Task { [weak self] in do { try await RiderCashHubBackend.command(requestId:request.id,action:"decline_offer",body:["offerId":offer.id]);await MainActor.run{self?.confirmationMessage="That price was declined. The conversation is still open."} } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
    }

    func proposePrice(_ context: CashHubMessageContext, amountText: String, message: String) -> Bool {
        guard let conversationId = context.conversationId,
              let offerAmount = cleanAmount(amountText) else {
            errorMessage = "Enter a valid proposed price."
            return false
        }
        var body: [String: Any] = ["offerAmount": offerAmount]
        let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { body["message"] = note }
        Task { [weak self] in do { try await RiderCashHubBackend.conversationCommand(conversationId:conversationId,action:"propose_price",body:body);await MainActor.run{self?.confirmationMessage="Your price was sent for the driver to accept or decline."} } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
        return true
    }

    func acceptPrice(_ context: CashHubMessageContext) {
        guard let conversationId = context.conversationId else { errorMessage = "Conversation not found."; return }
        Task { [weak self] in do { try await RiderCashHubBackend.conversationCommand(conversationId:conversationId,action:"accept_price");await MainActor.run{self?.confirmationMessage="Price accepted. You and the driver are now connected."} } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
    }

    func declinePrice(_ context: CashHubMessageContext) {
        guard let conversationId = context.conversationId else { errorMessage = "Conversation not found."; return }
        Task { [weak self] in do { try await RiderCashHubBackend.conversationCommand(conversationId:conversationId,action:"decline_price");await MainActor.run{self?.confirmationMessage="Price declined. The conversation remains open."} } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
    }

    func endChat(_ context: CashHubMessageContext) {
        guard let conversationId = context.conversationId else {
            errorMessage = "Conversation not found."
            return
        }
        Task { [weak self] in do { try await RiderCashHubBackend.conversationCommand(conversationId:conversationId,action:"end_chat");await MainActor.run{self?.confirmationMessage="Chat ended."} } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
    }

    func reportChat(_ context: CashHubMessageContext) {
        guard let conversationId = context.conversationId else {
            errorMessage = "Conversation not found."
            return
        }
        let payload: [String: Any] = [
            "reportType": "Cash Hub chat report",
            "cashHubRequestId": context.request.id,
            "cashHubConversationId": conversationId,
            "description": "Rider reported a Cash Hub chat for review."
        ]
        Task { [weak self] in do { try await RiderSafetyBackend.submit(payload);await MainActor.run{self?.confirmationMessage="Chat reported to Rydr safety support."} } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
    }

    func cancelListing(_ request: CashRydrRequest) {
        guard Auth.auth().currentUser?.uid == request.riderUid else {
            errorMessage = "Only the rider who posted this request can cancel it."
            return
        }
        Task { [weak self] in do { try await RiderCashHubBackend.command(requestId:request.id,action:"rider_cancel");await MainActor.run{self?.confirmationMessage="Your Cash Hub listing was cancelled."} } catch { await MainActor.run{self?.errorMessage=error.localizedDescription} } }
    }

    func offers(for request: CashRydrRequest) -> [CashHubResponse] {
        (responsesByRequest[request.id] ?? []).filter(\.isDriverOffer)
    }

    func selectedOffer(for request: CashRydrRequest) -> CashHubResponse? {
        guard let selectedOfferId = request.selectedOfferId else { return nil }
        return responsesByRequest[request.id]?.first { $0.id == selectedOfferId }
    }

    func messages(for context: CashHubMessageContext) -> [CashHubResponse] {
        guard let conversationId = context.conversationId else { return [] }
        return messagesByConversation[conversationId] ?? []
    }

    func conversation(for context: CashHubMessageContext) -> CashHubResponse? {
        guard let conversationId = context.conversationId else { return nil }
        return responsesByRequest[context.request.id]?.first { $0.id == conversationId }
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
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let activeIDs = Set(requests.map(\.id))
        for (id, listener) in responseListeners where !activeIDs.contains(id) {
            listener.remove()
            responseListeners[id] = nil
            responsesByRequest[id] = nil
        }

        for request in requests where responseListeners[request.id] == nil {
            responseListeners[request.id] = db.collection("cashHubConversations")
                .whereField("requestId", isEqualTo: request.id)
                .whereField("riderUid", isEqualTo: uid)
                .addSnapshotListener { [weak self] snap, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error {
                            self.errorMessage = error.localizedDescription
                            return
                        }
                        let conversations = (snap?.documents ?? [])
                            .compactMap(Self.makeConversationSummary)
                            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                        self.responsesByRequest[request.id] = conversations
                        self.syncMessageListeners(for: conversations)
                    }
                }
        }
    }

    private func syncMessageListeners(for conversations: [CashHubResponse]) {
        let activeIDs = Set(conversations.map(\.id))
        for (id, listener) in messageListeners where !activeIDs.contains(id) {
            listener.remove()
            messageListeners[id] = nil
            messagesByConversation[id] = nil
        }

        for conversation in conversations where messageListeners[conversation.id] == nil {
            messageListeners[conversation.id] = db.collection("cashHubConversations")
                .document(conversation.id)
                .collection("messages")
                .order(by: "createdAt", descending: false)
                .addSnapshotListener { [weak self] snap, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let error {
                            self.errorMessage = error.localizedDescription
                            return
                        }
                        self.messagesByConversation[conversation.id] = (snap?.documents ?? []).compactMap(Self.makeConversationMessage)
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
            tripFormat: data["tripFormat"] as? String ?? data["rideType"] as? String ?? "Scheduled",
            visibility: CashHubVisibility.normalized(data["visibility"] as? String).rawValue,
            status: data["status"] as? String ?? "open",
            driverQueueStatus: data["driverQueueStatus"] as? String,
            connectedDriverUid: data["connectedDriverUid"] as? String ?? data["acceptedByUid"] as? String,
            connectedDriverName: data["connectedDriverName"] as? String ?? data["acceptedByName"] as? String,
            selectedOfferId: data["selectedOfferId"] as? String,
            agreedPrice: data["agreedPrice"] as? Double,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            isHiddenFromMyPosts: data["riderHiddenFromMyPosts"] as? Bool ?? false
        )
    }

    private static func makeConversationSummary(_ doc: QueryDocumentSnapshot) -> CashHubResponse? {
        let data = doc.data()
        guard let driverUid = data["driverUid"] as? String else { return nil }
        return CashHubResponse(
            id: doc.documentID,
            authorUid: driverUid,
            authorName: data["driverName"] as? String ?? "Cash Hub Driver",
            authorRole: "driver",
            kind: "offer",
            status: (data["chatStatus"] as? String == "ended") ? "ended" : (data["offerStatus"] as? String ?? "pending"),
            message: data["lastMessage"] as? String ?? "",
            offerAmount: data["offerAmount"] as? Double,
            availability: data["availability"] as? String ?? "Availability provided by message",
            vehicleInfo: data["vehicleInfo"] as? String ?? "Vehicle details not provided",
            cashHubRating: data["cashHubRating"] as? Double,
            isIdentityVerified: data["isIdentityVerified"] as? Bool ?? false,
            isLicenseVerified: data["isLicenseVerified"] as? Bool ?? false,
            isRydrVerifiedDriver: data["isRydrVerifiedDriver"] as? Bool ?? false,
            createdAt: (data["lastMessageAt"] as? Timestamp)?.dateValue() ?? (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }

    private static func makeConversationMessage(_ doc: QueryDocumentSnapshot) -> CashHubResponse? {
        let data = doc.data()
        guard let senderUid = data["senderUid"] as? String,
              let senderRole = data["senderRole"] as? String else { return nil }
        return CashHubResponse(
            id: doc.documentID,
            authorUid: senderUid,
            authorName: data["senderName"] as? String ?? "Cash Hub User",
            authorRole: senderRole,
            kind: data["kind"] as? String ?? "message",
            status: "sent",
            message: data["text"] as? String ?? "",
            offerAmount: data["offerAmount"] as? Double,
            availability: data["availability"] as? String ?? "",
            vehicleInfo: data["vehicleInfo"] as? String ?? "",
            cashHubRating: nil,
            isIdentityVerified: false,
            isLicenseVerified: false,
            isRydrVerifiedDriver: false,
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
    @State private var requestPendingCancellation: CashRydrRequest?
    @State private var selectedHomeTab: CashHubHomeTab = .feed
    @AppStorage("cashHubSafetyFooterDismissed") private var safetyFooterDismissed = false
    private var showSafetyFooter: Bool {
        get { !safetyFooterDismissed }
        nonmutating set { safetyFooterDismissed = !newValue }
    }
    @State private var selectedFeedCategory: CashHubFeedCategory = .all
    @State private var activityRange: CashHubActivityRange = .days30
    @AppStorage("cashHubDismissedFeedEventIDs") private var dismissedFeedEventIDsStorage = ""
    @State private var pendingNotificationRoute: [AnyHashable: Any]?

    private var currentUID: String { Auth.auth().currentUser?.uid ?? "" }
    private var riderRequests: [CashRydrRequest] { vm.requests.filter { $0.riderUid == currentUID } }
    private var myRequests: [CashRydrRequest] { riderRequests.filter { !$0.isHiddenFromMyPosts } }
    private var completedCashRideCount: Int {
        riderRequests.filter { $0.status == "completed" }.count
    }

    private var cashHubFeedEvents: [CashHubFeedEvent] {
        var events: [CashHubFeedEvent] = []

        for driver in vm.favoriteDrivers {
            events.append(.init(
                id: "cash-hub-active-\(driver.driverUid)",
                title: "\(driver.name) is in your favorites",
                detail: "Saved as a favorite Cash Hub driver",
                cta: "Post a trip to request offers",
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

        for request in riderRequests where !request.isHiddenFromMyPosts || request.status == "completed" {
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
                    requestId: request.id,
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
                    requestId: request.id,
                    accessory: .avatarInitial(message.authorName)
                ))
            }

            if request.status == "completed" {
                events.append(.init(
                    id: "completed-\(request.id)",
                    title: "You closed a Cash Hub listing",
                    detail: "Your listing with \(request.connectedDriverName ?? "your driver") is closed.",
                    cta: nil,
                    systemImage: "checkmark.seal.fill",
                    date: request.createdAt ?? request.scheduledTime,
                    tint: .green,
                    category: .trips,
                    requestId: request.id,
                    accessory: .badge("Closed", .green)
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
                    requestId: request.id,
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
                    category: .posts,
                    requestId: request.id
                ))
            }
        }

        if completedCashRideCount >= 10 {
            events.append(.init(
                id: "milestone-10",
                title: "You closed your 10th Cash Hub listing",
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
                title: "You closed your first Cash Hub listing",
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
            } else if !vm.termsAcceptanceEnabled || !vm.termsAccepted {
                CashHubTermsView(
                    isConfirmed: $acceptedTermsCheckbox,
                    isSaving: vm.isSaving,
                    canAcceptTerms: vm.termsAcceptanceEnabled,
                    onContinue: { vm.acceptTerms() }
                )
            } else {
                marketplace
            }
        }
        .navigationTitle("Cash Rydr Hub")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: NotificationView()) {
                    Image(systemName: "bell.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.red)
                        .frame(width: 40, height: 40)
                        .background(Color.red.opacity(0.10), in: Circle())
                }
                .accessibilityLabel("Notifications")
            }
        }
        .task { vm.loadAccess() }
        .onReceive(NotificationCenter.default.publisher(for: .riderNotificationRouteRequested)) { notification in
            guard (notification.userInfo?["target"] as? String) == "cashHub" else { return }
            pendingNotificationRoute = notification.userInfo
            openPendingNotificationRoute()
        }
        .onChange(of: vm.requests.count) { _, _ in openPendingNotificationRoute() }
        .onChange(of: vm.responsesByRequest.count) { _, _ in openPendingNotificationRoute() }
        .onDisappear { vm.stop() }
        .sheet(isPresented: $showPostRequest) {
            CashHubRequestForm(title: "Post Ride Request") { draft in
                vm.createRequest(from: draft, riderName: session.userName) { didSave in
                    if didSave { showPostRequest = false }
                }
            }
        }
        .sheet(item: $editingRequest) { request in
            CashHubRequestForm(title: "Edit Ride Request", initialDraft: CashHubRequestDraft(request: request)) { draft in
                vm.updateRequest(request, from: draft) { didSave in
                    if didSave { editingRequest = nil }
                }
            }
        }
        .sheet(item: $messagingContext) { context in
            CashHubMessageForm(
                request: context.request,
                mode: context.mode,
                messages: vm.messages(for: context),
                conversation: vm.conversation(for: context),
                onSend: { text in vm.sendMessage(to: context, message: text, authorName: session.userName) },
                onProposePrice: { amount, note in vm.proposePrice(context, amountText: amount, message: note) },
                onAccept: { vm.acceptPrice(context) },
                onDecline: { vm.declinePrice(context) },
                onEndChat: { vm.endChat(context) },
                onReportChat: { vm.reportChat(context) }
            )
        }
        .sheet(item: $viewingConnection) { request in
            CashHubAcceptedRequestView(
                request: request,
                offer: vm.selectedOffer(for: request),
                onMessage: {
                    viewingConnection = nil
                    DispatchQueue.main.async {
                        messagingContext = CashHubMessageContext(request: request, mode: .directConnection, offer: vm.selectedOffer(for: request))
                    }
                },
                onCancel: {
                    viewingConnection = nil
                    requestPendingCancellation = request
                },
                onReportProblem: { vm.reportConnectedListingProblem(request) },
                onReportDriver: {
                    if let offer = vm.selectedOffer(for: request) {
                        vm.reportDriver(offer, for: request)
                    }
                }
            )
        }
        .sheet(item: $riderPanel) { panel in
            CashHubRiderPanelView(
                panel: panel,
                requests: myRequests,
                responses: vm.responsesByRequest,
                favoriteDrivers: vm.favoriteDrivers,
                onEdit: { request in
                    riderPanel = nil
                    DispatchQueue.main.async { editingRequest = request }
                },
                onDelete: { vm.removeRequest($0) },
                onVisibilityChange: { request, visibility in vm.updateVisibility(for: request, to: visibility) },
                onOpenConnection: { request in
                    riderPanel = nil
                    DispatchQueue.main.async { viewingConnection = request }
                },
                onMessage: { request, mode, offer in
                    riderPanel = nil
                    DispatchQueue.main.async {
                        messagingContext = CashHubMessageContext(request: request, mode: mode, offer: offer)
                    }
                },
                onFavorite: { vm.addFavoriteDriver(from: $0) },
                onViewFavoriteDriver: { viewingFavoriteDriver = $0 },
                onRemoveFavoriteDriver: { vm.removeFavoriteDriver($0) },
                onBlockFavoriteDriver: { driverPendingBlock = $0 },
                onBlockOfferDriver: { vm.blockDriver($0) },
                onReportOfferDriver: { offer, request in vm.reportDriver(offer, for: request) },
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
            "Cancel this listing?",
            isPresented: Binding(
                get: { requestPendingCancellation != nil },
                set: { if !$0 { requestPendingCancellation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Cancel Listing", role: .destructive) {
                if let requestPendingCancellation {
                    vm.cancelListing(requestPendingCancellation)
                }
                requestPendingCancellation = nil
            }
            Button("Keep Listing", role: .cancel) { requestPendingCancellation = nil }
        } message: {
            Text("This ends the listing and any agreement with a connected driver. It does not delete the post from My Posts.")
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
                Text("This removes the request from My Posts. The driver can still complete the agreed listing, and its history will remain in Activity.")
            } else if requestPendingDeletion?.status == "completed" {
                Text("This removes the request from My Posts. Its completed listing history will remain in Activity.")
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
                        CashHubDriversAvailableBanner(
                            previewDrivers: vm.favoriteDrivers,
                            onTap: { riderPanel = .favorites }
                        )
                        CashHubQuickPostCard(onPost: { showPostRequest = true })
                        CashHubFeedTimelineCard(
                            events: cashHubFeedEvents.filter { !dismissedFeedEventIDs.contains($0.id) },
                            selectedCategory: $selectedFeedCategory,
                            onSelect: openFeedEvent,
                            onDelete: dismissFeedEvent
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
                                    onTripChat: { messagingContext = CashHubMessageContext(request: request, mode: .directConnection, offer: vm.selectedOffer(for: request)) },
                                    onConnection: { viewingConnection = request },
                                    onCancel: { requestPendingCancellation = request },
                                    onDelete: { requestPendingDeletion = request }
                                )
                            }
                        }
                    case .activity:
                        let completedRequests = riderRequests.filter { $0.status == "completed" }
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
                                title: "No closed Cash Hub listings yet",
                                message: "Listing activity appears here once a connected listing is marked closed."
                            )
                        } else {
                            HStack {
                                Text("Recent Listings")
                                    .font(.headline.weight(.black))
                                Spacer()
                            }

                            ForEach(activityRequests) { request in
                                CashHubRideHistoryCard(
                                    request: request,
                                    offer: vm.selectedOffer(for: request)
                                )
                            }

                            Text("Cash Hub listings are settled directly between you and the driver — no in-app receipt is issued.")
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

    private func openFeedEvent(_ event: CashHubFeedEvent) {
        switch event.category {
        case .favorites:
            riderPanel = .favorites
        case .offers:
            riderPanel = .offers
        case .messages:
            guard let request = riderRequests.first(where: { $0.id == event.requestId }) else { return }
            let offer = vm.responsesByRequest[request.id]?.first
            messagingContext = CashHubMessageContext(
                request: request,
                mode: request.isConnected ? .directConnection : .requestThread,
                offer: offer
            )
        case .posts:
            selectedHomeTab = .myPosts
        case .trips:
            selectedHomeTab = .activity
        case .all:
            break
        }
    }

    private var dismissedFeedEventIDs: Set<String> {
        Set(dismissedFeedEventIDsStorage.split(separator: "|").map(String.init))
    }

    private func dismissFeedEvent(_ event: CashHubFeedEvent) {
        var ids = dismissedFeedEventIDs
        ids.insert(event.id)
        dismissedFeedEventIDsStorage = ids.sorted().joined(separator: "|")
    }

    private func openPendingNotificationRoute() {
        guard let route = pendingNotificationRoute,
              let requestId = route["requestId"] as? String,
              let request = riderRequests.first(where: { $0.id == requestId }) else { return }
        let type = route["type"] as? String ?? "cashHubUpdate"
        switch type {
        case "cashHubOffer":
            riderPanel = .offers
        case "cashHubMessage":
            let chatId = route["chatId"] as? String
            let offer = vm.responsesByRequest[request.id]?.first(where: { chatId == nil || $0.id == chatId })
            guard offer != nil || request.isConnected else { return }
            messagingContext = CashHubMessageContext(
                request: request,
                mode: request.isConnected ? .directConnection : .requestThread,
                offer: offer
            )
        default:
            selectedHomeTab = request.isConnected ? .myPosts : .feed
        }
        pendingNotificationRoute = nil
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
    let canAcceptTerms: Bool
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            CashHubTermsBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    CashHubTermsHero()

                    CashHubTermsKnowledgeCard()

                    CashHubResponsibilityCard()

                    if !canAcceptTerms {
                        CashHubBetaLockedNotice()
                    }

                    CashHubConfirmationToggle(
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

private struct CashHubBetaLockedNotice: View {
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

private struct CashHubTermsBackground: View {
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

private struct CashHubTermsHero: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                CashHubTermsArc()
                    .stroke(Color.red.opacity(0.26), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 8]))
                    .frame(height: 88)
                    .offset(y: 24)
                    .accessibilityHidden(true)

                HStack {
                    CashHubHeroBubble(systemImage: "car.fill")
                    Spacer()
                    CashHubHeroBubble(systemImage: "person.fill")
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

private struct CashHubHeroBubble: View {
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

private struct CashHubTermsArc: Shape {
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

private struct CashHubTermsKnowledgeCard: View {
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
                CashHubTermsFactRow(systemImage: "paperplane.fill", text: "Rydr does not dispatch Cash Hub rides.")
                Divider().padding(.leading, 82)
                CashHubTermsFactRow(systemImage: "dollarsign.circle", text: "Rydr does not set Cash Hub prices or process Cash Hub payments.")
                Divider().padding(.leading, 82)
                CashHubTermsFactRow(systemImage: "shield", text: "Rydr does not guarantee driver availability, ride completion, or user conduct.")
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

private struct CashHubTermsFactRow: View {
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

private struct CashHubResponsibilityCard: View {
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

                Text("By continuing, you understand that any ride arranged through Cash Rydr Hub is coordinated directly between you and the other user. You are responsible for confirming pickup, destination, timing, payment, and safety expectations before starting the ride.")
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

private struct CashHubConfirmationToggle: View {
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

private struct CashHubHeader: View {
    var body: some View {
        CashRydrHubBannerView()
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
    }
}

private struct CashRydrHubBannerView: View {
    private let aspectRatio: CGFloat = 1774.0 / 887.0

    var body: some View {
        GeometryReader { proxy in
            let height = min(max(proxy.size.width / aspectRatio, 170), 220)

            Image("CashRydrHubBanner")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.70), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.16), radius: 20, x: 0, y: 12)
                .accessibilityLabel("CashRydr Hub. Post a ride, compare offers, chat, and choose the best driver.")
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxHeight: 220)
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
                    Text("Need A Cash Ride?")
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

private struct CashHubDriversAvailableBanner: View {
    let previewDrivers: [CashHubFavoriteDriver]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                HStack(spacing: -10) {
                    if previewDrivers.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
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
                        Text("Cash Hub drivers respond anytime")
                            .font(.subheadline.weight(.bold))
                    }
                    Text("Post a trip to receive driver offers")
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
    let onSelect: (CashHubFeedEvent) -> Void
    let onDelete: (CashHubFeedEvent) -> Void

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
                     ? "Your CashRydr Hub updates will appear here as you post ride needs, favorite drivers, close listings, and update your profile."
                     : "Nothing in this category yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(filteredEvents.prefix(12))) { event in
                    CashHubFeedRow(event: event, onSelect: { onSelect(event) }, onDelete: { onDelete(event) })
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
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var horizontalOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Clear", systemImage: "trash.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 82)
                    .frame(maxHeight: .infinity)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

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
            .padding(.horizontal, 2)
            .background(Color(.systemBackground))
            .offset(x: horizontalOffset)
            .contentShape(Rectangle())
            .onTapGesture {
                if horizontalOffset == 0 { onSelect() }
                else { withAnimation { horizontalOffset = 0 } }
            }
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        horizontalOffset = min(0, max(-82, value.translation.width))
                    }
                    .onEnded { value in
                        withAnimation(.snappy) {
                            horizontalOffset = value.translation.width < -42 ? -82 : 0
                        }
                    }
            )
        }
        .frame(minHeight: 58)
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
    let onTripChat: () -> Void
    let onConnection: () -> Void
    let onCancel: () -> Void
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
                    if request.isOpen || request.isConnected {
                        Button(role: .destructive, action: onCancel) {
                            Label("Cancel Listing", systemImage: "xmark.circle.fill")
                        }
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete Post", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title2.weight(.black))
                        .foregroundStyle(Color.red)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
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
                Button(request.isConnected ? "Details" : "View Offers") {
                    request.isConnected ? onConnection() : onOffers()
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.red.opacity(0.06)))

            HStack(spacing: 10) {
                if request.isConnected {
                    CashHubPostActionButton(icon: "bubble.left.and.bubble.right", label: "Trip Chat", action: onTripChat)
                    CashHubPostActionButton(icon: "checkmark.seal.fill", label: "Details", tint: .green, action: onConnection)
                } else {
                    CashHubPostActionButton(icon: "pencil", label: "Edit Post", action: onEdit)
                    CashHubPostActionButton(icon: "tag.fill", label: "Offers (\(offers.count))", tint: .red, action: onOffers)
                }
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
                Text("Listing History")
                    .font(.title2.weight(.black))
                Text("Your closed Cash Hub listings at a glance.")
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
                Text(request.tripFormat)
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
                Label("Cash Hub listings are arranged directly between rider and driver.", systemImage: "shield.checkered")
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
        case "connected", "accepted": return "Connected"
        case "completed": return "Closed"
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
            CashHubActionCard(title: "Trip Chats", icon: "bubble.left.and.bubble.right", action: onMessages)
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
                            CashHubAccessStatusLabel()
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
                            CashHubAccessStatusLabel()
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

private struct CashHubAccessStatusLabel: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
            Text("Cash Hub favorite")
        }
        .font(.caption)
        .foregroundStyle(.green)
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
            Text("\(request.tripFormat) | \(request.passengers) passenger\(request.passengers == 1 ? "" : "s") | \(request.visibility)")
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
                Button("Make Offer", action: onPrimary)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                Button("Open", action: onMessage)
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
    let onMessage: (CashRydrRequest, CashHubMessageMode, CashHubResponse?) -> Void
    let onFavorite: (CashHubResponse) -> Void
    let onViewFavoriteDriver: (CashHubFavoriteDriver) -> Void
    let onRemoveFavoriteDriver: (CashHubFavoriteDriver) -> Void
    let onBlockFavoriteDriver: (CashHubFavoriteDriver) -> Void
    let onBlockOfferDriver: (CashHubResponse) -> Void
    let onReportOfferDriver: (CashHubResponse, CashRydrRequest) -> Void
    let onAcceptOffer: (CashHubResponse, CashRydrRequest) -> Void
    let onDeclineOffer: (CashHubResponse, CashRydrRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var requestPendingDeletion: CashRydrRequest?

    private var title: String {
        switch panel {
        case .requests: return "My Requests"
        case .offers: return "Driver Offers"
        case .messages: return "Trip Chats"
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
                                        Text("Offers closed")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Button("Edit") { onEdit(request) }.buttonStyle(.bordered)
                                        Button("Offer Conversation") {
                                            onMessage(request, .requestThread, (responses[request.id] ?? []).first)
                                        }.buttonStyle(.bordered)
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
                                    onMessage: { onMessage(request, request.isConnected ? .directConnection : .requestThread, offer) },
                                    onFavorite: { onFavorite(offer) },
                                    onReport: { onReportOfferDriver(offer, request) },
                                    onBlock: { onBlockOfferDriver(offer) },
                                    onAccept: { onAcceptOffer(offer, request) },
                                    onDecline: { onDeclineOffer(offer, request) }
                                )
                            }
                        }
                    case .messages:
                        ForEach(connectedRequests) { request in
                            let conversations = responses[request.id] ?? []
                            if !conversations.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(request.pickup) to \(request.destination)").font(.headline)
                                    ForEach(conversations.prefix(3)) { response in
                                        Text("\(response.authorName): \(response.message.isEmpty ? "Conversation open" : response.message)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Button("Open Trip Chat") { onMessage(request, .directConnection, conversations.first) }
                                        .buttonStyle(.bordered)
                                }
                                .cashHubCard()
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(request.pickup) to \(request.destination)").font(.headline)
                                    Text("No trip chat messages yet.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Button("Open Trip Chat") { onMessage(request, .directConnection, (responses[request.id] ?? []).first) }
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
                    Text("This removes the request from My Posts. The driver can still complete the agreed listing, and its history will remain in Activity.")
                } else if requestPendingDeletion?.status == "completed" {
                    Text("This removes the request from My Posts. Its completed listing history will remain in Activity.")
                } else {
                    Text("This cancels and removes your request from My Posts.")
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
    let onReport: () -> Void
    let onBlock: () -> Void
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
            if !offer.message.isEmpty {
                Text(offer.message).font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Button(isConnected ? "Trip Chat" : "Open", action: onMessage).buttonStyle(.bordered)
                Button("Favorite", action: onFavorite).buttonStyle(.bordered)
                Button(offer.status == "declined" ? "Declined" : "Accept Offer", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isConnected || offer.status == "declined")
                Button("Decline", action: onDecline)
                    .buttonStyle(.bordered)
                    .disabled(isConnected || offer.status == "declined")
                Menu {
                    Button("Report Driver", role: .destructive, action: onReport)
                    Button("Block Driver", role: .destructive, action: onBlock)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
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
    let onReportProblem: () -> Void
    let onReportDriver: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    connectionHero
                    driverCard
                    tripCard
                    connectionNotice

                    Button {
                        onMessage()
                    } label: {
                        Label("Open trip chat", systemImage: "bubble.left.fill")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Capsule().fill(Styles.rydrGradient))
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Connection confirmed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.headline.weight(.bold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive, action: onCancel) {
                            Label("Cancel Listing", systemImage: "xmark.circle")
                        }
                        Button(action: onReportProblem) {
                            Label("Report a Problem", systemImage: "exclamationmark.bubble")
                        }
                        Button(role: .destructive, action: onReportDriver) {
                            Label("Report Driver", systemImage: "person.crop.circle.badge.exclamationmark")
                        }
                        .disabled(offer == nil)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title2.weight(.black))
                            .frame(width: 44, height: 44)
                    }
                }
            }
        }
    }

    private var connectionHero: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.green.opacity(0.16)).frame(width: 92, height: 92)
                Circle().fill(Color.green).frame(width: 68, height: 68)
                Image(systemName: "checkmark").font(.system(size: 34, weight: .black)).foregroundStyle(.white)
            }
            Text("You’re Connected")
                .font(.largeTitle.weight(.black))
            Text("\(driverName) accepted your CashRydr Trip Post.")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Label("SCHEDULED", systemImage: "calendar")
                .font(.caption.weight(.black))
                .foregroundStyle(.red)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.red.opacity(0.10)))
        }
        .padding(.vertical, 6)
    }

    private var driverCard: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Styles.rydrGradient)
                .frame(width: 72, height: 72)
                .overlay(Text(initials).font(.title2.weight(.black)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(driverName).font(.title3.weight(.black))
                    if offer?.isRydrVerifiedDriver == true {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue)
                    }
                }
                if let rating = offer?.cashHubRating {
                    Label(String(format: "%.1f Cash Hub rating", rating), systemImage: "star.fill")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let vehicle = offer?.vehicleInfo, !vehicle.isEmpty {
                    Label(vehicle, systemImage: "car.side.fill")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button(action: onMessage) {
                VStack(spacing: 5) {
                    Image(systemName: "bubble.left.fill").font(.title3)
                        .frame(width: 48, height: 48).background(Circle().fill(Color.red.opacity(0.09)))
                    Text("Chat").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .cashHubPremiumCard()
    }

    private var tripCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your trip").font(.title2.weight(.black))
            CashHubConnectedRoutePreview(pickup: request.pickup, destination: request.destination)
            connectedAddress(request.pickup, icon: "mappin.circle.fill", color: .green)
            connectedAddress(request.destination, icon: "mappin.circle.fill", color: .red)
            HStack(spacing: 8) {
                connectedPill(request.scheduledTime.formatted(date: .abbreviated, time: .shortened), icon: "calendar")
                connectedPill("\(request.passengers) rider\(request.passengers == 1 ? "" : "s")", icon: "person.2.fill")
            }
            Divider()
            HStack {
                Label("Agreed contribution", systemImage: "dollarsign.circle.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(agreedPriceText).font(.title2.weight(.black))
            }
        }
        .cashHubPremiumCard()
    }

    private var connectionNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled").font(.title).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("CashRydr Hub connection").font(.headline.weight(.bold))
                Text("This is a direct connection, not a Rydr-dispatched ride. Confirm pickup, payment, and trip details with \(driverName) in chat.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.blue.opacity(0.09)))
    }

    private func connectedAddress(_ value: String, icon: String, color: Color) -> some View {
        Label(value, systemImage: icon).font(.headline).foregroundStyle(.primary)
            .symbolRenderingMode(.palette).foregroundStyle(color, color.opacity(0.15))
    }

    private func connectedPill(_ value: String, icon: String) -> some View {
        Label(value, systemImage: icon)
            .font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.75)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 11).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var driverName: String { request.connectedDriverName ?? offer?.authorName ?? "Your driver" }
    private var initials: String {
        driverName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
    private var agreedPriceText: String {
        if let price = request.agreedPrice { return price.formatted(.currency(code: "USD")) }
        return request.budgetRange.isEmpty ? "Cash" : request.budgetRange
    }
}

private struct CashHubConnectedRoutePreview: View {
    let pickup: String
    let destination: String
    @State private var position: MapCameraPosition = .automatic
    @State private var start: CLLocationCoordinate2D?
    @State private var end: CLLocationCoordinate2D?
    @State private var route: MKRoute?

    var body: some View {
        Map(position: $position, interactionModes: []) {
            if let start { Marker("Pickup", coordinate: start).tint(.green) }
            if let end { Marker("Drop-off", coordinate: end).tint(.red) }
            if let route { MapPolyline(route.polyline).stroke(Styles.rydrGradient, lineWidth: 5) }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .task(id: pickup + destination) { await resolveRoute() }
    }

    private func resolveRoute() async {
        guard let startItem = try? await MKLocalSearch(request: searchRequest(pickup)).start().mapItems.first,
              let endItem = try? await MKLocalSearch(request: searchRequest(destination)).start().mapItems.first else { return }
        let request = MKDirections.Request()
        request.source = startItem
        request.destination = endItem
        request.transportType = .automobile
        guard let response = try? await MKDirections(request: request).calculate(), let resolved = response.routes.first else { return }
        start = startItem.placemark.coordinate
        end = endItem.placemark.coordinate
        route = resolved
        position = .rect(resolved.polyline.boundingMapRect.insetBy(dx: -resolved.polyline.boundingMapRect.width * 0.12, dy: -resolved.polyline.boundingMapRect.height * 0.25))
    }

    private func searchRequest(_ query: String) -> MKLocalSearch.Request {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        return request
    }
}

private struct CashHubRequestForm: View {
    private enum SuggestedPricing {
        static let perMile = 0.90
        static let perMinute = 0.28
    }

    let title: String
    var initialDraft = CashHubRequestDraft()
    var onSave: (CashHubRequestDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CashHubRequestDraft
    @State private var minimumScheduledTime: Date
    @StateObject private var pickupCompleter = SearchCompleter()
    @StateObject private var destinationCompleter = SearchCompleter()
    @StateObject private var locationManager = LocationManager()
    @FocusState private var focusedAddressField: AddressField?
    @State private var pickupMapItem: MKMapItem?
    @State private var destinationMapItem: MKMapItem?
    @State private var route: MKRoute?
    @State private var returnRoute: MKRoute?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isResolvingRoute = false
    @State private var routeMessage: String?
    @State private var lastSuggestedBudget: String?
    @State private var resolvedPickupText = ""
    @State private var resolvedDestinationText = ""

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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title == "Edit Ride Request" ? "Edit your post" : "Create a ride post")
                            .font(.largeTitle.weight(.black))
                        Text("Share your trip and connect with a driver traveling your route.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    routeCard
                    scheduleCard
                    passengerCard
                    visibilityCard
                    contributionCard
                    notesCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                minimumScheduledTime = CashHubScheduling.earliestRequestTime()
                if draft.scheduledTime < minimumScheduledTime {
                    draft.scheduledTime = minimumScheduledTime
                }
                if !draft.pickup.isEmpty && !draft.destination.isEmpty {
                    Task { await resolveInitialRoute() }
                }
            }
            .onChange(of: locationManager.lastLocation?.coordinate.latitude) { _, _ in
                guard pickupMapItem == nil, let location = locationManager.lastLocation else { return }
                Task { await useLocationAsPickup(location) }
            }
            .onChange(of: draft.tripFormat) { _, _ in
                Task { await calculateRoute() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .fontWeight(.bold)
                        .foregroundStyle(Color.red)
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        Image(systemName: "car.side.fill")
                            .foregroundStyle(Styles.rydrGradient)
                        Text("CashRydr Hub")
                            .font(.headline.weight(.black))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(title == "Edit Ride Request" ? "Save Changes" : "Submit Post") {
                    var submission = draft
                    if let coordinate = pickupMapItem?.placemark.coordinate {
                        submission.pickupLatitude = coordinate.latitude
                        submission.pickupLongitude = coordinate.longitude
                    }
                    if let coordinate = destinationMapItem?.placemark.coordinate {
                        submission.destinationLatitude = coordinate.latitude
                        submission.destinationLongitude = coordinate.longitude
                    }
                    onSave(submission)
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(Styles.rydrGradient))
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.45)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Where are you going?", systemImage: "mappin.and.ellipse")
                .font(.title3.weight(.black))

            pointAddressField(
                point: "A",
                color: .green,
                title: "Pickup location",
                text: $draft.pickup,
                field: .pickup,
                completer: pickupCompleter,
                showsCurrentLocation: true
            )
            addressSuggestions(for: pickupCompleter, field: .pickup)

            pointAddressField(
                point: "B",
                color: .red,
                title: "Destination",
                text: $draft.destination,
                field: .destination,
                completer: destinationCompleter,
                showsCurrentLocation: false
            )
            addressSuggestions(for: destinationCompleter, field: .destination)

            routeMap
            tripPreview
        }
        .cashHubPremiumCard()
    }

    private var routeMap: some View {
        Group {
            if let route {
                Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
                    if let coordinate = pickupMapItem?.placemark.coordinate {
                        Marker("Point A", systemImage: "a.circle.fill", coordinate: coordinate)
                            .tint(.green)
                    }
                    if let coordinate = destinationMapItem?.placemark.coordinate {
                        Marker("Point B", systemImage: "b.circle.fill", coordinate: coordinate)
                            .tint(.red)
                    }
                    MapPolyline(route.polyline)
                        .stroke(Styles.rydrGradient, lineWidth: 5)
                }
            } else {
                ZStack {
                    LinearGradient(colors: [Color.red.opacity(0.08), Color.gray.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 8) {
                        Image(systemName: isResolvingRoute ? "hourglass" : "map.fill")
                            .font(.title)
                            .foregroundStyle(Styles.rydrGradient)
                        Text(isResolvingRoute ? "Building trip preview…" : "Choose Point A and Point B to preview your trip")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.black.opacity(0.06)))
    }

    private var tripPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trip Preview")
                .font(.headline.weight(.black))
            HStack {
                previewMetric(value: distanceText, label: "Distance")
                Divider().frame(height: 38)
                previewMetric(value: durationText, label: "Est. time")
                Divider().frame(height: 38)
                previewMetric(value: suggestedPriceText, label: "Suggested")
            }
            if let routeMessage {
                Text(routeMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text(draft.tripFormat == "Round trip"
                     ? "Includes Point A → Point B → Point A at \(SuggestedPricing.perMile.formatted(.currency(code: "USD"))) per mile plus \(SuggestedPricing.perMinute.formatted(.currency(code: "USD"))) per minute."
                     : "Calculated from the live route at \(SuggestedPricing.perMile.formatted(.currency(code: "USD"))) per mile plus \(SuggestedPricing.perMinute.formatted(.currency(code: "USD"))) per minute.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("When are you leaving?", systemImage: "calendar.badge.clock")
                .font(.headline.weight(.black))
            HStack(spacing: 12) {
                DatePicker("Date", selection: $draft.scheduledTime, in: minimumScheduledTime..., displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                DatePicker("Time", selection: $draft.scheduledTime, in: minimumScheduledTime..., displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }
            Text("Schedule at least 2 hours in advance.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cashHubPremiumCard()
    }

    private var passengerCard: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Passengers", systemImage: "person.2.fill")
                    .font(.headline.weight(.black))
                Spacer()
                HStack(spacing: 18) {
                    Button { draft.passengers = max(1, draft.passengers - 1) } label: {
                        Image(systemName: "minus")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(draft.passengers == 1)
                    Text("\(draft.passengers)")
                        .font(.headline.monospacedDigit())
                        .frame(minWidth: 22)
                    Button { draft.passengers = min(12, draft.passengers + 1) } label: {
                        Image(systemName: "plus")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(draft.passengers == 12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
            }
            Picker("Trip format", selection: $draft.tripFormat) {
                Text("One way").tag("One-way")
                Text("Round trip").tag("Round trip")
            }
            .pickerStyle(.segmented)
        }
        .cashHubPremiumCard()
    }

    private var visibilityCard: some View {
        Menu {
            ForEach(CashHubVisibility.allCases) { option in
                Button {
                    draft.visibility = option.rawValue
                } label: {
                    Label(option.rawValue, systemImage: option.rawValue == draft.visibility ? "checkmark" : "circle")
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.3.fill")
                    .font(.title3)
                    .foregroundStyle(Styles.rydrGradient)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Visibility")
                        .font(.headline.weight(.black))
                    Text(CashHubVisibility.normalized(draft.visibility).explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Text(visibilityShortLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .cashHubPremiumCard()
    }

    private var contributionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Suggested shared contribution", systemImage: "dollarsign.circle.fill")
                .font(.headline.weight(.black))
            HStack(spacing: 4) {
                Text("$")
                    .font(.headline.weight(.bold))
                TextField("Enter an amount", text: Binding(
                    get: { draft.budgetRange },
                    set: { draft.budgetRange = cashHubCurrencyInput($0) }
                ))
                .keyboardType(.decimalPad)
                .font(.headline.weight(.semibold))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
            Text("Optional — drivers may propose a different amount.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cashHubPremiumCard()
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Luggage or special notes", systemImage: "note.text")
                .font(.headline.weight(.black))
            TextField("Add luggage, stops, accessibility needs, or other details", text: $draft.notes, axis: .vertical)
                .lineLimit(4, reservesSpace: true)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        }
        .cashHubPremiumCard()
    }

    private var canSubmit: Bool {
        !draft.pickup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && CashHubScheduling.isAllowed(draft.scheduledTime)
    }

    private var distanceText: String {
        guard route != nil else { return "—" }
        return String(format: "%.1f mi", totalRouteDistance / 1609.344)
    }

    private var durationText: String {
        guard route != nil else { return "—" }
        return "\(Int((totalRouteDuration / 60).rounded())) min"
    }

    private var suggestedPriceText: String {
        guard let suggestedAmount else { return "—" }
        return suggestedAmount.formatted(.currency(code: "USD"))
    }

    private var suggestedAmount: Double? {
        guard route != nil else { return nil }
        let miles = totalRouteDistance / 1609.344
        let minutes = totalRouteDuration / 60
        return ((miles * SuggestedPricing.perMile + minutes * SuggestedPricing.perMinute) * 100).rounded() / 100
    }

    private var totalRouteDistance: CLLocationDistance {
        (route?.distance ?? 0) + (draft.tripFormat == "Round trip" ? returnRoute?.distance ?? 0 : 0)
    }

    private var totalRouteDuration: TimeInterval {
        (route?.expectedTravelTime ?? 0) + (draft.tripFormat == "Round trip" ? returnRoute?.expectedTravelTime ?? 0 : 0)
    }

    private var visibilityShortLabel: String {
        CashHubVisibility.normalized(draft.visibility) == .publicCommunity ? "Public" : "Favorites"
    }

    private func previewMetric(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.weight(.black))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func pointAddressField(
        point: String,
        color: Color,
        title: String,
        text: Binding<String>,
        field: AddressField,
        completer: SearchCompleter,
        showsCurrentLocation: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Text(point)
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(color))
            TextField(title, text: text)
                .textContentType(.fullStreetAddress)
                .textInputAutocapitalization(.words)
                .focused($focusedAddressField, equals: field)
                .onChange(of: text.wrappedValue) { _, value in
                    completer.setQuery(value)
                    if field == .pickup, value != resolvedPickupText {
                        pickupMapItem = nil
                        invalidateRouteSuggestion()
                    } else if field == .destination, value != resolvedDestinationText {
                        destinationMapItem = nil
                        invalidateRouteSuggestion()
                    }
                }
            if showsCurrentLocation {
                Button {
                    if let location = locationManager.lastLocation {
                        Task { await useLocationAsPickup(location) }
                    } else {
                        locationManager.requestIfNeeded()
                    }
                } label: {
                    Image(systemName: "location.fill")
                        .foregroundStyle(Color.red)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.red.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    @ViewBuilder
    private func addressSuggestions(for completer: SearchCompleter, field: AddressField) -> some View {
        if focusedAddressField == field && !addressText(for: field).isEmpty {
            ForEach(Array(completer.results.prefix(5)).indices, id: \.self) { index in
                let result = completer.results[index]
                Button {
                    Task { await selectAddress(result, for: field) }
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
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
        }
    }

    private func addressText(for field: AddressField) -> String {
        switch field {
        case .pickup: return draft.pickup
        case .destination: return draft.destination
        }
    }

    private func selectAddress(_ completion: MKLocalSearchCompletion, for field: AddressField) async {
        do {
            let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
            guard let mapItem = response.mapItems.first else { return }
            let fullAddress = completion.title + (completion.subtitle.isEmpty ? "" : ", \(completion.subtitle)")
            switch field {
            case .pickup:
                resolvedPickupText = fullAddress
                draft.pickup = fullAddress
                pickupMapItem = mapItem
                pickupCompleter.setQuery("")
            case .destination:
                resolvedDestinationText = fullAddress
                draft.destination = fullAddress
                destinationMapItem = mapItem
                destinationCompleter.setQuery("")
            }
            focusedAddressField = nil
            await calculateRoute()
        } catch {
            routeMessage = "That location could not be resolved. Choose another search result."
        }
    }

    private func resolveInitialRoute() async {
        pickupMapItem = await searchMapItem(for: draft.pickup)
        destinationMapItem = await searchMapItem(for: draft.destination)
        resolvedPickupText = draft.pickup
        resolvedDestinationText = draft.destination
        await calculateRoute()
    }

    private func searchMapItem(for query: String) async -> MKMapItem? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        return try? await MKLocalSearch(request: request).start().mapItems.first
    }

    private func calculateRoute() async {
        guard let pickupMapItem, let destinationMapItem else { return }
        isResolvingRoute = true
        routeMessage = nil
        let request = MKDirections.Request()
        request.source = pickupMapItem
        request.destination = destinationMapItem
        request.transportType = .automobile
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let resolvedRoute = response.routes.first else {
                routeMessage = "No driving route was found for these locations."
                isResolvingRoute = false
                return
            }
            route = resolvedRoute
            if draft.tripFormat == "Round trip" {
                let returnRequest = MKDirections.Request()
                returnRequest.source = destinationMapItem
                returnRequest.destination = pickupMapItem
                returnRequest.transportType = .automobile
                guard let resolvedReturnRoute = try await MKDirections(request: returnRequest).calculate().routes.first else {
                    throw CashHubRoutePreviewError.returnRouteUnavailable
                }
                returnRoute = resolvedReturnRoute
            } else {
                returnRoute = nil
            }
            mapPosition = .rect(resolvedRoute.polyline.boundingMapRect)
            applySuggestedContribution()
        } catch {
            route = nil
            returnRoute = nil
            routeMessage = "A driving route could not be calculated right now."
        }
        isResolvingRoute = false
    }

    private func applySuggestedContribution() {
        guard let suggestedAmount else { return }
        let suggestion = String(format: "%.2f", suggestedAmount)
        if draft.budgetRange.isEmpty || draft.budgetRange == lastSuggestedBudget {
            draft.budgetRange = suggestion
        }
        lastSuggestedBudget = suggestion
    }

    private func invalidateRouteSuggestion() {
        route = nil
        returnRoute = nil
        if draft.budgetRange == lastSuggestedBudget {
            draft.budgetRange = ""
        }
        lastSuggestedBudget = nil
    }

    private func useLocationAsPickup(_ location: CLLocation) async {
        do {
            let placemark = try await CLGeocoder().reverseGeocodeLocation(location).first
            let parts = [placemark?.name, placemark?.locality, placemark?.administrativeArea]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            let address = parts.joined(separator: ", ")
            resolvedPickupText = address
            draft.pickup = address
            pickupMapItem = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
            pickupCompleter.setQuery("")
            focusedAddressField = nil
            await calculateRoute()
        } catch {
            routeMessage = "Your current pickup location could not be resolved."
        }
    }
}

private enum CashHubRoutePreviewError: Error {
    case returnRouteUnavailable
}

private struct CashHubOfferForm: View {
    let request: CashRydrRequest
    var onSend: (CashHubOfferDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CashHubOfferDraft()

    private var hasValidAmount: Bool {
        let cleaned = draft.offerAmount
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Double(cleaned) else { return false }
        return amount > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Request") {
                    LabeledContent("Pickup", value: request.pickup)
                    LabeledContent("Destination", value: request.destination)
                }
                Section("Your Offer") {
                    TextField("Proposed price", text: $draft.offerAmount).keyboardType(.decimalPad)
                    TextField("Message (optional)", text: $draft.message, axis: .vertical)
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
                        .disabled(!hasValidAmount)
                }
            }
        }
    }
}

private struct CashHubMessageForm: View {
    let request: CashRydrRequest
    let mode: CashHubMessageMode
    let messages: [CashHubResponse]
    let conversation: CashHubResponse?
    var onSend: (String) -> Bool
    var onProposePrice: (String, String) -> Bool
    var onAccept: () -> Void
    var onDecline: () -> Void
    var onEndChat: () -> Void
    var onReportChat: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var confirmEndChat = false
    @State private var showPriceEditor = false
    @State private var priceDraft = ""
    @State private var priceMessage = ""

    private var canSend: Bool { conversation?.status != "ended" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tripSummary.padding(.horizontal).padding(.top, 10)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            Text("Today").font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
                            if messages.isEmpty {
                                Text(mode == .requestThread ? "The price conversation will appear here." : "Start coordinating the trip here.")
                                    .font(.subheadline).foregroundStyle(.secondary).padding(.top, 30)
                            } else {
                                ForEach(messages) { response in
                                    CashHubChatBubble(response: response).id(response.id)
                                }
                            }
                            if shouldShowPriceDecision { priceDecisionCard }
                            if isWaitingForPriceResponse {
                                Label("Waiting for the driver to respond to your price", systemImage: "clock")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
                            }
                            if conversation?.status == "ended" {
                                Text("Chat ended")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                if canSend { composer }
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 9) {
                        Circle().fill(Styles.rydrGradient).frame(width: 38, height: 38)
                            .overlay(Text(driverInitial).font(.headline.weight(.black)).foregroundStyle(.white))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(conversation?.authorName ?? "Cash Hub Driver").font(.headline.weight(.black))
                            HStack(spacing: 4) {
                                Circle().fill(.green).frame(width: 7, height: 7)
                                Text(request.isConnected ? "Connected" : "Price conversation")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        if canNegotiatePrice {
                            Button("Propose or Edit Price", systemImage: "dollarsign.arrow.circlepath") { beginPriceProposal() }
                        }
                        Button("End Chat", systemImage: "xmark.bubble", role: .destructive) { confirmEndChat = true }
                        Button("Report Chat", systemImage: "exclamationmark.bubble", role: .destructive, action: onReportChat)
                    } label: { Image(systemName: "ellipsis").font(.title3.weight(.black)) }
                }
            }
            .confirmationDialog("End this chat?", isPresented: $confirmEndChat, titleVisibility: .visible) {
                Button("End Chat", role: .destructive) { onEndChat(); dismiss() }
                Button("Keep Chat Open", role: .cancel) {}
            } message: {
                Text(request.isConnected ? "This closes messaging but does not cancel the connected listing." : "This closes the negotiation without accepting the price.")
            }
            .sheet(isPresented: $showPriceEditor) {
                CashHubPriceProposalEditor(
                    amount: $priceDraft,
                    message: $priceMessage,
                    recipientName: conversation?.authorName ?? "the driver"
                ) {
                    if onProposePrice(priceDraft, priceMessage) {
                        showPriceEditor = false
                        priceMessage = ""
                    }
                }
            }
        }
    }

    private var tripSummary: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("CashRydr Trip Post").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                Text(request.isConnected ? "CONNECTED" : "OPEN")
                    .font(.caption2.weight(.black)).foregroundStyle(request.isConnected ? .green : .red)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill((request.isConnected ? Color.green : Color.red).opacity(0.1)))
                Spacer()
            }
            Label(request.pickup, systemImage: "a.circle.fill").font(.subheadline.weight(.bold)).foregroundStyle(.green)
            Label(request.destination, systemImage: "b.circle.fill").font(.subheadline.weight(.bold)).foregroundStyle(.red)
            Divider()
            HStack {
                Label(request.scheduledTime.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                Spacer()
                Label("\(request.passengers) rider\(request.passengers == 1 ? "" : "s")", systemImage: "person")
                Spacer()
                Text(priceSummary).font(.caption.weight(.black)).foregroundStyle(.red)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(15)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message \(conversation?.authorName ?? "driver")…", text: $message, axis: .vertical)
                .lineLimit(1...4).padding(.horizontal, 15).padding(.vertical, 11)
                .background(Capsule().stroke(Color.secondary.opacity(0.3)))
            Button {
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if onSend(trimmed) { message = "" }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).foregroundStyle(Styles.rydrGradient)
            }
            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal).padding(.vertical, 10).background(.ultraThinMaterial)
    }

    private var priceDecisionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("New price proposed", systemImage: "dollarsign.circle.fill").font(.headline.weight(.black)).foregroundStyle(.red)
            if let amount = unresolvedPriceProposal?.offerAmount {
                Text(amount.formatted(.currency(code: "USD"))).font(.title3.weight(.black))
            }
            HStack {
                Button("Decline", action: onDecline).buttonStyle(.bordered).tint(.red)
                Button("Accept Price") { onAccept(); dismiss() }.buttonStyle(.borderedProminent).tint(.green)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.green.opacity(0.08)))
    }

    private var shouldShowPriceDecision: Bool {
        mode == .requestThread && !request.isConnected && unresolvedPriceProposal?.authorUid != Auth.auth().currentUser?.uid
    }
    private var isWaitingForPriceResponse: Bool {
        mode == .requestThread && !request.isConnected && unresolvedPriceProposal?.authorUid == Auth.auth().currentUser?.uid
    }
    private var canNegotiatePrice: Bool {
        mode == .requestThread
            && !request.isConnected
            && canSend
            && ["pending", "negotiating"].contains(conversation?.status ?? "")
    }
    private var unresolvedPriceProposal: CashHubResponse? {
        for response in messages.sorted(by: { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }) {
            if ["priceAccepted", "offerDeclined"].contains(response.kind) { return nil }
            if ["offer", "priceProposal"].contains(response.kind), response.offerAmount != nil { return response }
        }
        return nil
    }
    private func beginPriceProposal() {
        if let amount = unresolvedPriceProposal?.offerAmount ?? conversation?.offerAmount {
            priceDraft = String(format: "%.2f", amount)
        }
        showPriceEditor = true
    }
    private var driverInitial: String { String((conversation?.authorName ?? "D").prefix(1)).uppercased() }
    private var priceSummary: String {
        if let agreedPrice = request.agreedPrice { return agreedPrice.formatted(.currency(code: "USD")) }
        if let amount = conversation?.offerAmount { return "\(amount.formatted(.currency(code: "USD"))) proposed" }
        guard !request.budgetRange.isEmpty else { return "Open price" }
        return request.budgetRange.hasPrefix("$") ? request.budgetRange : "$\(request.budgetRange)"
    }
}

private struct CashHubPriceProposalEditor: View {
    @Binding var amount: String
    @Binding var message: String
    let recipientName: String
    let onSend: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        let cleaned = amount.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (Double(cleaned) ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Proposed price") {
                    TextField("$0.00", text: $amount).keyboardType(.decimalPad)
                }
                Section("Optional note") {
                    TextField("Add context for \(recipientName)", text: $message, axis: .vertical).lineLimit(3, reservesSpace: true)
                }
                Section {
                    Text("The other person will receive an Accept or Decline choice. Declining keeps this chat open so either of you can propose another price.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Propose a Price")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Send") { onSend() }.disabled(!isValid) }
            }
        }
    }
}

private struct CashHubChatBubble: View {
    let response: CashHubResponse
    private var isCurrentUser: Bool { response.authorUid == Auth.auth().currentUser?.uid }
    private var isSystem: Bool { response.authorRole == "system" }

    var body: some View {
        if isSystem {
            Text(response.message)
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                if isCurrentUser { Spacer(minLength: 44) }
                if !isCurrentUser {
                    Circle().fill(Color.gray.opacity(0.2)).frame(width: 30, height: 30)
                        .overlay(Text(String(response.authorName.prefix(1))).font(.caption.weight(.black)))
                }
                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                    if let amount = response.offerAmount {
                        Text("Price proposal · \(amount.formatted(.currency(code: "USD")))")
                            .font(.caption.weight(.black)).foregroundStyle(isCurrentUser ? .white.opacity(0.9) : .red)
                    }
                    if !response.message.isEmpty { Text(response.message).font(.body) }
                    if let createdAt = response.createdAt {
                        Text(createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2).foregroundStyle(isCurrentUser ? .white.opacity(0.8) : .secondary)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(isCurrentUser ? .white : .primary)
                .background(RoundedRectangle(cornerRadius: 20).fill(isCurrentUser ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color(.secondarySystemGroupedBackground))))
                if !isCurrentUser { Spacer(minLength: 44) }
            }
        }
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
