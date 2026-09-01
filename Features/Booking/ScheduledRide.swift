//
//  ScheduledRide.swift
//  RydrPlayground
//
//  Models for the Scheduled Rides feature (Sprint 1 — Rider Experience).
//
//  SCHEMA NOTE: This is the original mock-backed Rider shape. The authoritative
//  product workflow now lives in SCHEDULED_RIDES_MVP.md and the canonical
//  server mapping lives in Rydr_Firebase/SCHEDULED_RIDES_IMPLEMENTATION_CONTRACT.md.
//  These legacy mode/status names must be translated or replaced during the
//  Rider integration sprint; they are not Firestore authority.
//
//  Legacy assumed collection shape (reference only; do not implement as-is):
//    scheduledRideRequests/{requestId}
//      - rider-writable fields: riderId, pickup, dropoff, pickupCoordinate,
//        dropoffCoordinate, rideType, mode, requestedPickupDate, status
//        ("pendingOffers" only), createdAt, updatedAt, riderApprovedMaxCents
//      - PROTECTED (backend/driver-owned only, rider app must never write):
//        acceptedOfferId, lockedPriceCents, assignedDriverId, status values
//        other than "pendingOffers" / "cancelledByRider"
//    scheduledRideRequests/{requestId}/offers/{offerId}
//      - fully backend/driver-owned. Rider app only ever reads this
//        subcollection via a snapshot listener; it never writes to it.
//

import Foundation
import CoreLocation

/// How the rider wants their scheduled ride matched to a driver.
enum ScheduledRideMode: String, Codable, CaseIterable, Identifiable {
    /// Rider approves a maximum price up front; the first available driver
    /// within that ceiling is auto-assigned. No manual offer comparison.
    case quickSchedule = "quickSchedule"
    /// Rider waits for 1-3 driver offers to come in and manually picks one,
    /// reusing the existing driver-comparison card UI.
    case chooseMyDriver = "chooseMyDriver"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickSchedule:   return "Quick Schedule"
        case .chooseMyDriver:  return "Choose My Driver"
        }
    }

    var subtitle: String {
        switch self {
        case .quickSchedule:
            return "Approve a maximum price now. We'll match you with the first available driver under that price."
        case .chooseMyDriver:
            return "Review up to three driver offers as they come in and pick the one you want."
        }
    }

    var systemImage: String {
        switch self {
        case .quickSchedule:   return "bolt.fill"
        case .chooseMyDriver:  return "person.2.fill"
        }
    }
}

enum ScheduledRideStatus: String, Codable {
    case pendingOffers        // waiting on driver offers / auto-match
    case priceLocked          // Quick Schedule: matched, price locked, driver assigned
    case awaitingRiderChoice  // Choose My Driver: offers present, rider hasn't picked yet
    case confirmed            // Choose My Driver: rider picked an offer
    /// Khris's feedback (8/6): "A selected driver may cancel." Backend moves
    /// a matched/confirmed request back to this state instead of dropping it
    /// or forcing the rider to restart — the UI should treat this as a
    /// continuation of the same request, not a dead end.
    case driverCancelledFindingReplacement
    /// Khris's feedback: "A payment failure might not be discovered until
    /// the ride is about to begin." Gives the rider a clear, actionable
    /// state instead of a silent failure right at pickup time.
    case paymentFailed
    case cancelledByRider
    case cancelledNoDrivers   // backend gave up finding a match
    case expired
    case completed

    /// Statuses the rider app is ever allowed to write via a direct update.
    /// Everything else must come from the backend/driver side.
    static let riderWritable: Set<ScheduledRideStatus> = [.cancelledByRider]

    /// States where the request is still "alive" and the rider can still
    /// edit trip details or cancel outright.
    var isActionable: Bool {
        switch self {
        case .pendingOffers, .awaitingRiderChoice, .driverCancelledFindingReplacement, .paymentFailed:
            return true
        case .priceLocked, .confirmed, .cancelledByRider, .cancelledNoDrivers, .expired, .completed:
            return false
        }
    }

    /// States where the rider should be able to tap "Try Again" and
    /// re-enter the schedule flow with the same trip details prefilled,
    /// per Khris's "no drivers may respond" concern.
    var offersRetry: Bool {
        self == .cancelledNoDrivers || self == .expired
    }
}

/// A single driver's offer against a scheduled ride request.
/// Entirely backend/driver-owned — the rider app only reads these.
struct ScheduledDriverOffer: Identifiable, Equatable {
    let id: String
    let driverId: String
    let driverName: String
    let driverProfileImage: String?
    let carImage: String?
    let carMakeModel: String
    let rating: Double
    let ratingCount: Int
    let perMile: Double
    let perMinute: Double
    /// Final, locked price for this offer — authoritative, computed server/driver-side.
    let lockedPriceCents: Int
    let offeredAt: Date

    var lockedPrice: Double { Double(lockedPriceCents) / 100.0 }

    /// Bridges an offer into the existing `Driver` model so the on-demand
    /// driver-comparison UI (DriverSelectionView / DriverCard) can be reused
    /// as-is for the "Choose My Driver" scheduled flow.
    func asDriver(coordinate: CLLocationCoordinate2D) -> Driver {
        Driver(
            id: driverId,
            name: driverName,
            profileImage: driverProfileImage,
            carImage: carImage,
            carMakeModel: carMakeModel,
            rating: rating,
            compliments: [],
            perMinute: perMinute,
            perMile: perMile,
            coordinate: coordinate,
            score: 0,
            ratingCount: ratingCount
        )
    }
}

/// A rider's scheduled ride request, as reflected back from Firestore.
struct ScheduledRideRequest: Identifiable, Equatable {
    let id: String
    var riderId: String
    var pickup: String
    var dropoff: String
    var pickupCoordinate: CLLocationCoordinate2D?
    var dropoffCoordinate: CLLocationCoordinate2D?
    var rideType: String
    var mode: ScheduledRideMode
    var requestedPickupDate: Date
    var status: ScheduledRideStatus
    var estimate: RideEstimate
    /// Maximum price the rider approved at booking time (Quick Schedule ceiling,
    /// or the display ceiling shown before offers arrive in Choose My Driver).
    /// This is rider-approved and rider-visible, but it is NOT the same as a
    /// locked/final price — see `lockedPriceCents` below.
    var riderApprovedMaxCents: Int
    /// Set by the backend once a price is actually locked (Quick Schedule
    /// auto-match, or after the rider accepts an offer in Choose My Driver).
    /// PROTECTED — rider app never writes this.
    var lockedPriceCents: Int?
    /// PROTECTED — rider app never writes this.
    var assignedDriverId: String?
    var createdAt: Date

    var riderApprovedMax: Double { Double(riderApprovedMaxCents) / 100.0 }
    var lockedPrice: Double? { lockedPriceCents.map { Double($0) / 100.0 } }

    static func == (lhs: ScheduledRideRequest, rhs: ScheduledRideRequest) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.lockedPriceCents == rhs.lockedPriceCents
    }
}
