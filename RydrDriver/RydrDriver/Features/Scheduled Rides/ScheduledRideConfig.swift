//
//  ScheduledRideConfig.swift
//  Rydr Driver
//
//  Client mirror of the approved `platformConfig/scheduledRides` values.
//
//  Display-only: "Firebase config is authoritative; iOS copies become
//  display-only." Nothing here may decide whether an action is allowed — only
//  describe timing without a round trip.
//
//  Once the backend stores real `checkInOpensAt` / `checkInDeadlineAt`
//  timestamps, prefer those and keep these as the fallback.
//

import Foundation

enum ScheduledRideConfig {
    /// Check-in opens this long before pickup.
    static let driverCheckInLeadMinutes: Double = 60

    /// Grace after opening, so the deadline is 50 minutes before pickup.
    static let driverCheckInGraceMinutes: Double = 10

    /// A submitted MapKit ETA must be fresher than this.
    static let checkInEtaMaxAgeMinutes: Double = 5

    /// Added to `pickup − ETA` when the server computes activation time.
    static let activationBufferMinutes: Double = 5

    /// Response window for the targeted request activation creates.
    static let activationDispatchTimeoutSeconds = 18

    /// A quote fingerprint's lifetime.
    static let driverQuoteValidityMinutes: Double = 5

    /// Choose My Driver's offer cap.
    static let maximumOffers = 3

    /// Driver's share of the ride subtotal (7000 = 70%).
    static let driverPayoutBasisPoints = 7000
}
