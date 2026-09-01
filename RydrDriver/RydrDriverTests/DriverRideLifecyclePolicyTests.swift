import XCTest
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
