//
//  ScheduledRideService.swift
//  Rydr Driver
//
//  Mock-backed for now. The Firebase opportunity/request collections and the
//  respondToScheduledRide callable now exist, but this client has not been
//  wired to them. The Driver integration sprint replaces these bodies with
//  authorized reads/listeners and callable Functions while preserving the
//  deterministic mock fixtures for QA.
//

import Foundation
import CoreLocation

final class ScheduledRideService {
    func fetchEligibleOpportunities(
        near coordinate: CLLocationCoordinate2D,
        radiusMiles: Double
    ) async throws -> [ScheduledRideOpportunity] {
        try await Task.sleep(nanoseconds: 400_000_000)
        return Self.mockOpportunities(near: coordinate)
    }

    func fetchConfirmedReservations(driverId: String) async throws -> [ScheduledRideReservation] {
        try await Task.sleep(nanoseconds: 400_000_000)
        return Self.mockReservations
    }

    /// Client "assume success" happy path for now — no rejection case to
    /// simulate yet, since mock data has no second driver to race against.
    /// The real respondToScheduledRide callable is the eventual replacement
    /// for this body; the async throws shape is already what it will need.
    func acceptOpportunity(_ opportunity: ScheduledRideOpportunity, driverId: String) async throws -> ScheduledRideReservation {
        try await Task.sleep(nanoseconds: 400_000_000)
        return ScheduledRideReservation(accepting: opportunity)
    }

    /// Mock "assume success" for now, same as acceptOpportunity — the real
    /// cancellation-and-reassignment flow (returning the ride to the
    /// matching pool for other drivers) is backend work not built yet.
    func cancelReservation(_ reservationID: String, driverId: String, reason: String) async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
    }

    /// The Driver app calculates the ETA via MapKit client-side (see
    /// ScheduledRidesDashboardVM.checkIn), then sends the result up here.
    /// This mock just accepts it; the real check-in callable would persist
    /// it and compute activation time = pickup − ETA − buffer server-side.
    func checkIn(reservationID: String, driverId: String, pickupETAMinutes: Double) async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
    }
}

private extension ScheduledRideService {
    static func mockOpportunities(near coordinate: CLLocationCoordinate2D) -> [ScheduledRideOpportunity] {
        let now = Date()
        return [
            ScheduledRideOpportunity(
                id: "mock-opp-1",
                rideType: "Rydr Go",
                pickupArea: "Midtown pickup area",
                pickupCoordinate: CLLocationCoordinate2D(
                    latitude: coordinate.latitude + 0.010,
                    longitude: coordinate.longitude + 0.008
                ),
                destinationArea: "Airport drop-off area",
                // Deliberately overlaps mockReservations' Buckhead ride below,
                // so this pin demonstrates the .conflicting eligibility state.
                pickupTime: now.addingTimeInterval(2 * 3600 + 10 * 60),
                estimatedTripMiles: 12.4,
                estimatedTripMinutes: 26,
                approvedMaximumCents: 3800,
                currency: "USD",
                responseDeadline: now.addingTimeInterval(45 * 60)
            ),
            ScheduledRideOpportunity(
                id: "mock-opp-2",
                rideType: "Rydr XL",
                pickupArea: "Downtown pickup area",
                pickupCoordinate: CLLocationCoordinate2D(
                    latitude: coordinate.latitude - 0.006,
                    longitude: coordinate.longitude + 0.014
                ),
                destinationArea: "Stadium drop-off area",
                pickupTime: now.addingTimeInterval(5 * 3600),
                estimatedTripMiles: 6.1,
                estimatedTripMinutes: 15,
                approvedMaximumCents: 2450,
                currency: "USD",
                responseDeadline: now.addingTimeInterval(90 * 60)
            ),
            ScheduledRideOpportunity(
                id: "mock-opp-3",
                rideType: "Rydr Go",
                pickupArea: "Sandy Springs pickup area",
                pickupCoordinate: CLLocationCoordinate2D(
                    latitude: coordinate.latitude + 0.022,
                    longitude: coordinate.longitude - 0.004
                ),
                destinationArea: "Perimeter drop-off area",
                pickupTime: now.addingTimeInterval(4 * 3600),
                estimatedTripMiles: 8.2,
                estimatedTripMinutes: 19,
                approvedMaximumCents: 2900,
                currency: "USD",
                // Deliberately in the past — demonstrates the .expired
                // eligibility state immediately, instead of requiring a real
                // 45-90 minute wait for mock-opp-1/2 to naturally expire.
                responseDeadline: now.addingTimeInterval(-10 * 60)
            )
        ]
    }

    static var mockReservations: [ScheduledRideReservation] {
        [
            ScheduledRideReservation(
                id: "mock-res-1",
                rideType: "Rydr Go",
                pickupArea: "Buckhead pickup area",
                pickupCoordinate: CLLocationCoordinate2D(
                    latitude: DriverMapDefaults.pilotCoordinate.latitude + 0.018,
                    longitude: DriverMapDefaults.pilotCoordinate.longitude - 0.012
                ),
                destinationArea: "Airport drop-off area",
                pickupTime: Date().addingTimeInterval(2 * 3600),
                estimatedTripMiles: 11.8,
                estimatedTripMinutes: 24,
                lockedBaseFareCents: 4200,
                currency: "USD",
                status: .confirmed,
                confirmedAt: Date().addingTimeInterval(-1800),
                checkedInAt: nil,
                pickupETAMinutes: nil
            ),
            ScheduledRideReservation(
                id: "mock-res-2",
                rideType: "Rydr Go",
                pickupArea: "Sandy Springs pickup area",
                pickupCoordinate: CLLocationCoordinate2D(
                    latitude: DriverMapDefaults.pilotCoordinate.latitude + 0.009,
                    longitude: DriverMapDefaults.pilotCoordinate.longitude + 0.021
                ),
                destinationArea: "Downtown drop-off area",
                // Deliberately clear of every other fixture's window —
                // exists so "already checked in to a different ride" is
                // testable without first manually accepting an opportunity
                // to create a second reservation.
                pickupTime: Date().addingTimeInterval(6 * 3600),
                estimatedTripMiles: 9.4,
                estimatedTripMinutes: 21,
                lockedBaseFareCents: 3100,
                currency: "USD",
                status: .confirmed,
                confirmedAt: Date().addingTimeInterval(-900),
                checkedInAt: nil,
                pickupETAMinutes: nil
            )
        ]
    }
}
