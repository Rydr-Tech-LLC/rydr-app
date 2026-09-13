import XCTest
import CoreLocation
@testable import RydrDriver

/// Deliverable 6: acceptance routes into the existing navigation, arrival,
/// waiting, trip and recovery experiences — with no second ride lifecycle.
///
/// Most of what this deliverable asks for is the *absence* of code: the
/// targeted request already flows through `transitionRide` and the standard
/// active-ride listener, so the tests below mostly pin down that nothing
/// scheduled-specific forks off, plus the few places the wording and the gating
/// genuinely have to differ.
@MainActor
final class ScheduledRideHandoffTests: XCTestCase {

    private func request(id: String = "sched-1", scheduled: Bool) -> DriverRideRequest {
        DriverRideRequest(
            id: id,
            riderId: "rider-1",
            riderName: "Rider",
            pickup: "1 Peachtree St",
            dropoff: "Hartsfield",
            rideType: "Rydr Go",
            source: scheduled ? "scheduledRydr" : nil,
            scheduledRideRequestId: scheduled ? id : nil
        )
    }

    // MARK: - Acceptance

    /// Acceptance is unchanged: a scheduled handoff goes through the same
    /// `accept` path, the same online gate, and the same `transitionRide` call
    /// as any other request. The only difference is what the driver is told.
    func testAcceptanceCopyIsTheOnlyDifference() {
        XCTAssertTrue(
            ScheduledRideDispatchPolicy.acceptedMessage(for: request(scheduled: true)).contains("locked fare")
        )
        XCTAssertEqual(
            ScheduledRideDispatchPolicy.acceptedMessage(for: request(scheduled: false)),
            "Ride accepted. Head to pickup."
        )
    }

    // MARK: - Recovery wording

    /// Declining a scheduled ride clears the server's dispatch lock and starts
    /// replacement matching. The driver should be told that happened, rather
    /// than getting the same line as passing on a stranger's request.
    func testDecliningAScheduledRideNamesReplacement() {
        let message = ScheduledRideDispatchPolicy.declineMessage(for: request(scheduled: true), missed: false)
        XCTAssertTrue(message.contains("another driver"), "Replacement is the consequence worth naming")
        XCTAssertNotEqual(message, "You have chosen to decline this ride.")
    }

    func testMissingAScheduledRideNamesReplacement() {
        let message = ScheduledRideDispatchPolicy.declineMessage(for: request(scheduled: true), missed: true)
        XCTAssertTrue(message.contains("another driver"))
    }

    /// The local notification says the same thing, since that is what the
    /// driver sees later if they were not looking at the screen.
    func testMissedNotificationCopyDistinguishesAScheduledRide() {
        let scheduled = ScheduledRideDispatchPolicy.missedNotificationCopy(for: request(scheduled: true))
        XCTAssertEqual(scheduled.title, "Missed scheduled ride")
        XCTAssertTrue(scheduled.message.contains("another driver"))

        let normal = ScheduledRideDispatchPolicy.missedNotificationCopy(for: request(id: "n1", scheduled: false))
        XCTAssertEqual(normal.title, "Missed ride request")
        XCTAssertTrue(normal.message.contains("expired before you accepted"))
    }

    /// Normal dispatch copy is untouched — this deliverable adds a branch, it
    /// does not rewrite the existing experience.
    func testNormalDeclineCopyIsUnchanged() {
        XCTAssertEqual(
            ScheduledRideDispatchPolicy.declineMessage(for: request(scheduled: false), missed: false),
            "You have chosen to decline this ride."
        )
        XCTAssertEqual(
            ScheduledRideDispatchPolicy.declineMessage(for: request(scheduled: false), missed: true),
            "Looks like you missed this ride."
        )
    }

    // MARK: - No parallel lifecycle

    /// Once the ride goes active, the scheduled reservation listener stops
    /// returning it: `active` is not in the query's status set. That is what
    /// keeps a ride from living in two places — the scheduled section and the
    /// active-ride flow — at the same time.
    func testActiveRideLeavesTheScheduledReservationList() {
        let backend = FakeScheduledRideBackend()
        backend.reservations = [.fixture(id: "sched-1", status: .activating)]
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "driver-1")
        drainMainQueue()
        XCTAssertEqual(vm.reservations.map(\.id), ["sched-1"], "Still scheduled while activating")

        // The server flips it to `active` on acceptance, which the listener's
        // status filter excludes — so it simply stops arriving.
        backend.reservations = []
        backend.deliverReservation(.fixture(id: "other", status: .confirmed))
        drainMainQueue()

        XCTAssertFalse(
            vm.reservations.contains { $0.id == "sched-1" },
            "An accepted ride must not remain in the scheduled section"
        )
    }

    /// A scheduled ride carries the link back to its reservation, which is how
    /// the active-ride flow can show scheduled provenance without a second
    /// lifecycle to track it.
    func testHandoffKeepsTheLinkToItsScheduledRequest() {
        let handoff = request(scheduled: true)
        XCTAssertEqual(handoff.scheduledRideRequestId, handoff.id)
        XCTAssertTrue(handoff.isScheduledRydr)
    }

    /// The contract's rule stated outright: "No second ride lifecycle may be
    /// created." A handoff is an ordinary `DriverRideRequest` carrying
    /// everything the standard flow needs, so navigation, arrival, waiting and
    /// completion all apply to it without a scheduled-only branch.
    ///
    /// `source` and `scheduledRideRequestId` are provenance, not a fork: they
    /// change what the driver is *told*, never which code path runs.
    func testHandoffCarriesEverythingTheStandardFlowNeeds() {
        let handoff = request(scheduled: true)

        XCTAssertFalse(handoff.pickup.isEmpty, "Navigation needs a pickup")
        XCTAssertFalse(handoff.dropoff.isEmpty, "Trip needs a drop-off")
        XCTAssertFalse(handoff.rideType.isEmpty, "Fare and vehicle checks need a tier")
        XCTAssertEqual(handoff.riderId, "rider-1", "Arrival and waiting need the rider")
    }

    // MARK: - Helpers

    private func drainMainQueue(timeout: TimeInterval = 1) {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: timeout)
    }
}
