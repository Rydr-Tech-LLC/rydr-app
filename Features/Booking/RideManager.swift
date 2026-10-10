//
//  Driver.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 8/24/25.
//
import SwiftUI
import MapKit
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import AVFoundation

// MARK: - Models
struct Driver: Identifiable, Equatable {
    let id: String
    let name: String
    let profileImage: String?
    let carImage: String?
    let carMakeModel: String
    let rating: Double
    let compliments: [String]
    let perMinute: Double
    let perMile: Double
    var minimumFare: Double = 0
    var usesSuggestedPricing: Bool = false
    var coordinate: CLLocationCoordinate2D
    var score: Int                 // proximity/quality score
    var ratingCount: Int = 0
    var completedRideCount: Int? = nil
    var acceptanceRate: Int? = nil
    var stripeAccountId: String? = nil       // Stripe Connect account, for destination-charge payouts
    var stripeChargesEnabled: Bool = false   // Connect account has completed onboarding
    var gender: String? = nil
    var quotedRiderTotalCents: Int? = nil
    var quotedDriverPayoutCents: Int? = nil

    static func == (lhs: Driver, rhs: Driver) -> Bool { lhs.id == rhs.id }
}

struct RideEstimate: Equatable, Codable {
    var distanceMiles: Double
    var durationMinutes: Double
}

struct PaymentCard: Identifiable, Equatable {
    let id = UUID()
    let last4: String
    let brand: String              // "Visa", "Mastercard", etc.
    var stripePaymentMethodId: String? = nil   // nil for mock/placeholder cards (no real charge possible)
}

struct ReceiptChargeLine: Identifiable, Equatable {
    let id: String
    let title: String
    let amount: Double
}

struct ReceiptChargeBreakdown: Equatable {
    var rideFare: Double = 0
    var distanceCharge: Double = 0
    var timeCharge: Double = 0
    var minimumFareAdjustment: Double = 0
    var bookingFee: Double = 0
    var waitCharge: Double = 0
    var cancellationFee: Double = 0
    var destinationChangeCharge: Double = 0
    var additionalStopCharge: Double = 0
    var timeAdjustment: Double = 0
    var promoDiscount: Double = 0
    var tip: Double = 0
    var otherAdjustment: Double = 0

    static func legacy(total: Double) -> ReceiptChargeBreakdown {
        ReceiptChargeBreakdown(rideFare: total)
    }

    var calculatedTotal: Double {
        [
            rideFare,
            distanceCharge,
            timeCharge,
            minimumFareAdjustment,
            bookingFee,
            waitCharge,
            cancellationFee,
            destinationChangeCharge,
            additionalStopCharge,
            timeAdjustment,
            promoDiscount,
            tip,
            otherAdjustment
        ].reduce(0, +).currencyRounded
    }

    var lineItems: [ReceiptChargeLine] {
        [
            line("ride-fare", "Ride fare", rideFare),
            line("distance", "Distance", distanceCharge),
            line("time", "Time", timeCharge),
            line("minimum-fare", "Minimum fare adjustment", minimumFareAdjustment),
            line("booking-fee", "Booking fee", bookingFee),
            line("wait-time", "Wait time", waitCharge),
            line("cancellation-fee", "Cancellation fee", cancellationFee),
            line("destination-change", "Destination change", destinationChangeCharge),
            line("additional-stop", "Additional stop", additionalStopCharge),
            line("time-adjustment", "Ride time adjustment", timeAdjustment),
            line("promo", "RydrBank credit", promoDiscount),
            line("tip", "Tip", tip),
            line("adjustment", "Adjustment", otherAdjustment)
        ].compactMap { $0 }
    }

    func addingTip(_ tipAmount: Double) -> ReceiptChargeBreakdown {
        var copy = self
        copy.tip = tipAmount.currencyRounded
        return copy
    }

    private func line(_ id: String, _ title: String, _ amount: Double) -> ReceiptChargeLine? {
        guard abs(amount) >= 0.01 else { return nil }
        return ReceiptChargeLine(id: id, title: title, amount: amount.currencyRounded)
    }
}

struct Receipt: Identifiable, Equatable {
    let id: UUID
    let rideId: UUID
    let date: Date
    let driverName: String
    let pickup: String
    let dropoff: String
    let distanceMiles: Double
    let durationMinutes: Double
    let fare: Double
    let cardMasked: String
    let chargeBreakdown: ReceiptChargeBreakdown
    /// The backend (Firestore) ride document id — distinct from `rideId`,
    /// which is the client-local UUID. Needed so the Payment Failed UI can
    /// call `retryFailedPayment(rideId:...)` against the same ride the
    /// backend tracks `paymentStatus` on. Optional/back-compat for any
    /// existing call sites that don't have a backend id on hand.
    let backendRideId: String?

    init(
        id: UUID = UUID(),
        rideId: UUID,
        date: Date,
        driverName: String,
        pickup: String,
        dropoff: String,
        distanceMiles: Double,
        durationMinutes: Double,
        fare: Double,
        cardMasked: String,
        chargeBreakdown: ReceiptChargeBreakdown? = nil,
        backendRideId: String? = nil
    ) {
        self.id = id
        self.rideId = rideId
        self.date = date
        self.driverName = driverName
        self.pickup = pickup
        self.dropoff = dropoff
        self.distanceMiles = distanceMiles
        self.durationMinutes = durationMinutes
        self.fare = fare.currencyRounded
        self.cardMasked = cardMasked
        self.chargeBreakdown = chargeBreakdown ?? .legacy(total: fare)
        self.backendRideId = backendRideId
    }

    func addingTip(cents: Int) -> Receipt {
        let tipAmount = (Double(max(0, cents)) / 100.0).currencyRounded
        let updatedBreakdown = chargeBreakdown.addingTip(tipAmount)
        return Receipt(
            id: id,
            rideId: rideId,
            date: date,
            driverName: driverName,
            pickup: pickup,
            dropoff: dropoff,
            distanceMiles: distanceMiles,
            durationMinutes: durationMinutes,
            fare: updatedBreakdown.calculatedTotal,
            cardMasked: cardMasked,
            chargeBreakdown: updatedBreakdown,
            backendRideId: backendRideId
        )
    }
}

private extension Double {
    var currencyRounded: Double {
        (self * 100).rounded() / 100
    }
}

struct Ride: Identifiable, Equatable {
    enum Status: String, Codable { case enRouteToPickup, waitingForRider, enRouteToDropoff, completed, cancelled }
    let id = UUID()
    var pickup: String
    var dropoff: String
    var rideType: String
    var estimate: RideEstimate
    var driver: Driver
    var startedAt: Date = Date()
    var status: Status = .enRouteToPickup
    var fare: Double = 0
}

struct RideChatContext: Equatable {
    let rideId: String
    let riderId: String
    let driverId: String
    let driverName: String
}

// MARK: - Service protocol
enum DriverDecision { case accepted(driverId: String?), declined }

struct RideDispatchRefresh {
    let status: String
    let dispatchStatus: String?
    let driverId: String?
}

enum RideCancellationMode: String, Codable {
    case cancelRide
    case findAnotherDriver
}

struct BackendRideFinancialOutcome: Codable, Equatable {
    struct CalculationInputs: Codable, Equatable {
        let distanceMiles: Double?
        let billableDistance: Double?
        let billableMinutes: Double?
        let paidWaitSeconds: Int?
        let evidenceSource: String?
    }

    let pricingVersion: String?
    let outcomeType: String?
    let currency: String?
    let distanceChargeCents: Int
    let timeChargeCents: Int
    let minimumFareAdjustmentCents: Int
    let rideSubtotalCents: Int
    let bookingFeeCents: Int
    let waitChargeCents: Int
    let cancellationFeeCents: Int
    let grossChargeCents: Int
    let promotionDiscountCents: Int
    let finalRiderChargeCents: Int
    let driverPayoutCents: Int
    let platformShareCents: Int
    let calculationInputs: CalculationInputs?

    var receiptBreakdown: ReceiptChargeBreakdown {
        var breakdown: ReceiptChargeBreakdown
        switch outcomeType {
        case "rider_cancellation", "driver_cancellation":
            breakdown = ReceiptChargeBreakdown(
                bookingFee: Self.dollars(bookingFeeCents),
                waitCharge: Self.dollars(waitChargeCents),
                cancellationFee: Self.dollars(cancellationFeeCents),
                promoDiscount: -Self.dollars(promotionDiscountCents)
            )
        default:
            breakdown = ReceiptChargeBreakdown(
                distanceCharge: Self.dollars(distanceChargeCents),
                timeCharge: Self.dollars(timeChargeCents),
                minimumFareAdjustment: Self.dollars(minimumFareAdjustmentCents),
                bookingFee: Self.dollars(bookingFeeCents),
                waitCharge: Self.dollars(waitChargeCents),
                cancellationFee: Self.dollars(cancellationFeeCents),
                promoDiscount: -Self.dollars(promotionDiscountCents)
            )
        }

        // The backend total is authoritative. This also keeps receipts exact if
        // a future pricing version adds a component an older app does not know.
        let target = Self.dollars(finalRiderChargeCents)
        let reconciliation = (target - breakdown.calculatedTotal).currencyRounded
        if abs(reconciliation) >= 0.01 {
            breakdown.otherAdjustment = reconciliation
        }
        return breakdown
    }

    private static func dollars(_ cents: Int) -> Double {
        Double(cents) / 100.0
    }
}

struct RideLifecycleSnapshot {
    let status: Ride.Status?
    let rawStatus: String?
    let driverCoordinate: CLLocationCoordinate2D?
    let pickupCoordinate: CLLocationCoordinate2D?
    let dropoffCoordinate: CLLocationCoordinate2D?
    let pickupWaitStartedAt: Date?
    let pickupComplimentaryWaitSeconds: Int?
    let financialOutcome: BackendRideFinancialOutcome?
    let backendDistanceMiles: Double?
    let backendDurationMinutes: Double?
    let proratedCancellationChargeCents: Int?
    let proratedCancellationDistanceMiles: Double?
}

struct RideRecoverySnapshot {
    let rideId: String
    let pickup: String
    let dropoff: String
    let rideType: String
    let estimate: RideEstimate
    let driver: Driver
    let status: Ride.Status
    let startedAt: Date
    let fare: Double
    let pickupCoordinate: CLLocationCoordinate2D
    let dropoffCoordinate: CLLocationCoordinate2D
    let driverCoordinate: CLLocationCoordinate2D
    let waitChargePerMinute: Double
}

enum RideRequestError: LocalizedError {
    case driverTimedOut
    case noDriversAvailable
    case routeEstimateRequired

    var errorDescription: String? {
        switch self {
        case .driverTimedOut:
            return "That driver did not respond in time. Pick another nearby driver."
        case .noDriversAvailable:
            return "No nearby drivers are available right now. Try again in a moment."
        case .routeEstimateRequired:
            return "We need a confirmed route before showing drivers. Please choose a valid pickup and drop-off."
        }
    }
}

protocol RideService: AnyObject, Sendable {
    func fetchNearbyDrivers(
        pickup: String,
        dropoff: String,
        rideType: String,
        near: CLLocationCoordinate2D,
        pickupCoordinate: CLLocationCoordinate2D?,
        dropoffCoordinate: CLLocationCoordinate2D?,
        estimatedDistanceMiles: Double?,
        riderPreferences: RiderRidePreferences?
    ) async throws -> [Driver]
    func requestRide(
        driverId: String,
        pickup: String,
        dropoff: String,
        rideType: String,
        pickupCoordinate: CLLocationCoordinate2D?,
        dropoffCoordinate: CLLocationCoordinate2D?,
        estimate: RideEstimate?,
        rydrBankCode: String?,
        replacementForRideId: String?,
        riderPreferences: RiderRidePreferences?,
        riderVerified: Bool,
        candidateDriverIds: [String]
    ) async throws -> String // returns rideId
    func awaitDriverDecision(rideId: String) async throws -> DriverDecision
    func refreshRideDispatch(rideId: String) async throws -> RideDispatchRefresh
    func rideLifecycleStream(rideId: String) -> AsyncThrowingStream<RideLifecycleSnapshot, Error>
    func recoverRide(rideId: String) async throws -> RideRecoverySnapshot
    func driverLocationStream(rideId: String) -> AsyncStream<CLLocationCoordinate2D>
    func cancelRide(rideId: String, mode: RideCancellationMode) async throws -> BackendRideFinancialOutcome?
    func cancelMidRide(rideId: String) async throws -> BackendRideFinancialOutcome
}

// MARK: - Manager (rider app)
@MainActor
final class RideManager: ObservableObject {

    // Flow state
    enum State: Equatable { case idle, selecting, awaitingDriver, inProgress, completed, cancelled }

    @Published var state: State = .idle
    @Published var availableDrivers: [Driver] = []
    @Published var selectedDriver: Driver?
    @Published var currentRide: Ride?
    @Published var lastReceipt: Receipt?
    @Published var history: [Receipt] = []
    @Published var isLoadingDrivers = false
    @Published var driverSearchTargetCount = 3
    @Published var driverSearchCompletedCount = 0
    @Published var rideRequestErrorMessage: String?
    @Published var rideCancellationErrorMessage: String?
    @Published private(set) var isCancellingRide = false
    @Published var hasRecoveredActiveRide = false

    // Payment
    // Starts empty — no mock/placeholder cards. Populated only from the
    // rider's real Stripe wallet via loadRealPaymentMethods(). A ride cannot
    // be requested until at least one real card is on file (see
    // `hasRealPaymentMethod` / the gate in `confirm(driver:)`).
    @Published var savedCards: [PaymentCard] = []
    @Published var selectedCardIndex: Int = 0
    @Published var stripeCustomerId: String?
    @Published var paymentStatus: String?           // "pending" | "processing" | "succeeded" | "failed" | "refunded"
    @Published var paymentFailureReason: String?
    @Published var isRetryingPayment = false

    /// True once at least one real (non-mock) saved card is on file.
    var hasRealPaymentMethod: Bool {
        savedCards.contains { $0.stripePaymentMethodId != nil }
    }

    /// Safe accessor for the selected card — never indexes into an empty
    /// array (can no longer happen in the real ride-request flow since
    /// `confirm(driver:)` gates on `hasRealPaymentMethod`, but receipts
    /// shouldn't crash even if state ever drifts).
    private var selectedCard: PaymentCard? {
        guard !savedCards.isEmpty else { return nil }
        return savedCards[min(selectedCardIndex, savedCards.count - 1)]
    }

    private let stripeBackendBase = RydrStripeBackendConfig.baseURL

    // Live locations for in-progress map/route
    @Published var liveDriverCoordinate: CLLocationCoordinate2D = .init(latitude: 33.7490, longitude: -84.3880)
    @Published var pickupCoordinate: CLLocationCoordinate2D?
    @Published var dropoffCoordinate: CLLocationCoordinate2D?
    @Published var pickupEtaSecondsRemaining: Int = 0
    @Published var destinationEtaSecondsRemaining: Int = 0
    @Published var pickupWaitSecondsRemaining: Int = 180
    @Published var paidPickupWaitSeconds: Int = 0
    @Published var pickupWaitCharge: Double = 0

    // Dependencies & tasks
    private let rideService: RideService
    private var driverSearchTask: Task<Void, Never>?
    private var decisionTask: Task<Void, Never>?
    private var rideLifecycleTask: Task<Void, Never>?
    private var pickupWaitCountdownTask: Task<Void, Never>?

    // Internals used across steps
    private var cachedEstimate: RideEstimate = .init(distanceMiles: 6.2, durationMinutes: 18)
    private var cachedPickup = ""
    private var cachedDropoff = ""
    private var cachedRideType = ""
    private var cachedPickupCoordinate: CLLocationCoordinate2D?
    private var cachedDropoffCoordinate: CLLocationCoordinate2D?
    private var currentServiceRideId: String?
    private var replacementForRideId: String?
    private var currentAppliedRydrBankCode: String?
    private var lastCompletedDriverId: String?
    private var cachedRidePreferences: RiderRidePreferences?
    private var cachedRiderVerified = false
    private var currentBaseFare: Double = 0
    private var currentWaitChargePerMinute: Double = 0
    private var hasPlayedTripStartedSoundForCurrentRide = false
    private let tripTransitionSoundPlayer = RiderTripTransitionSoundPlayer()
    private let cancellationSoundPlayer = RiderCancellationSoundPlayer()
    private let activeRideSnapshotKey = "rydr.activeRideSnapshot.v1"
    private let pendingRideSnapshotKey = "rydr.pendingRideSnapshot.v1"
    private let driverDecisionTimeoutSeconds: UInt64 = 18
    private var pendingRideWasRestored = false
    private var recoveringRideId: String?

    init(rideService: RideService = FirestoreRideService()) {
        self.rideService = rideService
        restoreActiveRideIfNeeded()
        if state == .inProgress {
            clearPendingRideSnapshot()
            observeActiveRideLifecycleIfNeeded()
        } else {
            restorePendingRideIfNeeded()
            if state == .awaitingDriver {
                reconcilePendingRideIfNeeded()
            }
        }
        Task { await loadRealPaymentMethods() }
    }

    deinit {
        decisionTask?.cancel()
        rideLifecycleTask?.cancel()
        pickupWaitCountdownTask?.cancel()
    }

    // Remaining minutes (toy ETA for the chip)
    var remainingMinutesRounded: Double {
        guard let ride = currentRide else { return 0 }
        switch ride.status {
        case .enRouteToPickup:  return max(1, ceil(Double(pickupEtaSecondsRemaining) / 60.0))
        case .waitingForRider:  return 0
        case .enRouteToDropoff: return max(1, ceil(Double(destinationEtaSecondsRemaining) / 60.0))
        default: return 0
        }
    }

    var activeRideChatContext: RideChatContext? {
        guard let ride = currentRide,
              let riderId = Auth.auth().currentUser?.uid else {
            return nil
        }

        return RideChatContext(
            rideId: currentServiceRideId ?? ride.id.uuidString,
            riderId: riderId,
            driverId: ride.driver.id,
            driverName: ride.driver.name
        )
    }

    // MARK: - Promo helpers

    /// Public helper for views to price with any saved promo applied.
    func applyPromo(to amount: Double) -> Double {
        hasAppliedRydrBankCode ? 0 : ((amount * 100).rounded() / 100.0)
    }

    var hasAppliedRydrBankCode: Bool {
        !normalizedSavedPromoCode().isEmpty
    }

    private func normalizedSavedPromoCode() -> String {
        if let v = UserDefaults.standard.string(forKey: "appliedRydrBankCode"), !v.isEmpty { return v }
        return ""
    }

    private func loadSavedRidePreferences() async -> RiderRidePreferences? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        do {
            let preferences = try await RiderRidePreferenceStore().load(uid: uid)
            return preferences.isDefault ? nil : preferences
        } catch {
            return nil
        }
    }

    private static func normalizedMatchmakingText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    // MARK: - Public API used by the UI

    /// Step 1: fetch nearest drivers (via service)
    func requestDrivers(
        pickup: String,
        dropoff: String,
        rideType: String,
        near center: CLLocationCoordinate2D,
        pickupCoordinate: CLLocationCoordinate2D? = nil,
        dropoffCoordinate: CLLocationCoordinate2D? = nil,
        estimate: RideEstimate? = nil,
        riderVerified: Bool = false
    ) {
        let isSameTripDetails = Self.normalizedMatchmakingText(pickup) == Self.normalizedMatchmakingText(cachedPickup)
            && Self.normalizedMatchmakingText(dropoff) == Self.normalizedMatchmakingText(cachedDropoff)
            && Self.normalizedMatchmakingText(rideType) == Self.normalizedMatchmakingText(cachedRideType)
        let effectivePickupCoordinate = pickupCoordinate ?? (isSameTripDetails ? cachedPickupCoordinate : nil)
        let effectiveDropoffCoordinate = dropoffCoordinate ?? (isSameTripDetails ? cachedDropoffCoordinate : nil)

        cachedPickup = pickup
        cachedDropoff = dropoff
        cachedRideType = rideType
        cachedPickupCoordinate = effectivePickupCoordinate
        cachedDropoffCoordinate = effectiveDropoffCoordinate
        cachedRiderVerified = riderVerified
        cachedRidePreferences = nil
        guard let estimate else {
            availableDrivers = []
            selectedDriver = nil
            driverSearchCompletedCount = 0
            isLoadingDrivers = false
            state = .idle
            rideRequestErrorMessage = RideRequestError.routeEstimateRequired.localizedDescription
            return
        }
        cachedEstimate = estimate

        driverSearchTask?.cancel()
        selectedDriver = nil
        availableDrivers = []
        driverSearchCompletedCount = 0
        driverSearchTargetCount = 3
        rideRequestErrorMessage = nil
        isLoadingDrivers = true
        state = .selecting

        driverSearchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let preferences = await self.loadSavedRidePreferences()
                self.cachedRidePreferences = preferences
                let drivers = try await rideService.fetchNearbyDrivers(
                    pickup: pickup,
                    dropoff: dropoff,
                    rideType: rideType,
                    near: center,
                    pickupCoordinate: effectivePickupCoordinate,
                    dropoffCoordinate: effectiveDropoffCoordinate,
                    estimatedDistanceMiles: estimate.distanceMiles,
                    riderPreferences: preferences
                )

                guard !Task.isCancelled else { return }

                let eligibleDrivers = drivers
                let previewDrivers = Array(eligibleDrivers.prefix(3))
                self.driverSearchTargetCount = 3
                if eligibleDrivers.isEmpty {
                    self.availableDrivers = []
                    self.driverSearchCompletedCount = 0
                    self.isLoadingDrivers = false
                    self.rideRequestErrorMessage = RideRequestError.noDriversAvailable.localizedDescription
                    return
                }

                try await Task.sleep(nanoseconds: 420_000_000)
                for (index, driver) in previewDrivers.enumerated() {
                    guard !Task.isCancelled else { return }
                    if index > 0 {
                        try await Task.sleep(nanoseconds: 340_000_000)
                    }
                    self.availableDrivers.append(driver)
                    self.driverSearchCompletedCount = min(self.availableDrivers.count, self.driverSearchTargetCount)
                }

                self.availableDrivers = eligibleDrivers
                self.isLoadingDrivers = false
            } catch {
                guard !Task.isCancelled else { return }
                self.availableDrivers = []
                self.driverSearchCompletedCount = 0
                self.isLoadingDrivers = false
                self.rideRequestErrorMessage = error.localizedDescription
            }
        }
    }

    /// Step 2: user taps a driver; send request, await accept/decline.
    func confirm(driver: Driver) {
        driverSearchTask?.cancel()
        isLoadingDrivers = false

        // Part 6 (Payment Hardening): never let a ride be requested without a
        // real, verified Stripe payment method on file — mock/placeholder
        // cards can no longer reach the request flow.
        guard hasRealPaymentMethod else {
            rideRequestErrorMessage = "Add a payment method before requesting a ride."
            return
        }
        guard driver.quotedRiderTotalCents != nil,
              driver.quotedDriverPayoutCents != nil else {
            rideRequestErrorMessage = "The backend quote expired. Refresh nearby drivers and try again."
            return
        }

        selectedDriver = driver
        rideRequestErrorMessage = nil
        state = .awaitingDriver

        decisionTask?.cancel()
        decisionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let code = self.normalizedSavedPromoCode()
                self.currentAppliedRydrBankCode = code.isEmpty ? nil : code
                let rideId = try await rideService.requestRide(
                    driverId: driver.id,
                    pickup: cachedPickup,
                    dropoff: cachedDropoff,
                    rideType: cachedRideType,
                    pickupCoordinate: cachedPickupCoordinate,
                    dropoffCoordinate: cachedDropoffCoordinate,
                    estimate: cachedEstimate,
                    rydrBankCode: self.currentAppliedRydrBankCode,
                    replacementForRideId: self.replacementForRideId,
                    riderPreferences: cachedRidePreferences,
                    riderVerified: cachedRiderVerified,
                    candidateDriverIds: availableDrivers.map(\.id)
                )
                self.currentServiceRideId = rideId
                self.persistPendingRideSnapshot()
                self.startDecisionMonitoring(rideId: rideId, reconcileFirst: false)
            } catch {
                guard !Task.isCancelled else { return }
                self.handleDecline(message: error.localizedDescription)
            }
        }
    }

    /// Driver accepted – seed the ride from the request and observe backend lifecycle updates.
    func handleAccept() {
        guard state == .awaitingDriver, let driver = selectedDriver else { return }
        let shouldPresentRecoveredRide = pendingRideWasRestored
        pendingRideWasRestored = false
        replacementForRideId = nil

        guard let quotedRiderTotalCents = driver.quotedRiderTotalCents else {
            handleDecline(message: "The backend quote expired. Refresh nearby drivers and try again.")
            return
        }
        let fareBeforePromo = Double(quotedRiderTotalCents) / 100
        let fareAfterPromo = currentAppliedRydrBankCode == nil ? applyPromo(to: fareBeforePromo) : 0
        currentBaseFare = fareAfterPromo
        currentWaitChargePerMinute = displayWaitRate(for: driver)
        hasPlayedTripStartedSoundForCurrentRide = false

        let start  = driver.coordinate
        let pickup = cachedPickupCoordinate ?? CLLocationCoordinate2D(latitude: start.latitude + 0.02, longitude: start.longitude + 0.02)
        let drop = cachedDropoffCoordinate ?? CLLocationCoordinate2D(latitude: pickup.latitude + 0.03, longitude: pickup.longitude + 0.03)
        pickupCoordinate  = pickup
        dropoffCoordinate = drop

        currentRide = Ride(
            pickup: cachedPickup,
            dropoff: cachedDropoff,
            rideType: cachedRideType,
            estimate: cachedEstimate,
            driver: driver,
            status: .enRouteToPickup,
            fare: fareAfterPromo
        )
        liveDriverCoordinate = start
        pickupEtaSecondsRemaining = estimatedPickupEtaSeconds(from: start, to: pickup)
        destinationEtaSecondsRemaining = max(60, Int((cachedEstimate.durationMinutes * 0.6 * 60).rounded()))
        pickupWaitSecondsRemaining = 180
        paidPickupWaitSeconds = 0
        pickupWaitCharge = 0
        state = .inProgress
        persistActiveRideSnapshot()
        clearPendingRideSnapshot()
        if shouldPresentRecoveredRide {
            hasRecoveredActiveRide = true
        }
        observeActiveRideLifecycleIfNeeded()
    }

    /// If driver declines, take user back to selection (remove that driver).
    func handleDecline(message: String? = nil) {
        guard state == .awaitingDriver else { return }
        clearPendingRideSnapshot()
        pendingRideWasRestored = false
        currentServiceRideId = nil
        selectedDriver = nil
        // Every card belongs to the match session that created this request.
        // That session may now be consumed, expired, or based on a driver who
        // has gone offline. Keeping the array here displayed the previous
        // driver's card and stale quote as though it were still selectable.
        availableDrivers = []
        driverSearchCompletedCount = 0
        isLoadingDrivers = false
        rideRequestErrorMessage = message ?? RideRequestError.noDriversAvailable.localizedDescription
        state = .selecting
    }

    /// Rider cancels before pickup → return to driver cards. Mid-ride → end with a prorated receipt.
    func riderCancelAndAutoReassign() {
        riderCancelAndFindAnother()
    }

    func riderCancelAndFindAnother() {
        guard let ride = currentRide else { return }

        switch ride.status {
        case .enRouteToPickup, .waitingForRider:
            cancelBeforePickupAndReturnToSelection(mode: .findAnotherDriver)
        case .enRouteToDropoff:
            cancelMidRideAndComplete()
        default:
            cancelAll()
        }
    }

    func riderCancelRide() {
        guard currentRide != nil else { return }
        cancelRideWithoutReassignment(mode: .cancelRide)
    }

    /// Rebuilds the rider's active UI from the authoritative ride document.
    /// Scheduled dispatch can create a live ride while the app is backgrounded,
    /// so it cannot rely on the local snapshot used by ordinary matching.
    func recoverActiveRide(rideId: String) async {
        guard !rideId.isEmpty else { return }
        if currentServiceRideId == rideId, currentRide != nil { return }
        guard recoveringRideId != rideId else { return }

        recoveringRideId = rideId
        defer { recoveringRideId = nil }
        do {
            let recovered = try await rideService.recoverRide(rideId: rideId)
            currentServiceRideId = recovered.rideId
            cachedPickup = recovered.pickup
            cachedDropoff = recovered.dropoff
            cachedRideType = recovered.rideType
            cachedEstimate = recovered.estimate
            cachedPickupCoordinate = recovered.pickupCoordinate
            cachedDropoffCoordinate = recovered.dropoffCoordinate
            pickupCoordinate = recovered.pickupCoordinate
            dropoffCoordinate = recovered.dropoffCoordinate
            liveDriverCoordinate = recovered.driverCoordinate
            selectedDriver = recovered.driver
            currentBaseFare = recovered.fare
            currentWaitChargePerMinute = recovered.waitChargePerMinute
            currentRide = Ride(
                pickup: recovered.pickup,
                dropoff: recovered.dropoff,
                rideType: recovered.rideType,
                estimate: recovered.estimate,
                driver: recovered.driver,
                startedAt: recovered.startedAt,
                status: recovered.status,
                fare: recovered.fare
            )
            pickupEtaSecondsRemaining = recovered.status == .enRouteToPickup
                ? estimatedPickupEtaSeconds(from: recovered.driverCoordinate, to: recovered.pickupCoordinate)
                : 0
            destinationEtaSecondsRemaining = max(60, Int((recovered.estimate.durationMinutes * 0.6 * 60).rounded()))
            state = .inProgress
            hasRecoveredActiveRide = true
            clearPendingRideSnapshot()
            persistActiveRideSnapshot()
            observeActiveRideLifecycleIfNeeded()
        } catch {
            rideRequestErrorMessage = "Unable to restore your active ride: \(error.localizedDescription)"
        }
    }

    /// Finalize the rider UI exclusively from the backend financial outcome.
    private func completeRide(
        outcome: BackendRideFinancialOutcome,
        backendDistanceMiles: Double?,
        backendDurationMinutes: Double?
    ) {
        rideLifecycleTask?.cancel()
        rideLifecycleTask = nil

        guard let ride = currentRide else { return }
        tripTransitionSoundPlayer.play()
        guard let backendRideId = currentServiceRideId else {
            rideRequestErrorMessage = "The completed ride is missing its backend identifier."
            return
        }
        let trustedDistance = backendDistanceMiles
            ?? outcome.calculationInputs?.distanceMiles
            ?? ride.estimate.distanceMiles

        finalizeRide(
            ride,
            backendRideId: backendRideId,
            outcome: outcome,
            distanceMiles: trustedDistance,
            durationMinutes: backendDurationMinutes ?? outcome.calculationInputs?.billableMinutes
        )

        Task {
            await MainActor.run {
                UserDefaults.standard.removeObject(forKey: "appliedRydrBankCode")
                UserDefaults.standard.removeObject(forKey: "appliedRydrBankBookingId")
            }
            _ = try? await RydrBankAPI.rideComplete(rideId: backendRideId)
        }
    }

    private func finalizeRide(
        _ ride: Ride,
        backendRideId: String,
        outcome: BackendRideFinancialOutcome,
        distanceMiles: Double?,
        durationMinutes: Double?
    ) {
        let chatContext = activeRideChatContext
        let card = selectedCard
        let receipt = Receipt(
            rideId: ride.id,
            date: Date(),
            driverName: ride.driver.name,
            pickup: ride.pickup,
            dropoff: ride.dropoff,
            distanceMiles: distanceMiles ?? ride.estimate.distanceMiles,
            durationMinutes: durationMinutes ?? ride.estimate.durationMinutes,
            fare: Double(outcome.finalRiderChargeCents) / 100.0,
            cardMasked: card.map { "\($0.brand) ••\($0.last4)" } ?? "No card on file",
            chargeBreakdown: outcome.receiptBreakdown,
            backendRideId: backendRideId
        )

        lastReceipt = receipt
        lastCompletedDriverId = ride.driver.id
        history.insert(receipt, at: 0)
        currentRide = nil
        currentServiceRideId = nil
        currentAppliedRydrBankCode = nil
        currentBaseFare = 0
        currentWaitChargePerMinute = 0
        hasPlayedTripStartedSoundForCurrentRide = false
        clearActiveRideSnapshot()
        state = .completed
        closeRideChatIfNeeded(chatContext)
    }

    func applyTipToLastReceipt(cents: Int) async throws {
        guard cents >= 0 else { throw RideTipError.invalidAmount }
        guard let receipt = lastReceipt else { throw RideTipError.missingReceipt }
        guard cents > 0 else { return }
        guard let backendRideId = receipt.backendRideId else { throw RideTipError.missingRideId }
        guard paymentStatus == "succeeded" else { throw RideTipError.ridePaymentNotSettled }

        try await chargeTip(rideId: backendRideId, cents: cents)

        let updatedReceipt = receipt.addingTip(cents: cents)
        lastReceipt = updatedReceipt
        if let index = history.firstIndex(where: { $0.id == receipt.id }) {
            history[index] = updatedReceipt
        }
    }

    func submitDriverFeedback(_ draft: DriverFeedbackDraft) async throws {
        guard let user = Auth.auth().currentUser else { throw RideFeedbackError.notSignedIn }
        guard let receipt = lastReceipt else { throw RideFeedbackError.missingReceipt }
        guard let backendRideId = receipt.backendRideId else { throw RideFeedbackError.missingRideId }

        let rating = draft.rating
        let trimmedFeedback = draft.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        let compliments = draft.compliments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard rating != nil || !trimmedFeedback.isEmpty || !compliments.isEmpty || draft.favoriteDriver else {
            return
        }
        if let rating, !(1...5).contains(rating) {
            throw RideFeedbackError.invalidRating
        }

        var payload: [String: Any] = [
            "compliments": compliments,
            "feedback": trimmedFeedback,
            "favoriteDriver": draft.favoriteDriver
        ]
        if let rating { payload["rating"] = rating }
        guard let rawBase = Bundle.main.object(forInfoDictionaryKey: "RYDR_BACKEND_BASE_URL") as? String,
              let base = URL(string: rawBase),
              let url = URL(string: "/rides/\(backendRideId)/rating", relativeTo: base) else { throw URLError(.badURL) }
        let token = try await user.getIDToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw NSError(domain: "RydrRating", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: body?["error"] as? String ?? "Rating could not be saved."])
        }
    }

    func cancelAll() {
        decisionTask?.cancel()
        rideLifecycleTask?.cancel()
        pickupWaitCountdownTask?.cancel()
        let chatContext = activeRideChatContext
        currentRide = nil
        selectedDriver = nil
        currentServiceRideId = nil
        currentBaseFare = 0
        currentWaitChargePerMinute = 0
        hasPlayedTripStartedSoundForCurrentRide = false
        releaseAppliedRydrBankCodeIfNeeded()
        clearPendingRideSnapshot()
        clearActiveRideSnapshot()
        state = .cancelled
        closeRideChatIfNeeded(chatContext)
    }

    private func estimatedPickupEtaSeconds(
        from driverCoordinate: CLLocationCoordinate2D,
        to pickupCoordinate: CLLocationCoordinate2D
    ) -> Int {
        let driverLocation = CLLocation(latitude: driverCoordinate.latitude, longitude: driverCoordinate.longitude)
        let pickupLocation = CLLocation(latitude: pickupCoordinate.latitude, longitude: pickupCoordinate.longitude)
        let distanceMeters = max(0, driverLocation.distance(from: pickupLocation))
        guard distanceMeters > 20 else { return 0 }

        // Conservative city pickup speed. This replaces the old trip-duration
        // percentage estimate, which made same-device tests look 10+ minutes away.
        let metersPerSecond = 8.0
        return Int(ceil(distanceMeters / metersPerSecond))
    }

    func markRiderPickedUp() {
        guard currentRide?.status == .waitingForRider else { return }
        destinationEtaSecondsRemaining = max(60, Int(((currentRide?.estimate.durationMinutes ?? cachedEstimate.durationMinutes) * 0.6 * 60).rounded()))
        persistActiveRideSnapshot()
    }

    private func updatePaidPickupWait(seconds: Int) {
        // Display-only estimate. The backend determines the billable wait time
        // and authoritative charge when it finalizes the ride.
        paidPickupWaitSeconds = max(0, seconds)
        let minutes = Double(paidPickupWaitSeconds) / 60.0
        pickupWaitCharge = ((minutes * currentWaitChargePerMinute) * 100).rounded() / 100
        currentRide?.fare = ((currentBaseFare + pickupWaitCharge) * 100).rounded() / 100
    }

    private func cancelBeforePickupAndReturnToSelection(
        mode: RideCancellationMode = .findAnotherDriver,
        notifyBackend: Bool = true
    ) {
        if notifyBackend, let rideId = currentServiceRideId {
            guard !isCancellingRide else { return }
            rideCancellationErrorMessage = nil
            isCancellingRide = true
            Task { [weak self] in
                guard let self else { return }
                do {
                    _ = try await rideService.cancelRide(rideId: rideId, mode: mode)
                    await MainActor.run {
                        self.cancellationSoundPlayer.play()
                        self.isCancellingRide = false
                        self.cancelBeforePickupAndReturnToSelection(mode: mode, notifyBackend: false)
                    }
                } catch {
                    await MainActor.run {
                        self.isCancellingRide = false
                        let message = "Cancellation failed: \(error.localizedDescription)"
                        self.rideRequestErrorMessage = message
                        self.rideCancellationErrorMessage = message
                        self.observeActiveRideLifecycleIfNeeded()
                    }
                }
            }
            return
        }

        rideLifecycleTask?.cancel()
        decisionTask?.cancel()
        pickupWaitCountdownTask?.cancel()
        let chatContext = activeRideChatContext

        let cancelledServiceRideId = currentServiceRideId
        if mode == .findAnotherDriver {
            replacementForRideId = cancelledServiceRideId
        }
        currentRide = nil
        selectedDriver = nil
        currentServiceRideId = nil
        pickupEtaSecondsRemaining = 0
        pickupWaitSecondsRemaining = 180
        paidPickupWaitSeconds = 0
        pickupWaitCharge = 0
        currentBaseFare = 0
        currentWaitChargePerMinute = 0
        hasPlayedTripStartedSoundForCurrentRide = false
        clearActiveRideSnapshot()

        if availableDrivers.isEmpty {
            requestDrivers(
                pickup: cachedPickup,
                dropoff: cachedDropoff,
                rideType: cachedRideType,
                near: cachedPickupCoordinate ?? liveDriverCoordinate,
                pickupCoordinate: cachedPickupCoordinate,
                dropoffCoordinate: cachedDropoffCoordinate,
                estimate: cachedEstimate,
                riderVerified: cachedRiderVerified
            )
        } else {
            rideRequestErrorMessage = nil
            state = .selecting
        }

        closeRideChatIfNeeded(chatContext)
    }

    private func cancelRideWithoutReassignment(mode: RideCancellationMode) {
        guard let rideId = currentServiceRideId else {
            let message = "The backend ride record is unavailable. Please try again."
            rideRequestErrorMessage = message
            rideCancellationErrorMessage = message
            return
        }
        guard !isCancellingRide else { return }
        rideCancellationErrorMessage = nil
        isCancellingRide = true

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await rideService.cancelRide(rideId: rideId, mode: mode)
                await MainActor.run {
                    self.cancellationSoundPlayer.play()
                    self.isCancellingRide = false
                    self.finishRiderCancellation()
                }
            } catch {
                await MainActor.run {
                    self.isCancellingRide = false
                    let message = "Cancellation failed: \(error.localizedDescription)"
                    self.rideRequestErrorMessage = message
                    self.rideCancellationErrorMessage = message
                    self.observeActiveRideLifecycleIfNeeded()
                }
            }
        }
    }

    private func finishRiderCancellation() {
        rideLifecycleTask?.cancel()
        decisionTask?.cancel()
        pickupWaitCountdownTask?.cancel()
        let chatContext = activeRideChatContext
        replacementForRideId = nil

        currentRide = nil
        selectedDriver = nil
        currentServiceRideId = nil
        pickupEtaSecondsRemaining = 0
        destinationEtaSecondsRemaining = 0
        pickupWaitSecondsRemaining = 180
        paidPickupWaitSeconds = 0
        pickupWaitCharge = 0
        currentBaseFare = 0
        currentWaitChargePerMinute = 0
        hasPlayedTripStartedSoundForCurrentRide = false
        releaseAppliedRydrBankCodeIfNeeded()
        clearActiveRideSnapshot()
        state = .cancelled

        closeRideChatIfNeeded(chatContext)
    }

    private func cancelMidRideAndComplete() {
        guard let ride = currentRide else { return }
        guard let backendRideId = currentServiceRideId else {
            let message = "The backend ride record is unavailable. Please contact support before cancelling."
            rideRequestErrorMessage = message
            rideCancellationErrorMessage = message
            return
        }

        rideLifecycleTask?.cancel()
        decisionTask?.cancel()
        rideCancellationErrorMessage = nil
        isCancellingRide = true

        Task {
            do {
                let outcome = try await rideService.cancelMidRide(rideId: backendRideId)
                await MainActor.run {
                    self.cancellationSoundPlayer.play()
                    self.isCancellingRide = false
                    self.finalizeRide(
                        ride,
                        backendRideId: backendRideId,
                        outcome: outcome,
                        distanceMiles: outcome.calculationInputs?.billableDistance,
                        durationMinutes: outcome.calculationInputs?.billableMinutes
                    )
                }
            } catch {
                await MainActor.run {
                    self.isCancellingRide = false
                    let message = "Cancellation failed: \(error.localizedDescription)"
                    self.rideRequestErrorMessage = message
                    self.rideCancellationErrorMessage = message
                    self.observeActiveRideLifecycleIfNeeded()
                }
            }
        }
    }

    private func observeActiveRideLifecycleIfNeeded() {
        guard let rideId = currentServiceRideId else { return }
        rideLifecycleTask?.cancel()
        rideLifecycleTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await snapshot in rideService.rideLifecycleStream(rideId: rideId) {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self.applyLifecycleSnapshot(snapshot)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.rideRequestErrorMessage = "Ride updates paused: \(error.localizedDescription)"
                }
            }
        }
    }

    private func applyLifecycleSnapshot(_ snapshot: RideLifecycleSnapshot) {
        guard currentRide != nil else { return }

        if let outcome = snapshot.financialOutcome {
            currentRide?.fare = Double(outcome.finalRiderChargeCents) / 100.0
        }

        if let driverCoordinate = snapshot.driverCoordinate {
            liveDriverCoordinate = driverCoordinate
            if currentRide?.status == .enRouteToPickup, let pickupCoordinate {
                pickupEtaSecondsRemaining = estimatedPickupEtaSeconds(from: driverCoordinate, to: pickupCoordinate)
            }
        }
        if let pickup = snapshot.pickupCoordinate {
            pickupCoordinate = pickup
            cachedPickupCoordinate = pickup
        }
        if let dropoff = snapshot.dropoffCoordinate {
            dropoffCoordinate = dropoff
            cachedDropoffCoordinate = dropoff
        }
        if let status = snapshot.status {
            let previousStatus = currentRide?.status
            currentRide?.status = status
            switch status {
            case .enRouteToPickup:
                pickupWaitCountdownTask?.cancel()
                if let pickupCoordinate {
                    pickupEtaSecondsRemaining = estimatedPickupEtaSeconds(from: liveDriverCoordinate, to: pickupCoordinate)
                }
            case .waitingForRider:
                pickupEtaSecondsRemaining = 0
                startPickupWaitCountdown(
                    startedAt: snapshot.pickupWaitStartedAt,
                    complimentarySeconds: snapshot.pickupComplimentaryWaitSeconds ?? 180
                )
            case .enRouteToDropoff:
                pickupWaitCountdownTask?.cancel()
                pickupEtaSecondsRemaining = 0
                pickupWaitSecondsRemaining = 0
                if previousStatus != .enRouteToDropoff,
                   !hasPlayedTripStartedSoundForCurrentRide {
                    hasPlayedTripStartedSoundForCurrentRide = true
                    tripTransitionSoundPlayer.play()
                }
            case .completed:
                guard let outcome = snapshot.financialOutcome else {
                    rideRequestErrorMessage = "Final fare is still being calculated by the backend."
                    return
                }
                completeRide(
                    outcome: outcome,
                    backendDistanceMiles: snapshot.backendDistanceMiles,
                    backendDurationMinutes: snapshot.backendDurationMinutes
                )
                return
            case .cancelled:
                if snapshot.rawStatus == "driverCancelled" {
                    handleDriverCancelledAndReturnToSelection()
                } else {
                    cancelAll()
                }
                return
            }
        }
        persistActiveRideSnapshot()
    }

    private func handleDriverCancelledAndReturnToSelection() {
        cancellationSoundPlayer.play()
        rideRequestErrorMessage = "Your driver cancelled. Pick another nearby driver."
        cancelBeforePickupAndReturnToSelection(notifyBackend: false)
    }

    private func startPickupWaitCountdown(startedAt: Date?, complimentarySeconds: Int) {
        pickupWaitCountdownTask?.cancel()
        let graceSeconds = max(0, complimentarySeconds)
        let start = startedAt ?? Date()

        pickupWaitCountdownTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let elapsed = max(0, Int(Date().timeIntervalSince(start)))
                let remaining = max(0, graceSeconds - elapsed)
                await MainActor.run {
                    self.pickupWaitSecondsRemaining = remaining
                    if remaining == 0 {
                        self.updatePaidPickupWait(seconds: elapsed - graceSeconds)
                    } else {
                        self.paidPickupWaitSeconds = 0
                        self.pickupWaitCharge = 0
                    }
                    self.persistActiveRideSnapshot()
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func closeRideChatIfNeeded(_ context: RideChatContext?) {
        guard let context else { return }

        Task {
            try? await RideChatService().closeChat(
                rideId: context.rideId,
                riderId: context.riderId,
                driverId: context.driverId
            )
        }
    }

    private func releaseAppliedRydrBankCodeIfNeeded() {
        let code = normalizedSavedPromoCode()
        guard !code.isEmpty else { return }
        Task {
            try? await RydrBankAPI.release(code: code)
            await MainActor.run {
                UserDefaults.standard.removeObject(forKey: "appliedRydrBankCode")
                UserDefaults.standard.removeObject(forKey: "appliedRydrBankBookingId")
            }
        }
    }

    private func displayWaitRate(for driver: Driver) -> Double {
        max(0, driver.perMinute)
    }

    private func awaitDriverDecisionWithTimeout(rideId: String) async throws -> DriverDecision {
        while !Task.isCancelled {
            do {
                return try await withThrowingTaskGroup(of: DriverDecision.self) { group in
                    let service = rideService
                    let timeoutSeconds = driverDecisionTimeoutSeconds
                    group.addTask {
                        try await service.awaitDriverDecision(rideId: rideId)
                    }
                    group.addTask {
                        try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                        throw RideRequestError.driverTimedOut
                    }

                    guard let decision = try await group.next() else {
                        throw RideRequestError.driverTimedOut
                    }
                    group.cancelAll()
                    return decision
                }
            } catch RideRequestError.driverTimedOut {
                let dispatch = try await rideService.refreshRideDispatch(rideId: rideId)
                if dispatch.status.lowercased() == "nodriversavailable" {
                    return .declined
                }
            }
        }
        throw CancellationError()
    }

    /// Re-checks the backend whenever the app returns to the foreground. iOS
    /// may suspend Firestore callbacks while the rider switches to another
    /// app, so the UI must not depend on receiving one particular callback.
    func reconcilePendingRideIfNeeded() {
        guard state == .awaitingDriver, let rideId = currentServiceRideId else { return }
        startDecisionMonitoring(rideId: rideId, reconcileFirst: true)
    }

    private func startDecisionMonitoring(rideId: String, reconcileFirst: Bool) {
        decisionTask?.cancel()
        decisionTask = Task { [weak self] in
            guard let self else { return }
            do {
                if reconcileFirst {
                    do {
                        let dispatch = try await self.rideService.refreshRideDispatch(rideId: rideId)
                        guard !Task.isCancelled else { return }
                        switch dispatch.status.lowercased() {
                        case "accepted":
                            self.applyAcceptedDriver(dispatch.driverId)
                            self.handleAccept()
                            return
                        case "declined", "drivercancelled", "cancelled", "ridercancelled", "nodriversavailable":
                            self.handleDecline(message: "No nearby drivers are available right now. Try again in a moment.")
                            return
                        default:
                            break
                        }
                    } catch {
                        // A foreground HTTP refresh can briefly fail while the
                        // network reconnects. Keep the Firestore listener alive
                        // so cached or subsequently synchronized state can still
                        // move the rider into the accepted ride.
                        guard !Task.isCancelled else { return }
                    }
                }

                let decision = try await self.awaitDriverDecisionWithTimeout(rideId: rideId)
                guard !Task.isCancelled else { return }
                switch decision {
                case .accepted(let driverId):
                    self.applyAcceptedDriver(driverId)
                    self.handleAccept()
                case .declined:
                    self.handleDecline(message: "That match is no longer available. Refresh nearby drivers to get current availability and pricing.")
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.rideRequestErrorMessage = error.localizedDescription
            }
        }
    }

    private func applyAcceptedDriver(_ driverId: String?) {
        guard let driverId else { return }
        if let acceptedDriver = availableDrivers.first(where: { $0.id == driverId }) {
            selectedDriver = acceptedDriver
        }
    }

    private struct CoordinateSnapshot: Codable {
        let latitude: Double
        let longitude: Double

        init(_ coordinate: CLLocationCoordinate2D) {
            latitude = coordinate.latitude
            longitude = coordinate.longitude
        }

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    private struct DriverSnapshot: Codable {
        let id: String
        let name: String
        let carMakeModel: String
        let rating: Double
        let compliments: [String]
        let perMinute: Double
        let perMile: Double
        let minimumFare: Double?
        let usesSuggestedPricing: Bool?
        let coordinate: CoordinateSnapshot
        let score: Int
        let ratingCount: Int?
        let completedRideCount: Int?
        let acceptanceRate: Int?
        let quotedRiderTotalCents: Int?
        let quotedDriverPayoutCents: Int?

        init(_ driver: Driver) {
            id = driver.id
            name = driver.name
            carMakeModel = driver.carMakeModel
            rating = driver.rating
            compliments = driver.compliments
            perMinute = driver.perMinute
            perMile = driver.perMile
            minimumFare = driver.minimumFare
            usesSuggestedPricing = driver.usesSuggestedPricing
            coordinate = CoordinateSnapshot(driver.coordinate)
            score = driver.score
            ratingCount = driver.ratingCount
            completedRideCount = driver.completedRideCount
            acceptanceRate = driver.acceptanceRate
            quotedRiderTotalCents = driver.quotedRiderTotalCents
            quotedDriverPayoutCents = driver.quotedDriverPayoutCents
        }

        var driver: Driver {
            Driver(
                id: id,
                name: name,
                profileImage: nil,
                carImage: nil,
                carMakeModel: carMakeModel,
                rating: rating,
                compliments: compliments,
                perMinute: perMinute,
                perMile: perMile,
                minimumFare: minimumFare ?? 0,
                usesSuggestedPricing: usesSuggestedPricing ?? false,
                coordinate: coordinate.coordinate,
                score: score,
                ratingCount: ratingCount ?? 0,
                completedRideCount: completedRideCount,
                acceptanceRate: acceptanceRate,
                quotedRiderTotalCents: quotedRiderTotalCents,
                quotedDriverPayoutCents: quotedDriverPayoutCents
            )
        }
    }

    private struct ActiveRideSnapshot: Codable {
        let savedAt: Date
        let serviceRideId: String?
        let pickup: String
        let dropoff: String
        let rideType: String
        let estimate: RideEstimate
        let driver: DriverSnapshot
        let rideStartedAt: Date
        let status: Ride.Status
        let fare: Double
        let liveDriverCoordinate: CoordinateSnapshot
        let pickupCoordinate: CoordinateSnapshot?
        let dropoffCoordinate: CoordinateSnapshot?
        let pickupEtaSecondsRemaining: Int
        let destinationEtaSecondsRemaining: Int
        let pickupWaitSecondsRemaining: Int
        let paidPickupWaitSeconds: Int
        let pickupWaitCharge: Double
        let appliedRydrBankCode: String?
        let baseFare: Double
        let waitChargePerMinute: Double
    }

    private struct PendingRideSnapshot: Codable {
        let savedAt: Date
        let serviceRideId: String
        let pickup: String
        let dropoff: String
        let rideType: String
        let estimate: RideEstimate
        let selectedDriverId: String
        let drivers: [DriverSnapshot]
        let pickupCoordinate: CoordinateSnapshot?
        let dropoffCoordinate: CoordinateSnapshot?
        let appliedRydrBankCode: String?
    }

    private func persistPendingRideSnapshot() {
        guard state == .awaitingDriver,
              let serviceRideId = currentServiceRideId,
              let driver = selectedDriver else { return }
        let snapshot = PendingRideSnapshot(
            savedAt: Date(),
            serviceRideId: serviceRideId,
            pickup: cachedPickup,
            dropoff: cachedDropoff,
            rideType: cachedRideType,
            estimate: cachedEstimate,
            selectedDriverId: driver.id,
            drivers: availableDrivers.isEmpty ? [DriverSnapshot(driver)] : availableDrivers.map(DriverSnapshot.init),
            pickupCoordinate: cachedPickupCoordinate.map(CoordinateSnapshot.init),
            dropoffCoordinate: cachedDropoffCoordinate.map(CoordinateSnapshot.init),
            appliedRydrBankCode: currentAppliedRydrBankCode
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: pendingRideSnapshotKey)
    }

    private func clearPendingRideSnapshot() {
        UserDefaults.standard.removeObject(forKey: pendingRideSnapshotKey)
    }

    private func restorePendingRideIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: pendingRideSnapshotKey),
              let snapshot = try? JSONDecoder().decode(PendingRideSnapshot.self, from: data) else {
            return
        }
        guard Date().timeIntervalSince(snapshot.savedAt) < 4 * 60 * 60 else {
            clearPendingRideSnapshot()
            return
        }

        let drivers = snapshot.drivers.map(\.driver)
        guard let driver = drivers.first(where: { $0.id == snapshot.selectedDriverId }) ?? drivers.first else {
            clearPendingRideSnapshot()
            return
        }
        currentServiceRideId = snapshot.serviceRideId
        cachedPickup = snapshot.pickup
        cachedDropoff = snapshot.dropoff
        cachedRideType = snapshot.rideType
        cachedEstimate = snapshot.estimate
        cachedPickupCoordinate = snapshot.pickupCoordinate?.coordinate
        cachedDropoffCoordinate = snapshot.dropoffCoordinate?.coordinate
        currentAppliedRydrBankCode = snapshot.appliedRydrBankCode
        selectedDriver = driver
        availableDrivers = drivers
        state = .awaitingDriver
        pendingRideWasRestored = true
    }

    private func persistActiveRideSnapshot() {
        guard state == .inProgress, let ride = currentRide else { return }
        let snapshot = ActiveRideSnapshot(
            savedAt: Date(),
            serviceRideId: currentServiceRideId,
            pickup: ride.pickup,
            dropoff: ride.dropoff,
            rideType: ride.rideType,
            estimate: ride.estimate,
            driver: DriverSnapshot(ride.driver),
            rideStartedAt: ride.startedAt,
            status: ride.status,
            fare: ride.fare,
            liveDriverCoordinate: CoordinateSnapshot(liveDriverCoordinate),
            pickupCoordinate: pickupCoordinate.map(CoordinateSnapshot.init),
            dropoffCoordinate: dropoffCoordinate.map(CoordinateSnapshot.init),
            pickupEtaSecondsRemaining: pickupEtaSecondsRemaining,
            destinationEtaSecondsRemaining: destinationEtaSecondsRemaining,
            pickupWaitSecondsRemaining: pickupWaitSecondsRemaining,
            paidPickupWaitSeconds: paidPickupWaitSeconds,
            pickupWaitCharge: pickupWaitCharge,
            appliedRydrBankCode: currentAppliedRydrBankCode,
            baseFare: currentBaseFare,
            waitChargePerMinute: currentWaitChargePerMinute
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: activeRideSnapshotKey)
    }

    private func clearActiveRideSnapshot() {
        UserDefaults.standard.removeObject(forKey: activeRideSnapshotKey)
        hasRecoveredActiveRide = false
    }

    private func restoreActiveRideIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: activeRideSnapshotKey),
              let snapshot = try? JSONDecoder().decode(ActiveRideSnapshot.self, from: data) else {
            return
        }

        guard Date().timeIntervalSince(snapshot.savedAt) < 4 * 60 * 60 else {
            clearActiveRideSnapshot()
            return
        }

        var driver = snapshot.driver.driver
        driver.coordinate = snapshot.liveDriverCoordinate.coordinate
        currentRide = Ride(
            pickup: snapshot.pickup,
            dropoff: snapshot.dropoff,
            rideType: snapshot.rideType,
            estimate: snapshot.estimate,
            driver: driver,
            startedAt: snapshot.rideStartedAt,
            status: snapshot.status,
            fare: snapshot.fare
        )
        cachedPickup = snapshot.pickup
        cachedDropoff = snapshot.dropoff
        cachedRideType = snapshot.rideType
        cachedEstimate = snapshot.estimate
        currentServiceRideId = snapshot.serviceRideId
        currentAppliedRydrBankCode = snapshot.appliedRydrBankCode
        currentBaseFare = snapshot.baseFare
        currentWaitChargePerMinute = snapshot.waitChargePerMinute
        liveDriverCoordinate = snapshot.liveDriverCoordinate.coordinate
        pickupCoordinate = snapshot.pickupCoordinate?.coordinate
        dropoffCoordinate = snapshot.dropoffCoordinate?.coordinate
        cachedPickupCoordinate = pickupCoordinate
        cachedDropoffCoordinate = dropoffCoordinate
        pickupEtaSecondsRemaining = snapshot.pickupEtaSecondsRemaining
        destinationEtaSecondsRemaining = snapshot.destinationEtaSecondsRemaining
        pickupWaitSecondsRemaining = snapshot.pickupWaitSecondsRemaining
        paidPickupWaitSeconds = snapshot.paidPickupWaitSeconds
        pickupWaitCharge = snapshot.pickupWaitCharge
        hasPlayedTripStartedSoundForCurrentRide = snapshot.status == .enRouteToDropoff || snapshot.status == .completed
        state = .inProgress
        hasRecoveredActiveRide = true
    }

    // MARK: - Stripe wallet and backend-owned ride charges

    private func currentIDToken() async -> String? {
        guard let user = Auth.auth().currentUser else { return nil }
        return try? await user.getIDToken()
    }

    private func stripeRequest(_ path: String, body: [String: Any]) async -> Data? {
        var request = URLRequest(url: stripeBackendBase.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        if let token = await currentIDToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        } catch {
            print("❌ Stripe request to \(path) failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Looks up (or creates, idempotently) the signed-in rider's Stripe customerId.
    /// The backend derives/owns this from the verified Firebase uid — only
    /// `email`/`name` (display data, not an identity the server trusts) are sent.
    private func ensureStripeCustomerId() async -> String? {
        if let stripeCustomerId { return stripeCustomerId }
        guard let user = Auth.auth().currentUser else { return nil }

        let name = user.displayName ?? "Rydr Rider"
        guard let data = await stripeRequest("create-customer", body: ["name": name]),
              let response = try? JSONDecoder().decode(StripeCustomerResponse_Ride.self, from: data) else {
            return nil
        }
        stripeCustomerId = response.customerId
        return response.customerId
    }

    /// Loads the rider's real Stripe wallet. `savedCards` starts empty (no mock
    /// cards) and stays empty if this fails or the rider has no real cards yet
    /// — ride requests are blocked until at least one succeeds (see
    /// `hasRealPaymentMethod`).
    func loadRealPaymentMethods() async {
        guard await ensureStripeCustomerId() != nil else { return }
        guard let data = await stripeRequest("list-payment-methods", body: [:]),
              let response = try? JSONDecoder().decode(StripePaymentMethodsResponse_Ride.self, from: data),
              !response.paymentMethods.isEmpty else {
            return
        }

        savedCards = response.paymentMethods.map {
            PaymentCard(last4: $0.last4, brand: $0.brand.capitalized, stripePaymentMethodId: $0.id)
        }
        if let defaultIndex = response.paymentMethods.firstIndex(where: { $0.isDefault }) {
            selectedCardIndex = defaultIndex
        } else {
            selectedCardIndex = 0
        }
    }

    /// Retries a ride whose payment previously failed (Phase 2: "retry failed
    /// payment flow"). Optionally pass a different `paymentMethodId` if the
    /// rider just updated their card. Backend rejects this unless the ride's
    /// current `paymentStatus` is "failed", so it can never double-charge.
    func retryFailedPayment(rideId: String, paymentMethodId: String? = nil) async {
        guard !isRetryingPayment else { return }
        isRetryingPayment = true
        defer { isRetryingPayment = false }

        var body: [String: Any] = ["rideId": rideId, "currency": "usd"]
        if let paymentMethodId { body["paymentMethodId"] = paymentMethodId }
        await performChargeRequest(path: "payments/retry", body: body)
    }

    private func chargeTip(rideId: String, cents: Int) async throws {
        var body: [String: Any] = [
            "rideId": rideId,
            "amountCents": cents,
            "currency": "usd"
        ]
        if let paymentMethodId = selectedCard?.stripePaymentMethodId {
            body["paymentMethodId"] = paymentMethodId
        }

        guard let data = await stripeRequest("payments/tip", body: body) else {
            throw RideTipError.networkUnavailable
        }
        guard let response = try? JSONDecoder().decode(StripePaymentIntentResponse_Ride.self, from: data) else {
            throw RideTipError.unconfirmed
        }
        if let error = response.error {
            throw RideTipError.backend(response.message ?? error)
        }
        guard response.status == "succeeded" else {
            throw RideTipError.unconfirmed
        }
    }

    private func performChargeRequest(path: String, body: [String: Any]) async {
        paymentStatus = "processing"
        paymentFailureReason = nil

        guard let data = await stripeRequest(path, body: body) else {
            paymentStatus = "failed"
            paymentFailureReason = "Couldn't reach the payment server. Please try again."
            return
        }
        if let response = try? JSONDecoder().decode(StripePaymentIntentResponse_Ride.self, from: data) {
            if let error = response.error {
                paymentStatus = "failed"
                paymentFailureReason = response.message ?? error
                print("❌ Ride charge failed: \(error)")
            } else {
                paymentStatus = response.status == "succeeded" ? "succeeded" : "processing"
                paymentFailureReason = nil
                print("✅ Ride charge succeeded: \(response.paymentIntentId ?? "") status=\(response.status ?? "")")
            }
        } else {
            paymentStatus = "failed"
            paymentFailureReason = "Payment status could not be confirmed. Please try again."
        }
    }
}

@MainActor
private final class RiderCancellationSoundPlayer {
    private var player: AVAudioPlayer?

    func play() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true)

            if player == nil {
                guard let url = Bundle.main.url(forResource: "ride-cancelled", withExtension: "mp3") else {
                    return
                }
                let audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer.numberOfLoops = 0
                audioPlayer.prepareToPlay()
                player = audioPlayer
            }

            player?.currentTime = 0
            player?.play()
        } catch {
            player = nil
        }
    }
}

@MainActor
private final class RiderTripTransitionSoundPlayer {
    private var player: AVAudioPlayer?

    func play() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true)

            if player == nil {
                guard let url = Bundle.main.url(forResource: "trip-transition-chime", withExtension: "mp3") else {
                    return
                }
                let audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer.numberOfLoops = 0
                audioPlayer.prepareToPlay()
                player = audioPlayer
            }

            player?.currentTime = 0
            player?.play()
        } catch {
            player = nil
        }
    }
}

private struct StripeCustomerResponse_Ride: Decodable {
    let customerId: String
}

private struct StripePaymentMethodDTO_Ride: Decodable {
    let id: String
    let brand: String
    let last4: String
    let isDefault: Bool
}

private struct StripePaymentMethodsResponse_Ride: Decodable {
    let paymentMethods: [StripePaymentMethodDTO_Ride]
}

private struct StripePaymentIntentResponse_Ride: Decodable {
    let clientSecret: String?
    let paymentIntentId: String?
    let status: String?
    let error: String?
    let message: String?
}

private enum RideTipError: LocalizedError {
    case invalidAmount
    case missingReceipt
    case missingRideId
    case ridePaymentNotSettled
    case networkUnavailable
    case unconfirmed
    case backend(String)

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "Choose a valid tip amount."
        case .missingReceipt, .missingRideId:
            return "We could not find this completed ride. Please contact support before adding a tip."
        case .ridePaymentNotSettled:
            return "Finish the ride payment before adding a tip."
        case .networkUnavailable:
            return "Couldn't reach the payment server. Please try again."
        case .unconfirmed:
            return "We couldn't confirm the tip charge. Please try again."
        case .backend(let message):
            return message
        }
    }
}

private enum RideFeedbackError: LocalizedError {
    case notSignedIn
    case missingReceipt
    case missingRideId
    case invalidRating

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Please sign in again before saving your ride feedback."
        case .missingReceipt, .missingRideId:
            return "We could not find this completed ride. Please contact support before submitting feedback."
        case .invalidRating:
            return "Choose a rating between 1 and 5 stars."
        }
    }
}
