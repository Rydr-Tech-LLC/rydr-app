//
//  MockRideService.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 8/24/25.
//


import Foundation
import MapKit

/// A local, deterministic-ish mock of your backend.
/// Swap this out later for a real network implementation of `RideService`.
final class MockRideService: RideService, @unchecked Sendable {

    private struct RideSession {
        let id: String
        let driverId: String
        var cancelled: Bool = false
    }

    private var sessions: [String: RideSession] = [:]
    private let queue = DispatchQueue(label: "mock.ride.service")

    // MARK: - Nearby drivers

    func fetchNearbyDrivers(pickup: String, dropoff: String, rideType: String, near center: CLLocationCoordinate2D) async throws -> [Driver] {
        let names = ["Alex","Jamie","Taylor","Jordan","Riley","Morgan","Sam"]
        let cars = rideType.localizedCaseInsensitiveContains("eco")
            ? ["Tesla Model 3","Tesla Model Y","Ford Mustang Mach-E","Hyundai IONIQ 5","Kia EV6"]
            : ["Toyota Camry","Honda Accord","Tesla Model 3","BMW 3 Series","Audi A4"]

        func jitter(_ delta: Double) -> Double { Double.random(in: -delta...delta) }

        return (0..<3).map { _ in
            let coord = CLLocationCoordinate2D(latitude: center.latitude + jitter(0.01),
                                               longitude: center.longitude + jitter(0.01))
            return Driver(
                id: UUID().uuidString,
                name: names.randomElement()!,
                profileImage: nil,
                carImage: nil,
                carMakeModel: cars.randomElement()!,
                rating: Double.random(in: 4.5...4.95),
                compliments: ["Great Service","Clean Car","Friendly","Excellent Navigation"].shuffled().prefix(3).map { $0 },
                perMinute: [0.45,0.55,0.65].randomElement()!,
                perMile:   [1.10,1.25,1.35].randomElement()!,
                coordinate: coord,
                score: Int.random(in: 85...98)
            )
        }
    }

    // MARK: - Ride lifecycle

    func requestRide(
        driverId: String,
        pickup: String,
        dropoff: String,
        rideType: String,
        pickupCoordinate: CLLocationCoordinate2D?,
        dropoffCoordinate: CLLocationCoordinate2D?,
        estimate: RideEstimate?
    ) async throws -> String {
        let id = UUID().uuidString
        queue.sync {
            sessions[id] = RideSession(id: id, driverId: driverId)
        }
        return id
    }

    func awaitDriverDecision(rideId: String) async throws -> DriverDecision {
        // Simulate a short delay and a ~65% acceptance rate.
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1.0s

        // honour cancellation
        if Task.isCancelled { throw CancellationError() }

        let accept = Bool.random() && Bool.random()
        return accept ? .accepted : .declined
    }

    func driverLocationStream(rideId: String) -> AsyncStream<CLLocationCoordinate2D> {
        // Produce ~50 ticks of a simple linear movement.
        let totalTicks = 50
        let tickNs: UInt64 = 800_000_000 // 0.8s

        // Seed a start point per ride (stable within this stream)
        let start = CLLocationCoordinate2D(latitude: 33.7490 + Double.random(in: -0.01...0.01),
                                           longitude: -84.3880 + Double.random(in: -0.01...0.01))
        let end   = CLLocationCoordinate2D(latitude: start.latitude + 0.035,
                                           longitude: start.longitude + 0.035)

        return AsyncStream { continuation in
            Task.detached {
                for i in 0...totalTicks {
                    if Task.isCancelled { continuation.finish(); return }
                    let t = Double(i) / Double(totalTicks)
                    let lat = start.latitude * (1 - t) + end.latitude * t
                    let lon = start.longitude * (1 - t) + end.longitude * t
                    continuation.yield(.init(latitude: lat, longitude: lon))
                    try? await Task.sleep(nanoseconds: tickNs)
                }
                continuation.finish()
            }
        }
    }

    func cancelRide(rideId: String) async throws {
        queue.sync {
            sessions[rideId] = nil
        }
        // Nothing else to do in mock; real impl would notify the driver and stop streams.
    }
}
