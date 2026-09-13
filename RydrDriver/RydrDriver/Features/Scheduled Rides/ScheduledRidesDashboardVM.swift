//
//  ScheduledRidesDashboardVM.swift
//  Rydr Driver
//
//  "See What's Ahead" — the Scheduled Rides dashboard driver reach from the
//  main dashboard's floating action stack. Map opens around the driver's
//  location; eligible opportunities plot as price markers. Confirmed
//  reservations live behind a top-right button as a sheet list.
//

import SwiftUI
import Combine
import MapKit
import CoreLocation
import FirebaseFirestore
#if canImport(_MapKit_SwiftUI)
import _MapKit_SwiftUI
#endif

/// Where a selected opportunity is in the two-step accept.
///
/// An enum rather than booleans: the states are exclusive, and booleans would
/// let the UI express "loading a quote and also showing a payout."
enum ScheduledRideQuoteState: Equatable {
    /// Nothing selected, or the selection can't be quoted — no point spending
    /// a callable on it.
    case idle
    case loading
    /// The only state that may show a fare.
    case ready(ScheduledRideDriverQuote)
    /// The price moved — fingerprint aged out locally, or the server returned
    /// QUOTE_CHANGED. Same recovery: show the new number, require another tap.
    case repriced(ScheduledRideDriverQuote)
    case responding
    /// Quick Schedule acked; the reservation is still in flight on the
    /// listener. This covers that gap.
    case confirming
    /// Choose My Driver acked. Terminal for the card — no reservation arrives
    /// unless the rider picks this driver.
    case offerSubmitted
    case failed(String)

    var quote: ScheduledRideDriverQuote? {
        switch self {
        case .ready(let quote), .repriced(let quote): return quote
        default: return nil
        }
    }

    var isBusy: Bool {
        switch self {
        case .loading, .responding, .confirming: return true
        default: return false
        }
    }
}

/// Where a check-in attempt is. Mirrors the quote machine — the payload lives
/// on the case that owns it, so an activation time is unreachable before the
/// server supplies one.
enum ScheduledRideCheckInState: Equatable {
    case idle
    /// MapKit is computing the route to pickup.
    case locating
    /// The callable is in flight.
    case submitting
    /// Accepted. Holds the receipt until the listener delivers the status
    /// change — the reservation is server-owned.
    case accepted(ScheduledRideCheckInReceipt)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .locating, .submitting: return true
        default: return false
        }
    }
}

/// How the pickup ETA gets calculated.
///
/// Injectable like the callables, but for a device capability: a test that
/// calls MapKit is slow, needs connectivity, and can't reproduce "no route
/// exists" on demand.
typealias ScheduledRideRouteEstimator = (
    _ from: CLLocationCoordinate2D,
    _ to: CLLocationCoordinate2D
) async -> RideRequestLegEstimate?

// MARK: - ViewModel

final class ScheduledRidesDashboardVM: ObservableObject {
    @Published var mapPosition: MapCameraPosition = .region(DriverMapDefaults.pilotRegion)
    @Published var opportunities: [ScheduledRideOpportunity] = []
    @Published var reservations: [ScheduledRideReservation] = []
    @Published var selectedOpportunityID: String? {
        didSet {
            guard oldValue != selectedOpportunityID else { return }
            // A quote belongs to one opportunity. Changing pins must not leave
            // the previous ride's payout on screen.
            quoteTask?.cancel()
            quoteState = .idle
        }
    }
    @Published var quoteState: ScheduledRideQuoteState = .idle
    @Published var acceptError: String?
    @Published var isCancelling = false
    @Published var cancelError: String?
    @Published var checkInState: ScheduledRideCheckInState = .idle
    @Published var checkInError: String?
    @Published var loadError: String?
    /// Firestore is answering from its local cache. The data is real but may
    /// be behind the server — worth telling the driver before they act on it.
    @Published var isShowingCachedData = false
    /// Distinguishes "the listener has never answered" from "it answered with
    /// nothing." An empty list means something different in each case, and the
    /// reservations sheet says so.
    @Published var hasLoadedReservations = false
    /// Offers the rider hasn't acted on yet — Choose My Driver responses that
    /// are recorded server-side but not yet accepted or declined. Read from
    /// the offer documents rather than remembered in memory, so it survives a
    /// relaunch.
    @Published var pendingOfferRequestIDs: Set<String> = []

    /// A coarser fix can't produce a trustworthy ETA, and a bad ETA moves the
    /// server's activation time.
    ///
    /// Deliberately not in ScheduledRideConfig — that type mirrors approved
    /// server values, and this is a client-side judgement.
    static let maximumLocationAccuracyMeters: CLLocationAccuracy = 100

    private let backend: any ScheduledRideBackend
    private let routeEstimator: ScheduledRideRouteEstimator
    private var opportunityRegistration: ListenerRegistration?
    private var reservationRegistration: ListenerRegistration?
    private var offerRegistration: ListenerRegistration?
    /// The raw request documents, before money is joined on. Kept separate so
    /// a late offer snapshot can re-run the join without re-reading anything.
    private var rawReservations: [ScheduledRideReservation] = []
    private var offersByRequestID: [String: ScheduledRideDriverOffer] = [:]
    private var quoteTask: Task<Void, Never>?
    /// Set while a Quick Schedule ack is waiting for its reservation to arrive
    /// on the listener. Cleared the moment that reservation shows up.
    private var confirmingRequestID: String?
    /// Idempotency keys, kept per reservation so a retry of the same check-in
    /// carries the same `operationId` the first attempt used.
    private var checkInOperationIDs: [String: String] = [:]

    /// `any ScheduledRideBackend` rather than a generic parameter: the view
    /// model never needs the concrete type, and a generic would infect every
    /// type holding one, including the SwiftUI views.
    init(
        backend: any ScheduledRideBackend = FirebaseScheduledRideBackend(),
        routeEstimator: @escaping ScheduledRideRouteEstimator = ScheduledRidesDashboardVM.liveRouteEstimate
    ) {
        self.backend = backend
        self.routeEstimator = routeEstimator
    }

    /// The same estimator the cards already use — one MapKit integration.
    static func liveRouteEstimate(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) async -> RideRequestLegEstimate? {
        await RideRequestRouteEstimator.estimateUsingMapKit(from: start, to: end)
    }

    deinit {
        opportunityRegistration?.remove()
        reservationRegistration?.remove()
        offerRegistration?.remove()
        quoteTask?.cancel()
    }

    func eligibility(for opportunity: ScheduledRideOpportunity) -> ScheduledRideOpportunityEligibility {
        opportunity.eligibility(against: reservations)
    }

    // MARK: Accept — step one, the quote

    /// Selecting a pin triggers the quote, not tapping Accept.
    ///
    /// Forced by the contract: the card must show `driverPayoutCents`, and the
    /// only other number we hold is the rider's ceiling, which may not be
    /// presented as earnings. So there is nothing to render until it arrives.
    ///
    /// Ineligible opportunities are selected but never quoted — a callable
    /// costs money, and the answer can't be acted on.
    func select(_ opportunity: ScheduledRideOpportunity) {
        selectedOpportunityID = opportunity.id
        guard case .eligible = eligibility(for: opportunity) else { return }
        loadQuote(requestId: opportunity.id)
    }

    func retryQuote() {
        guard let requestId = selectedOpportunityID else { return }
        loadQuote(requestId: requestId)
    }

    private func loadQuote(requestId: String, repricing: Bool = false) {
        quoteTask?.cancel()
        quoteState = .loading
        quoteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let quote = try await self.backend.previewQuote(requestId: requestId)
                guard !Task.isCancelled, self.selectedOpportunityID == requestId else { return }
                self.quoteState = repricing ? .repriced(quote) : .ready(quote)
            } catch {
                guard !Task.isCancelled, self.selectedOpportunityID == requestId else { return }
                let callableError = ScheduledRideCallableError(error)
                self.quoteState = .failed(callableError.errorDescription ?? "Couldn't load this ride's pay.")
            }
        }
    }

    // MARK: Accept — step two, the fingerprint

    /// Accepts at the exact fingerprint the driver is looking at.
    ///
    /// Two paths lead to "show a new number and ask again" — a locally expired
    /// fingerprint, or a server QUOTE_CHANGED. Both land on `.repriced`, so
    /// the driver always re-confirms against a price they have seen.
    ///
    /// Nothing here appends to `reservations`: the response only acknowledges,
    /// and the confirmed reservation arrives on the listener.
    func acceptSelected() async {
        guard let quote = quoteState.quote else { return }

        // Locally stale fingerprint: re-quote rather than spend a doomed call.
        if quote.isExpired {
            loadQuote(requestId: quote.requestId, repricing: true)
            return
        }

        let selectionMode = opportunities.first { $0.id == quote.requestId }?.selectionMode

        quoteState = .responding
        do {
            try await backend.respond(
                requestId: quote.requestId,
                quoteFingerprint: quote.quoteFingerprint
            )
            if selectionMode == .chooseDriver {
                // No reservation is coming unless the rider picks this driver.
                // The offer listener will confirm this durably; this just
                // covers the moment before that snapshot arrives.
                quoteState = .offerSubmitted
            } else {
                // Quick Schedule, or a projection that didn't tell us the
                // mode. Either way a reservation may be on its way, so wait
                // for the listener rather than declaring an outcome.
                confirmingRequestID = quote.requestId
                quoteState = .confirming
            }
        } catch {
            handleAcceptFailure(error, quote: quote)
        }
    }

    private func handleAcceptFailure(_ error: Error, quote: ScheduledRideDriverQuote) {
        let callableError = ScheduledRideCallableError(error)

        if callableError.requiresFreshQuote {
            loadQuote(requestId: quote.requestId, repricing: true)
            return
        }

        quoteState = .failed(callableError.errorDescription ?? "Couldn't accept this ride.")

        if callableError.invalidatesLocalState {
            // The server just told us our picture of this driver's
            // commitments is wrong. Drop the selection so the card can't be
            // re-tapped against stale state; the listeners are already
            // pushing the corrected version.
            acceptError = callableError.errorDescription
            selectedOpportunityID = nil
        }
    }

    func cancel(_ reservation: ScheduledRideReservation, driverId: String, reason: String) async {
        isCancelling = true
        defer { isCancelling = false }

        do {
            try await backend.cancelReservation(
                requestId: reservation.id,
                operationId: UUID().uuidString,
                reasonCode: reason
            )
            reservations.removeAll { $0.id == reservation.id }
        } catch {
            cancelError = "Couldn't cancel this ride. Please try again."
        }
    }

    func checkInEligibility(for reservation: ScheduledRideReservation) -> ScheduledRideCheckInEligibility {
        reservation.checkInEligibility(against: reservations)
    }

    /// Calculates the pickup ETA with MapKit and sends it to Firebase.
    ///
    /// Firebase has no server-side routing in the MVP, so the device is the
    /// only thing that can produce this number. That puts three device-side
    /// failures in front of the call, each with a different fix the driver can
    /// act on — hence separate cases rather than one message.
    ///
    /// `location` is a `CLLocation` because a coordinate can't say how much to
    /// trust itself. Nothing here writes to `reservations`; the server owns
    /// the status change.
    func checkIn(
        _ reservation: ScheduledRideReservation,
        driverId: String,
        location: CLLocation?,
        now: Date = Date()
    ) async {
        guard case .eligible = checkInEligibility(for: reservation) else { return }

        // Client-side window check — fast local feedback only. The server
        // re-checks and can still reject with WINDOW_CLOSED / INVALID_STATUS.
        guard reservation.timing(now: now) == .checkInOpen else {
            fail(with: ScheduledRideCheckInPreflightError.windowNotOpen)
            return
        }

        guard let location, CLLocationCoordinate2DIsValid(location.coordinate) else {
            fail(with: ScheduledRideCheckInPreflightError.locationUnavailable)
            return
        }
        // A negative horizontalAccuracy means Core Location considers the fix
        // invalid outright, not merely imprecise.
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.maximumLocationAccuracyMeters else {
            fail(with: ScheduledRideCheckInPreflightError.locationTooInaccurate)
            return
        }

        checkInState = .locating
        guard let estimate = await routeEstimator(location.coordinate, reservation.pickupCoordinate) else {
            fail(with: ScheduledRideCheckInPreflightError.routeUnavailable)
            return
        }

        // Stamped the moment MapKit answered. The server validates freshness
        // against this, not against when the call arrives.
        let etaCalculatedAt = Date()

        // One operationId per attempt, reused across retries of that attempt
        // so the server can recognize a repeat rather than treating it as a
        // second check-in.
        let operationId = checkInOperationIDs[reservation.id] ?? UUID().uuidString
        checkInOperationIDs[reservation.id] = operationId

        checkInState = .submitting
        do {
            let receipt = try await backend.submitCheckIn(
                requestId: reservation.id,
                operationId: operationId,
                pickupEtaSeconds: estimate.durationMinutes * 60,
                etaCalculatedAt: etaCalculatedAt
            )
            // Succeeded, so this attempt is over — a later check-in on this
            // ride would be a genuinely new operation.
            checkInOperationIDs[reservation.id] = nil
            checkInState = .accepted(receipt)
        } catch {
            let callableError = ScheduledRideCallableError(error)
            checkInState = .failed(callableError.errorDescription ?? "Couldn't check in.")
            checkInError = callableError.errorDescription

            // ETA_STALE means the number aged out between calculating and
            // submitting — a slow network, or a driver who tapped twice with a
            // pause. Re-running the estimate is the fix, and the retained
            // operationId keeps that a retry rather than a new attempt.
            if callableError == .etaStale {
                checkInState = .failed("Your ETA went stale before it reached us. Tap Check In again.")
            }
        }
    }

    private func fail(with error: ScheduledRideCheckInPreflightError) {
        checkInState = .failed(error.errorDescription ?? "Couldn't check in.")
        checkInError = error.errorDescription
    }

    func start(near coordinate: CLLocationCoordinate2D, driverId: String) {
        mapPosition = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
            )
        )
        startListening(driverId: driverId)
    }

    /// Listeners rather than fetches: the backend moves this data without the
    /// driver acting — another driver takes an opportunity, a deadline passes,
    /// a rider cancels.
    ///
    /// Snapshots arrive on Firestore's queue, so every published mutation hops
    /// to main first.
    func startListening(driverId: String) {
        stopListening()
        // A relaunch, or reopening the screen, starts from "nothing known"
        // rather than inheriting the previous session's flags — otherwise a
        // stale offline banner or a stale empty state renders for one frame
        // before the first snapshot lands.
        hasLoadedReservations = false
        isShowingCachedData = false
        loadError = nil
        rawReservations = []
        offersByRequestID = [:]
        pendingOfferRequestIDs = []

        opportunityRegistration = backend.listenToOpportunities(driverId: driverId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let snapshot):
                    self.opportunities = snapshot.items
                    self.isShowingCachedData = snapshot.isFromCache
                    self.loadError = nil
                case .failure(let error):
                    self.opportunities = []
                    self.loadError = Self.message(for: error)
                }
            }
        }

        offerRegistration = backend.listenToOffers(driverId: driverId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .success(let snapshot) = result else {
                    // An offer failure must not blank the schedule: the
                    // reservations themselves are still valid, they just lose
                    // their money until this recovers.
                    return
                }
                self.offersByRequestID = Dictionary(
                    snapshot.items.map { ($0.requestId, $0) },
                    uniquingKeysWith: { _, newer in newer }
                )
                self.pendingOfferRequestIDs = Set(
                    snapshot.items.filter { $0.status == .active }.map(\.requestId)
                )
                self.publishReservations()
            }
        }

        reservationRegistration = backend.listenToReservations(driverId: driverId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let snapshot):
                    self.rawReservations = snapshot.items
                    self.isShowingCachedData = snapshot.isFromCache
                    self.hasLoadedReservations = true
                    self.loadError = nil
                    self.publishReservations()
                    self.resolveConfirmationIfDelivered()
                case .failure(let error):
                    self.rawReservations = []
                    self.reservations = []
                    self.hasLoadedReservations = true
                    self.loadError = Self.message(for: error)
                }
            }
        }
    }

    /// Closes the loop on a Quick Schedule accept: the card sits in
    /// `.confirming` until the server's confirmed request lands, then gets out
    /// of the way.
    private func resolveConfirmationIfDelivered() {
        guard let requestID = confirmingRequestID,
              reservations.contains(where: { $0.id == requestID }) else { return }
        confirmingRequestID = nil
        quoteState = .idle
        selectedOpportunityID = nil
    }

    /// Firestore has no joins. Requests carry the ride, offers carry the
    /// money, and they meet on `requestId` — re-run whenever either changes,
    /// since they arrive independently and in no guaranteed order.
    private func publishReservations() {
        reservations = rawReservations
            .map { reservation in
                guard let offer = offersByRequestID[reservation.id] else { return reservation }
                return reservation.withMoney(from: offer)
            }
            // Soonest pickup first. The server returns documents in its own
            // order, and a schedule read top-down has to be chronological.
            .sorted { $0.pickupTime < $1.pickupTime }
    }

    func stopListening() {
        offerRegistration?.remove()
        offerRegistration = nil
        opportunityRegistration?.remove()
        opportunityRegistration = nil
        reservationRegistration?.remove()
        reservationRegistration = nil
    }

    /// Our errors carry driver-readable text; anything else is a raw Firestore
    /// failure the driver shouldn't see verbatim.
    private static func message(for error: Error) -> String {
        (error as? ScheduledRideServiceError)?.errorDescription
            ?? "Couldn't load your scheduled rides. Pull down to try again."
    }
}

// MARK: - View

struct ScheduledRidesDashboardView: View {
    /// A full `CLLocation`, not a coordinate. The map only needs the point,
    /// but check-in also needs `horizontalAccuracy` to decide whether the fix
    /// is good enough to build a pickup ETA from.
    let driverLocation: CLLocation?
    let driverId: String

    private var driverCoordinate: CLLocationCoordinate2D? { driverLocation?.coordinate }

    @Environment(\.dismiss) private var dismiss
    #if DEBUG
    // The Scheduled Rides collections are not deployed yet, so DEBUG builds
    // run this screen on the same fixtures the unit tests use. Delete this
    // branch (not the #else) when the backend goes live.
    @StateObject private var vm = ScheduledRidesDashboardVM(backend: FakeScheduledRideBackend.qaFixtures())
    #else
    @StateObject private var vm = ScheduledRidesDashboardVM()
    #endif
    @State private var showReservations = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $vm.mapPosition) {
                ForEach(vm.opportunities) { opportunity in
                    Annotation("", coordinate: opportunity.pickupCoordinate) {
                        ScheduledRideOpportunityMarker(
                            opportunity: opportunity,
                            isSelected: vm.selectedOpportunityID == opportunity.id
                        )
                        .onTapGesture {
                            vm.select(opportunity)
                        }
                    }
                }
            }
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Circle().fill(.regularMaterial)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.primary)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Button {
                showReservations = true
            } label: {
                Circle().fill(.regularMaterial)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "list.bullet")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.primary)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .trailing)

            if let selectedOpportunity {
                ScheduledRideOpportunityCard(
                    opportunity: selectedOpportunity,
                    eligibility: vm.eligibility(for: selectedOpportunity),
                    quoteState: vm.quoteState,
                    onAccept: { Task { await vm.acceptSelected() } },
                    onRetryQuote: { vm.retryQuote() },
                    onDismiss: { vm.selectedOpportunityID = nil }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .alert(
            "Couldn't Accept",
            isPresented: Binding(
                get: { vm.acceptError != nil },
                set: { isPresented in if !isPresented { vm.acceptError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.acceptError ?? "")
        }
        .alert(
            "Scheduled Rides Unavailable",
            isPresented: Binding(
                get: { vm.loadError != nil },
                set: { isPresented in if !isPresented { vm.loadError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.loadError ?? "")
        }
        .task {
            vm.start(
                near: driverCoordinate ?? DriverMapDefaults.pilotCoordinate,
                driverId: driverId
            )
        }
        .onDisappear {
            // Firestore listeners bill and fire until removed. `deinit` also
            // cleans up, but a @StateObject outlives a single presentation of
            // this screen, so detaching here is what actually stops the work
            // when the driver closes the dashboard.
            vm.stopListening()
        }
        .sheet(isPresented: $showReservations) {
            ScheduledRideReservationsSheet(vm: vm, driverId: driverId, driverLocation: driverLocation)
        }
    }

    private var selectedOpportunity: ScheduledRideOpportunity? {
        vm.opportunities.first { $0.id == vm.selectedOpportunityID }
    }
}

private struct ScheduledRideOpportunityMarker: View {
    let opportunity: ScheduledRideOpportunity
    let isSelected: Bool

    /// Shows the pickup time, not a price. The rider's approved maximum may
    /// not be presented as earnings, and the real payout only exists once a
    /// quote is fetched — one callable per visible pin is too expensive.
    var body: some View {
        Text(opportunity.pickupTime.formatted(date: .omitted, time: .shortened))
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Styles.rydrGradient))
            .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
            .shadow(color: Color.red.opacity(0.28), radius: 8, y: 3)
            .scaleEffect(isSelected ? 1.12 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Reservations Sheet

private struct ScheduledRideReservationsSheet: View {
    @ObservedObject var vm: ScheduledRidesDashboardVM
    let driverId: String
    let driverLocation: CLLocation?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if vm.isShowingCachedData {
                    offlineBanner
                }
                content
            }
            .navigationTitle("Scheduled Reservations")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Three empty-ish states that mean different things. Collapsing them into
    /// one "No Confirmed Rides" would tell a driver with a network problem
    /// that they have no work.
    @ViewBuilder
    private var content: some View {
        if !vm.hasLoadedReservations && vm.reservations.isEmpty {
            ProgressView("Loading your scheduled rides…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError = vm.loadError, vm.reservations.isEmpty {
            ContentUnavailableView(
                "Couldn't Load Your Rides",
                systemImage: "exclamationmark.triangle",
                description: Text(loadError)
            )
        } else if vm.reservations.isEmpty {
            ContentUnavailableView(
                "No Confirmed Rides",
                systemImage: "calendar.badge.clock",
                description: Text("Accepted scheduled rides will appear here.")
            )
        } else {
            List(vm.reservations) { reservation in
                NavigationLink {
                    ScheduledRideReservationDetailView(
                        reservationID: reservation.id,
                        vm: vm,
                        driverId: driverId,
                        driverLocation: driverLocation
                    )
                } label: {
                    ScheduledRideReservationRow(reservation: reservation)
                }
            }
            .listStyle(.plain)
        }
    }

    /// Not an error: the reservations are real, just possibly behind.
    private var offlineBanner: some View {
        Label("Showing saved rides — you're offline", systemImage: "wifi.slash")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.12))
    }
}

private struct ScheduledRideReservationRow: View {
    let reservation: ScheduledRideReservation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(reservation.rideType)
                    .font(.subheadline.weight(.black))
                Spacer()
                // driverPayoutCents, never lockedBaseFareCents. The driver is
                // permitted to see the locked rider fare, but the contract is
                // explicit that it "is not driver payout" — so when the
                // projection omits the payout we show nothing rather than
                // labelling the rider's fare as earnings.
                if let payout = reservation.driverPayoutDisplay {
                    Text(payout)
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(Color.red)
                }
            }

            Text("\(reservation.pickupArea) → \(reservation.destinationArea)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(reservation.pickupTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let badge {
                    Text(badge.text)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(badge.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(badge.color.opacity(0.14)))
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(reservation.timing() == .stale ? 0.55 : 1)
    }

    /// Derived from the canonical status plus the clock — see
    /// `ScheduledRideReservation.timing(now:)`. Nothing here is persisted.
    private var badge: (text: String, color: Color)? {
        switch reservation.timing() {
        case .upcoming, .closed:
            return nil
        case .checkInOpen:
            return ("CHECK IN NOW", .orange)
        case .checkInMissed:
            return ("CHECK-IN MISSED", .red)
        case .checkedIn:
            return ("CHECKED IN", .green)
        case .stale:
            // The server's deadline job runs every minute; if pickup has
            // passed and this never moved, it is not actionable.
            return ("NEEDS ATTENTION", .secondary)
        }
    }
}

private struct ScheduledRideReservationDetailView: View {
    let reservationID: String
    @ObservedObject var vm: ScheduledRidesDashboardVM
    let driverId: String
    let driverLocation: CLLocation?

    @Environment(\.dismiss) private var dismiss
    @State private var showCancelConfirmation = false

    /// Looked up fresh each render rather than held as a snapshot, so
    /// check-in and cancel changes actually show.
    private var reservation: ScheduledRideReservation? {
        vm.reservations.first { $0.id == reservationID }
    }

    var body: some View {
        Group {
            if let reservation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(reservation.pickupTime.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        // Same rule as the row: show the driver's payout, or
                        // nothing. The locked rider fare appears below as
                        // trip context, clearly labelled as the rider's.
                        if let payoutCents = reservation.driverPayoutCents {
                            UpfrontFareHero(fare: Double(payoutCents) / 100)
                        }

                        if let lockedFare = reservation.lockedBaseFareDisplay {
                            Text("Rider's locked fare: \(lockedFare)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        RideRequestRouteDetails(
                            pickupAddress: reservation.pickupArea,
                            dropoffAddress: reservation.destinationArea,
                            pickupEstimate: nil,
                            dropoffEstimate: tripEstimate(for: reservation)
                        )

                        checkInSection(for: reservation)

                        Button(role: .destructive) {
                            showCancelConfirmation = true
                        } label: {
                            HStack {
                                if vm.isCancelling {
                                    ProgressView()
                                } else {
                                    Text("Cancel Ride")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .font(.headline.weight(.bold))
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.red, lineWidth: 1.5)
                        )
                        .foregroundStyle(Color.red)
                        .buttonStyle(.plain)
                        .disabled(vm.isCancelling)
                        .accessibilityLabel(vm.isCancelling ? "Cancelling ride" : "Cancel scheduled ride")
                    }
                    .padding(18)
                }
                .navigationTitle(reservation.rideType)
                .confirmationDialog(
                    "Why are you cancelling?",
                    isPresented: $showCancelConfirmation,
                    titleVisibility: .visible
                ) {
                    ForEach(Self.cancellationReasons, id: \.self) { reason in
                        Button(reason, role: .destructive) {
                            Task {
                                await vm.cancel(reservation, driverId: driverId, reason: reason)
                                dismiss()
                            }
                        }
                    }
                    Button("Keep Ride", role: .cancel) {}
                } message: {
                    Text("The rider will be notified and this reason will be saved with the ride.")
                }
            } else {
                // Reservation is gone from vm.reservations (e.g. cancelled
                // from elsewhere) — nothing to show, and the NavigationLink
                // will pop this screen on its own.
                EmptyView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Couldn't Cancel",
            isPresented: Binding(
                get: { vm.cancelError != nil },
                set: { isPresented in if !isPresented { vm.cancelError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.cancelError ?? "")
        }
        .alert(
            "Couldn't Check In",
            isPresented: Binding(
                get: { vm.checkInError != nil },
                set: { isPresented in if !isPresented { vm.checkInError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.checkInError ?? "")
        }
    }

    // TODO: Check In has no time gating yet — available immediately on
    // confirmation, even hours before pickup. The contract lists check-in
    // windows as a platformConfig/scheduledRides value (server-configured,
    // not a client constant), so this should read that config once it
    // exists rather than hardcoding a guess here.
    @ViewBuilder
    private func checkInSection(for reservation: ScheduledRideReservation) -> some View {
        switch reservation.status {
        case .activating, .active:
            // The server is creating the targeted rideRequests record now,
            // which arrives through the existing dispatch card.
            statusPanel(
                icon: "bolt.horizontal.circle.fill",
                tint: .blue,
                title: "Activating now",
                detail: "Your scheduled pickup is becoming a ride request. Accept it from your dashboard."
            )

        case .checkedIn:
            checkedInPanel(for: reservation)

        default:
            checkInControl(for: reservation)
        }
    }

    private func statusPanel(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.bold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.10)))
    }

    @ViewBuilder
    private func checkedInPanel(for reservation: ScheduledRideReservation) -> some View {
        // Prefer the reservation's activation time; the receipt covers the
        // gap before the listener delivers the updated document.
        let activationAt = reservation.activationAt ?? {
            if case .accepted(let receipt) = vm.checkInState { return receipt.activationAt }
            return nil
        }()

        VStack(alignment: .leading, spacing: 6) {
            statusPanel(
                icon: "checkmark.circle.fill",
                tint: .green,
                title: reservation.pickupETAMinutes.map { "Checked in — \(Int($0)) min to pickup" } ?? "Checked in",
                detail: reservation.checkedInAt.map {
                    "Checked in at \($0.formatted(date: .omitted, time: .shortened))"
                } ?? "Waiting for confirmation…"
            )

            if let activationAt {
                Label(
                    "Activates at \(activationAt.formatted(date: .omitted, time: .shortened))",
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func checkInControl(for reservation: ScheduledRideReservation) -> some View {
        Group {
            let eligibility = vm.checkInEligibility(for: reservation)
            let timing = reservation.timing()
            // Gated on the derived window as fast local feedback. The server
            // re-checks and can still reject with WINDOW_CLOSED.
            let isBlocked = eligibility != .eligible || timing != .checkInOpen

            VStack(alignment: .leading, spacing: 8) {
                if case .blockedByExistingCheckIn(let other) = eligibility {
                    Label(
                        "Already checked in to your \(other.pickupTime.formatted(date: .omitted, time: .shortened)) ride. Complete or cancel it first.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                } else if let windowNotice = windowNotice(for: reservation, timing: timing) {
                    Label(windowNotice, systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(timing == .checkInMissed ? Color.red : Color.secondary)
                }

                if case .failed(let message) = vm.checkInState {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.orange)
                }

                Button {
                    Task { await vm.checkIn(reservation, driverId: driverId, location: driverLocation) }
                } label: {
                    HStack {
                        if vm.checkInState.isBusy {
                            ProgressView().tint(.white)
                            Text(vm.checkInState == .locating ? "Calculating ETA…" : "Checking in…")
                        } else {
                            Text("Check In")
                            Image(systemName: "location.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .font(.headline.weight(.bold))
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Styles.rydrGradient))
                .foregroundStyle(.white)
                .shadow(color: Color.red.opacity(0.26), radius: 14, y: 8)
                .buttonStyle(.plain)
                .opacity(isBlocked || vm.checkInState.isBusy ? 0.5 : 1)
                .disabled(isBlocked || vm.checkInState.isBusy)
                .accessibilityLabel(vm.checkInState.isBusy ? "Checking in" : "Check in and calculate pickup ETA")
            }
        }
    }

    /// Explains *why* check-in is unavailable, rather than leaving a dimmed
    /// button with no reason attached.
    private func windowNotice(for reservation: ScheduledRideReservation, timing: ScheduledRideReservationTiming) -> String? {
        switch timing {
        case .upcoming:
            return "Check-in opens at \(reservation.checkInOpensAt.formatted(date: .omitted, time: .shortened))."
        case .checkInMissed:
            return "Check-in closed at \(reservation.checkInDeadlineAt.formatted(date: .omitted, time: .shortened))."
        case .stale:
            return "This ride's pickup time has passed."
        case .checkInOpen, .checkedIn, .closed:
            return nil
        }
    }

    private func tripEstimate(for reservation: ScheduledRideReservation) -> RideRequestLegEstimate? {
        guard let miles = reservation.estimatedTripMiles,
              let minutes = reservation.estimatedTripMinutes else { return nil }
        return RideRequestLegEstimate(distanceMiles: miles, durationMinutes: minutes)
    }

    /// Subset of DriverRideInProgressView.driverCancellationReasons — drops
    /// "Deciding to go offline" and "Rider no-show", which only make sense
    /// once a ride is already underway, not before a scheduled pickup.
    private static let cancellationReasons: [String] = [
        "Destination too far",
        "Ride undesirable",
        "Accepted by mistake",
        "Safety concern",
        "Other"
    ]
}
