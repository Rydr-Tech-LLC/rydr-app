import XCTest
@testable import RydrDriver

final class DriverRideLifecyclePolicyTests: XCTestCase {
    func testNormalizesLegacyStatuses() {
        XCTAssertEqual(DriverRideLifecyclePolicy.normalizedStatus("arrived"), "arrivedAtPickup")
        XCTAssertEqual(DriverRideLifecyclePolicy.normalizedStatus("waitingForRider"), "arrivedAtPickup")
        XCTAssertEqual(DriverRideLifecyclePolicy.normalizedStatus("waitingAtStop"), "arrivedAtStop")
        XCTAssertEqual(DriverRideLifecyclePolicy.normalizedStatus("navigatingToDropoff"), "inProgress")
        XCTAssertEqual(DriverRideLifecyclePolicy.normalizedStatus("dropoffArrived"), "arrivedAtDropoff")
        XCTAssertEqual(DriverRideLifecyclePolicy.normalizedStatus("driverCancelled"), "cancelled")
    }

    func testMapsDriverStatusToRiderState() {
        XCTAssertEqual(DriverRideLifecyclePolicy.riderState(forDriverStatus: "accepted"), "driverEnRoute")
        XCTAssertEqual(DriverRideLifecyclePolicy.riderState(forDriverStatus: "arrivedAtPickup"), "driverArrived")
        XCTAssertEqual(DriverRideLifecyclePolicy.riderState(forDriverStatus: "navigatingToStop"), "inProgress")
        XCTAssertEqual(DriverRideLifecyclePolicy.riderState(forDriverStatus: "arrivedAtStop"), "driverAtStop")
        XCTAssertEqual(DriverRideLifecyclePolicy.riderState(forDriverStatus: "completed"), "completed")
    }

    func testPickupPaidWaitStartsAfterComplimentaryWindow() {
        let started = Date(timeIntervalSince1970: 1_000)
        let beforeGraceEnds = started.addingTimeInterval(120)
        let afterGraceEnds = started.addingTimeInterval(195)

        XCTAssertEqual(
            DriverRideLifecyclePolicy.pickupPaidWaitSeconds(
                waitStartedAt: started,
                paidWaitStartedAt: nil,
                now: beforeGraceEnds
            ),
            0
        )
        XCTAssertEqual(
            DriverRideLifecyclePolicy.pickupPaidWaitSeconds(
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
            DriverRideLifecyclePolicy.stopPaidWaitSeconds(stopWaitStartedAt: started, now: now),
            42
        )
    }
}
