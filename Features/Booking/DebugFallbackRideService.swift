import Foundation
import CoreLocation

final class DebugFallbackRideService: RideService, @unchecked Sendable {
    private let primary: RideService
    private let fallback: RideService
    private let queue = DispatchQueue(label: "debug.fallback.ride.service")
    private var fallbackRideIds: Set<String> = []

    #if DEBUG
    private var shouldUseMockRidesImmediately: Bool {
        ProcessInfo.processInfo.environment["RYDR_USE_MOCK_RIDES"] == "1"
    }
    #endif

    init(primary: RideService, fallback: RideService) {
        self.primary = primary
        self.fallback = fallback
    }

    func fetchNearbyDrivers(
        pickup: String,
        dropoff: String,
        rideType: String,
        near center: CLLocationCoordinate2D,
        pickupCoordinate: CLLocationCoordinate2D?,
        dropoffCoordinate: CLLocationCoordinate2D?
    ) async throws -> [Driver] {
        #if DEBUG
        if shouldUseMockRidesImmediately {
            return try await fallback.fetchNearbyDrivers(
                pickup: pickup,
                dropoff: dropoff,
                rideType: rideType,
                near: center,
                pickupCoordinate: pickupCoordinate,
                dropoffCoordinate: dropoffCoordinate
            )
        }

        do {
            let drivers = try await primary.fetchNearbyDrivers(
                pickup: pickup,
                dropoff: dropoff,
                rideType: rideType,
                near: center,
                pickupCoordinate: pickupCoordinate,
                dropoffCoordinate: dropoffCoordinate
            )
            if !drivers.isEmpty { return drivers }
        } catch {
            print("Using mock drivers after primary driver lookup failed:", error.localizedDescription)
        }
        return try await fallback.fetchNearbyDrivers(
            pickup: pickup,
            dropoff: dropoff,
            rideType: rideType,
            near: center,
            pickupCoordinate: pickupCoordinate,
            dropoffCoordinate: dropoffCoordinate
        )
        #else
        return try await primary.fetchNearbyDrivers(
            pickup: pickup,
            dropoff: dropoff,
            rideType: rideType,
            near: center,
            pickupCoordinate: pickupCoordinate,
            dropoffCoordinate: dropoffCoordinate
        )
        #endif
    }

    func requestRide(
        driverId: String,
        pickup: String,
        dropoff: String,
        rideType: String,
        pickupCoordinate: CLLocationCoordinate2D?,
        dropoffCoordinate: CLLocationCoordinate2D?,
        estimate: RideEstimate?
    ) async throws -> String {
        #if DEBUG
        if shouldUseMockRidesImmediately {
            let rideId = try await fallback.requestRide(
                driverId: driverId,
                pickup: pickup,
                dropoff: dropoff,
                rideType: rideType,
                pickupCoordinate: pickupCoordinate,
                dropoffCoordinate: dropoffCoordinate,
                estimate: estimate
            )
            markFallbackRide(rideId)
            return rideId
        }

        do {
            return try await primary.requestRide(
                driverId: driverId,
                pickup: pickup,
                dropoff: dropoff,
                rideType: rideType,
                pickupCoordinate: pickupCoordinate,
                dropoffCoordinate: dropoffCoordinate,
                estimate: estimate
            )
        } catch {
            print("Using mock ride request after primary request failed:", error.localizedDescription)
            let rideId = try await fallback.requestRide(
                driverId: driverId,
                pickup: pickup,
                dropoff: dropoff,
                rideType: rideType,
                pickupCoordinate: pickupCoordinate,
                dropoffCoordinate: dropoffCoordinate,
                estimate: estimate
            )
            markFallbackRide(rideId)
            return rideId
        }
        #else
        return try await primary.requestRide(
            driverId: driverId,
            pickup: pickup,
            dropoff: dropoff,
            rideType: rideType,
            pickupCoordinate: pickupCoordinate,
            dropoffCoordinate: dropoffCoordinate,
            estimate: estimate
        )
        #endif
    }

    func awaitDriverDecision(rideId: String) async throws -> DriverDecision {
        #if DEBUG
        if shouldUseMockRidesImmediately || isFallbackRide(rideId) {
            return try await fallback.awaitDriverDecision(rideId: rideId)
        }
        do {
            return try await primary.awaitDriverDecision(rideId: rideId)
        } catch {
            print("Using mock driver decision after primary decision failed:", error.localizedDescription)
            return try await fallback.awaitDriverDecision(rideId: rideId)
        }
        #else
        return try await primary.awaitDriverDecision(rideId: rideId)
        #endif
    }

    func driverLocationStream(rideId: String) -> AsyncStream<CLLocationCoordinate2D> {
        #if DEBUG
        if shouldUseMockRidesImmediately || isFallbackRide(rideId) {
            return fallback.driverLocationStream(rideId: rideId)
        }
        #endif
        return primary.driverLocationStream(rideId: rideId)
    }

    func rideLifecycleStream(rideId: String) -> AsyncThrowingStream<RideLifecycleSnapshot, Error> {
        #if DEBUG
        if shouldUseMockRidesImmediately || isFallbackRide(rideId) {
            return fallback.rideLifecycleStream(rideId: rideId)
        }
        #endif
        return primary.rideLifecycleStream(rideId: rideId)
    }

    func cancelRide(rideId: String) async throws {
        #if DEBUG
        if shouldUseMockRidesImmediately || isFallbackRide(rideId) {
            try await fallback.cancelRide(rideId: rideId)
            return
        }
        #endif
        try await primary.cancelRide(rideId: rideId)
    }

    private func markFallbackRide(_ rideId: String) {
        queue.sync {
            _ = fallbackRideIds.insert(rideId)
        }
    }

    private func isFallbackRide(_ rideId: String) -> Bool {
        queue.sync {
            fallbackRideIds.contains(rideId)
        }
    }
}
