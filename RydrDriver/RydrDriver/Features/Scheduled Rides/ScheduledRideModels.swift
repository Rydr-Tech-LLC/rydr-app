//
//  ScheduledRideModels.swift
//  Rydr Driver
//
//  Driver-facing shapes for the Scheduled Rides Firestore documents (schema
//  version 1). Field names mirror the contract's own terms, so the decoders
//  are a direct mapping rather than a translation layer.
//

import Foundation
import CoreLocation
import FirebaseFirestore

enum ScheduledRideStatus: String {
    case seekingDrivers
    case awaitingRiderSelection
    case confirmed
    case checkInRequired
    case checkedIn
    case activating
    case active
    case completed
    case replacementSearching
    case replacementApprovalRequired
    case cancelled
    case expired
}

/// How the rider chose to fill this ride. Canonical values only — the legacy
/// `quickSchedule` / `chooseMyDriver` spellings are Rider-side.
///
/// Matters before the tap: `quick` means accepting gets you the ride,
/// `chooseDriver` means submitting one of up to three offers.
enum ScheduledRideSelectionMode: String {
    case quick
    case chooseDriver
}

/// The projection's own status values — separate from `ScheduledRideStatus`,
/// which tracks the request's lifecycle. Conflating them is the bug this type
/// prevents: querying the projection for `seekingDrivers` matches nothing.
///
/// Verified against Rydr_Firebase/functions/src/scheduledRides/service.ts.
enum ScheduledRideOpportunityStatus: String {
    /// Takeable.
    case open
    /// A driver was assigned (Quick Schedule) or the rider selected one.
    case assigned
    /// Choose My Driver reached its three-offer cap.
    case offerLimitReached
}

/// An unaccepted scheduled ride the driver could take — the approved-driver
/// "browse projection" (scheduledRideOpportunities), never the rider's exact
/// address per the contract's privacy boundary.
struct ScheduledRideOpportunity: Identifiable, Equatable {
    let id: String
    let rideType: String
    let pickupArea: String
    /// Rebuilt from `pickupLatitudeBucket` / `pickupLongitudeBucket` — two
    /// values rounded to ~1km, not a GeoPoint. The rounding is the privacy
    /// boundary: the neighbourhood, not the doorstep.
    let pickupCoordinate: CLLocationCoordinate2D
    /// The projection carries no destination today. Pending confirmation that
    /// a coarse area will be added; until then the card says so rather than
    /// inventing one.
    let destinationArea: String?
    let pickupTime: Date
    let estimatedTripMiles: Double?
    let estimatedTripMinutes: Double?
    let approvedMaximumCents: Int
    let currency: String
    let responseDeadline: Date
    /// Optional while the projection's contents are still being finalized
    /// backend-side. When absent the card uses neutral wording rather than
    /// guessing. Make it non-optional once confirmed.
    let selectionMode: ScheduledRideSelectionMode?

    var isExpired: Bool { Date() >= responseDeadline }

    var approvedMaximumDisplay: String {
        currencyFormatter.string(from: NSDecimalNumber(value: Double(approvedMaximumCents) / 100)) ?? "$0.00"
    }

    /// Fast local feedback only. `respondToScheduledRide` is the real
    /// authority and can still reject something this calls `.eligible`.
    func eligibility(against reservations: [ScheduledRideReservation]) -> ScheduledRideOpportunityEligibility {
        if isExpired { return .expired }

        let occupiedEnd = pickupTime.addingTimeInterval(
            (estimatedTripMinutes ?? Self.defaultTripMinutes) * 60
        )

        for reservation in reservations {
            let reservationEnd = reservation.pickupTime.addingTimeInterval(
                (reservation.estimatedTripMinutes ?? Self.defaultTripMinutes) * 60
            )
            let overlaps = pickupTime < reservationEnd && reservation.pickupTime < occupiedEnd
            if overlaps {
                return .conflicting(with: reservation)
            }
        }

        return .eligible
    }

    private static let defaultTripMinutes: Double = 30

    static func == (lhs: ScheduledRideOpportunity, rhs: ScheduledRideOpportunity) -> Bool {
        lhs.id == rhs.id
    }
}

enum ScheduledRideOpportunityEligibility: Equatable {
    case eligible
    case expired
    case conflicting(with: ScheduledRideReservation)
}

/// An already-accepted scheduled ride, shown in the driver's confirmed
/// reservations list. Denormalized rather than referencing its originating
/// opportunity — matches the contract's scheduledRideRequests being a
/// self-contained orchestration record.
struct ScheduledRideReservation: Identifiable, Equatable {
    let id: String
    let rideType: String
    let pickupArea: String
    /// The exact pickup point, not the opportunity's rounded one — the
    /// privacy boundary has passed once a ride is confirmed.
    let pickupCoordinate: CLLocationCoordinate2D
    let destinationArea: String
    let pickupTime: Date
    let estimatedTripMiles: Double?
    let estimatedTripMinutes: Double?
    /// The rider's locked base fare, and what this driver earns.
    ///
    /// Both `nil` out of the request document — neither lives there. They come
    /// from the driver's offer at `.../offers/{driverId}`, joined in by the
    /// view model. See `withMoney(from:)`.
    ///
    /// Optional rather than zero, so a reservation whose offer hasn't arrived
    /// doesn't advertise a $0.00 ride.
    let lockedBaseFareCents: Int?
    let driverPayoutCents: Int?
    let currency: String
    let status: ScheduledRideStatus
    let confirmedAt: Date
    let checkedInAt: Date?
    let pickupETAMinutes: Double?
    /// When the server hands this to standard dispatch:
    /// `max(server now, pickup − ETA − buffer)`. Displayed, never calculated —
    /// only Firebase knows its own clock.
    let activationAt: Date?

    var lockedBaseFareDisplay: String? {
        guard let lockedBaseFareCents else { return nil }
        return currencyFormatter.string(from: NSDecimalNumber(value: Double(lockedBaseFareCents) / 100))
    }

    /// `nil` when the projection didn't carry a payout. Callers must render
    /// nothing in that case — never substitute the rider fare.
    var driverPayoutDisplay: String? {
        guard let driverPayoutCents else { return nil }
        return currencyFormatter.string(from: NSDecimalNumber(value: Double(driverPayoutCents) / 100))
    }

    /// `pickup − driverCheckInLeadMinutes`. Derived locally until the backend
    /// stores a real `checkInOpensAt` — only the server knows whether config
    /// changed after this ride was confirmed.
    var checkInOpensAt: Date {
        pickupTime.addingTimeInterval(-ScheduledRideConfig.driverCheckInLeadMinutes * 60)
    }

    /// When it closes: lead minus grace, so 50 minutes before pickup.
    var checkInDeadlineAt: Date {
        pickupTime.addingTimeInterval(
            -(ScheduledRideConfig.driverCheckInLeadMinutes - ScheduledRideConfig.driverCheckInGraceMinutes) * 60
        )
    }

    /// A friendly sub-state derived from the canonical status plus the clock.
    /// Permitted by the contract; nothing here is persisted.
    ///
    /// Needed because `advanceScheduledRideDeadlines` runs only once a minute,
    /// so a reservation can still read `confirmed` while its check-in window
    /// is already open.
    func timing(now: Date = Date()) -> ScheduledRideReservationTiming {
        switch status {
        case .checkedIn, .activating, .active:
            return .checkedIn
        case .completed, .cancelled, .expired:
            return .closed
        default:
            break
        }

        if now < checkInOpensAt { return .upcoming }
        if now < checkInDeadlineAt { return .checkInOpen }
        if now < pickupTime { return .checkInMissed }
        // Pickup time has come and gone and the server never moved this on.
        return .stale
    }

    /// Firebase's real ETA-based activation math (scheduled pickup − travel
    /// ETA − configurable buffer) is deferred backend work per the contract.
    /// This just records what MapKit calculated at check-in time, matching
    /// the driver-side half of that pipeline this deliverable covers.
    func checkedIn(pickupETAMinutes: Double, at date: Date = Date(), activationAt: Date? = nil) -> ScheduledRideReservation {
        ScheduledRideReservation(
            id: id,
            rideType: rideType,
            pickupArea: pickupArea,
            pickupCoordinate: pickupCoordinate,
            destinationArea: destinationArea,
            pickupTime: pickupTime,
            estimatedTripMiles: estimatedTripMiles,
            estimatedTripMinutes: estimatedTripMinutes,
            lockedBaseFareCents: lockedBaseFareCents,
            driverPayoutCents: driverPayoutCents,
            currency: currency,
            status: .checkedIn,
            confirmedAt: confirmedAt,
            checkedInAt: date,
            pickupETAMinutes: pickupETAMinutes,
            activationAt: activationAt ?? self.activationAt
        )
    }

    /// A driver can only be checked in to one ride at a time. Distinct from
    /// the accept-time conflict check: two reservations whose windows don't
    /// overlap still collide here if the driver is already checked into one.
    func checkInEligibility(against reservations: [ScheduledRideReservation]) -> ScheduledRideCheckInEligibility {
        if let existing = reservations.first(where: { $0.id != id && $0.status == .checkedIn }) {
            return .blockedByExistingCheckIn(existing)
        }
        return .eligible
    }

    static func == (lhs: ScheduledRideReservation, rhs: ScheduledRideReservation) -> Bool {
        lhs.id == rhs.id
    }
}

/// Where a reservation sits relative to the clock. Derived, never persisted.
enum ScheduledRideReservationTiming: Equatable {
    /// Check-in hasn't opened yet.
    case upcoming
    /// Inside the approved check-in window.
    case checkInOpen
    /// Window closed without a check-in. The server's deadline job catches up
    /// shortly; until then the driver should know.
    case checkInMissed
    case checkedIn
    /// Pickup passed and nothing progressed. Not actionable, so it shouldn't
    /// sit in the list looking live.
    case stale
    /// Terminal per the canonical status.
    case closed
}

enum ScheduledRideCheckInEligibility: Equatable {
    case eligible
    case blockedByExistingCheckIn(ScheduledRideReservation)
}

// MARK: - Firestore decoding

/// Shared field readers for the scheduled-ride documents.
///
/// Firestore hands every value back as `Any?`, and numbers arrive as `Int`,
/// `Double`, or `NSNumber` depending on how the writer produced them, so each
/// numeric read has to tolerate all three. This is the same defensive shape
/// `DriverRideRequest.init(document:)` already uses for standard requests —
/// kept private here rather than shared, since that one bakes in
/// standard-request-specific fallbacks we don't want.
private enum ScheduledRideField {
    static func double(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let double = value as? Double { return Int(double) }
        return nil
    }

    /// The contract stores times as Firestore UTC timestamps, but callable
    /// responses use `...EpochMs` numbers. Accepting both means a document
    /// written from either side decodes the same way.
    static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let epochMs = double(value) { return Date(timeIntervalSince1970: epochMs / 1000) }
        return nil
    }

    static func coordinate(_ value: Any?) -> CLLocationCoordinate2D? {
        if let point = value as? GeoPoint {
            return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        }
        guard
            let map = value as? [String: Any],
            let latitude = double(map["latitude"] ?? map["lat"]),
            let longitude = double(map["longitude"] ?? map["lng"])
        else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension ScheduledRideOpportunity {
    /// Decodes one `scheduledRideOpportunities/{requestId}` document.
    ///
    /// Failable rather than defaulting: a missing rider area string can safely
    /// fall back to placeholder text, but a missing price, pickup time, or
    /// deadline cannot — defaulting those would put a wrong number or a wrong
    /// expiry in front of a driver. A `nil` here means "skip this document",
    /// and the listener's `compactMap` drops it rather than showing a
    /// half-decoded card.
    ///
    /// Field names verified against the backend's own write in
    /// `Rydr_Firebase/functions/src/scheduledRides/service.ts`, not inferred
    /// from the prose contracts.
    init?(document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        self.init(id: document.documentID, data: data)
    }

    /// The half with all the decisions in it.
    ///
    /// Split out from `init?(document:)` because `DocumentSnapshot` can only
    /// be produced by Firestore itself — which meant every field name here was
    /// unverifiable until it ran against a live backend. A plain dictionary
    /// makes the mapping testable, and the wrapper above keeps the call site
    /// unchanged.
    init?(id: String, data: [String: Any]) {
        guard
            let pickupTime = ScheduledRideField.date(data["scheduledAt"]),
            let responseDeadline = ScheduledRideField.date(data["offerClosesAt"]),
            let approvedMaximumCents = ScheduledRideField.int(data["approvedMaximumCents"]),
            // Two separate rounded numbers, not a GeoPoint or a nested map.
            let latitude = ScheduledRideField.double(data["pickupLatitudeBucket"]),
            let longitude = ScheduledRideField.double(data["pickupLongitudeBucket"])
        else { return nil }

        let routeEstimate = data["routeEstimate"] as? [String: Any]

        self.init(
            id: id,
            rideType: data["rideType"] as? String ?? "Rydr",
            pickupArea: data["pickupArea"] as? String ?? "Pickup area",
            pickupCoordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            destinationArea: data["destinationArea"] as? String,
            pickupTime: pickupTime,
            estimatedTripMiles: ScheduledRideField.double(routeEstimate?["distanceMiles"]),
            estimatedTripMinutes: ScheduledRideField.double(routeEstimate?["durationMinutes"]),
            approvedMaximumCents: approvedMaximumCents,
            currency: data["currency"] as? String ?? "USD",
            responseDeadline: responseDeadline,
            selectionMode: (data["selectionMode"] as? String)
                .flatMap(ScheduledRideSelectionMode.init(rawValue:))
        )
    }
}

extension ScheduledRideReservation {
    /// Decodes one `scheduledRideRequests/{requestId}` document that this
    /// driver is assigned to.
    ///
    /// Unlike the opportunity projection, this is the private orchestration
    /// record — it carries the exact pickup coordinate and the locked fare,
    /// which is why the reservation model has both and the opportunity model
    /// has neither.
    ///
    /// Note the unit change: the contract's check-in interface speaks in
    /// `pickupEtaSeconds`, while the Driver UI and MapKit estimate work in
    /// minutes. Converting here keeps that translation at the Firestore
    /// boundary instead of scattering `/ 60` through the view layer.
    /// Field names verified against the backend's own request write in
    /// `Rydr_Firebase/functions/src/scheduledRides/service.ts`.
    init?(document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        self.init(id: document.documentID, data: data)
    }

    init?(id: String, data: [String: Any]) {
        let pickup = data["pickup"] as? [String: Any]
        guard
            let pickupTime = ScheduledRideField.date(data["scheduledAt"]),
            let status = (data["status"] as? String).flatMap(ScheduledRideStatus.init(rawValue:)),
            let confirmedAt = ScheduledRideField.date(data["confirmedAt"]),
            let pickupCoordinate = ScheduledRideField.coordinate(pickup ?? data["pickupCoordinate"])
        else { return nil }

        let routeEstimate = data["routeEstimate"] as? [String: Any]

        self.init(
            id: id,
            rideType: data["rideType"] as? String ?? "Rydr",
            pickupArea: pickup?["area"] as? String ?? "Pickup area",
            pickupCoordinate: pickupCoordinate,
            destinationArea: (data["destination"] as? [String: Any])?["area"] as? String ?? "Drop-off area",
            pickupTime: pickupTime,
            estimatedTripMiles: ScheduledRideField.double(routeEstimate?["distanceMiles"]),
            estimatedTripMinutes: ScheduledRideField.double(routeEstimate?["durationMinutes"]),
            // Deliberately absent: the request document carries no money.
            // Both are filled in from the driver's offer — see withMoney(from:).
            lockedBaseFareCents: nil,
            driverPayoutCents: nil,
            currency: data["currency"] as? String ?? "USD",
            status: status,
            confirmedAt: confirmedAt,
            checkedInAt: ScheduledRideField.date(data["checkedInAt"]),
            pickupETAMinutes: ScheduledRideField.double(data["pickupEtaSeconds"]).map { $0 / 60 },
            activationAt: ScheduledRideField.date(data["activationAt"])
        )
    }
}

// MARK: - Driver quote

/// The server's answer to `previewScheduledRideDriverQuote` — the exact money
/// this driver would earn, plus the fingerprint that binds it.
///
/// The fingerprint is the whole point of the two-step accept. It encodes the
/// request, driver, price, rates, pricing version, and expiry, and
/// `respondToScheduledRide` recomputes the quote inside its assignment
/// transaction. If anything moved in between, the fingerprint no longer
/// matches and the server refuses with `QUOTE_CHANGED` — so a driver can never
/// be assigned at a price they were not shown.
///
/// Note which number is which. `driverPayoutCents` is the only figure that may
/// be presented as earnings; the contract is explicit that
/// `approvedMaximumCents` and `lockedBaseFareCents` are not driver payout.
/// `exactBaseFareCents` is carried because the contract lists it as trip
/// context for the selected driver, not because it belongs in the fare hero.
struct ScheduledRideDriverQuote: Equatable {
    let requestId: String
    let quoteFingerprint: String
    let exactBaseFareCents: Int
    let driverPayoutCents: Int
    let currency: String
    let pricingVersion: String
    let expiresAt: Date

    /// Valid for five minutes or until the opportunity closes, whichever comes
    /// first. We can only observe the first of those locally, which is why a
    /// locally-fresh quote can still be rejected server-side.
    var isExpired: Bool { Date() >= expiresAt }

    var driverPayoutDisplay: String {
        currencyFormatter.string(from: NSDecimalNumber(value: Double(driverPayoutCents) / 100)) ?? "$0.00"
    }

    /// Decodes the callable's success payload (`result.data`).
    ///
    /// Failable for the same reason the Firestore initializers are: there is
    /// no safe default for a payout or a fingerprint. A quote we cannot fully
    /// decode must not become a card offering an invented number.
    init?(callableResponse data: [String: Any]) {
        guard
            let requestId = data["requestId"] as? String,
            let quoteFingerprint = data["quoteFingerprint"] as? String,
            let exactBaseFareCents = ScheduledRideField.int(data["exactBaseFareCents"]),
            let driverPayoutCents = ScheduledRideField.int(data["driverPayoutCents"]),
            let expiresAt = ScheduledRideField.date(data["expiresAtEpochMs"])
        else { return nil }

        self.requestId = requestId
        self.quoteFingerprint = quoteFingerprint
        self.exactBaseFareCents = exactBaseFareCents
        self.driverPayoutCents = driverPayoutCents
        self.currency = data["currency"] as? String ?? "USD"
        self.pricingVersion = data["pricingVersion"] as? String ?? "unknown"
        self.expiresAt = expiresAt
    }

    init(
        requestId: String,
        quoteFingerprint: String,
        exactBaseFareCents: Int,
        driverPayoutCents: Int,
        currency: String = "USD",
        pricingVersion: String = "scheduled-rides-v1",
        expiresAt: Date
    ) {
        self.requestId = requestId
        self.quoteFingerprint = quoteFingerprint
        self.exactBaseFareCents = exactBaseFareCents
        self.driverPayoutCents = driverPayoutCents
        self.currency = currency
        self.pricingVersion = pricingVersion
        self.expiresAt = expiresAt
    }
}

// MARK: - Check-in

/// What `checkInScheduledRide` returns.
///
/// The activation time is the important half. Firebase computes it as
/// `max(server now, scheduled pickup − pickup ETA − activation buffer)` and
/// the client only ever displays it — the formula depends on the server's own
/// clock, so recomputing it locally would produce a number that drifts from
/// the one activation actually uses.
struct ScheduledRideCheckInReceipt: Equatable {
    let activationAt: Date
    /// The ETA the server accepted, which may be rounded from what we sent.
    /// Displaying the accepted value rather than our submitted one keeps the
    /// screen consistent with what activation will actually use.
    let acceptedEtaSeconds: Double

    var acceptedEtaMinutes: Double { acceptedEtaSeconds / 60 }

    init?(callableResponse data: [String: Any]) {
        guard let activationAt = ScheduledRideField.date(data["activationAtEpochMs"]) else { return nil }
        self.activationAt = activationAt
        self.acceptedEtaSeconds = ScheduledRideField.double(data["pickupEtaSeconds"]) ?? 0
    }

    init(activationAt: Date, acceptedEtaSeconds: Double) {
        self.activationAt = activationAt
        self.acceptedEtaSeconds = acceptedEtaSeconds
    }
}

/// Why a check-in never reached the server.
///
/// Distinct from `ScheduledRideCallableError`, which describes failures the
/// *server* reported. Everything here happens on the device, before any call
/// is made, and each case has a different fix the driver can actually act on —
/// which is why they are cases rather than one generic message.
enum ScheduledRideCheckInPreflightError: LocalizedError, Equatable {
    /// No usable fix — Location Services denied, or nothing acquired yet.
    case locationUnavailable
    /// A fix exists but is too coarse to build a driving ETA from.
    case locationTooInaccurate
    /// MapKit could not return a route (no connectivity, no drivable path).
    case routeUnavailable
    /// The window closed while the driver was on this screen.
    case windowNotOpen

    var errorDescription: String? {
        switch self {
        case .locationUnavailable:
            return "Rydr needs your location to check in. Turn on Location Services and try again."
        case .locationTooInaccurate:
            return "Your location isn't precise enough yet. Move somewhere with a clearer view of the sky and try again."
        case .routeUnavailable:
            return "Couldn't find a route to the pickup. Check your connection and try again."
        case .windowNotOpen:
            return "Check-in isn't open for this ride yet."
        }
    }
}

// MARK: - Driver offer

/// The driver's own offer at `scheduledRideRequests/{requestId}/offers/{driverId}`.
///
/// This is where driver-specific money lives, and it is the right place for it:
/// the document ID *is* the driver ID, so Security Rules scope it to one driver
/// without a query filter. Denormalising `driverPayoutCents` onto the request
/// would expose driver pay to the rider, which the money table forbids.
///
/// It also outlives its usefulness as money: an offer with `status == .active`
/// is the durable "the rider hasn't picked yet" state that Choose My Driver
/// needs, which the view model previously had to keep in memory.
struct ScheduledRideDriverOffer: Identifiable, Equatable {
    /// The request this offer belongs to — the join key onto a reservation.
    let requestId: String
    let status: ScheduledRideOfferStatus
    /// From the offer's embedded `quote`. The only figure presentable as
    /// driver earnings.
    let driverPayoutCents: Int?
    /// The rider's base fare for this driver. The money table lists it as
    /// visible to the "selected driver as trip context."
    let exactBaseFareCents: Int?
    let currency: String
    let expiresAt: Date?

    var id: String { requestId }

    init?(document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        self.init(data: data)
    }

    init?(data: [String: Any]) {
        guard let requestId = data["requestId"] as? String else { return nil }
        self.requestId = requestId
        self.status = (data["status"] as? String)
            .flatMap(ScheduledRideOfferStatus.init(rawValue:)) ?? .active
        // driverPayoutCents sits inside the offer's embedded server quote,
        // not at the top level.
        let quote = data["quote"] as? [String: Any]
        self.driverPayoutCents = ScheduledRideField.int(quote?["driverPayoutCents"])
        self.exactBaseFareCents = ScheduledRideField.int(data["exactBaseFareCents"])
            ?? ScheduledRideField.int(quote?["riderBaseFareCents"])
        self.currency = data["currency"] as? String ?? "USD"
        self.expiresAt = ScheduledRideField.date(data["expiresAt"])
    }

    init(
        requestId: String,
        status: ScheduledRideOfferStatus = .active,
        driverPayoutCents: Int? = nil,
        exactBaseFareCents: Int? = nil,
        currency: String = "USD",
        expiresAt: Date? = nil
    ) {
        self.requestId = requestId
        self.status = status
        self.driverPayoutCents = driverPayoutCents
        self.exactBaseFareCents = exactBaseFareCents
        self.currency = currency
        self.expiresAt = expiresAt
    }
}

/// Offer statuses, again a separate vocabulary from the request's.
/// Verified against the backend's offer writes.
enum ScheduledRideOfferStatus: String {
    /// Choose My Driver: submitted, rider has not chosen yet.
    case active
    /// Quick Schedule assigned immediately, or the rider picked this driver.
    case selected
}

extension ScheduledRideReservation {
    /// Returns a copy carrying the money from this driver's offer.
    ///
    /// The join Firestore can't do. Kept as "return a new value" rather than
    /// mutation so a reservation is still a snapshot of one moment.
    func withMoney(from offer: ScheduledRideDriverOffer) -> ScheduledRideReservation {
        ScheduledRideReservation(
            id: id,
            rideType: rideType,
            pickupArea: pickupArea,
            pickupCoordinate: pickupCoordinate,
            destinationArea: destinationArea,
            pickupTime: pickupTime,
            estimatedTripMiles: estimatedTripMiles,
            estimatedTripMinutes: estimatedTripMinutes,
            lockedBaseFareCents: offer.exactBaseFareCents ?? lockedBaseFareCents,
            driverPayoutCents: offer.driverPayoutCents ?? driverPayoutCents,
            currency: offer.currency,
            status: status,
            confirmedAt: confirmedAt,
            checkedInAt: checkedInAt,
            pickupETAMinutes: pickupETAMinutes,
            activationAt: activationAt
        )
    }
}

// MARK: - Dispatch handoff

/// The backend-owned lock at `driver_status/{driverId}.scheduledRideDispatchLock`.
///
/// Written by the activation transaction. The contract's rule is blunt: "While
/// it exists, the driver receives no normal opportunities." The server enforces
/// that by not creating them; the client enforces it again because a normal
/// request created moments before activation can still be sitting pending when
/// the lock appears.
///
/// One ID, not two: activation creates `rideRequests/{requestId}` with the
/// *same* ID as the scheduled request, so the lock's request and the targeted
/// standard request are the same document ID.
struct ScheduledRideDispatchLock: Equatable {
    let requestId: String
    /// Server activation time plus the approved dispatch timeout. Past this,
    /// the driver did not respond and the server begins replacement.
    let expiresAt: Date

    func isActive(now: Date = Date()) -> Bool { now < expiresAt }

    init(requestId: String, expiresAt: Date) {
        self.requestId = requestId
        self.expiresAt = expiresAt
    }

    /// Decodes the nested map off a `driver_status` document. Returns `nil`
    /// when no lock is held, which is the common case.
    init?(driverStatusData data: [String: Any]) {
        guard let lock = data["scheduledRideDispatchLock"] as? [String: Any] else { return nil }
        guard
            let requestId = (lock["requestId"] as? String) ?? (lock["scheduledRequestId"] as? String),
            let expiresAt = ScheduledRideField.date(lock["expiresAt"])
        else { return nil }
        self.requestId = requestId
        self.expiresAt = expiresAt
    }
}
