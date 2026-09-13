import XCTest
import CoreLocation
@testable import RydrDriver

/// Pins every Firestore decoder to the shapes the backend actually writes.
///
/// The dictionaries below are transcribed from
/// `Rydr_Firebase/functions/src/scheduledRides/service.ts` — the real
/// `tx.create` payloads, not the prose contracts. An earlier pass inferred
/// these names from documentation and got four of them wrong, one of which
/// (querying the projection for a request-lifecycle status) would have
/// returned an empty map forever with no error.
@MainActor
final class ScheduledRideDecodingTests: XCTestCase {

    // MARK: - Opportunity projection

    /// Mirrors the backend's opportunity `tx.create` exactly.
    private func opportunityDocument() -> [String: Any] {
        [
            "schemaVersion": 1,
            "requestId": "req-1",
            "selectionMode": "chooseDriver",
            "rideType": "go",
            "pickupArea": "Midtown",
            "pickupLatitudeBucket": 33.78,
            "pickupLongitudeBucket": -84.38,
            "scheduledAt": 1_760_000_000_000,
            "routeEstimate": [
                "distanceMiles": 12.4,
                "durationMinutes": 26.0,
                "source": "mapKit",
                "version": "1"
            ],
            "preferences": [:],
            "approvedMaximumCents": 3800,
            "currency": "usd",
            "status": "open",
            "offerClosesAt": 1_759_998_000_000
        ]
    }

    func testOpportunityDecodesTheBackendsActualDocument() {
        let opportunity = ScheduledRideOpportunity(id: "req-1", data: opportunityDocument())

        XCTAssertEqual(opportunity?.id, "req-1")
        XCTAssertEqual(opportunity?.rideType, "go")
        XCTAssertEqual(opportunity?.pickupArea, "Midtown")
        XCTAssertEqual(opportunity?.approvedMaximumCents, 3800)
        XCTAssertEqual(opportunity?.selectionMode, .chooseDriver)
        XCTAssertEqual(opportunity?.estimatedTripMiles, 12.4)
        XCTAssertEqual(opportunity?.estimatedTripMinutes, 26)
    }

    /// The deadline field is `offerClosesAt`. A previous pass read
    /// `offerDeadlineAt`, which silently dropped every document.
    func testOpportunityReadsOfferClosesAtNotOfferDeadlineAt() {
        var data = opportunityDocument()
        data["offerDeadlineAt"] = data.removeValue(forKey: "offerClosesAt")

        XCTAssertNil(
            ScheduledRideOpportunity(id: "req-1", data: data),
            "Only offerClosesAt exists; a document without it must be dropped, not defaulted"
        )
    }

    /// The pickup point is two separately-stored rounded numbers, not a
    /// GeoPoint and not a nested map. The rounding is the privacy boundary.
    func testOpportunityRebuildsCoordinateFromTwoBucketFields() {
        let opportunity = ScheduledRideOpportunity(id: "req-1", data: opportunityDocument())

        XCTAssertEqual(opportunity?.pickupCoordinate.latitude, 33.78)
        XCTAssertEqual(opportunity?.pickupCoordinate.longitude, -84.38)
    }

    func testOpportunityWithoutBucketFieldsIsDropped() {
        var data = opportunityDocument()
        data.removeValue(forKey: "pickupLatitudeBucket")

        XCTAssertNil(ScheduledRideOpportunity(id: "req-1", data: data))
    }

    /// The projection carries no destination — an approved driver sees where
    /// to be, not where they're going, until they accept.
    func testOpportunityHasNoDestinationToday() {
        let opportunity = ScheduledRideOpportunity(id: "req-1", data: opportunityDocument())
        XCTAssertNil(opportunity?.destinationArea, "Nothing should be invented here")
    }

    /// If the projection gains a coarse destination area, it decodes without
    /// any other change.
    func testOpportunityPicksUpDestinationAreaIfTheProjectionAddsOne() {
        var data = opportunityDocument()
        data["destinationArea"] = "Airport"

        XCTAssertEqual(ScheduledRideOpportunity(id: "req-1", data: data)?.destinationArea, "Airport")
    }

    /// The projection's status vocabulary is its own — `open` / `assigned` /
    /// `offerLimitReached`, never the request's lifecycle values.
    func testOpportunityStatusIsADistinctVocabularyFromTheRequest() {
        XCTAssertEqual(ScheduledRideOpportunityStatus(rawValue: "open"), .open)
        XCTAssertEqual(ScheduledRideOpportunityStatus(rawValue: "assigned"), .assigned)
        XCTAssertEqual(ScheduledRideOpportunityStatus(rawValue: "offerLimitReached"), .offerLimitReached)

        // The bug this type exists to prevent: querying the projection for a
        // request-lifecycle status matches nothing, forever, silently.
        XCTAssertNil(ScheduledRideOpportunityStatus(rawValue: "seekingDrivers"))
        XCTAssertNil(ScheduledRideOpportunityStatus(rawValue: "confirmed"))
    }

    // MARK: - Request document → reservation

    private func requestDocument() -> [String: Any] {
        [
            "schemaVersion": 1,
            "requestId": "req-1",
            "riderId": "rider-1",
            "selectionMode": "quick",
            "rideType": "go",
            "pickup": ["address": "1 Peachtree St", "latitude": 33.7812, "longitude": -84.3841, "area": "Midtown"],
            "destination": ["address": "Hartsfield", "latitude": 33.6407, "longitude": -84.4277, "area": "Airport"],
            "routeEstimate": ["distanceMiles": 11.8, "durationMinutes": 24.0, "source": "mapKit", "version": "1"],
            "scheduledAt": 1_760_000_000_000,
            "originalTimeZone": "America/New_York",
            "status": "confirmed",
            "assignedDriverId": "driver-1",
            "priceLockId": "v1",
            "approvedMaximumCents": 4500,
            "currency": "usd",
            "confirmedAt": 1_759_990_000_000
        ]
    }

    func testReservationDecodesTheRequestDocument() {
        let reservation = ScheduledRideReservation(id: "req-1", data: requestDocument())

        XCTAssertEqual(reservation?.pickupArea, "Midtown")
        XCTAssertEqual(reservation?.destinationArea, "Airport")
        XCTAssertEqual(reservation?.status, .confirmed)
        XCTAssertEqual(reservation?.pickupCoordinate.latitude, 33.7812)
        XCTAssertEqual(reservation?.estimatedTripMinutes, 24)
    }

    /// Money is not on the request. Decoding must leave it absent rather than
    /// defaulting to zero, or a confirmed ride advertises $0.00 until its
    /// offer arrives.
    func testReservationCarriesNoMoneyFromTheRequestDocument() {
        let reservation = ScheduledRideReservation(id: "req-1", data: requestDocument())

        XCTAssertNil(reservation?.driverPayoutCents)
        XCTAssertNil(reservation?.lockedBaseFareCents)
        XCTAssertNil(reservation?.driverPayoutDisplay)
        XCTAssertNil(reservation?.lockedBaseFareDisplay)
    }

    // MARK: - Offer document

    /// Mirrors the backend's offer `tx.create`. Note `driverPayoutCents` sits
    /// inside the embedded server quote, not at the top level.
    private func offerDocument(status: String = "selected") -> [String: Any] {
        [
            "requestId": "req-1",
            "driverId": "driver-1",
            "status": status,
            "quote": [
                "pricingVersion": "scheduled-rides-v1",
                "rideSubtotalCents": 3600,
                "bookingFeeCents": 600,
                "riderBaseFareCents": 4200,
                "driverPayoutCents": 2520,
                "platformShareCents": 1080,
                "currency": "usd"
            ],
            "exactBaseFareCents": 4200,
            "currency": "usd",
            "expiresAt": 1_759_998_000_000
        ]
    }

    func testOfferReadsPayoutFromTheEmbeddedQuote() {
        let offer = ScheduledRideDriverOffer(data: offerDocument())

        XCTAssertEqual(offer?.driverPayoutCents, 2520)
        XCTAssertEqual(offer?.exactBaseFareCents, 4200)
        XCTAssertEqual(offer?.status, .selected)
    }

    func testOfferStatusDistinguishesPendingFromSelected() {
        XCTAssertEqual(ScheduledRideDriverOffer(data: offerDocument(status: "active"))?.status, .active)
        XCTAssertEqual(ScheduledRideDriverOffer(data: offerDocument(status: "selected"))?.status, .selected)
    }

    // MARK: - The join

    /// Firestore has no joins: the ride comes from one document and the money
    /// from another, and the client merges them on `requestId`.
    func testJoiningAnOfferSuppliesTheMoneyTheRequestLacks() {
        guard let reservation = ScheduledRideReservation(id: "req-1", data: requestDocument()),
              let offer = ScheduledRideDriverOffer(data: offerDocument()) else {
            return XCTFail("Fixtures failed to decode")
        }

        let merged = reservation.withMoney(from: offer)

        XCTAssertEqual(merged.driverPayoutCents, 2520)
        XCTAssertEqual(merged.driverPayoutDisplay, "$25.20")
        XCTAssertEqual(merged.lockedBaseFareDisplay, "$42.00", "Rider's fare, shown as trip context")
        XCTAssertEqual(merged.id, reservation.id, "The join must not alter the ride itself")
        XCTAssertEqual(merged.status, reservation.status)
    }

    /// The two listeners arrive independently and in no guaranteed order, so
    /// the view model must re-run the join when the later one lands.
    func testOfferArrivingAfterItsReservationStillAttachesMoney() {
        let backend = FakeScheduledRideBackend()
        backend.reservations = [.fixture(id: "r1", lockedBaseFareCents: nil)]
        backend.offers = [.fixture(requestId: "r1", exactBaseFareCents: 4200)]
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "driver-1")
        drainMainQueue()

        XCTAssertEqual(vm.reservations.first?.driverPayoutCents, 2940, "70% of $42.00")
    }

    /// A reservation whose offer hasn't arrived shows no money rather than a
    /// placeholder figure.
    func testReservationWithoutAnOfferShowsNoMoney() {
        let backend = FakeScheduledRideBackend()
        backend.reservations = [.fixture(id: "r1", lockedBaseFareCents: nil)]
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "driver-1")
        drainMainQueue()

        XCTAssertNil(vm.reservations.first?.driverPayoutDisplay)
    }

    /// Choose My Driver's pending state now comes from the offer document, so
    /// it survives a relaunch instead of living in view-model memory.
    func testPendingOfferStateIsReadFromTheOfferDocuments() {
        let backend = FakeScheduledRideBackend()
        backend.offers = [
            .fixture(requestId: "awaiting", status: .active),
            .fixture(requestId: "won", status: .selected)
        ]
        let vm = ScheduledRidesDashboardVM(backend: backend)
        vm.startListening(driverId: "driver-1")
        drainMainQueue()

        XCTAssertEqual(vm.pendingOfferRequestIDs, ["awaiting"])
    }

    // MARK: - Helpers

    private func drainMainQueue(timeout: TimeInterval = 1) {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: timeout)
    }
}
