import Foundation

/// Terminal server observations win over delayed active-query/cache snapshots.
struct DriverRideObservationPolicy {
    private var terminalIDs = Set<String>()
    func allows(_ rideID: String) -> Bool { !terminalIDs.contains(rideID) }
    mutating func markTerminal(_ rideID: String) { terminalIDs.insert(rideID) }
}
