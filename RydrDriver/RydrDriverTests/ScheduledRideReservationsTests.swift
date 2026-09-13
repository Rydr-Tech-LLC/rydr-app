import XCTest
@testable import RydrDriver

/// Deliverable 3: the confirmed-reservations section and the four states the
/// sprint calls out — empty, stale, relaunch, and offline.
@MainActor
final class ScheduledRideReservationsTests: XCTestCase {

    // MARK: - Money

    /// The contract permits the assigned driver to see `lockedBaseFareCents`
    /// but is explicit it "is not driver payout." The row and detail hero must
    /// render `driverPayoutCents`, and nothing at all when it is absent —
    /// never the rider's fare standing in for earnings.
    func testPayoutIsSeparateFromTheRidersLockedFare() {
        let reservation = ScheduledRideReservation.fixture(
            lockedBaseFareCents: 4200,
            driverPayoutCents: 2940
        )
        XCTAssertEqual(reservation.lockedBaseFareDisplay, "$42.00")
        XCTAssertEqual(reservation.driverPayoutDisplay, "$29.40")
    }

    func testMissingPayoutRendersNothingRatherThanTheRiderFare() {
        // Built directly rather than via `.fixture()`, which supplies a
        // payout by default — the point here is the projection omitting one.
        let withoutPayout = ScheduledRideReservation(
            id: "r", rideType: "Rydr Go", pickupArea: "A",
            pickupCoordinate: DriverMapDefaults.pilotCoordinate, destinationArea: "B",
            pickupTime: Date(), estimatedTripMiles: nil, estimatedTripMinutes: nil,
            lockedBaseFareCents: 4200, driverPayoutCents: nil, currency: "USD",
            status: .confirmed, confirmedAt: Date(), checkedInAt: nil, pickupETAMinutes: nil,
            activationAt: nil
        )
        XCTAssertNil(withoutPayout.driverPayoutDisplay)
        XCTAssertEqual(withoutPayout.lockedBaseFareDisplay, "$42.00")
    }

    /// Fixture money should mirror real money's relationship, not be two
    /// unrelated numbers.
    func testFixturePayoutUsesTheApprovedBasisPoints() {
        let reservation = ScheduledRideReservation.fixture(lockedBaseFareCents: 4200)
        XCTAssertEqual(reservation.driverPayoutCents, 2940, "70% of $42.00")
    }

    // MARK: - Derived timing (the "stale" state)

    /// Check-in opens 60 minutes before pickup and closes 50 minutes before,
    /// per the approved config.
    func testTimingWindowsMatchApprovedConfig() {
        let pickup = Date().addingTimeInterval(3 * 3600)
        let reservation = ScheduledRideReservation.fixture(pickupTime: pickup)

        XCTAssertEqual(reservation.checkInOpensAt, pickup.addingTimeInterval(-60 * 60))
        XCTAssertEqual(reservation.checkInDeadlineAt, pickup.addingTimeInterval(-50 * 60))
    }

    func testTimingProgressesThroughTheWindow() {
        let pickup = Date()
        let reservation = ScheduledRideReservation.fixture(pickupTime: pickup, status: .confirmed)

        XCTAssertEqual(reservation.timing(now: pickup.addingTimeInterval(-90 * 60)), .upcoming)
        XCTAssertEqual(reservation.timing(now: pickup.addingTimeInterval(-55 * 60)), .checkInOpen)
        XCTAssertEqual(reservation.timing(now: pickup.addingTimeInterval(-20 * 60)), .checkInMissed)
    }

    /// The headline "stale" case: pickup came and went and the server's
    /// once-a-minute deadline job never moved this on.
    func testPickupPassedWithoutProgressIsStale() {
        let reservation = ScheduledRideReservation.fixture(
            pickupTime: Date().addingTimeInterval(-30 * 60),
            status: .confirmed
        )
        XCTAssertEqual(reservation.timing(), .stale)
    }

    /// A reservation still reading `confirmed` inside its check-in window is
    /// normal, not broken — `advanceScheduledRideDeadlines` runs every minute,
    /// so the client is routinely ahead of it. The driver must be told the
    /// window is open rather than being asked to wait for one they're in.
    func testClientLeadsServerInsideTheCheckInWindow() {
        let reservation = ScheduledRideReservation.fixture(
            pickupTime: Date().addingTimeInterval(55 * 60),
            status: .confirmed          // server hasn't written checkInRequired yet
        )
        XCTAssertEqual(reservation.timing(), .checkInOpen)
    }

    func testTerminalStatusesAreClosedRegardlessOfClock() {
        for status in [ScheduledRideStatus.completed, .cancelled, .expired] {
            let reservation = ScheduledRideReservation.fixture(
                pickupTime: Date().addingTimeInterval(-5 * 3600),
                status: status
            )
            XCTAssertEqual(reservation.timing(), .closed, "\(status) should be closed")
        }
    }

    func testCheckedInIsNotReportedAsMissed() {
        let reservation = ScheduledRideReservation.fixture(
            pickupTime: Date().addingTimeInterval(10 * 60),
            status: .checkedIn
        )
        XCTAssertEqual(reservation.timing(), .checkedIn)
    }

    // MARK: - Empty vs loading vs failed

    /// Three states that all show no rows but mean different things. Telling a
    /// driver with a network problem "No Confirmed Rides" would be a lie about
    /// their work.
    func testLoadingIsDistinguishableFromEmpty() {
        let backend = FakeScheduledRideBackend()
        backend.answersListeners = false
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "d1")

        XCTAssertFalse(vm.hasLoadedReservations, "Never-answered must not read as loaded")
        XCTAssertTrue(vm.reservations.isEmpty)
        XCTAssertNil(vm.loadError)
    }

    func testEmptyAfterLoadingIsDistinguishableFromFailure() {
        let vm = ScheduledRidesDashboardVM(backend: FakeScheduledRideBackend())
        vm.startListening(driverId: "d1")
        drainMainQueue()

        XCTAssertTrue(vm.hasLoadedReservations, "An answered-with-nothing listener has loaded")
        XCTAssertTrue(vm.reservations.isEmpty)
        XCTAssertNil(vm.loadError)
    }

    func testFailureIsDistinguishableFromEmpty() {
        let backend = FakeScheduledRideBackend()
        backend.listenerError = ScheduledRideServiceError.notAuthenticated
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "d1")
        drainMainQueue()

        XCTAssertTrue(vm.hasLoadedReservations)
        XCTAssertTrue(vm.reservations.isEmpty)
        XCTAssertNotNil(vm.loadError)
    }

    // MARK: - Offline

    /// Firestore serves from its local cache when offline. The data is real,
    /// so it stays on screen — the banner says it may be behind.
    func testCachedSnapshotSurfacesOfflineWithoutHidingData() {
        let backend = FakeScheduledRideBackend()
        backend.reservations = [.fixture(id: "r1"), .fixture(id: "r2")]
        backend.isFromCache = true
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "d1")
        drainMainQueue()

        XCTAssertTrue(vm.isShowingCachedData)
        XCTAssertEqual(vm.reservations.count, 2, "Offline must not empty the list")
        XCTAssertNil(vm.loadError, "Cached data is not an error")
    }

    func testServerSnapshotClearsTheOfflineFlag() {
        let vm = ScheduledRidesDashboardVM(backend: FakeScheduledRideBackend.qaFixtures())
        vm.startListening(driverId: "d1")
        drainMainQueue()

        XCTAssertFalse(vm.isShowingCachedData)
    }

    // MARK: - Relaunch

    /// Reopening the screen must re-derive everything from the server rather
    /// than carrying the previous session's flags — otherwise a stale offline
    /// banner or empty state renders before the first snapshot lands.
    func testRelaunchResetsStateBeforeReattaching() {
        let cached = FakeScheduledRideBackend()
        cached.reservations = [.fixture(id: "r1")]
        cached.isFromCache = true
        let vm = ScheduledRidesDashboardVM(backend: cached)
        vm.startListening(driverId: "d1")
        drainMainQueue()
        XCTAssertTrue(vm.isShowingCachedData)

        vm.stopListening()

        // Relaunch against a service that answers from the server.
        let fresh = FakeScheduledRideBackend()
        fresh.reservations = [.fixture(id: "r1")]
        let relaunched = ScheduledRidesDashboardVM(backend: fresh)
        relaunched.startListening(driverId: "d1")
        XCTAssertFalse(relaunched.hasLoadedReservations, "Flags start cleared, not inherited")
        drainMainQueue()

        XCTAssertFalse(relaunched.isShowingCachedData)
        XCTAssertEqual(relaunched.reservations.map(\.id), ["r1"])
    }

    /// Relaunch renders whatever the server currently says, including rides
    /// that were cancelled while the app was closed.
    func testRelaunchReflectsServerTruthNotLastKnownState() {
        let backend = FakeScheduledRideBackend()
        backend.reservations = [.fixture(id: "r1"), .fixture(id: "gone")]
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "d1")
        drainMainQueue()
        XCTAssertEqual(vm.reservations.count, 2)

        // Server no longer returns "gone" — a rider cancelled it while away.
        let afterCancel = FakeScheduledRideBackend()
        afterCancel.reservations = [.fixture(id: "r1")]
        let afterRelaunch = ScheduledRidesDashboardVM(backend: afterCancel)
        afterRelaunch.startListening(driverId: "d1")
        drainMainQueue()

        XCTAssertEqual(afterRelaunch.reservations.map(\.id), ["r1"])
    }

    // MARK: - Ordering

    /// A schedule read top-down has to be chronological. The server returns
    /// documents in its own order.
    func testReservationsAreSortedBySoonestPickup() {
        let now = Date()
        let backend = FakeScheduledRideBackend()
        backend.reservations = [
            .fixture(id: "late", pickupTime: now.addingTimeInterval(6 * 3600)),
            .fixture(id: "soon", pickupTime: now.addingTimeInterval(1 * 3600)),
            .fixture(id: "mid", pickupTime: now.addingTimeInterval(3 * 3600))
        ]
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "d1")
        drainMainQueue()

        XCTAssertEqual(vm.reservations.map(\.id), ["soon", "mid", "late"])
    }

    // MARK: - Helpers

    private func drainMainQueue(timeout: TimeInterval = 1) {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: timeout)
    }
}
