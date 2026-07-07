import Foundation

enum DriverRideLifecyclePolicy {
    static let pickupComplimentaryWaitSeconds: TimeInterval = 180

    static func normalizedStatus(_ status: String) -> String {
        switch status {
        case "arrived":
            return "arrivedAtPickup"
        case "waitingForRider":
            return "arrivedAtPickup"
        case "waitingAtStop":
            return "arrivedAtStop"
        case "navigatingToDropoff":
            return "inProgress"
        case "dropoffArrived":
            return "arrivedAtDropoff"
        case "driverCancelled", "riderCancelled", "adminCancelled":
            return "cancelled"
        default:
            return status
        }
    }

    static func riderState(forDriverStatus status: String) -> String {
        switch normalizedStatus(status) {
        case "accepted", "enRouteToPickup", "navigatingToPickup":
            return "driverEnRoute"
        case "arrivedAtPickup":
            return "driverArrived"
        case "navigatingToStop":
            return "inProgress"
        case "arrivedAtStop":
            return "driverAtStop"
        case "inProgress":
            return "inProgress"
        case "completed":
            return "completed"
        case "cancelled":
            return "cancelled"
        default:
            return "driverUpdated"
        }
    }

    static func pickupPaidWaitSeconds(
        waitStartedAt: Date?,
        paidWaitStartedAt: Date?,
        now: Date
    ) -> Int {
        if let paidWaitStartedAt {
            return max(0, Int(now.timeIntervalSince(paidWaitStartedAt).rounded(.down)))
        }

        guard let waitStartedAt else { return 0 }
        let elapsed = now.timeIntervalSince(waitStartedAt)
        return max(0, Int((elapsed - pickupComplimentaryWaitSeconds).rounded(.down)))
    }

    static func stopPaidWaitSeconds(stopWaitStartedAt: Date?, now: Date) -> Int {
        guard let stopWaitStartedAt else { return 0 }
        return max(0, Int(now.timeIntervalSince(stopWaitStartedAt).rounded(.down)))
    }
}
