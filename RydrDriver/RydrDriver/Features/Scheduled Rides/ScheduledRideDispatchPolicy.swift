//
//  ScheduledRideDispatchPolicy.swift
//  Rydr Driver
//
//  What the driver sees and is told while a scheduled ride is activating.
//
//  Pure functions so the rules are testable: DriverDashboardVM has no
//  injection seam, and retrofitting one was out of scope. It keeps the
//  plumbing; the rules live here.
//

import Foundation

enum ScheduledRideDispatchPolicy {

    /// Filters the pending queue.
    ///
    /// Dispatch still requires being online, scheduled or not — activation
    /// allows 18 seconds to respond, which is meaningless to someone who isn't
    /// watching. Reminders, not this filter, get them online in time.
    ///
    /// An active lock then suppresses everything that isn't the scheduled ride.
    /// The server stops creating normal requests once it writes the lock, but
    /// one created moments earlier can still be pending.
    static func presentableRequests(
        _ requests: [DriverRideRequest],
        lock: ScheduledRideDispatchLock?,
        isOnline: Bool,
        now: Date = Date()
    ) -> [DriverRideRequest] {
        guard isOnline else { return [] }
        guard lock?.isActive(now: now) == true else { return requests }
        return requests.filter(\.isScheduledRydr)
    }

    /// Whether to stop advertising availability for normal work. Drives copy
    /// and the searching animation, not the queue.
    static func suppressesNormalDispatch(
        lock: ScheduledRideDispatchLock?,
        now: Date = Date()
    ) -> Bool {
        lock?.isActive(now: now) ?? false
    }

    /// What the driver is told while the lock is held.
    ///
    /// An expired lock returns `nil`: the server has moved on to replacement,
    /// and the client is in no position to claim otherwise.
    ///
    /// Offline is the case that matters — the driver is about to miss a ride
    /// they committed to, and going online is the only thing left that helps.
    static func statusMessage(
        lock: ScheduledRideDispatchLock?,
        reservation: ScheduledRideReservation?,
        isOnline: Bool,
        now: Date = Date()
    ) -> String? {
        guard let lock, lock.isActive(now: now) else { return nil }
        let time = reservation?.pickupTime.formatted(date: .omitted, time: .shortened)

        guard isOnline else {
            guard let time else {
                return "Your scheduled ride is activating — go online now to accept it."
            }
            return "Your \(time) scheduled ride is activating — go online now to accept it."
        }

        guard let reservation, let time else {
            return "Your scheduled ride is activating. Normal requests are paused."
        }
        return "Heading to your \(time) pickup in \(reservation.pickupArea). Normal requests are paused."
    }

    // MARK: - Acceptance and recovery

    /// A scheduled fare was locked at confirmation and can't move for traffic
    /// or later rate changes — worth saying once, here.
    static func acceptedMessage(for request: DriverRideRequest) -> String {
        request.isScheduledRydr
            ? "Scheduled ride accepted at your locked fare. Head to pickup."
            : "Ride accepted. Head to pickup."
    }

    /// Declining a scheduled ride clears the dispatch lock and starts
    /// replacement matching. The client doesn't start that — it reports it.
    static func declineMessage(for request: DriverRideRequest, missed: Bool) -> String {
        switch (request.isScheduledRydr, missed) {
        case (true, true):
            return "You missed your scheduled ride. We're finding the rider another driver."
        case (true, false):
            return "You declined your scheduled ride. We're finding the rider another driver."
        case (false, true):
            return "Looks like you missed this ride."
        case (false, false):
            return "You have chosen to decline this ride."
        }
    }

    /// Returned as a pair so the dashboard sets both values from one call.
    static func missedNotificationCopy(
        for request: DriverRideRequest
    ) -> (title: String, message: String) {
        guard request.isScheduledRydr else {
            return (
                "Missed ride request",
                "\(request.rideType) request from \(request.pickup) expired before you accepted."
            )
        }
        return (
            "Missed scheduled ride",
            "Your scheduled \(request.rideType) from \(request.pickup) activated and timed out. The rider is being matched with another driver."
        )
    }
}
