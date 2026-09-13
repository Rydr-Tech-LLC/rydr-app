import XCTest
import CoreLocation
@testable import RydrDriver

/// Proves the injection seam works end to end: a test can replace the Firestore
/// listeners, drive the dashboard view model with fixture data, and assert on
/// what it publishes — with no Firebase project, no network, and no signed-in
/// user anywhere in the process.
@MainActor
final class ScheduledRideListenerTests: XCTestCase {

    // MARK: Service-level injection

    func testInjectedOpportunityListenerReplacesTheLiveOne() {
        let backend = FakeScheduledRideBackend()
        backend.opportunities = [.fixture(id: "opp-under-test")]

        var received: ScheduledRideSnapshot<ScheduledRideOpportunity>?
        _ = backend.listenToOpportunities(driverId: "any-driver") { result in
            received = try? result.get()
        }

        XCTAssertEqual(received?.items.map(\.id), ["opp-under-test"])
    }

    func testInjectedReservationListenerReplacesTheLiveOne() {
        let backend = FakeScheduledRideBackend()
        backend.reservations = [.fixture(id: "res-under-test", lockedBaseFareCents: 5150)]

        var received: ScheduledRideSnapshot<ScheduledRideReservation>?
        _ = backend.listenToReservations(driverId: "any-driver") { result in
            received = try? result.get()
        }

        XCTAssertEqual(received?.items.first?.id, "res-under-test")
        XCTAssertEqual(received?.items.first?.lockedBaseFareDisplay, "$51.50")
    }

    /// The failure half of the seam. Without injection this path would need a
    /// genuinely signed-out Firebase session to reach.
    func testFailingListenerDeliversAFailureResult() {
        let backend = FakeScheduledRideBackend()
        backend.listenerError = ScheduledRideServiceError.notAuthenticated

        var received: Result<ScheduledRideSnapshot<ScheduledRideOpportunity>, Error>?
        _ = backend.listenToOpportunities(driverId: "any-driver") { received = $0 }

        guard case .failure(let error) = received else {
            return XCTFail("Expected a failure result")
        }
        XCTAssertEqual(error as? ScheduledRideServiceError, .notAuthenticated)
    }

    // MARK: View-model integration

    func testDashboardPublishesInjectedFixtures() {
        let backend = FakeScheduledRideBackend()
        backend.opportunities = [.fixture(id: "opp-1"), .fixture(id: "opp-2")]
        backend.reservations = [.fixture(id: "res-1")]
        let vm = ScheduledRidesDashboardVM(backend: backend)

        vm.startListening(driverId: "any-driver")

        // The view model republishes on the main queue, so the assertions have
        // to wait for one turn of the run loop rather than reading straight
        // after the call. This is real behavior, not a test artifact — it is
        // why the published properties are safe to bind to from SwiftUI.
        expectMainQueueToDrain()

        XCTAssertEqual(vm.opportunities.map(\.id), ["opp-1", "opp-2"])
        XCTAssertEqual(vm.reservations.map(\.id), ["res-1"])
        XCTAssertNil(vm.loadError)
    }

    func testDashboardSurfacesListenerFailureAsDriverReadableText() {
        let backend = FakeScheduledRideBackend()
        backend.listenerError = ScheduledRideServiceError.notAuthenticated
        let vm = ScheduledRidesDashboardVM(backend: backend)

        vm.startListening(driverId: "any-driver")
        expectMainQueueToDrain()

        XCTAssertTrue(vm.opportunities.isEmpty)
        XCTAssertEqual(vm.loadError, ScheduledRideServiceError.notAuthenticated.errorDescription)
    }

    func testStopListeningRemovesEveryRegistration() {
        let backend = FakeScheduledRideBackend()
        let vm = ScheduledRidesDashboardVM(backend: backend)

        vm.startListening(driverId: "any-driver")
        XCTAssertEqual(backend.registrations.count, 3, "opportunities, reservations, offers")
        XCTAssertTrue(backend.registrations.allSatisfy { !$0.isRemoved })

        vm.stopListening()
        XCTAssertTrue(backend.registrations.allSatisfy(\.isRemoved))
    }

    /// Restarting must detach the previous listeners, or every reopen of the
    /// dashboard would leak a Firestore subscription that keeps firing.
    func testRestartingListenersRemovesThePreviousOnes() {
        let backend = FakeScheduledRideBackend()
        let vm = ScheduledRidesDashboardVM(backend: backend)

        vm.startListening(driverId: "any-driver")
        vm.startListening(driverId: "any-driver")

        XCTAssertEqual(backend.registrations.count, 6)
        XCTAssertTrue(backend.registrations.prefix(3).allSatisfy(\.isRemoved), "First set should have been detached")
        XCTAssertTrue(backend.registrations.suffix(3).allSatisfy { !$0.isRemoved }, "Second set should still be attached")
    }

    // MARK: Eligibility against fixture data

    /// The QA fixture set is deliberately shaped so each eligibility state is
    /// reachable immediately. If someone "tidies up" those fixtures, this test
    /// is what fails and explains why they mattered.
    func testQAFixtureSetCoversEveryEligibilityState() {
        let now = Date()
        let opportunities = ScheduledRideFixtures.opportunities(now: now)
        let reservations = ScheduledRideFixtures.reservations(now: now)

        let states = opportunities.map { $0.eligibility(against: reservations) }

        XCTAssertEqual(states.count, 3)
        guard case .conflicting = states[0] else {
            return XCTFail("fixture-opp-1 should overlap fixture-res-1")
        }
        XCTAssertEqual(states[1], .eligible)
        XCTAssertEqual(states[2], .expired)
    }

    // MARK: Helpers

    /// Lets already-queued `DispatchQueue.main.async` blocks run before the
    /// assertions that depend on them.
    private func expectMainQueueToDrain(timeout: TimeInterval = 1) {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: timeout)
    }
}
