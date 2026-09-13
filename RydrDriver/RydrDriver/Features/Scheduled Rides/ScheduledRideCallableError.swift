//
//  ScheduledRideCallableError.swift
//  Rydr Driver
//
//  Translates a Firebase callable failure into a case the app can act on.
//
//  The contract's instruction: "clients must branch on the reason rather than
//  message text." Message text can be reworded server-side at any time; the
//  `details.reason` is the contract. So this reads the reason first and falls
//  back to the coarse Firebase code only when it's absent or unrecognized.
//
//  Every Scheduled Rides callable goes through here.
//

import Foundation
import FirebaseFunctions

enum ScheduledRideCallableError: LocalizedError, Equatable {
    // unauthenticated
    case signInRequired
    // invalid-argument
    case invalidInput
    // permission-denied
    case notOwner
    case notAssignedDriver
    case driverNotEligible
    case notAllowlisted
    // not-found
    case requestNotFound
    case offerNotFound
    // failed-precondition
    case featureDisabled
    case invalidStatus
    case windowClosed
    case quoteChanged
    case activeRideConflict
    case scheduleConflict
    case paymentMethodUnavailable
    case etaStale
    // already-exists
    case requestIdInUse
    case operationAlreadyApplied
    // resource-exhausted
    case offerLimitReached
    case replacementCutoffReached
    // aborted
    case concurrentUpdate
    // unavailable
    case temporaryBackendFailure
    /// A reason this build doesn't know, or a non-callable failure like no
    /// network. Carries what we saw so it can be logged, not shown raw.
    case unrecognized(reason: String?)

    /// The full contract table, transcribed whole rather than trimmed to the
    /// reasons reachable today — so a later addition doesn't have to wonder
    /// whether a missing case was deliberate.
    private static let byReason: [String: ScheduledRideCallableError] = [
        "SIGN_IN_REQUIRED": .signInRequired,
        "INVALID_INPUT": .invalidInput,
        "NOT_OWNER": .notOwner,
        "NOT_ASSIGNED_DRIVER": .notAssignedDriver,
        "DRIVER_NOT_ELIGIBLE": .driverNotEligible,
        "NOT_ALLOWLISTED": .notAllowlisted,
        "REQUEST_NOT_FOUND": .requestNotFound,
        "OFFER_NOT_FOUND": .offerNotFound,
        "FEATURE_DISABLED": .featureDisabled,
        "INVALID_STATUS": .invalidStatus,
        "WINDOW_CLOSED": .windowClosed,
        "QUOTE_CHANGED": .quoteChanged,
        "ACTIVE_RIDE_CONFLICT": .activeRideConflict,
        "SCHEDULE_CONFLICT": .scheduleConflict,
        "PAYMENT_METHOD_UNAVAILABLE": .paymentMethodUnavailable,
        "ETA_STALE": .etaStale,
        "REQUEST_ID_IN_USE": .requestIdInUse,
        "OPERATION_ALREADY_APPLIED": .operationAlreadyApplied,
        "OFFER_LIMIT_REACHED": .offerLimitReached,
        "REPLACEMENT_CUTOFF_REACHED": .replacementCutoffReached,
        "CONCURRENT_UPDATE": .concurrentUpdate,
        "TEMPORARY_BACKEND_FAILURE": .temporaryBackendFailure
    ]

    init(_ error: Error) {
        // An error we already classified (a fixture, or a re-thrown one)
        // passes straight through instead of being re-parsed.
        if let already = error as? ScheduledRideCallableError {
            self = already
            return
        }

        let nsError = error as NSError
        let details = nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
        let reason = details?["reason"] as? String

        if let reason, let mapped = Self.byReason[reason] {
            self = mapped
            return
        }

        // No usable reason. Fall back to the Firebase code, which is coarse
        // but still tells us whether retrying could possibly help.
        guard nsError.domain == FunctionsErrorDomain,
              let code = FunctionsErrorCode(rawValue: nsError.code) else {
            self = .unrecognized(reason: reason)
            return
        }

        switch code {
        case .unauthenticated: self = .signInRequired
        case .invalidArgument: self = .invalidInput
        case .unavailable, .deadlineExceeded: self = .temporaryBackendFailure
        case .aborted: self = .concurrentUpdate
        default: self = .unrecognized(reason: reason)
        }
    }

    /// What the driver reads — each should say what happened and what next.
    var errorDescription: String? {
        switch self {
        case .signInRequired:
            return "Sign in again to continue."
        case .invalidInput:
            return "Something about this request looks wrong on our end. Try again."
        case .notOwner, .notAssignedDriver:
            return "This scheduled ride isn't assigned to you anymore."
        case .driverNotEligible:
            return "You're not eligible for this scheduled ride."
        case .notAllowlisted:
            return "Scheduled Rides isn't available on your account yet."
        case .requestNotFound, .offerNotFound:
            return "This scheduled ride is no longer available."
        case .featureDisabled:
            return "Scheduled Rides is temporarily unavailable."
        case .invalidStatus:
            return "This scheduled ride has already moved on."
        case .windowClosed:
            return "The window for this scheduled ride has closed."
        case .quoteChanged:
            return "The pay for this ride changed. Review the new amount and accept again."
        case .activeRideConflict:
            return "Finish your current ride before accepting a scheduled one."
        case .scheduleConflict:
            return "This overlaps a ride you've already committed to."
        case .paymentMethodUnavailable:
            return "The rider's payment method is unavailable."
        case .etaStale:
            return "Your pickup ETA was out of date. Try checking in again."
        case .requestIdInUse:
            return "That request is already in progress."
        case .operationAlreadyApplied:
            return "You've already done that."
        case .offerLimitReached:
            return "This ride already has the maximum number of driver offers."
        case .replacementCutoffReached:
            return "It's too late to take over this scheduled ride."
        case .concurrentUpdate:
            return "Someone else updated this at the same moment. Try again."
        case .temporaryBackendFailure:
            return "We couldn't reach Rydr. Check your connection and try again."
        case .unrecognized:
            return "Something went wrong. Try again."
        }
    }

    /// A property rather than an equality check at the call site, because a
    /// locally-expired fingerprint needs the identical recovery.
    var requiresFreshQuote: Bool {
        self == .quoteChanged
    }

    /// Our local view of the driver's commitments is stale — trust the
    /// listener's next snapshot over whatever the client just decided.
    var invalidatesLocalState: Bool {
        switch self {
        case .scheduleConflict, .activeRideConflict, .requestNotFound,
             .offerNotFound, .invalidStatus, .windowClosed, .notAssignedDriver:
            return true
        default:
            return false
        }
    }
}
