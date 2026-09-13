import XCTest
import CoreLocation
@testable import RydrDriver

/// Deliverable 4: MapKit ETA, the real check-in callable, and the
/// check-in-required / checked-in / activating states.
///
/// Covers the sprint's named cases — MapKit success, stale ETA, location
/// denial, low accuracy, and route failure.
@MainActor
final class ScheduledRideCheckInTests: XCTestCase {

    /// Inside the approved window: pickup 55 minutes out sits between
    /// `pickup − 60m` (opens) and `pickup − 50m` (deadline).
    private func openWindowReservation(
        id: String = "res-1",
        status: ScheduledRideStatus = .checkInRequired
    ) -> ScheduledRideReservation {
        .fixture(id: id, pickupTime: Date().addingTimeInterval(55 * 60), status: status)
    }

    /// A stand-in for MapKit that always finds a 12-minute route.
    private let routeFound: ScheduledRideRouteEstimator = { _, _ in
        RideRequestLegEstimate(distanceMiles: 4.2, durationMinutes: 12)
    }

    /// MapKit could not produce a route — no connectivity, or no drivable path.
    private let routeMissing: ScheduledRideRouteEstimator = { _, _ in nil }

    private func goodFix() -> CLLocation {
        CLLocation(
            coordinate: DriverMapDefaults.pilotCoordinate,
            altitude: 0,
            horizontalAccuracy: 12,
            verticalAccuracy: 12,
            timestamp: Date()
        )
    }

    // MARK: - Preflight: the three device-side failures

    /// Location denial. No fix means no ETA, and no ETA means no check-in —
    /// Firebase has no server-side routing to fall back on.
    func testLocationDenialIsRefusedBeforeAnyCall() async {
        let reservation = openWindowReservation()
        let backend = FakeScheduledRideBackend()
        backend.reservations = [reservation]
        let vm = ScheduledRidesDashboardVM(backend: backend, routeEstimator: routeFound)
        vm.startListening(driverId: "d1")
        await drain()

        await vm.checkIn(reservation, driverId: "d1", location: nil)

        XCTAssertFalse(backend.didSubmitCheckIn, "Must not call the server without a location")
        XCTAssertEqual(
            vm.checkInState,
            .failed(ScheduledRideCheckInPreflightError.locationUnavailable.errorDescription!)
        )
    }

    /// Low accuracy. A coarse fix produces a bad ETA, and a bad ETA moves the
    /// server's activation time — so we refuse rather than submit a number we
    /// don't believe.
    func testLowAccuracyFixIsRefused() async {
        let reservation = openWindowReservation()
        let backend = FakeScheduledRideBackend()
        backend.reservations = [reservation]
        let vm = ScheduledRidesDashboardVM(backend: backend, routeEstimator: routeFound)
        vm.startListening(driverId: "d1")
        await drain()

        let coarse = CLLocation(
            coordinate: DriverMapDefaults.pilotCoordinate,
            altitude: 0,
            horizontalAccuracy: 500,   // well past the 100 m ceiling
            verticalAccuracy: 500,
            timestamp: Date()
        )
        await vm.checkIn(reservation, driverId: "d1", location: coarse)

        XCTAssertFalse(backend.didSubmitCheckIn)
        XCTAssertEqual(
            vm.checkInState,
            .failed(ScheduledRideCheckInPreflightError.locationTooInaccurate.errorDescription!)
        )
    }

    /// Core Location reports an invalid fix as a *negative* accuracy, which a
    /// naive `<= 100` comparison would happily accept.
    func testNegativeAccuracyIsTreatedAsInvalidNotPrecise() async {
        let reservation = openWindowReservation()
        let backend = FakeScheduledRideBackend()
        backend.reservations = [reservation]
        let vm = ScheduledRidesDashboardVM(backend: backend, routeEstimator: routeFound)
        vm.startListening(driverId: "d1")
        await drain()

        let invalid = CLLocation(
            coordinate: DriverMapDefaults.pilotCoordinate,
            altitude: 0,
            horizontalAccuracy: -1,
            verticalAccuracy: -1,
            timestamp: Date()
        )
        await vm.checkIn(reservation, driverId: "d1", location: invalid)

        XCTAssertEqual(
            vm.checkInState,
            .failed(ScheduledRideCheckInPreflightError.locationTooInaccurate.errorDescription!)
        )
    }

    // MARK: - Window gating

    func testCheckInBeforeTheWindowOpensIsRefused() async {
        let tooEarly = ScheduledRideReservation.fixture(
            id: "res-1",
            pickupTime: Date().addingTimeInterval(4 * 3600),   // window opens at pickup − 60m
            status: .confirmed
        )
        let backend = FakeScheduledRideBackend()
        backend.reservations = [tooEarly]
        let vm = ScheduledRidesDashboardVM(backend: backend, routeEstimator: routeFound)
        vm.startListening(driverId: "d1")
        await drain()

        await vm.checkIn(tooEarly, driverId: "d1", location: goodFix())

        XCTAssertFalse(backend.didSubmitCheckIn)
        XCTAssertEqual(
            vm.checkInState,
            .failed(ScheduledRideCheckInPreflightError.windowNotOpen.errorDescription!)
        )
    }

    func testCheckInAfterTheDeadlineIsRefused() async {
        let missed = ScheduledRideReservation.fixture(
            id: "res-1",
            pickupTime: Date().addingTimeInterval(20 * 60),   // deadline was pickup − 50m
            status: .checkInRequired
        )
        let backend = FakeScheduledRideBackend()
        backend.reservations = [missed]
        let vm = ScheduledRidesDashboardVM(backend: backend, routeEstimator: routeFound)
        vm.startListening(driverId: "d1")
        await drain()

        await vm.checkIn(missed, driverId: "d1", location: goodFix())

        XCTAssertEqual(missed.timing(), .checkInMissed)
        XCTAssertEqual(
            vm.checkInState,
            .failed(ScheduledRideCheckInPreflightError.windowNotOpen.errorDescription!)
        )
    }

    /// A driver can only be heading to one pickup at a time — this predates
    /// deliverable 4 and must survive it.
    func testSecondSimultaneousCheckInStillBlocked() async {
        let alreadyCheckedIn = ScheduledRideReservation.fixture(
            id: "other", pickupTime: Date().addingTimeInterval(3 * 3600), status: .checkedIn
        )
        let target = openWindowReservation()
        var submitted = false
        let backend = FakeScheduledRideBackend()
        backend.reservations = [alreadyCheckedIn, target]
        let vm = ScheduledRidesDashboardVM(backend: backend, routeEstimator: routeFound)
        vm.startListening(driverId: "d1")
        await drain()

        await vm.checkIn(target, driverId: "d1", location: goodFix())
        XCTAssertFalse(backend.didSubmitCheckIn)
    }

    // MARK: - Contract payload

    /// The contract speaks in seconds; the UI and MapKit work in minutes. The
    /// conversion belongs at the callable boundary, and this is what pins it.
    func testEtaIsSubmittedInSecondsWithAFreshTimestamp() async {
        let reservation = openWindowReservation()
        let backend = FakeScheduledRideBackend()
        backend.reservations = [reservation]
        let vm = ScheduledRidesDashboardVM(backend: backend, routeEstimator: routeFound)
        vm.startListening(driverId: "d1")
        await drain()

        let before = Date()
        await vm.checkIn(reservation, driverId: "d1", location: goodFix())

        guard let submission = backend.recordedCheckIns.first else {
            return XCTFail("Nothing reached the callable")
        }
        XCTAssertEqual(submission.etaSeconds, 12 * 60, "12 minutes must be submitted as 720 seconds")
        let capturedCalculatedAt = submission.calculatedAt
        XCTAssertGreaterThanOrEqual(capturedCalculatedAt, before)
        XCTAssertLessThanOrEqual(
            capturedCalculatedAt.timeIntervalSinceNow.magnitude,
            ScheduledRideConfig.checkInEtaMaxAgeMinutes * 60,
            "Submitted timestamp must be inside the server's freshness window"
        )
    }

    /// MapKit couldn't produce a route — distinct from "no location" and from
    /// a server rejection, because the fix is different for each.
    func testRouteFailureIsReportedSeparately() async {
        let reservation = openWindowReservation()
        var submitted = false
        let backend = FakeScheduledRideBackend()
        backend.reservations = [reservation]
        let vm = ScheduledRidesDashboardVM(backend: backend, routeEstimator: routeMissing)
        vm.startListening(driverId: "d1")
        await drain()

        await vm.checkIn(reservation, driverId: "d1", location: goodFix())

        XCTAssertFalse(backend.didSubmitCheckIn, "No ETA means nothing to submit")
        XCTAssertEqual(
            vm.checkInState,
            .failed(ScheduledRideCheckInPreflightError.routeUnavailable.errorDescription!)
        )
    }

    // MARK: - Server rejections

    /// `ETA_STALE` depends on wall-clock time passing between calculating an
    /// ETA and submitting it. Unstageable against a live backend, which is the
    /// whole argument for the injection seam.
    func testStaleEtaAsksForAnotherAttemptRatherThanFailingSilently() async {
        let reservation = openWindowReservation()
        let backend = FakeScheduledRideBackend()
        backend.reservations = [reservation]
        backend.checkInError = .etaStale
        let vm = ScheduledRidesDashboardVM(backend: backend, routeEstimator: routeFound)
        vm.startListening(driverId: "d1")
        await drain()

        await vm.checkIn(reservation, driverId: "d1", location: goodFix())

        XCTAssertEqual(
            vm.checkInState,
            .failed("Your ETA went stale before it reached us. Tap Check In again."),
            "A stale ETA must invite another attempt, not read as a dead end"
        )
    }

    /// The server owns the window; a client that thinks it is open can still
    /// be told otherwise.
    func testServerWindowClosedSurfacesEvenWhenClientThinksItIsOpen() async {
        let reservation = openWindowReservation()
        let backend = FakeScheduledRideBackend()
        backend.reservations = [reservation]
        backend.checkInError = .windowClosed
        let vm = ScheduledRidesDashboardVM(backend: backend, routeEstimator: routeFound)
        vm.startListening(driverId: "d1")
        await drain()

        XCTAssertEqual(reservation.timing(), .checkInOpen, "Client believes the window is open")
        await vm.checkIn(reservation, driverId: "d1", location: goodFix())

        guard case .failed = vm.checkInState else {
            return XCTFail("A server rejection must not leave the card looking successful")
        }
    }

    // MARK: - Receipt and rendered states

    func testReceiptDecodesActivationTimeAndAcceptedEta() {
        let receipt = ScheduledRideCheckInReceipt(callableResponse: [
            "status": "checkedIn",
            "activationAtEpochMs": 1_760_000_000_000,
            "pickupEtaSeconds": 780
        ])
        XCTAssertEqual(receipt?.activationAt, Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertEqual(receipt?.acceptedEtaSeconds, 780)
        XCTAssertEqual(receipt?.acceptedEtaMinutes, 13)
    }

    /// Without an activation time there is nothing to render and no way to
    /// tell the driver when dispatch takes over — so it is required.
    func testReceiptRejectsResponseMissingActivationTime() {
        XCTAssertNil(ScheduledRideCheckInReceipt(callableResponse: ["status": "checkedIn"]))
    }

    /// The client never computes activation — the formula uses the server's
    /// clock, so a local copy would drift from what activation actually uses.
    func testActivationTimeComesFromTheServerNotTheClient() {
        let serverActivation = Date().addingTimeInterval(42 * 60)
        let reservation = ScheduledRideReservation.fixture(
            status: .checkedIn,
            pickupETAMinutes: 13,
            activationAt: serverActivation
        )
        XCTAssertEqual(reservation.activationAt, serverActivation)
    }

    func testActivatingIsADistinctRenderedState() {
        let activating = ScheduledRideReservation.fixture(
            pickupTime: Date().addingTimeInterval(20 * 60),
            status: .activating
        )
        // `.activating` must not be mistaken for a missed check-in just
        // because the deadline has passed — it is further along, not behind.
        XCTAssertEqual(activating.timing(), .checkedIn)
    }

    // MARK: - Helpers

    private func drain() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
