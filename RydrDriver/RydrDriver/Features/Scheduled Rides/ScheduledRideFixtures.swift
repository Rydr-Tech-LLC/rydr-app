//
//  ScheduledRideFixtures.swift
//  Rydr Driver
//
//  Test data for Scheduled Rides, plus the fake backend that serves it.
//
//  The whole file is inside `#if DEBUG`: a release build doesn't merely avoid
//  calling this, it never compiles it. Tests build Debug, so they see it all.
//

#if DEBUG

import Foundation
import CoreLocation
import FirebaseFirestore

/// Stands in for a Firestore listener registration. Records removal so a test
/// can assert cleanup — a real registration gives no way to observe that.
nonisolated final class ScheduledRideFixtureListener: NSObject, ListenerRegistration {
    private(set) var isRemoved = false

    func remove() {
        isRemoved = true
    }
}

// MARK: - Model builders

extension ScheduledRideOpportunity {
    /// Every parameter defaults, so a test names only what it cares about:
    /// `.fixture(responseDeadline: .distantPast)` reads as "expired".
    static func fixture(
        id: String = "fixture-opp",
        rideType: String = "Rydr Go",
        pickupArea: String = "Midtown pickup area",
        pickupCoordinate: CLLocationCoordinate2D = DriverMapDefaults.pilotCoordinate,
        destinationArea: String? = "Airport drop-off area",
        pickupTime: Date = Date().addingTimeInterval(3 * 3600),
        estimatedTripMiles: Double? = 10,
        estimatedTripMinutes: Double? = 22,
        approvedMaximumCents: Int = 3500,
        currency: String = "USD",
        responseDeadline: Date = Date().addingTimeInterval(45 * 60),
        selectionMode: ScheduledRideSelectionMode? = .quick
    ) -> ScheduledRideOpportunity {
        ScheduledRideOpportunity(
            id: id,
            rideType: rideType,
            pickupArea: pickupArea,
            pickupCoordinate: pickupCoordinate,
            destinationArea: destinationArea,
            pickupTime: pickupTime,
            estimatedTripMiles: estimatedTripMiles,
            estimatedTripMinutes: estimatedTripMinutes,
            approvedMaximumCents: approvedMaximumCents,
            currency: currency,
            responseDeadline: responseDeadline,
            selectionMode: selectionMode
        )
    }
}

extension ScheduledRideReservation {
    static func fixture(
        id: String = "fixture-res",
        rideType: String = "Rydr Go",
        pickupArea: String = "Buckhead pickup area",
        pickupCoordinate: CLLocationCoordinate2D = DriverMapDefaults.pilotCoordinate,
        destinationArea: String = "Airport drop-off area",
        pickupTime: Date = Date().addingTimeInterval(2 * 3600),
        estimatedTripMiles: Double? = 11.8,
        estimatedTripMinutes: Double? = 24,
        lockedBaseFareCents: Int? = 4200,
        driverPayoutCents: Int? = nil,
        currency: String = "USD",
        status: ScheduledRideStatus = .confirmed,
        confirmedAt: Date = Date().addingTimeInterval(-1800),
        checkedInAt: Date? = nil,
        pickupETAMinutes: Double? = nil,
        activationAt: Date? = nil
    ) -> ScheduledRideReservation {
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
            // Defaults to the contract's approved 70% driver share, so fixture
            // money has the same relationship real money does.
            driverPayoutCents: driverPayoutCents
                ?? lockedBaseFareCents.map {
                    Int(Double($0) * Double(ScheduledRideConfig.driverPayoutBasisPoints) / 10_000)
                },
            currency: currency,
            status: status,
            confirmedAt: confirmedAt,
            checkedInAt: checkedInAt,
            pickupETAMinutes: pickupETAMinutes,
            activationAt: activationAt
        )
    }
}


extension ScheduledRideDriverQuote {
    /// Payout defaults to the approved 70% share, so fixture money has the
    /// same relationship real money does.
    static func fixture(
        requestId: String = "fixture-opp-2",
        quoteFingerprint: String = "fixture-fingerprint-v1",
        exactBaseFareCents: Int = 2450,
        driverPayoutCents: Int? = nil,
        currency: String = "USD",
        pricingVersion: String = "scheduled-rides-v1",
        expiresAt: Date = Date().addingTimeInterval(5 * 60)
    ) -> ScheduledRideDriverQuote {
        ScheduledRideDriverQuote(
            requestId: requestId,
            quoteFingerprint: quoteFingerprint,
            exactBaseFareCents: exactBaseFareCents,
            driverPayoutCents: driverPayoutCents ?? Int(Double(exactBaseFareCents) * 0.70),
            currency: currency,
            pricingVersion: pricingVersion,
            expiresAt: expiresAt
        )
    }
}

// MARK: - The QA fixture set

/// The deterministic set the QA matrix is written against. Each entry makes
/// one state reachable without waiting on real time or a second driver — the
/// reasons are noted per fixture, because an unexplained fixture gets deleted.
///
/// `now` and `anchor` are parameters so a test can pin them.
///
/// Coordinates are spread ~0.04° apart because the map opens on a 0.15° span:
/// closer together and the pins overlap on screen and can't be tapped apart.
enum ScheduledRideFixtures {
    static func opportunities(
        anchor: CLLocationCoordinate2D = DriverMapDefaults.pilotCoordinate,
        now: Date = Date()
    ) -> [ScheduledRideOpportunity] {
        [
            .fixture(
                id: "fixture-opp-1",
                pickupArea: "Midtown pickup area",
                pickupCoordinate: CLLocationCoordinate2D(
                    latitude: anchor.latitude + 0.046,
                    longitude: anchor.longitude - 0.034
                ),
                // Deliberately overlaps fixture-res-1's window below, so this
                // pin demonstrates the .conflicting eligibility state.
                pickupTime: now.addingTimeInterval(2 * 3600 + 10 * 60),
                estimatedTripMiles: 12.4,
                estimatedTripMinutes: 26,
                approvedMaximumCents: 3800,
                responseDeadline: now.addingTimeInterval(45 * 60)
            ),
            .fixture(
                id: "fixture-opp-2",
                rideType: "Rydr XL",
                pickupArea: "Downtown pickup area",
                pickupCoordinate: CLLocationCoordinate2D(
                    latitude: anchor.latitude - 0.042,
                    longitude: anchor.longitude + 0.040
                ),
                destinationArea: "Stadium drop-off area",
                // The clean baseline: eligible, no conflict, not expired.
                pickupTime: now.addingTimeInterval(5 * 3600),
                estimatedTripMiles: 6.1,
                estimatedTripMinutes: 15,
                approvedMaximumCents: 2450,
                responseDeadline: now.addingTimeInterval(90 * 60),
                // The only Choose My Driver fixture — makes the "Submit Offer"
                // wording and the offer-submitted terminal state reachable
                // without editing fixtures by hand.
                selectionMode: .chooseDriver
            ),
            .fixture(
                id: "fixture-opp-3",
                pickupArea: "Sandy Springs pickup area",
                pickupCoordinate: CLLocationCoordinate2D(
                    latitude: anchor.latitude + 0.040,
                    longitude: anchor.longitude + 0.048
                ),
                destinationArea: "Perimeter drop-off area",
                pickupTime: now.addingTimeInterval(4 * 3600),
                estimatedTripMiles: 8.2,
                estimatedTripMinutes: 19,
                approvedMaximumCents: 2900,
                // Deadline already in the past — demonstrates the .expired
                // state immediately, instead of waiting 45-90 minutes for the
                // two above to expire naturally.
                responseDeadline: now.addingTimeInterval(-10 * 60)
            )
        ]
    }

    static func reservations(
        anchor: CLLocationCoordinate2D = DriverMapDefaults.pilotCoordinate,
        now: Date = Date()
    ) -> [ScheduledRideReservation] {
        [
            .fixture(
                id: "fixture-res-1",
                pickupArea: "Buckhead pickup area",
                pickupCoordinate: CLLocationCoordinate2D(
                    latitude: anchor.latitude + 0.018,
                    longitude: anchor.longitude - 0.012
                ),
                pickupTime: now.addingTimeInterval(2 * 3600),
                estimatedTripMiles: 11.8,
                estimatedTripMinutes: 24,
                lockedBaseFareCents: 4200,
                confirmedAt: now.addingTimeInterval(-1800)
            ),
            .fixture(
                id: "fixture-res-3",
                pickupArea: "Midtown pickup area",
                pickupCoordinate: CLLocationCoordinate2D(
                    latitude: anchor.latitude - 0.030,
                    longitude: anchor.longitude - 0.036
                ),
                destinationArea: "Perimeter drop-off area",
                // Pickup 59 minutes out puts this inside the check-in window
                // right now — it opens at pickup − 60 and closes at pickup − 50,
                // so the Check In button is live for the first ~9 minutes of a
                // session. The only fixture that makes the real MapKit ETA and
                // submit path reachable by hand.
                pickupTime: now.addingTimeInterval(59 * 60),
                estimatedTripMiles: 7.3,
                estimatedTripMinutes: 18,
                lockedBaseFareCents: 2800,
                status: .checkInRequired,
                confirmedAt: now.addingTimeInterval(-3600)
            ),
            .fixture(
                id: "fixture-res-2",
                pickupArea: "Sandy Springs pickup area",
                pickupCoordinate: CLLocationCoordinate2D(
                    latitude: anchor.latitude + 0.009,
                    longitude: anchor.longitude + 0.021
                ),
                destinationArea: "Downtown drop-off area",
                // Deliberately clear of every other fixture's window — exists
                // so "already checked in to a different ride" is testable
                // without first accepting an opportunity to create a second
                // reservation.
                pickupTime: now.addingTimeInterval(6 * 3600),
                estimatedTripMiles: 9.4,
                estimatedTripMinutes: 21,
                lockedBaseFareCents: 3100,
                confirmedAt: now.addingTimeInterval(-900)
            )
        ]
    }
}

extension ScheduledRideDriverOffer {
    static func fixture(
        requestId: String = "fixture-res",
        status: ScheduledRideOfferStatus = .selected,
        exactBaseFareCents: Int = 4200,
        driverPayoutCents: Int? = nil,
        currency: String = "USD",
        expiresAt: Date? = nil
    ) -> ScheduledRideDriverOffer {
        ScheduledRideDriverOffer(
            requestId: requestId,
            status: status,
            driverPayoutCents: driverPayoutCents
                ?? Int(Double(exactBaseFareCents) * Double(ScheduledRideConfig.driverPayoutBasisPoints) / 10_000),
            exactBaseFareCents: exactBaseFareCents,
            currency: currency,
            expiresAt: expiresAt
        )
    }
}

extension ScheduledRideCheckInReceipt {
    static func fixture(
        activationAt: Date = Date().addingTimeInterval(30 * 60),
        acceptedEtaSeconds: Double = 12 * 60
    ) -> ScheduledRideCheckInReceipt {
        ScheduledRideCheckInReceipt(activationAt: activationAt, acceptedEtaSeconds: acceptedEtaSeconds)
    }
}

// MARK: - One configurable fake

/// Stands in for the whole backend.
///
/// Replaces eight closure-factory functions plus two helper classes that
/// existed only to give closures memory — both are properties here now.
///
/// Configure what a test cares about, leave the rest, then read the
/// `recorded*` properties to assert what the app actually asked for.
final class FakeScheduledRideBackend: ScheduledRideBackend {

    // MARK: What the listeners deliver

    var opportunities: [ScheduledRideOpportunity] = []
    var reservations: [ScheduledRideReservation] = []
    var offers: [ScheduledRideDriverOffer] = []
    /// Firestore answering from disk — an offline launch.
    var isFromCache = false
    /// When set, every listener reports this instead of delivering data.
    var listenerError: Error?
    /// The activation lock. `nil` — no lock held — is the ordinary case.
    var dispatchLock: ScheduledRideDispatchLock?
    /// `false` attaches listeners that never answer — the only way to reach a
    /// loading state.
    var answersListeners = true

    // MARK: What the callables do

    var quote: ScheduledRideDriverQuote = .fixture()
    /// Returned from the second preview onward: `QUOTE_CHANGED` makes the app
    /// re-quote, and the re-confirm must show the new price.
    var repricedQuote: ScheduledRideDriverQuote?
    var quoteError: ScheduledRideCallableError?
    var respondError: ScheduledRideCallableError?
    var checkInReceipt: ScheduledRideCheckInReceipt = .fixture()
    var checkInError: ScheduledRideCallableError?
    var cancelError: ScheduledRideCallableError?

    // MARK: What the app asked for

    private(set) var quotePreviewCount = 0
    private(set) var recordedResponses: [(requestId: String, fingerprint: String)] = []
    private(set) var recordedCheckIns: [(requestId: String, operationId: String, etaSeconds: Double, calculatedAt: Date)] = []
    private(set) var recordedCancellations: [(requestId: String, reasonCode: String)] = []
    /// Every registration handed out, so a test can assert cleanup.
    private(set) var registrations: [ScheduledRideFixtureListener] = []

    var didRespond: Bool { !recordedResponses.isEmpty }
    var didSubmitCheckIn: Bool { !recordedCheckIns.isEmpty }

    init() {}

    /// The QA set, with one selected offer per reservation so fixture rides
    /// carry money the way confirmed ones do.
    static func qaFixtures() -> FakeScheduledRideBackend {
        let backend = FakeScheduledRideBackend()
        backend.opportunities = ScheduledRideFixtures.opportunities()
        backend.reservations = ScheduledRideFixtures.reservations()
        backend.offers = backend.reservations.map {
            .fixture(requestId: $0.id, exactBaseFareCents: $0.lockedBaseFareCents ?? 4200)
        }
        return backend
    }

    // MARK: Pushing a later snapshot

    /// The server writing a confirmed reservation and the listener picking it
    /// up — what happens a moment after a Quick Schedule ack.
    func deliverReservation(_ reservation: ScheduledRideReservation) {
        reservations.append(reservation)
        reservationSubscriber?(.success(ScheduledRideSnapshot(items: reservations, isFromCache: isFromCache)))
    }

    func deliverOffer(_ offer: ScheduledRideDriverOffer) {
        offers.append(offer)
        offerSubscriber?(.success(ScheduledRideSnapshot(items: offers, isFromCache: isFromCache)))
    }

    private var reservationSubscriber: ((Result<ScheduledRideSnapshot<ScheduledRideReservation>, Error>) -> Void)?
    private var offerSubscriber: ((Result<ScheduledRideSnapshot<ScheduledRideDriverOffer>, Error>) -> Void)?

    // MARK: ScheduledRideBackend

    func listenToOpportunities(
        driverId: String,
        onChange: @escaping (Result<ScheduledRideSnapshot<ScheduledRideOpportunity>, Error>) -> Void
    ) -> ListenerRegistration {
        emit(onChange, items: opportunities)
    }

    func listenToReservations(
        driverId: String,
        onChange: @escaping (Result<ScheduledRideSnapshot<ScheduledRideReservation>, Error>) -> Void
    ) -> ListenerRegistration {
        reservationSubscriber = onChange
        return emit(onChange, items: reservations)
    }

    func listenToOffers(
        driverId: String,
        onChange: @escaping (Result<ScheduledRideSnapshot<ScheduledRideDriverOffer>, Error>) -> Void
    ) -> ListenerRegistration {
        offerSubscriber = onChange
        return emit(onChange, items: offers)
    }

    func listenToDispatchLock(
        driverId: String,
        onChange: @escaping (Result<ScheduledRideDispatchLock?, Error>) -> Void
    ) -> ListenerRegistration {
        dispatchLockSubscriber = onChange
        let registration = ScheduledRideFixtureListener()
        registrations.append(registration)
        guard answersListeners else { return registration }
        if let listenerError {
            onChange(.failure(listenerError))
        } else {
            onChange(.success(dispatchLock))
        }
        return registration
    }

    /// Activation writing the lock, or a decline clearing it.
    func deliverDispatchLock(_ lock: ScheduledRideDispatchLock?) {
        dispatchLock = lock
        dispatchLockSubscriber?(.success(lock))
    }

    private var dispatchLockSubscriber: ((Result<ScheduledRideDispatchLock?, Error>) -> Void)?

    func previewQuote(requestId: String) async throws -> ScheduledRideDriverQuote {
        quotePreviewCount += 1
        if let quoteError { throw quoteError }
        if quotePreviewCount > 1, let repricedQuote { return repricedQuote }
        return quote
    }

    func respond(requestId: String, quoteFingerprint: String) async throws {
        recordedResponses.append((requestId, quoteFingerprint))
        if let respondError { throw respondError }
    }

    func submitCheckIn(
        requestId: String,
        operationId: String,
        pickupEtaSeconds: Double,
        etaCalculatedAt: Date
    ) async throws -> ScheduledRideCheckInReceipt {
        recordedCheckIns.append((requestId, operationId, pickupEtaSeconds, etaCalculatedAt))
        if let checkInError { throw checkInError }

        // The server half: it writes `checkedIn` plus the activation time, and
        // the listener delivers it. Without simulating that the DEBUG flow
        // stops at the receipt and the card never leaves its Check In state —
        // because the reservation, not the receipt, is what the UI switches on.
        if let index = reservations.firstIndex(where: { $0.id == requestId }) {
            reservations[index] = reservations[index].checkedIn(
                pickupETAMinutes: pickupEtaSeconds / 60,
                activationAt: checkInReceipt.activationAt
            )
            reservationSubscriber?(.success(
                ScheduledRideSnapshot(items: reservations, isFromCache: isFromCache)
            ))
        }
        return checkInReceipt
    }

    func cancelReservation(requestId: String, operationId: String, reasonCode: String) async throws {
        recordedCancellations.append((requestId, reasonCode))
        if let cancelError { throw cancelError }
    }

    // MARK: Shared emission

    private func emit<T>(
        _ onChange: @escaping (Result<ScheduledRideSnapshot<T>, Error>) -> Void,
        items: [T]
    ) -> ListenerRegistration {
        let registration = ScheduledRideFixtureListener()
        registrations.append(registration)
        guard answersListeners else { return registration }
        if let listenerError {
            onChange(.failure(listenerError))
        } else {
            onChange(.success(ScheduledRideSnapshot(items: items, isFromCache: isFromCache)))
        }
        return registration
    }
}

#endif
