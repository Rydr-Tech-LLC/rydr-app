import XCTest
import CoreLocation
@testable import RydrDriver

/// Deliverable 5: the activation handoff — suppressing normal opportunities
/// while the dispatch lock is held, and letting the targeted request through
/// the existing dispatch card.
@MainActor
final class ScheduledRideDispatchTests: XCTestCase {

    private func request(id: String, scheduled: Bool, rideType: String = "Rydr Go") -> DriverRideRequest {
        DriverRideRequest(
            id: id,
            riderId: "rider-1",
            riderName: "Rider",
            pickup: "1 Peachtree St",
            dropoff: "Hartsfield",
            rideType: rideType,
            source: scheduled ? "scheduledRydr" : nil,
            scheduledRideRequestId: scheduled ? id : nil
        )
    }

    private func activeLock(requestId: String = "sched-1") -> ScheduledRideDispatchLock {
        // Activation time plus the approved 18-second dispatch timeout.
        ScheduledRideDispatchLock(
            requestId: requestId,
            expiresAt: Date().addingTimeInterval(TimeInterval(ScheduledRideConfig.activationDispatchTimeoutSeconds))
        )
    }

    // MARK: - Recognising the handoff

    func testScheduledSourceIdentifiesTheHandoff() {
        XCTAssertTrue(request(id: "sched-1", scheduled: true).isScheduledRydr)
        XCTAssertFalse(request(id: "normal-1", scheduled: false).isScheduledRydr)
    }

    /// The targeted request is decoded by the existing dispatch listener, so
    /// the marker fields have to survive that path.
    func testScheduledMarkersDecodeFromTheTargetedRequestShape() {
        let decoded = DriverRideRequest(
            id: "sched-1",
            riderId: "rider-1",
            riderName: "Rider",
            pickup: "1 Peachtree St",
            dropoff: "Hartsfield",
            rideType: "Rydr Go",
            source: "scheduledRydr",
            scheduledRideRequestId: "sched-1"
        )
        XCTAssertTrue(decoded.isScheduledRydr)
        XCTAssertEqual(decoded.scheduledRideRequestId, decoded.id, "Activation reuses the same document ID")
    }

    // MARK: - Suppression

    /// The contract's rule: "While it exists, the driver receives no normal
    /// opportunities." The server stops creating them, but one created moments
    /// earlier can still be pending — so the client filters too.
    func testActiveLockSuppressesNormalRequests() {
        let presentable = ScheduledRideDispatchPolicy.presentableRequests(
            [request(id: "normal-1", scheduled: false), request(id: "sched-1", scheduled: true)],
            lock: activeLock(),
            isOnline: true
        )
        XCTAssertEqual(presentable.map(\.id), ["sched-1"])
    }

    func testNoLockLeavesNormalDispatchAlone() {
        let presentable = ScheduledRideDispatchPolicy.presentableRequests(
            [request(id: "normal-1", scheduled: false), request(id: "normal-2", scheduled: false)],
            lock: nil,
            isOnline: true
        )
        XCTAssertEqual(presentable.count, 2)
    }

    /// A decline or timeout clears the lock server-side; an expired one must
    /// not keep suppressing work.
    func testExpiredLockStopsSuppressing() {
        let stale = ScheduledRideDispatchLock(
            requestId: "sched-1",
            expiresAt: Date().addingTimeInterval(-1)
        )
        let presentable = ScheduledRideDispatchPolicy.presentableRequests(
            [request(id: "normal-1", scheduled: false)],
            lock: stale,
            isOnline: true
        )
        XCTAssertEqual(presentable.map(\.id), ["normal-1"], "Normal work resumes once the lock lapses")
        XCTAssertFalse(ScheduledRideDispatchPolicy.suppressesNormalDispatch(lock: stale))
    }

    // MARK: - The commitment outranks the toggle

    /// Dispatch requires being online, scheduled or not. Activation gives the
    /// driver 18 seconds to respond, which is meaningless to someone who isn't
    /// watching — the reminder schedule is what gets them online in time, not
    /// a card they never see.
    func testOfflineDriverReceivesNothingEvenWithAnActiveLock() {
        let presentable = ScheduledRideDispatchPolicy.presentableRequests(
            [request(id: "normal-1", scheduled: false), request(id: "sched-1", scheduled: true)],
            lock: activeLock(),
            isOnline: false
        )
        XCTAssertTrue(presentable.isEmpty)
    }

    func testOfflineStillSuppressesNormalRequests() {
        let presentable = ScheduledRideDispatchPolicy.presentableRequests(
            [request(id: "normal-1", scheduled: false)],
            lock: nil,
            isOnline: false
        )
        XCTAssertTrue(presentable.isEmpty)
    }

    // MARK: - Status copy

    /// The offline case is the one that matters: the driver is about to miss a
    /// ride they committed to and has seconds to notice.
    func testOfflineDriverIsToldToGoOnline() {
        let message = ScheduledRideDispatchPolicy.statusMessage(
            lock: activeLock(),
            reservation: .fixture(id: "sched-1"),
            isOnline: false
        )
        XCTAssertNotNil(message)
        XCTAssertTrue(message!.contains("go online"), "Got: \(message!)")
    }

    func testStatusNamesThePickupWhenTheReservationIsKnown() {
        let reservation = ScheduledRideReservation.fixture(
            id: "sched-1",
            pickupArea: "Buckhead pickup area"
        )
        let message = ScheduledRideDispatchPolicy.statusMessage(
            lock: activeLock(),
            reservation: reservation,
            isOnline: true
        )
        XCTAssertNotNil(message)
        XCTAssertTrue(message!.contains("Buckhead"), "The driver should be told where they're heading")
        XCTAssertTrue(message!.contains("paused"), "and that normal requests are paused")
    }

    func testStatusFallsBackWhenTheReservationHasNotArrived() {
        let message = ScheduledRideDispatchPolicy.statusMessage(lock: activeLock(), reservation: nil, isOnline: true)
        XCTAssertNotNil(message, "A lock with no reservation yet still deserves an explanation")
    }

    /// An expired lock means the server has moved on to replacement. Saying
    /// "heading to your pickup" then would be a claim the client can't support.
    func testNoStatusOnceTheLockLapses() {
        let stale = ScheduledRideDispatchLock(requestId: "sched-1", expiresAt: Date().addingTimeInterval(-1))
        XCTAssertNil(ScheduledRideDispatchPolicy.statusMessage(lock: stale, reservation: .fixture(id: "sched-1"), isOnline: true))
    }

    // MARK: - Decoding the lock

    func testLockDecodesFromTheDriverStatusDocument() {
        let lock = ScheduledRideDispatchLock(driverStatusData: [
            "isOnline": true,
            "scheduledRideDispatchLock": [
                "requestId": "sched-1",
                "expiresAt": 1_760_000_000_000
            ]
        ])
        XCTAssertEqual(lock?.requestId, "sched-1")
        XCTAssertEqual(lock?.expiresAt, Date(timeIntervalSince1970: 1_760_000_000))
    }

    /// No lock is the ordinary state, not an error.
    func testDriverStatusWithoutALockDecodesToNil() {
        XCTAssertNil(ScheduledRideDispatchLock(driverStatusData: ["isOnline": true]))
    }

    // MARK: - Live delivery

    /// Activation writes the lock and a decline clears it, both without the
    /// driver doing anything — which is why it's a listener.
    func testLockArrivesAndClearsThroughTheListener() {
        let backend = FakeScheduledRideBackend()
        var received: [ScheduledRideDispatchLock?] = []
        _ = backend.listenToDispatchLock(driverId: "driver-1") { result in
            if case .success(let lock) = result { received.append(lock) }
        }

        backend.deliverDispatchLock(activeLock())
        backend.deliverDispatchLock(nil)

        XCTAssertEqual(received.count, 3, "initial nil, then the lock, then cleared")
        XCTAssertNil(received[0])
        XCTAssertEqual(received[1]?.requestId, "sched-1")
        XCTAssertNil(received[2])
    }
}
