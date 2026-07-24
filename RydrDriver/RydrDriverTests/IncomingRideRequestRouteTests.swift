import CoreLocation
import XCTest
@testable import RydrDriver

final class IncomingRideRequestRouteTests: XCTestCase {
    private enum StubRouteError: Error {
        case unavailable
    }

    func testPickupRouteKeyChangesWhenFirstDriverLocationArrives() {
        let requestID = "request-1"
        let beforeLocation = PickupRouteCalculationKey(
            requestID: requestID,
            driverCoordinate: nil
        )
        let afterLocation = PickupRouteCalculationKey(
            requestID: requestID,
            driverCoordinate: CLLocationCoordinate2D(latitude: 45.5229, longitude: -122.9898)
        )

        XCTAssertNotEqual(beforeLocation, afterLocation)
    }

    func testPickupRouteKeyDoesNotChangeForLaterGPSMovement() {
        let requestID = "request-1"
        let firstLocation = PickupRouteCalculationKey(
            requestID: requestID,
            driverCoordinate: CLLocationCoordinate2D(latitude: 45.5229, longitude: -122.9898)
        )
        let nearbyLocation = PickupRouteCalculationKey(
            requestID: requestID,
            driverCoordinate: CLLocationCoordinate2D(latitude: 45.5230, longitude: -122.9897)
        )

        XCTAssertEqual(firstLocation, nearbyLocation)
    }

    func testPickupRouteKeyChangesForNewRequest() {
        let coordinate = CLLocationCoordinate2D(latitude: 45.5229, longitude: -122.9898)
        let firstRequest = PickupRouteCalculationKey(
            requestID: "request-1",
            driverCoordinate: coordinate
        )
        let nextRequest = PickupRouteCalculationKey(
            requestID: "request-2",
            driverCoordinate: coordinate
        )

        XCTAssertNotEqual(firstRequest, nextRequest)
    }

    func testNoMapKitRouteUsesStraightLineFallback() async {
        let start = CLLocationCoordinate2D(latitude: 45.5229, longitude: -122.9898)
        let end = CLLocationCoordinate2D(latitude: 45.5301, longitude: -122.9794)

        let estimate = await RideRequestRouteEstimator.estimate(
            from: start,
            to: end
        ) { _, _ in
            nil
        }

        XCTAssertNotNil(estimate)
        XCTAssertGreaterThan(estimate?.distanceMiles ?? 0, 0)
        XCTAssertGreaterThanOrEqual(estimate?.durationMinutes ?? 0, 1)
    }

    func testMapKitFailureUsesStraightLineFallback() async {
        let start = CLLocationCoordinate2D(latitude: 45.5229, longitude: -122.9898)
        let end = CLLocationCoordinate2D(latitude: 45.5301, longitude: -122.9794)

        let estimate = await RideRequestRouteEstimator.estimate(
            from: start,
            to: end
        ) { _, _ in
            throw StubRouteError.unavailable
        }

        XCTAssertNotNil(estimate)
        XCTAssertGreaterThan(estimate?.distanceMiles ?? 0, 0)
        XCTAssertGreaterThanOrEqual(estimate?.durationMinutes ?? 0, 1)
    }
}
