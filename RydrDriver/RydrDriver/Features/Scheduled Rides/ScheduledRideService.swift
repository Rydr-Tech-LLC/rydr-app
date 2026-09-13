//
//  ScheduledRideService.swift
//  Rydr Driver
//
//  The Driver app's door to the Scheduled Rides backend: a protocol, one live
//  implementation, and (in DEBUG) one configurable fake.
//
//  This was six injected closures until the fakes started needing state of
//  their own — a call counter, a snapshot sequencer. Needing objects to give
//  closures memory is the signal that the seam wanted to be a type.
//
//  Callable failures are classified into ScheduledRideCallableError before
//  they leave this file, so nothing above handles a raw Firebase NSError.
//

import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// Decoded documents plus where they came from.
///
/// The cache flag travels with the data because the two are only meaningful
/// together — "we are offline" delivered separately invites rendering it
/// against a different snapshot. Firestore's own API pairs them for the same
/// reason.
struct ScheduledRideSnapshot<Element> {
    let items: [Element]
    /// Firestore answered from its local cache instead of the server — the
    /// device is offline, or hasn't completed its first round trip. The data
    /// is real, just possibly behind.
    let isFromCache: Bool

    init(items: [Element], isFromCache: Bool = false) {
        self.items = items
        self.isFromCache = isFromCache
    }
}

enum ScheduledRideServiceError: LocalizedError, Equatable {
    case notAuthenticated
    case driverMismatch

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in to see your scheduled rides."
        case .driverMismatch:
            return "These scheduled rides belong to a different driver account."
        }
    }
}

/// Returned when a listener never starts — an unauthenticated call, say.
/// `NSObject` because `ListenerRegistration` is an `@objc` protocol.
nonisolated final class ScheduledRideNoOpListener: NSObject, ListenerRegistration {
    func remove() {}
}

// MARK: - The seam

/// Everything the Driver app asks of the Scheduled Rides backend.
///
/// Reads are listeners — the caller owns the returned registration and must
/// `remove()` it. Writes answer once.
///
/// Nothing here returns a reservation: `respond` and `submitCheckIn` only
/// acknowledge, and the server's documents arrive via the listeners. A locked
/// fare and a check-in status are server-created, so the client never invents
/// either.
protocol ScheduledRideBackend {
    func listenToOpportunities(
        driverId: String,
        onChange: @escaping (Result<ScheduledRideSnapshot<ScheduledRideOpportunity>, Error>) -> Void
    ) -> ListenerRegistration

    func listenToReservations(
        driverId: String,
        onChange: @escaping (Result<ScheduledRideSnapshot<ScheduledRideReservation>, Error>) -> Void
    ) -> ListenerRegistration

    /// The driver's own offers — where driver-specific money lives, and where
    /// a pending Choose My Driver response is durably recorded.
    func listenToOffers(
        driverId: String,
        onChange: @escaping (Result<ScheduledRideSnapshot<ScheduledRideDriverOffer>, Error>) -> Void
    ) -> ListenerRegistration

    /// The backend-owned dispatch lock on `driver_status/{driverId}`.
    /// `nil` means no lock held, which is almost always.
    ///
    /// A listener because it appears and disappears without the driver acting:
    /// activation writes it, a decline or timeout clears it.
    func listenToDispatchLock(
        driverId: String,
        onChange: @escaping (Result<ScheduledRideDispatchLock?, Error>) -> Void
    ) -> ListenerRegistration

    /// Step one of the two-step accept: what this driver would earn, plus the
    /// fingerprint binding that number.
    func previewQuote(requestId: String) async throws -> ScheduledRideDriverQuote

    /// Step two: accept at a specific fingerprint. Acknowledgement only.
    func respond(requestId: String, quoteFingerprint: String) async throws

    /// Submits a fresh MapKit ETA; returns the server-computed activation time.
    func submitCheckIn(
        requestId: String,
        operationId: String,
        pickupEtaSeconds: Double,
        etaCalculatedAt: Date
    ) async throws -> ScheduledRideCheckInReceipt

    func cancelReservation(requestId: String, operationId: String, reasonCode: String) async throws
}

// MARK: - Live implementation

/// The real backend. Production constructs this and nothing else.
struct FirebaseScheduledRideBackend: ScheduledRideBackend {
    init() {}

    func previewQuote(requestId: String) async throws -> ScheduledRideDriverQuote {
        let data = try await call("previewScheduledRideDriverQuote", payload: ["requestId": requestId])
        guard let quote = ScheduledRideDriverQuote(callableResponse: data) else {
            throw ScheduledRideCallableError.unrecognized(reason: "MALFORMED_QUOTE")
        }
        return quote
    }

    func respond(requestId: String, quoteFingerprint: String) async throws {
        _ = try await call(
            "respondToScheduledRide",
            payload: ["requestId": requestId, "quoteFingerprint": quoteFingerprint]
        )
    }

    /// The device calculates the ETA because Firebase has no server-side
    /// routing in the MVP. The server stores the ETA metadata, not the
    /// driver's location — nothing about where they are leaves the device.
    func submitCheckIn(
        requestId: String,
        operationId: String,
        pickupEtaSeconds: Double,
        etaCalculatedAt: Date
    ) async throws -> ScheduledRideCheckInReceipt {
        let data = try await call("checkInScheduledRide", payload: [
            "requestId": requestId,
            "operationId": operationId,
            // Seconds per the contract; the UI works in minutes and converts
            // here so two units never circulate inside the app.
            "pickupEtaSeconds": Int(pickupEtaSeconds.rounded()),
            "etaCalculatedAtEpochMs": Int(etaCalculatedAt.timeIntervalSince1970 * 1000),
            // The only value the contract defines. A constant, not a
            // parameter — there is no second source for a driver ETA today.
            "etaSource": "mapKit"
        ])
        guard let receipt = ScheduledRideCheckInReceipt(callableResponse: data) else {
            throw ScheduledRideCallableError.unrecognized(reason: "MALFORMED_CHECK_IN_RESPONSE")
        }
        return receipt
    }

    /// TODO: still a mock. The real `cancelScheduledRide` takes these exact
    /// arguments and starts replacement matching server-side.
    func cancelReservation(requestId: String, operationId: String, reasonCode: String) async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
    }
}

// MARK: - Live Firestore listeners

extension FirebaseScheduledRideBackend {
    /// Observes the approved-driver browse projection.
    ///
    /// `driverId` isn't in the query — the projection is one shared redacted
    /// view, with Security Rules deciding who may read it. It's used here as
    /// the authentication gate instead, so a stale screen can't quietly read
    /// under another account.
    nonisolated func listenToOpportunities(
        driverId: String,
        onChange: @escaping (Result<ScheduledRideSnapshot<ScheduledRideOpportunity>, Error>) -> Void
    ) -> ListenerRegistration {
        guard isAuthorized(driverId: driverId, onChange: onChange) else {
            return ScheduledRideNoOpListener()
        }

        return Firestore.firestore()
            .collection("scheduledRideOpportunities")
            // The projection has its OWN status vocabulary — "open" here, not
            // the request's "seekingDrivers". Verified against the backend's
            // opportunity write; querying the request's value matched nothing.
            .whereField("status", isEqualTo: ScheduledRideOpportunityStatus.open.rawValue)
            // includeMetadataChanges so a cache/server transition fires on its
            // own. Without it, going back online would not re-notify until
            // some document also changed, and the "showing saved data" banner
            // would linger after connectivity returned.
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    onChange(.failure(error))
                    return
                }
                // compactMap, not map: a document that fails to decode is
                // dropped rather than shown half-populated. See
                // ScheduledRideOpportunity.init?(document:).
                let opportunities = snapshot?.documents.compactMap {
                    ScheduledRideOpportunity(document: $0)
                } ?? []
                onChange(.success(ScheduledRideSnapshot(
                    items: opportunities,
                    isFromCache: snapshot?.metadata.isFromCache ?? false
                )))
            }
    }

    /// Observes the private orchestration records this driver is assigned to.
    ///
    /// Per-driver, so `assignedDriverId` is load-bearing. The status filter
    /// keeps finished and abandoned rides off the list.
    ///
    /// TODO: confirm whether the assigned driver reads `scheduledRideRequests`
    /// directly or gets a driver-side projection. If it becomes a projection,
    /// only this function and `ScheduledRideReservation.init?(document:)`
    /// change.
    nonisolated func listenToReservations(
        driverId: String,
        onChange: @escaping (Result<ScheduledRideSnapshot<ScheduledRideReservation>, Error>) -> Void
    ) -> ListenerRegistration {
        guard isAuthorized(driverId: driverId, onChange: onChange) else {
            return ScheduledRideNoOpListener()
        }

        let activeStatuses = [
            ScheduledRideStatus.confirmed,
            .checkInRequired,
            .checkedIn,
            .activating
        ].map(\.rawValue)

        return Firestore.firestore()
            .collection("scheduledRideRequests")
            .whereField("assignedDriverId", isEqualTo: driverId)
            .whereField("status", in: activeStatuses)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    onChange(.failure(error))
                    return
                }
                let reservations = snapshot?.documents.compactMap {
                    ScheduledRideReservation(document: $0)
                } ?? []
                onChange(.success(ScheduledRideSnapshot(
                    items: reservations,
                    isFromCache: snapshot?.metadata.isFromCache ?? false
                )))
            }
    }

    /// Reports the failure through `onChange` and returns `false` when the
    /// listener must not start. Generic because each listener carries a
    /// different `Result` success type.
    /// Every offer this driver holds, in one collectionGroup query.
    ///
    /// Needs a collection-group index on `offers.driverId` and a matching
    /// Security Rule — returns a permission error until those land.
    nonisolated func listenToOffers(
        driverId: String,
        onChange: @escaping (Result<ScheduledRideSnapshot<ScheduledRideDriverOffer>, Error>) -> Void
    ) -> ListenerRegistration {
        guard isAuthorized(driverId: driverId, onChange: onChange) else {
            return ScheduledRideNoOpListener()
        }

        return Firestore.firestore()
            .collectionGroup("offers")
            .whereField("driverId", isEqualTo: driverId)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    onChange(.failure(error))
                    return
                }
                let offers = snapshot?.documents.compactMap {
                    ScheduledRideDriverOffer(document: $0)
                } ?? []
                onChange(.success(ScheduledRideSnapshot(
                    items: offers,
                    isFromCache: snapshot?.metadata.isFromCache ?? false
                )))
            }
    }

    /// The driver's own status document, watched for the activation lock.
    nonisolated func listenToDispatchLock(
        driverId: String,
        onChange: @escaping (Result<ScheduledRideDispatchLock?, Error>) -> Void
    ) -> ListenerRegistration {
        guard isAuthorized(driverId: driverId, onChange: onChange) else {
            return ScheduledRideNoOpListener()
        }

        return Firestore.firestore()
            .collection("driver_status")
            .document(driverId)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onChange(.failure(error))
                    return
                }
                // No document, or a document with no lock, both mean "no lock
                // held" — the ordinary case, not a failure.
                guard let data = snapshot?.data() else {
                    onChange(.success(nil))
                    return
                }
                onChange(.success(ScheduledRideDispatchLock(driverStatusData: data)))
            }
    }

    nonisolated func isAuthorized<T>(
        driverId: String,
        onChange: @escaping (Result<T, Error>) -> Void
    ) -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            onChange(.failure(ScheduledRideServiceError.notAuthenticated))
            return false
        }
        guard uid == driverId else {
            onChange(.failure(ScheduledRideServiceError.driverMismatch))
            return false
        }
        return true
    }
}

// MARK: - Live callables

private extension FirebaseScheduledRideBackend {
    /// Computed rather than stored so it resolves after
    /// `FirebaseApp.configure()` whenever this type is first touched.
    var functions: Functions { Functions.functions() }

    /// Shared invoke-and-classify step. Every failure leaves here as a
    /// `ScheduledRideCallableError`, so no caller above handles a raw
    /// `NSError` or needs to know the `details.reason` convention.
    ///
    /// Callable names have no compile-time checking — a typo is a runtime
    /// `not-found` — so each appears exactly once, at its own method.
    func call(_ name: String, payload: [String: Any]) async throws -> [String: Any] {
        do {
            let result = try await functions.httpsCallable(name).call(payload)
            guard let data = result.data as? [String: Any] else {
                throw ScheduledRideCallableError.unrecognized(reason: "MALFORMED_RESPONSE")
            }
            return data
        } catch {
            throw ScheduledRideCallableError(error)
        }
    }
}
