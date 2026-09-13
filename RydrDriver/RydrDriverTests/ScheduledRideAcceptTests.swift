import XCTest
import FirebaseFunctions
@testable import RydrDriver

/// Deliverable 2: the two-step accept. Covers the error-reason map, the quote
/// state machine, and the recovery paths that are unreachable against a real
/// backend because they are server-side races.
@MainActor
final class ScheduledRideAcceptTests: XCTestCase {

    // MARK: - Error classification

    /// The contract's instruction is explicit: branch on `details.reason`,
    /// never on message text. These assert we read the reason even when the
    /// coarse Firebase code would suggest something else.
    func testClassifiesByDetailsReason() {
        XCTAssertEqual(ScheduledRideCallableError(callableError(.failedPrecondition, reason: "QUOTE_CHANGED")), .quoteChanged)
        XCTAssertEqual(ScheduledRideCallableError(callableError(.failedPrecondition, reason: "SCHEDULE_CONFLICT")), .scheduleConflict)
        XCTAssertEqual(ScheduledRideCallableError(callableError(.failedPrecondition, reason: "WINDOW_CLOSED")), .windowClosed)
        XCTAssertEqual(ScheduledRideCallableError(callableError(.resourceExhausted, reason: "OFFER_LIMIT_REACHED")), .offerLimitReached)
        XCTAssertEqual(ScheduledRideCallableError(callableError(.permissionDenied, reason: "DRIVER_NOT_ELIGIBLE")), .driverNotEligible)
    }

    func testFallsBackToFirebaseCodeWhenReasonIsMissing() {
        XCTAssertEqual(ScheduledRideCallableError(callableError(.unauthenticated, reason: nil)), .signInRequired)
        XCTAssertEqual(ScheduledRideCallableError(callableError(.unavailable, reason: nil)), .temporaryBackendFailure)
        XCTAssertEqual(ScheduledRideCallableError(callableError(.aborted, reason: nil)), .concurrentUpdate)
    }

    /// A reason this build doesn't recognize must not be mistaken for success
    /// or crash — the server can add reasons without a client release.
    func testUnknownReasonIsPreservedNotDropped() {
        let error = ScheduledRideCallableError(callableError(.failedPrecondition, reason: "SOME_FUTURE_REASON"))
        XCTAssertEqual(error, .unrecognized(reason: "SOME_FUTURE_REASON"))
        XCTAssertNotNil(error.errorDescription)
    }

    func testNonCallableErrorStillClassifies() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(ScheduledRideCallableError(offline), .unrecognized(reason: nil))
    }

    /// Every case must have driver-readable text; a nil would surface as an
    /// empty alert.
    func testEveryClassifiedErrorHasRecoveryText() {
        let all: [ScheduledRideCallableError] = [
            .signInRequired, .invalidInput, .notOwner, .notAssignedDriver, .driverNotEligible,
            .notAllowlisted, .requestNotFound, .offerNotFound, .featureDisabled, .invalidStatus,
            .windowClosed, .quoteChanged, .activeRideConflict, .scheduleConflict,
            .paymentMethodUnavailable, .etaStale, .requestIdInUse, .operationAlreadyApplied,
            .offerLimitReached, .replacementCutoffReached, .concurrentUpdate,
            .temporaryBackendFailure, .unrecognized(reason: nil)
        ]
        for error in all {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error) has no recovery text")
        }
    }

    // MARK: - Quote model

    func testQuoteDecodesCallableResponse() {
        let quote = ScheduledRideDriverQuote(callableResponse: [
            "requestId": "req-1",
            "quoteFingerprint": "fp-abc",
            "exactBaseFareCents": 2450,
            "driverPayoutCents": 1715,
            "currency": "USD",
            "pricingVersion": "scheduled-rides-v1",
            "expiresAtEpochMs": 1_760_000_000_000
        ])
        XCTAssertEqual(quote?.driverPayoutCents, 1715)
        XCTAssertEqual(quote?.driverPayoutDisplay, "$17.15")
        XCTAssertEqual(quote?.expiresAt, Date(timeIntervalSince1970: 1_760_000_000))
    }

    /// A quote missing its payout or fingerprint must not become a card
    /// offering an invented number.
    func testQuoteRejectsIncompleteResponse() {
        XCTAssertNil(ScheduledRideDriverQuote(callableResponse: [
            "requestId": "req-1",
            "quoteFingerprint": "fp-abc",
            "exactBaseFareCents": 2450
            // no driverPayoutCents, no expiry
        ]))
    }

    // MARK: - Happy path

    func testSelectingEligibleOpportunityLoadsQuote() async {
        let backend = FakeScheduledRideBackend.qaFixtures()
        backend.quote = .fixture(requestId: "fixture-opp-2", exactBaseFareCents: 2450)
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "d1")
        await drainMainQueue()

        vm.select(opportunity(vm, id: "fixture-opp-2"))
        await settle()

        XCTAssertEqual(vm.quoteState.quote?.driverPayoutCents, 1715)
    }

    /// The contract forbids showing the rider maximum as earnings, so an
    /// ineligible opportunity — which can never be accepted — must not spend a
    /// callable either.
    func testIneligibleOpportunityIsNotQuoted() async {
        let vm = ScheduledRidesDashboardVM(backend: FakeScheduledRideBackend.qaFixtures())
        vm.startListening(driverId: "d1")
        await drainMainQueue()

        vm.select(opportunity(vm, id: "fixture-opp-3"))  // pre-expired fixture
        await settle()

        XCTAssertEqual(vm.quoteState, .idle)
    }

    /// Quick Schedule: the ack leaves the card confirming, and only the
    /// reservation listener can end that wait.
    func testQuickScheduleWaitsForListenerToDeliverReservation() async {
        let backend = FakeScheduledRideBackend()
        backend.opportunities = [.fixture(id: "quick-ride", selectionMode: .quick)]
        backend.quote = .fixture(requestId: "quick-ride")
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "d1")
        await drainMainQueue()
        vm.select(opportunity(vm, id: "quick-ride"))
        await settle()

        await vm.acceptSelected()
        XCTAssertEqual(vm.quoteState, .confirming, "Ack alone must not clear the card")
        XCTAssertTrue(vm.reservations.isEmpty, "Client must never invent a reservation")

        // The server writes it; the listener delivers it.
        backend.deliverReservation(.fixture(id: "quick-ride", lockedBaseFareCents: 2450))
        await drainMainQueue()

        XCTAssertEqual(vm.reservations.map(\.id), ["quick-ride"])
        XCTAssertEqual(vm.quoteState, .idle)
        XCTAssertNil(vm.selectedOpportunityID)
    }

    /// Choose My Driver: no reservation is coming, so the card stops at
    /// "Offer submitted" rather than waiting forever.
    ///
    /// The branch is driven by the opportunity's `selectionMode`, which the
    /// driver can see *before* tapping — not by a field invented on the
    /// response, which the contract doesn't specify.
    func testChooseMyDriverStopsAtOfferSubmitted() async {
        let backend = FakeScheduledRideBackend()
        backend.opportunities = [.fixture(id: "bid-ride", selectionMode: .chooseDriver)]
        backend.quote = .fixture(requestId: "bid-ride")
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "d1")
        await drainMainQueue()
        vm.select(opportunity(vm, id: "bid-ride"))
        await settle()

        await vm.acceptSelected()

        XCTAssertEqual(vm.quoteState, .offerSubmitted)
        XCTAssertTrue(vm.reservations.isEmpty)
    }

    /// An opportunity whose projection didn't carry a selection mode must not
    /// be guessed at. It waits on the listener like Quick Schedule does, so a
    /// reservation that does arrive still resolves the card correctly.
    func testUnknownSelectionModeWaitsRatherThanGuessing() async {
        let backend = FakeScheduledRideBackend()
        backend.opportunities = [.fixture(id: "unknown-mode", selectionMode: nil)]
        backend.quote = .fixture(requestId: "unknown-mode")
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "d1")
        await drainMainQueue()
        vm.select(opportunity(vm, id: "unknown-mode"))
        await settle()

        await vm.acceptSelected()
        XCTAssertEqual(vm.quoteState, .confirming)

        backend.deliverReservation(.fixture(id: "unknown-mode"))
        await drainMainQueue()
        XCTAssertEqual(vm.quoteState, .idle)
    }

    func testSelectionModeDecodesFromTheProjection() {
        XCTAssertEqual(ScheduledRideSelectionMode(rawValue: "quick"), .quick)
        XCTAssertEqual(ScheduledRideSelectionMode(rawValue: "chooseDriver"), .chooseDriver)
        // Legacy Rider spellings must not resolve — the contract lists them as
        // values to remove, not aliases to accept.
        XCTAssertNil(ScheduledRideSelectionMode(rawValue: "quickSchedule"))
        XCTAssertNil(ScheduledRideSelectionMode(rawValue: "chooseMyDriver"))
    }

    // MARK: - Recovery paths

    /// The headline case. Server says the price moved; the driver must see the
    /// new number and accept again rather than being assigned silently.
    func testQuoteChangedRepricesAndRequiresAnotherAcceptance() async {
        let backend = FakeScheduledRideBackend.qaFixtures()
        backend.quote = .fixture(requestId: "fixture-opp-2", exactBaseFareCents: 2450)
        backend.repricedQuote = .fixture(
            requestId: "fixture-opp-2",
            quoteFingerprint: "fixture-fingerprint-v2",
            exactBaseFareCents: 3000
        )
        backend.respondError = .quoteChanged
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "d1")
        await drainMainQueue()
        vm.select(opportunity(vm, id: "fixture-opp-2"))
        await settle()
        XCTAssertEqual(vm.quoteState.quote?.driverPayoutCents, 1715)

        await vm.acceptSelected()
        await settle()

        guard case .repriced(let fresh) = vm.quoteState else {
            return XCTFail("Expected .repriced, got \(vm.quoteState)")
        }
        XCTAssertEqual(fresh.driverPayoutCents, 2100, "Must show the NEW payout")
        XCTAssertEqual(fresh.quoteFingerprint, "fixture-fingerprint-v2")
        XCTAssertFalse(
            vm.reservations.contains { $0.id == "fixture-opp-2" },
            "A changed quote must not assign the ride"
        )
    }

    /// A fingerprint that aged out locally takes the same recovery as a
    /// server-side QUOTE_CHANGED — one path, not two.
    func testLocallyExpiredFingerprintRepricesWithoutCallingRespond() async {
        let backend = FakeScheduledRideBackend.qaFixtures()
        backend.quote = .fixture(requestId: "fixture-opp-2", expiresAt: Date().addingTimeInterval(-1))
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "d1")
        await drainMainQueue()
        vm.select(opportunity(vm, id: "fixture-opp-2"))
        await settle()

        await vm.acceptSelected()
        await settle()

        XCTAssertFalse(backend.didRespond, "A stale fingerprint should be re-quoted, not sent")
        if case .repriced = vm.quoteState {} else {
            XCTFail("Expected .repriced, got \(vm.quoteState)")
        }
    }

    /// A schedule conflict means our local reservation list was stale, so the
    /// selection is dropped rather than left re-tappable against bad state.
    func testScheduleConflictSurfacesAndClearsSelection() async {
        let backend = FakeScheduledRideBackend.qaFixtures()
        backend.quote = .fixture(requestId: "fixture-opp-2")
        backend.respondError = .scheduleConflict
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "d1")
        await drainMainQueue()
        vm.select(opportunity(vm, id: "fixture-opp-2"))
        await settle()

        await vm.acceptSelected()

        XCTAssertEqual(vm.acceptError, ScheduledRideCallableError.scheduleConflict.errorDescription)
        XCTAssertNil(vm.selectedOpportunityID)
    }

    /// WINDOW_CLOSED is terminal — no re-quote, just an explanation.
    func testWindowClosedFailsWithoutRepricing() async {
        let backend = FakeScheduledRideBackend.qaFixtures()
        backend.quote = .fixture(requestId: "fixture-opp-2")
        backend.respondError = .windowClosed
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "d1")
        await drainMainQueue()
        vm.select(opportunity(vm, id: "fixture-opp-2"))
        await settle()

        await vm.acceptSelected()

        XCTAssertEqual(vm.acceptError, ScheduledRideCallableError.windowClosed.errorDescription)
    }

    func testQuotePreviewFailureIsRetryable() async {
        let backend = FakeScheduledRideBackend.qaFixtures()
        backend.quoteError = .temporaryBackendFailure
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "d1")
        await drainMainQueue()
        vm.select(opportunity(vm, id: "fixture-opp-2"))
        await settle()

        guard case .failed(let message) = vm.quoteState else {
            return XCTFail("Expected .failed, got \(vm.quoteState)")
        }
        XCTAssertEqual(message, ScheduledRideCallableError.temporaryBackendFailure.errorDescription)
    }

    /// Accept must be impossible without a fingerprint to accept at.
    func testAcceptDoesNothingWithoutAQuote() async {
        let backend = FakeScheduledRideBackend.qaFixtures()
        let vm = ScheduledRidesDashboardVM(backend: backend)

        await vm.acceptSelected()

        XCTAssertFalse(backend.didRespond)
    }

    /// Switching pins must not leave the previous ride's payout on screen.
    func testChangingSelectionClearsThePreviousQuote() async {
        let backend = FakeScheduledRideBackend.qaFixtures()
        backend.quote = .fixture(requestId: "fixture-opp-2")
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "d1")
        await drainMainQueue()
        vm.select(opportunity(vm, id: "fixture-opp-2"))
        await settle()
        XCTAssertNotNil(vm.quoteState.quote)

        vm.selectedOpportunityID = "fixture-opp-1"
        XCTAssertEqual(vm.quoteState, .idle)
    }

    // MARK: - Helpers

    /// Builds an `NSError` shaped exactly like a Firebase callable failure.
    private func callableError(_ code: FunctionsErrorCode, reason: String?) -> NSError {
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: "server message text"]
        if let reason {
            userInfo[FunctionsErrorDetailsKey] = ["reason": reason]
        }
        return NSError(domain: FunctionsErrorDomain, code: code.rawValue, userInfo: userInfo)
    }

    private func opportunity(_ vm: ScheduledRidesDashboardVM, id: String) -> ScheduledRideOpportunity {
        vm.opportunities.first { $0.id == id }!
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// Lets the detached quote `Task` run to completion, then flushes main.
    private func settle() async {
        for _ in 0..<3 {
            await Task.yield()
            await drainMainQueue()
        }
    }
}
