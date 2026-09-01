//
//  ScheduledRideModels.swift
//  Rydr Driver
//
//  Data shapes for the Scheduled Rides feature, tracking the driver-facing
//  fields of the scheduledRideOpportunities / scheduledRideRequests Firestore
//  contract (schema version 1). Field names mirror the contract's own terms
//  (approvedMaximumCents, lockedBaseFareCents) so the eventual
//  Firestore-decoding init is a direct mapping, not a translation layer.
//

import Foundation
import CoreLocation

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

/// An unaccepted scheduled ride the driver could take — the approved-driver
/// "browse projection" (scheduledRideOpportunities), never the rider's exact
/// address per the contract's privacy boundary.
struct ScheduledRideOpportunity: Identifiable, Equatable {
    let id: String
    let rideType: String
    let pickupArea: String
    let pickupCoordinate: CLLocationCoordinate2D
    let destinationArea: String
    let pickupTime: Date
    let estimatedTripMiles: Double?
    let estimatedTripMinutes: Double?
    let approvedMaximumCents: Int
    let currency: String
    let responseDeadline: Date

    var isExpired: Bool { Date() >= responseDeadline }

    var approvedMaximumDisplay: String {
        currencyFormatter.string(from: NSDecimalNumber(value: Double(approvedMaximumCents) / 100)) ?? "$0.00"
    }

    /// Client-side check only — fast local feedback so the driver isn't
    /// tapping Accept on something plainly stale or conflicting. Firebase's
    /// respondToScheduledRide transaction remains the real authority; this
    /// can say .eligible and the server can still reject (e.g. another
    /// driver won the same opportunity a moment earlier).
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
    /// The exact pickup point, distinct from an opportunity's coarse/rounded
    /// one — the contract's privacy reveal boundary has already passed once
    /// a ride is confirmed. Our mock data only has one coordinate fidelity
    /// to draw from today, so accept() below carries the opportunity's
    /// coordinate over as-is; a real integration needs the exact coordinate
    /// from the private orchestration record at this stage, not the browse
    /// projection's rounded one.
    let pickupCoordinate: CLLocationCoordinate2D
    let destinationArea: String
    let pickupTime: Date
    let estimatedTripMiles: Double?
    let estimatedTripMinutes: Double?
    let lockedBaseFareCents: Int
    let currency: String
    let status: ScheduledRideStatus
    let confirmedAt: Date
    let checkedInAt: Date?
    let pickupETAMinutes: Double?

    var lockedBaseFareDisplay: String {
        currencyFormatter.string(from: NSDecimalNumber(value: Double(lockedBaseFareCents) / 100)) ?? "$0.00"
    }

    /// Firebase's real ETA-based activation math (scheduled pickup − travel
    /// ETA − configurable buffer) is deferred backend work per the contract.
    /// This just records what MapKit calculated at check-in time, matching
    /// the driver-side half of that pipeline this deliverable covers.
    func checkedIn(pickupETAMinutes: Double, at date: Date = Date()) -> ScheduledRideReservation {
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
            currency: currency,
            status: .checkedIn,
            confirmedAt: confirmedAt,
            checkedInAt: date,
            pickupETAMinutes: pickupETAMinutes
        )
    }

    /// A driver can only be actively checked in to one scheduled ride at a
    /// time — checking in commits them to head toward that pickup next, and
    /// they can't be doing that for two rides simultaneously. This is
    /// distinct from the accept-time conflict check, which only compares
    /// pickup/trip time windows; two reservations can pass that check
    /// (their windows don't overlap) and still collide here if the driver
    /// tries to check into a second one while still checked into the first.
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

enum ScheduledRideCheckInEligibility: Equatable {
    case eligible
    case blockedByExistingCheckIn(ScheduledRideReservation)
}

extension ScheduledRideReservation {
    /// Quick Schedule locks the exact displayed upfront pay the instant the
    /// driver accepts — matches what the card showed, per the MVP's price-
    /// locking rule. No selectionMode branching since this sprint uses one
    /// uniform accept path.
    init(accepting opportunity: ScheduledRideOpportunity, confirmedAt: Date = Date()) {
        id = opportunity.id
        rideType = opportunity.rideType
        pickupArea = opportunity.pickupArea
        pickupCoordinate = opportunity.pickupCoordinate
        destinationArea = opportunity.destinationArea
        pickupTime = opportunity.pickupTime
        estimatedTripMiles = opportunity.estimatedTripMiles
        estimatedTripMinutes = opportunity.estimatedTripMinutes
        lockedBaseFareCents = opportunity.approvedMaximumCents
        currency = opportunity.currency
        status = .confirmed
        self.confirmedAt = confirmedAt
        checkedInAt = nil
        pickupETAMinutes = nil
    }
}
