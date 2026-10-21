import XCTest
import CoreLocation
@testable import RydrDriver

final class DriverRidePresentationPolicyTests: XCTestCase {
    func testNormalizesLegacyStatuses() {
        XCTAssertEqual(DriverRidePresentationPolicy.normalizedStatus("arrived"), "arrivedAtPickup")
        XCTAssertEqual(DriverRidePresentationPolicy.normalizedStatus("waitingForRider"), "arrivedAtPickup")
        XCTAssertEqual(DriverRidePresentationPolicy.normalizedStatus("waitingAtStop"), "arrivedAtStop")
        XCTAssertEqual(DriverRidePresentationPolicy.normalizedStatus("navigatingToDropoff"), "inProgress")
        XCTAssertEqual(DriverRidePresentationPolicy.normalizedStatus("dropoffArrived"), "arrivedAtDropoff")
        XCTAssertEqual(DriverRidePresentationPolicy.normalizedStatus("driverCancelled"), "cancelled")
    }

    func testMapsDriverStatusToRiderState() {
        XCTAssertEqual(DriverRidePresentationPolicy.riderState(forDriverStatus: "accepted"), "driverEnRoute")
        XCTAssertEqual(DriverRidePresentationPolicy.riderState(forDriverStatus: "arrivedAtPickup"), "driverArrived")
        XCTAssertEqual(DriverRidePresentationPolicy.riderState(forDriverStatus: "navigatingToStop"), "inProgress")
        XCTAssertEqual(DriverRidePresentationPolicy.riderState(forDriverStatus: "arrivedAtStop"), "driverAtStop")
        XCTAssertEqual(DriverRidePresentationPolicy.riderState(forDriverStatus: "completed"), "completed")
    }

    func testPickupPaidWaitStartsAfterComplimentaryWindow() {
        let started = Date(timeIntervalSince1970: 1_000)
        let beforeGraceEnds = started.addingTimeInterval(120)
        let afterGraceEnds = started.addingTimeInterval(195)

        XCTAssertEqual(
            DriverRidePresentationPolicy.pickupPaidWaitSeconds(
                waitStartedAt: started,
                paidWaitStartedAt: nil,
                now: beforeGraceEnds
            ),
            0
        )
        XCTAssertEqual(
            DriverRidePresentationPolicy.pickupPaidWaitSeconds(
                waitStartedAt: started,
                paidWaitStartedAt: nil,
                now: afterGraceEnds
            ),
            15
        )
    }

    func testStopWaitIsPaidImmediately() {
        let started = Date(timeIntervalSince1970: 1_000)
        let now = started.addingTimeInterval(42)

        XCTAssertEqual(
            DriverRidePresentationPolicy.stopPaidWaitSeconds(stopWaitStartedAt: started, now: now),
            42
        )
    }
}

final class NavigationRouteGeometryTests: XCTestCase {
    private let path = [CLLocationCoordinate2D(latitude: 33, longitude: -84),
                        CLLocationCoordinate2D(latitude: 33.001, longitude: -84),
                        CLLocationCoordinate2D(latitude: 33.001, longitude: -83.999)]
    func testAnimationFollowsRoadAroundCornerRatherThanDrawingDiagonal() throws {
        let firstLeg = NavigationRouteGeometry.distance(path[0], path[1])
        let corner = try XCTUnwrap(NavigationRouteGeometry.coordinate(at: firstLeg, path: path))
        XCTAssertEqual(corner.latitude, path[1].latitude, accuracy: 0.000001)
        XCTAssertEqual(corner.longitude, path[1].longitude, accuracy: 0.000001)
        let afterCorner = try XCTUnwrap(NavigationRouteGeometry.coordinate(at: firstLeg + 20, path: path))
        XCTAssertEqual(afterCorner.latitude, path[1].latitude, accuracy: 0.000001)
        XCTAssertGreaterThan(afterCorner.longitude, path[1].longitude)
    }
    func testOffRouteGPSIsNotGluedThroughBuildingsToDistantRoute() {
        let off = CLLocationCoordinate2D(latitude: 33.01, longitude: -84)
        let displayed = NavigationRouteGeometry.snapped(off, path: path)
        XCTAssertEqual(displayed.latitude, off.latitude)
        XCTAssertEqual(displayed.longitude, off.longitude)
    }
    func testHeadingUsesCurrentForwardSegmentAndWrapsAcrossNorth() throws {
        let heading = try XCTUnwrap(NavigationRouteGeometry.heading(at: CLLocationCoordinate2D(latitude: 33.001, longitude: -83.9998), path: path))
        XCTAssertEqual(heading, 90, accuracy: 1)
        XCTAssertLessThan(NavigationRouteGeometry.easedHeading(from: 359, to: 1), 3)
    }
    func testDuplicateVerticesStayFinite() throws {
        let p = path[0]
        let match = try XCTUnwrap(NavigationRouteGeometry.match(p, path: [p,p,path[1]]))
        XCTAssertTrue(match.progress.isFinite)
        XCTAssertEqual(match.distance, 0)
    }
}

final class DriverRideObservationPolicyTests: XCTestCase {
    func testCancelledRideCannotBeResurrectedByDelayedActiveSnapshot() {
        var state = DriverRideObservationPolicy()
        XCTAssertTrue(state.allows("first"))
        state.markTerminal("first")
        XCTAssertFalse(state.allows("first"))
        XCTAssertTrue(state.allows("next"))
        state.markTerminal("first")
        XCTAssertTrue(state.allows("next"))
    }
}

final class NavigationLocationQualityTests: XCTestCase {
    func testRejectsStaleInaccurateAndImpossibleJumps() {
        let now = Date()
        func fix(_ lat: Double, accuracy: Double = 5, age: Double = 0) -> CLLocation {
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: -84), altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5, timestamp: now.addingTimeInterval(-age))
        }
        XCTAssertFalse(NavigationRouteGeometry.usableLocation(fix(33,accuracy:100), previous:nil, now:now))
        XCTAssertFalse(NavigationRouteGeometry.usableLocation(fix(33,age:30), previous:nil, now:now))
        XCTAssertFalse(NavigationRouteGeometry.usableLocation(fix(33.01), previous:fix(33,age:1), now:now))
        XCTAssertTrue(NavigationRouteGeometry.usableLocation(fix(33.0001), previous:fix(33,age:1), now:now))
    }
}


final class NavigationInstructionProgressTests: XCTestCase {
    func testInstructionsAdvanceLocallyWithoutRequestingAnotherRoute() {
        XCTAssertEqual(NavigationRouteGeometry.instructionIndex(progress: 50, stepEnds: [100,200,300]), 0)
        XCTAssertEqual(NavigationRouteGeometry.instructionIndex(progress: 120, stepEnds: [100,200,300]), 1)
        XCTAssertEqual(NavigationRouteGeometry.instructionIndex(progress: 350, stepEnds: [100,200,300]), 2)
    }
}
