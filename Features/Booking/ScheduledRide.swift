import Foundation
import CoreLocation

enum ScheduledRideMode: String, CaseIterable, Identifiable {
    case quickSchedule
    case chooseMyDriver

    var id: String { rawValue }
    var title: String { self == .quickSchedule ? "Quick Schedule" : "Choose My Driver" }
    var subtitle: String {
        self == .quickSchedule
            ? "The first qualified driver who accepts within your approved maximum is assigned."
            : "Review up to three qualified driver responses and choose one."
    }
    var systemImage: String { self == .quickSchedule ? "bolt.fill" : "person.3.fill" }
}

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
    case dispatchFallbackSearching
    case dispatchFallbackActivating
    case cancelled
    case expired

    var title: String {
        switch self {
        case .seekingDrivers: "Finding drivers"
        case .awaitingRiderSelection: "Choose your driver"
        case .confirmed: "Scheduled ride confirmed"
        case .checkInRequired: "Driver check-in required"
        case .checkedIn: "Driver checked in"
        case .activating: "Preparing your ride"
        case .active: "Ride ready"
        case .completed: "Completed"
        case .replacementSearching: "Finding a replacement"
        case .replacementApprovalRequired: "Choose a replacement"
        case .dispatchFallbackSearching: "Finding a nearby driver"
        case .dispatchFallbackActivating: "Starting regular dispatch"
        case .cancelled: "Cancelled"
        case .expired: "Needs attention"
        }
    }
}

struct ScheduledRidePreview: Equatable {
    let distanceMiles: Double
    let durationMinutes: Double
    let suggestedLowCents: Int
    let suggestedHighCents: Int
    let eligibleDriverCount: Int
}

struct ScheduledDriverOffer: Identifiable, Equatable {
    let id: String
    let driverName: String
    let driverPhotoURL: String?
    let vehicleSummary: String?
    let rating: Double
    let ratingCount: Int
    let totalCents: Int
}

struct ScheduledRideRequest: Identifiable, Equatable {
    let id: String
    let pickup: String
    let dropoff: String
    let rideType: String
    let mode: ScheduledRideMode
    let scheduledPickupAt: Date
    let status: ScheduledRideStatus
    let riderApprovedMaxCents: Int?
    let lockedPriceCents: Int?
    let assignedDriverId: String?
    let activeRideId: String?
}

enum ScheduledRideError: LocalizedError {
    case notSignedIn
    case invalidTime(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Sign in before scheduling a ride."
        case .invalidTime(let message), .invalidResponse(let message): message
        }
    }
}
