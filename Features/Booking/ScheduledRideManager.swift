//
//  ScheduledRideManager.swift
//  RydrPlayground
//
//  Owns Firestore reads/writes for the Scheduled Rides feature.
//
//  IMPORTANT (Acceptance Criteria): this manager NEVER writes lockedPriceCents,
//  assignedDriverId, or any status other than .cancelledByRider to
//  scheduledRideRequests, and NEVER writes to the offers subcollection. Those
//  are backend/driver-owned. Firestore Security Rules should enforce this
//  server-side as well — this file only guarantees the client doesn't attempt it.
//
//  CONTRACT STATUS (per Ashank, 8/10/26): the shared Firestore contract
//  between rider/driver/backend has NOT been published yet — he said he'd
//  try to have it done "by tomorrow." He told James to build the driver
//  side against mock data until then, same story applies here: there is no
//  real driver-side code yet to ever populate `offers`, so the live
//  Firestore path below has nothing to talk to right now.
//
//  → Set `useMockData = true` (default) to demo/test the full rider flow
//    with simulated offers and matches, no backend required.
//  → Once Ashank's contract lands, reconcile the field names in
//    ScheduledRide.swift against it, flip `useMockData = false`, and this
//    manager switches to real Firestore listeners with no call-site changes.
//

import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
final class ScheduledRideManager: ObservableObject {
    /// TODO: flip to false once Ashank's shared contract is published and
    /// the driver side is actually writing offers/assignments.
    static let useMockData = true

    private let db = Firestore.firestore()
    private var offersListener: ListenerRegistration?
    private var requestListener: ListenerRegistration?
    private var mockTask: Task<Void, Never>?

    // MARK: - Booking flow state (steps 2-3 in the sprint: mode + review)

    @Published var isSchedulingForLater = false
    @Published var selectedMode: ScheduledRideMode = .quickSchedule
    @Published var requestedPickupDate: Date = Date().addingTimeInterval(60 * 60) // default: 1 hour out

    // MARK: - Active request state (steps 4-5: offers + confirmation)

    @Published private(set) var activeRequest: ScheduledRideRequest?
    @Published private(set) var offers: [ScheduledDriverOffer] = []
    @Published private(set) var isLoadingOffers = false
    @Published var errorMessage: String?

    // MARK: - Validation

    /// Testing requirement: reject invalid/past times. Requires at least a
    /// short minimum lead time so a request isn't placed for "right now"
    /// through the scheduling flow (that's what the existing on-demand flow is for).
    static let minimumLeadTime: TimeInterval = 30 * 60   // 30 minutes
    static let maximumLeadTime: TimeInterval = 60 * 60 * 24 * 14 // 14 days

    func validate(date: Date, referenceNow: Date = Date()) -> String? {
        let lead = date.timeIntervalSince(referenceNow)
        if lead < Self.minimumLeadTime {
            return "Please choose a time at least 30 minutes from now."
        }
        if lead > Self.maximumLeadTime {
            return "Scheduled rides can only be booked up to 14 days in advance."
        }
        return nil
    }

    // MARK: - Quick Schedule price range (Section 1 of the review screen)

    /// Returns the low end (min driver rate) / high end (max driver rate)
    /// fare for the given ride type + estimate, using the same clamped rate
    /// bounds RideManager already applies to on-demand fares. The high end
    /// doubles as the "approved maximum" the rider is agreeing to.
    func priceRange(estimate: RideEstimate, rideType: String) -> (low: Double, high: Double) {
        let config = RideManager.pricingConfig(for: rideType)
        let lowDriver = Driver(
            id: "range-low", name: "", profileImage: nil, carImage: nil, carMakeModel: "",
            rating: 0, compliments: [], perMinute: config.minPerMinute, perMile: config.minPerMile,
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), score: 0
        )
        let highDriver = Driver(
            id: "range-high", name: "", profileImage: nil, carImage: nil, carMakeModel: "",
            rating: 0, compliments: [], perMinute: config.maxPerMinute, perMile: config.maxPerMile,
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), score: 0
        )
        let low = RideManager.fareBreakdown(estimate: estimate, with: lowDriver, rideType: rideType).finalRiderTotal
        let high = RideManager.fareBreakdown(estimate: estimate, with: highDriver, rideType: rideType).finalRiderTotal
        return (low, high)
    }

    // MARK: - Create request

    /// Writes only rider-allowed fields. `status` is always seeded as
    /// `.pendingOffers` — the rider app never sets any other status on create.
    func createRequest(
        pickup: String,
        dropoff: String,
        pickupCoordinate: CLLocationCoordinate2D?,
        dropoffCoordinate: CLLocationCoordinate2D?,
        rideType: String,
        estimate: RideEstimate,
        approvedMax: Double
    ) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw ScheduledRideError.notSignedIn
        }
        if let validationError = validate(date: requestedPickupDate) {
            throw ScheduledRideError.invalidTime(validationError)
        }

        let id = UUID().uuidString

        if Self.useMockData {
            activeRequest = ScheduledRideRequest(
                id: id,
                riderId: user.uid,
                pickup: pickup,
                dropoff: dropoff,
                pickupCoordinate: pickupCoordinate,
                dropoffCoordinate: dropoffCoordinate,
                rideType: rideType,
                mode: selectedMode,
                requestedPickupDate: requestedPickupDate,
                status: .pendingOffers,
                estimate: estimate,
                riderApprovedMaxCents: Int((approvedMax * 100).rounded()),
                lockedPriceCents: nil,
                assignedDriverId: nil,
                createdAt: Date()
            )
            offers = []
            startMockProgression(requestId: id, estimate: estimate, rideType: rideType, approvedMax: approvedMax)
            return id
        }

        var payload: [String: Any] = [
            "id": id,
            "riderId": user.uid,
            "pickup": pickup,
            "dropoff": dropoff,
            "rideType": rideType,
            "mode": selectedMode.rawValue,
            "requestedPickupDate": Timestamp(date: requestedPickupDate),
            "status": ScheduledRideStatus.pendingOffers.rawValue,
            "estimatedDistanceMiles": estimate.distanceMiles,
            "estimatedDurationMinutes": estimate.durationMinutes,
            "riderApprovedMaxCents": Int((approvedMax * 100).rounded()),
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let pickupCoordinate {
            payload["pickupCoordinate"] = ["lat": pickupCoordinate.latitude, "lng": pickupCoordinate.longitude]
            payload["pickupGeoPoint"] = GeoPoint(latitude: pickupCoordinate.latitude, longitude: pickupCoordinate.longitude)
        }
        if let dropoffCoordinate {
            payload["dropoffCoordinate"] = ["lat": dropoffCoordinate.latitude, "lng": dropoffCoordinate.longitude]
            payload["dropoffGeoPoint"] = GeoPoint(latitude: dropoffCoordinate.latitude, longitude: dropoffCoordinate.longitude)
        }

        try await db.collection("scheduledRideRequests").document(id).setData(payload)
        listen(toRequestId: id)
        return id
    }

    // MARK: - Mock data mode (Ashank, 8/10/26: build against mock data until
    // the shared contract + driver side exist. Simulates 1-3 offers trickling
    // in for Choose My Driver, or a direct auto-match for Quick Schedule, so
    // the full rider flow is demoable end-to-end today.)

    private func startMockProgression(requestId: String, estimate: RideEstimate, rideType: String, approvedMax: Double) {
        mockTask?.cancel()
        mockTask = Task { [weak self] in
            guard let self else { return }
            let names = ["Marcus", "Priya", "Jordan"]
            let cars = ["Toyota Camry", "Honda Accord", "Tesla Model 3"]

            if self.selectedMode == .quickSchedule {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, self.activeRequest?.id == requestId else { return }
                let lockedPrice = approvedMax * Double.random(in: 0.7...0.95)
                self.activeRequest?.status = .priceLocked
                self.activeRequest?.lockedPriceCents = Int((lockedPrice * 100).rounded())
                self.activeRequest?.assignedDriverId = "mock-driver-1"
            } else {
                self.isLoadingOffers = true
                let offerCount = Int.random(in: 1...3)
                for index in 0..<offerCount {
                    try? await Task.sleep(nanoseconds: UInt64(2_000_000_000 * (index + 1)))
                    guard !Task.isCancelled, self.activeRequest?.id == requestId else { return }
                    let lockedPrice = approvedMax * Double.random(in: 0.65...0.95)
                    let offer = ScheduledDriverOffer(
                        id: "mock-offer-\(index)",
                        driverId: "mock-driver-\(index)",
                        driverName: names[index % names.count],
                        driverProfileImage: nil,
                        carImage: nil,
                        carMakeModel: cars[index % cars.count],
                        rating: Double.random(in: 4.6...5.0),
                        ratingCount: Int.random(in: 40...600),
                        perMile: RideManager.pricingConfig(for: rideType).clampedPerMile(Double.random(in: 0.6...1.4)),
                        perMinute: RideManager.pricingConfig(for: rideType).clampedPerMinute(Double.random(in: 0.15...0.4)),
                        lockedPriceCents: Int((lockedPrice * 100).rounded()),
                        offeredAt: Date()
                    )
                    self.offers.append(offer)
                    self.isLoadingOffers = false
                    if self.activeRequest?.status == .pendingOffers {
                        self.activeRequest?.status = .awaitingRiderChoice
                    }
                }
            }
        }
    }

    // MARK: - Listening

    func listen(toRequestId id: String) {
        // Mock mode: activeRequest/offers are already being driven by
        // startMockProgression() from createRequest(); nothing to attach to.
        if Self.useMockData {
            return
        }

        stopListening()
        isLoadingOffers = true

        requestListener = db.collection("scheduledRideRequests").document(id)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    self.errorMessage = "Couldn't load your scheduled ride: \(error.localizedDescription)"
                    return
                }
                guard let data = snapshot?.data() else { return }
                self.activeRequest = Self.parseRequest(id: id, data: data)
            }

        offersListener = db.collection("scheduledRideRequests").document(id).collection("offers")
            .order(by: "offeredAt", descending: false)
            .limit(to: 3)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                self.isLoadingOffers = false
                if let error {
                    self.errorMessage = "Couldn't load driver offers: \(error.localizedDescription)"
                    return
                }
                self.offers = snapshot?.documents.compactMap(Self.parseOffer) ?? []
            }
    }

    func stopListening() {
        requestListener?.remove()
        offersListener?.remove()
        requestListener = nil
        offersListener = nil
        mockTask?.cancel()
        mockTask = nil
    }

    // MARK: - Rider actions (Choose My Driver)

    /// Rider selects one of the offered drivers. This does NOT lock the
    /// price or assign the driver directly — it records the rider's choice
    /// as a request; the backend/driver side is responsible for confirming
    /// the assignment and writing `assignedDriverId` / `lockedPriceCents`.
    func selectOffer(_ offer: ScheduledDriverOffer, on requestId: String) async throws {
        if Self.useMockData {
            activeRequest?.status = .confirmed
            activeRequest?.lockedPriceCents = offer.lockedPriceCents
            activeRequest?.assignedDriverId = offer.driverId
            return
        }
        try await db.collection("scheduledRideRequests").document(requestId).updateData([
            "riderSelectedOfferId": offer.id,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Cancel (the one status the rider app IS allowed to write)

    func cancelRequest(_ requestId: String) async throws {
        if Self.useMockData {
            mockTask?.cancel()
            activeRequest?.status = .cancelledByRider
            return
        }
        try await db.collection("scheduledRideRequests").document(requestId).updateData([
            "status": ScheduledRideStatus.cancelledByRider.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Parsing

    private static func parseRequest(id: String, data: [String: Any]) -> ScheduledRideRequest? {
        guard
            let riderId = data["riderId"] as? String,
            let pickup = data["pickup"] as? String,
            let dropoff = data["dropoff"] as? String,
            let rideType = data["rideType"] as? String,
            let modeRaw = data["mode"] as? String,
            let mode = ScheduledRideMode(rawValue: modeRaw),
            let statusRaw = data["status"] as? String,
            let status = ScheduledRideStatus(rawValue: statusRaw),
            let approvedMaxCents = data["riderApprovedMaxCents"] as? Int
        else { return nil }

        let requestedDate = (data["requestedPickupDate"] as? Timestamp)?.dateValue() ?? Date()
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let distanceMiles = data["estimatedDistanceMiles"] as? Double ?? 0
        let durationMinutes = data["estimatedDurationMinutes"] as? Double ?? 0

        return ScheduledRideRequest(
            id: id,
            riderId: riderId,
            pickup: pickup,
            dropoff: dropoff,
            pickupCoordinate: coordinate(from: data["pickupCoordinate"]),
            dropoffCoordinate: coordinate(from: data["dropoffCoordinate"]),
            rideType: rideType,
            mode: mode,
            requestedPickupDate: requestedDate,
            status: status,
            estimate: RideEstimate(distanceMiles: distanceMiles, durationMinutes: durationMinutes),
            riderApprovedMaxCents: approvedMaxCents,
            lockedPriceCents: data["lockedPriceCents"] as? Int,
            assignedDriverId: data["assignedDriverId"] as? String,
            createdAt: createdAt
        )
    }

    private static func parseOffer(_ document: QueryDocumentSnapshot) -> ScheduledDriverOffer? {
        let data = document.data()
        guard
            let driverId = data["driverId"] as? String,
            let driverName = data["driverName"] as? String,
            let carMakeModel = data["carMakeModel"] as? String,
            let perMile = data["perMile"] as? Double,
            let perMinute = data["perMinute"] as? Double,
            let lockedPriceCents = data["lockedPriceCents"] as? Int
        else { return nil }

        return ScheduledDriverOffer(
            id: document.documentID,
            driverId: driverId,
            driverName: driverName,
            driverProfileImage: data["driverProfileImage"] as? String,
            carImage: data["carImage"] as? String,
            carMakeModel: carMakeModel,
            rating: data["rating"] as? Double ?? 0,
            ratingCount: data["ratingCount"] as? Int ?? 0,
            perMile: perMile,
            perMinute: perMinute,
            lockedPriceCents: lockedPriceCents,
            offeredAt: (data["offeredAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    private static func coordinate(from value: Any?) -> CLLocationCoordinate2D? {
        guard let data = value as? [String: Any],
              let lat = data["lat"] as? Double, let lng = data["lng"] as? Double else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

enum ScheduledRideError: LocalizedError {
    case notSignedIn
    case invalidTime(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in before scheduling a ride."
        case .invalidTime(let message): return message
        }
    }
}
