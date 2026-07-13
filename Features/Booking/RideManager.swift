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
    let perMinute: Double          // driver-set, will be capped by ride type
    let perMile: Double            // driver-set, will be capped by ride type
    var coordinate: CLLocationCoordinate2D
    var score: Int                 // proximity/quality score
    var ratingCount: Int = 0
    var completedRideCount: Int? = nil
    var acceptanceRate: Int? = nil
    var stripeAccountId: String? = nil       // Stripe Connect account, for destination-charge payouts
    var stripeChargesEnabled: Bool = false   // Connect account has completed onboarding
    var gender: String? = nil

    static func == (lhs: Driver, rhs: Driver) -> Bool { lhs.id == rhs.id }
}

struct RideEstimate: Equatable, Codable {
    var distanceMiles: Double
    var durationMinutes: Double
}

struct RidePricingSnapshot: Equatable, Codable {
    static let currentVersion = 1
    static let estimateSource = "apple_mapkit"

    let pricingVersion: Int
    let estimateSource: String
    let driverRatePerMileCents: Int
    let driverRatePerMinuteCents: Int
    let distanceCostCents: Int
    let timeCostCents: Int
    let calculatedSubtotalCents: Int
    let minimumFareAdjustmentCents: Int
    let rideSubtotalCents: Int
    let bookingFeeCents: Int
    let estimatedRiderTotalCents: Int
    let estimatedDriverPayoutCents: Int
    let estimatedPlatformShareCents: Int
    let promoDiscountCents: Int
    let authorizedRiderChargeCents: Int

    var asFirestoreFields: [String: Any] {
        [
            "pricingVersion": pricingVersion,
            "fareEstimateSource": estimateSource,
            "driverRatePerMileCents": driverRatePerMileCents,
            "driverRatePerMinuteCents": driverRatePerMinuteCents,
            "distanceCostCents": distanceCostCents,
            "timeCostCents": timeCostCents,
            "calculatedSubtotalCents": calculatedSubtotalCents,
            "minimumFareAdjustmentCents": minimumFareAdjustmentCents,
            "rideSubtotalCents": rideSubtotalCents,
            "bookingFeeCents": bookingFeeCents,
            "estimatedRiderTotalCents": estimatedRiderTotalCents,
            "estimatedDriverPayoutCents": estimatedDriverPayoutCents,
            "estimatedPlatformShareCents": estimatedPlatformShareCents,
            "promoDiscountCents": promoDiscountCents,
            "authorizedRiderChargeCents": authorizedRiderChargeCents,
            "finalRiderChargeCents": authorizedRiderChargeCents,
            "upfrontFare": Double(estimatedDriverPayoutCents) / 100.0,
            "estimatedFare": Double(estimatedDriverPayoutCents) / 100.0,
            "estimatedRiderTotal": Double(estimatedRiderTotalCents) / 100.0,
            "bookingFee": Double(bookingFeeCents) / 100.0
        ]
    }
}

enum RydrRideTier {
    case eco
    case go
    case xl
    case prestine
    case executive
}

struct RideTierPricing {
    let tier: RydrRideTier
    let title: String
    let purpose: String
    let serviceLevel: String
    let vehicleExpectations: String
    let minimumRideSubtotal: Double
    let bookingFeeUnderFiveMiles: Double
    let bookingFeeFiveMilesOrMore: Double
    let minPerMile: Double
    let maxPerMile: Double
    let minPerMinute: Double
    let maxPerMinute: Double

    func bookingFee(for distanceMiles: Double) -> Double {
        distanceMiles < 5 ? bookingFeeUnderFiveMiles : bookingFeeFiveMilesOrMore
    }

    var perMileRangeText: String {
        "$\(minPerMile.formattedRate) - $\(maxPerMile.formattedRate)/mi"
    }

    var perMinuteRangeText: String {
        "$\(minPerMinute.formattedRate) - $\(maxPerMinute.formattedRate)/min"
    }

    func clampedPerMile(_ value: Double) -> Double {
        min(max(value, minPerMile), maxPerMile)
    }

    func clampedPerMinute(_ value: Double) -> Double {
        min(max(value, minPerMinute), maxPerMinute)
    }
}

enum RydrPricing {
    static let driverPayoutShare = 0.70

    static func config(for rideType: String) -> RideTierPricing {
        switch tier(for: rideType) {
        case .eco:
            return .init(
                tier: .eco,
                title: "Rydr Eco",
                purpose: "Electric and environmentally conscious transportation.",
                serviceLevel: "Practical, efficient, and lower-impact.",
                vehicleExpectations: "Electric vehicles approved for Rydr Eco.",
                minimumRideSubtotal: 7.00,
                bookingFeeUnderFiveMiles: 3.00,
                bookingFeeFiveMilesOrMore: 5.00,
                minPerMile: 0.50,
                maxPerMile: 1.10,
                minPerMinute: 0.15,
                maxPerMinute: 0.25
            )
        case .go:
            return .init(
                tier: .go,
                title: "Rydr Go",
                purpose: "Affordable everyday transportation.",
                serviceLevel: "Accessible standard rides for daily trips.",
                vehicleExpectations: "Compact, mid-size, and full-size sedans or mid-size SUVs in good condition.",
                minimumRideSubtotal: 7.00,
                bookingFeeUnderFiveMiles: 3.00,
                bookingFeeFiveMilesOrMore: 6.00,
                minPerMile: 0.50,
                maxPerMile: 1.00,
                minPerMinute: 0.15,
                maxPerMinute: 0.25
            )
        case .xl:
            return .init(
                tier: .xl,
                title: "Rydr XL",
                purpose: "Groups, larger parties, and luggage.",
                serviceLevel: "More room while staying practical.",
                vehicleExpectations: "Large SUVs or qualifying high-capacity vehicles.",
                minimumRideSubtotal: 9.00,
                bookingFeeUnderFiveMiles: 4.00,
                bookingFeeFiveMilesOrMore: 8.00,
                minPerMile: 0.50,
                maxPerMile: 1.25,
                minPerMinute: 0.15,
                maxPerMinute: 0.25
            )
        case .prestine:
            return .init(
                tier: .prestine,
                title: "Rydr Prestine",
                purpose: "Premium transportation with elevated vehicle standards.",
                serviceLevel: "Premium, clean, well-maintained, and highly rated.",
                vehicleExpectations: "Vehicle less than 7 years old with clean interior, clean exterior, no visible damage, and well-maintained condition.",
                minimumRideSubtotal: 12.00,
                bookingFeeUnderFiveMiles: 5.00,
                bookingFeeFiveMilesOrMore: 10.00,
                minPerMile: 0.75,
                maxPerMile: 1.50,
                minPerMinute: 0.15,
                maxPerMinute: 0.35
            )
        case .executive:
            return .init(
                tier: .executive,
                title: "Rydr Executive",
                purpose: "Exclusive executive transportation experience.",
                serviceLevel: "More Than A Ride. An Arrival.",
                vehicleExpectations: "Luxury sedan or luxury SUV less than 5 years old with leather interior, premium appearance, exceptional cleanliness, and premium amenities.",
                minimumRideSubtotal: 18.00,
                bookingFeeUnderFiveMiles: 8.00,
                bookingFeeFiveMilesOrMore: 15.00,
                minPerMile: 1.00,
                maxPerMile: 2.00,
                minPerMinute: 0.25,
                maxPerMinute: 0.50
            )
        }
    }

    private static func tier(for rideType: String) -> RydrRideTier {
        let key = rideType.lowercased()
        if key.contains("eco") { return .eco }
        if key.contains("xl") { return .xl }
        if key.contains("prestine") || key.contains("pristine") { return .prestine }
        if key.contains("executive") { return .executive }
        return .go
    }
}

private extension Double {
    var formattedRate: String {
        String(format: "%.2f", self)
    }
}

struct RideFareBreakdown: Equatable {
    let distanceCost: Double
    let timeCost: Double
    let calculatedSubtotal: Double
    let minimumFareAdjustment: Double
    let rideSubtotal: Double
    let bookingFee: Double
    let finalRiderTotal: Double
    let driverPayout: Double
    let platformShare: Double
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
enum DriverDecision { case accepted, declined }

enum RideCancellationMode: String, Codable {
    case cancelRide
    case findAnotherDriver
}

struct RideCancellationQuote {
    let mode: RideCancellationMode
    let appliesFee: Bool
    let pickupEtaSeconds: Int
    let rideSubtotalCents: Int
    let bookingFeeCents: Int
    let cancellationFeeCents: Int
    let platformFeeCents: Int
    let driverPayoutCents: Int
    let totalChargeCents: Int

    var asFirestoreFields: [String: Any] {
        [
            "cancellationMode": mode.rawValue,
            "cancellationFeeApplies": appliesFee,
            "cancellationPickupEtaSeconds": pickupEtaSeconds,
            "cancellationRideSubtotalCents": rideSubtotalCents,
            "cancellationFeeRateBasisPoints": 2000,
            "cancellationFeeCents": cancellationFeeCents,
            "cancellationBookingFeeCents": bookingFeeCents,
            "cancellationPlatformFeeCents": platformFeeCents,
            "cancellationDriverPayoutCents": driverPayoutCents,
            "cancellationTotalChargeCents": totalChargeCents,
            "finalRiderChargeCents": totalChargeCents,
            "driverPayoutCents": driverPayoutCents
        ]
    }
}

struct ProratedRideCancellationQuote {
    let chargeCents: Int
    let distanceMiles: Double
    let driverPayoutCents: Int
    let platformFeeCents: Int
    let cancelledByRole: String

    var asFirestoreFields: [String: Any] {
        [
            "proratedCancellation": true,
            "proratedCancellationReason": "midRide",
            "proratedCancellationDistanceMiles": distanceMiles,
            "proratedCancellationChargeCents": chargeCents,
            "proratedCancellationDriverPayoutCents": driverPayoutCents,
            "proratedCancellationPlatformFeeCents": platformFeeCents,
            "finalRiderChargeCents": chargeCents,
            "driverPayoutCents": driverPayoutCents,
            "cancelledByRole": cancelledByRole
        ]
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
    let proratedCancellationChargeCents: Int?
    let proratedCancellationDistanceMiles: Double?
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
        pricingSnapshot: RidePricingSnapshot,
        riderPreferences: RiderRidePreferences?,
        riderVerified: Bool
    ) async throws -> String // returns rideId
    func awaitDriverDecision(rideId: String) async throws -> DriverDecision
    func rideLifecycleStream(rideId: String) -> AsyncThrowingStream<RideLifecycleSnapshot, Error>
    func driverLocationStream(rideId: String) -> AsyncStream<CLLocationCoordinate2D>
    func cancelRide(rideId: String, mode: RideCancellationMode, quote: RideCancellationQuote?) async throws
    func cancelMidRide(rideId: String, quote: ProratedRideCancellationQuote) async throws
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
    private var chargedProratedCancellationRideIDs = Set<String>()

    // Internals used across steps
    private var attemptedDriverIDs: Set<String> = []
    private var activeMatchmakingKey = ""
    private var cachedEstimate: RideEstimate = .init(distanceMiles: 6.2, durationMinutes: 18)
    private var cachedPickup = ""
    private var cachedDropoff = ""
    private var cachedRideType = ""
    private var cachedPickupCoordinate: CLLocationCoordinate2D?
    private var cachedDropoffCoordinate: CLLocationCoordinate2D?
    private var currentServiceRideId: String?
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
    private let driverDecisionTimeoutSeconds: UInt64 = 18
    private let cancellationFeeWindowSeconds = 120

    init(rideService: RideService = FirestoreRideService()) {
        self.rideService = rideService
        restoreActiveRideIfNeeded()
        if state == .inProgress {
            observeActiveRideLifecycleIfNeeded()
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

    private func resetMatchmakingAttempt() {
        activeMatchmakingKey = ""
        attemptedDriverIDs.removeAll()
    }

    private static func matchmakingKey(
        pickup: String,
        dropoff: String,
        rideType: String,
        pickupCoordinate: CLLocationCoordinate2D?,
        dropoffCoordinate: CLLocationCoordinate2D?
    ) -> String {
        [
            normalizedMatchmakingText(pickup),
            normalizedMatchmakingText(dropoff),
            normalizedMatchmakingText(rideType),
            coordinateKey(pickupCoordinate),
            coordinateKey(dropoffCoordinate)
        ].joined(separator: "|")
    }

    private static func normalizedMatchmakingText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func coordinateKey(_ coordinate: CLLocationCoordinate2D?) -> String {
        guard let coordinate else { return "" }
        return String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
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
        let matchmakingKey = Self.matchmakingKey(
            pickup: pickup,
            dropoff: dropoff,
            rideType: rideType,
            pickupCoordinate: effectivePickupCoordinate,
            dropoffCoordinate: effectiveDropoffCoordinate
        )
        if matchmakingKey != activeMatchmakingKey {
            activeMatchmakingKey = matchmakingKey
            attemptedDriverIDs.removeAll()
        }
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

                let eligibleDrivers = drivers.filter { !self.attemptedDriverIDs.contains($0.id) }
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

        selectedDriver = driver
        attemptedDriverIDs.insert(driver.id)
        rideRequestErrorMessage = nil
        state = .awaitingDriver

        decisionTask?.cancel()
        decisionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let code = self.normalizedSavedPromoCode()
                self.currentAppliedRydrBankCode = code.isEmpty ? nil : code
                let pricingSnapshot = self.pricingSnapshot(estimate: self.cachedEstimate, with: driver, rideType: self.cachedRideType)
                let rideId = try await rideService.requestRide(
                    driverId: driver.id,
                    pickup: cachedPickup,
                    dropoff: cachedDropoff,
                    rideType: cachedRideType,
                    pickupCoordinate: cachedPickupCoordinate,
                    dropoffCoordinate: cachedDropoffCoordinate,
                    estimate: cachedEstimate,
                    pricingSnapshot: pricingSnapshot,
                    riderPreferences: cachedRidePreferences,
                    riderVerified: cachedRiderVerified
                )
                self.currentServiceRideId = rideId

                let decision = try await self.awaitDriverDecisionWithTimeout(rideId: rideId)
                switch decision {
                case .accepted:
                    self.handleAccept()
                case .declined:
                    self.handleDecline(message: "That driver declined the ride. Pick another nearby driver.")
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.handleDecline(message: error.localizedDescription)
            }
        }
    }

    /// Driver accepted – seed the ride from the request and observe backend lifecycle updates.
    func handleAccept() {
        guard let driver = selectedDriver else { return }

        // Compute rider fare with caps, platform minimum subtotal, booking fee, and promo.
        let fareBeforePromo = rawFare(estimate: cachedEstimate, with: driver, rideType: cachedRideType)
        let fareAfterPromo = currentAppliedRydrBankCode == nil ? applyPromo(to: fareBeforePromo) : 0
        currentBaseFare = fareAfterPromo
        currentWaitChargePerMinute = cappedWaitRate(for: driver, rideType: cachedRideType)
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
        observeActiveRideLifecycleIfNeeded()
    }

    /// If driver declines, take user back to selection (remove that driver).
    func handleDecline(message: String? = nil) {
        if let declined = selectedDriver {
            attemptedDriverIDs.insert(declined.id)
            availableDrivers.removeAll { $0.id == declined.id }
        }
        selectedDriver = nil
        rideRequestErrorMessage = message
        if availableDrivers.isEmpty {
            rideRequestErrorMessage = RideRequestError.noDriversAvailable.localizedDescription
        }
        state = .selecting
    }

    /// Rider cancels before pickup → return to driver cards. Mid-ride → end with a prorated receipt.
    func riderCancelAndAutoReassign() {
        riderCancelAndFindAnother()
    }

    func riderCancelAndFindAnother() {
        guard let ride = currentRide else { return }
        cancellationSoundPlayer.play()

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
        cancellationSoundPlayer.play()
        cancelRideWithoutReassignment(mode: .cancelRide)
    }

    /// Complete ride -> create receipt + push to history.
    func completeRide() {
        rideLifecycleTask?.cancel()
        rideLifecycleTask = nil

        guard let ride = currentRide else { return }
        tripTransitionSoundPlayer.play()
        let card = selectedCard
        let chargeBreakdown = receiptChargeBreakdown(for: ride, finalFare: ride.fare)
        let receipt = Receipt(
            rideId: ride.id,
            date: Date(),
            driverName: ride.driver.name,
            pickup: ride.pickup,
            dropoff: ride.dropoff,
            distanceMiles: ride.estimate.distanceMiles,
            durationMinutes: ride.estimate.durationMinutes,
            fare: ride.fare,
            cardMasked: card.map { "\($0.brand) ••\($0.last4)" } ?? "No card on file",
            chargeBreakdown: chargeBreakdown,
            backendRideId: currentServiceRideId ?? ride.id.uuidString
        )
        lastReceipt = receipt
        lastCompletedDriverId = ride.driver.id
        history.insert(receipt, at: 0)
        let backendRideId = currentServiceRideId ?? ride.id.uuidString
        let chatContext = activeRideChatContext
        let appliedCode = currentAppliedRydrBankCode
        let rideType = ride.rideType
        let distance = ride.estimate.distanceMiles
        currentRide = nil
        currentServiceRideId = nil
        currentAppliedRydrBankCode = nil
        currentBaseFare = 0
        currentWaitChargePerMinute = 0
        hasPlayedTripStartedSoundForCurrentRide = false
        clearActiveRideSnapshot()
        resetMatchmakingAttempt()
        state = .completed
        closeRideChatIfNeeded(chatContext)

        Task {
            if let appliedCode, !appliedCode.isEmpty {
                try? await RydrBankAPI.consume(code: appliedCode, rideId: backendRideId, rideType: rideType, distanceMi: distance)
                await MainActor.run {
                    UserDefaults.standard.removeObject(forKey: "appliedRydrBankCode")
                    UserDefaults.standard.removeObject(forKey: "appliedRydrBankBookingId")
                }
            }
            _ = try? await RydrBankAPI.rideComplete(rideId: backendRideId, distanceMi: distance, rideType: rideType)
            await chargeRiderForRide(ride, rideId: backendRideId, totalAmount: chargeBreakdown.calculatedTotal)
        }
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
            "rideId": backendRideId,
            "riderId": user.uid,
            "driverName": receipt.driverName,
            "pickup": receipt.pickup,
            "dropoff": receipt.dropoff,
            "compliments": compliments,
            "feedback": trimmedFeedback,
            "favoriteDriver": draft.favoriteDriver,
            "source": "ios_rider_app",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let driverId = lastCompletedDriverId {
            payload["driverId"] = driverId
        }
        if let rating {
            payload["rating"] = rating
        }

        let db = Firestore.firestore()
        let ratingRef = db.collection("driverRatings").document(backendRideId)
        let rideRef = db.collection("rides").document(backendRideId)
        let batch = db.batch()
        batch.setData(payload, forDocument: ratingRef, merge: true)
        batch.setData([
            "riderDriverRating": payload,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: rideRef, merge: true)
        try await batch.commit()
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
        clearActiveRideSnapshot()
        resetMatchmakingAttempt()
        state = .cancelled
        closeRideChatIfNeeded(chatContext)
    }

    // MARK: - Estimation / Pricing

    static func pricingConfig(for rideType: String) -> RideTierPricing {
        RydrPricing.config(for: rideType)
    }

    static func fareBreakdown(estimate: RideEstimate, with driver: Driver, rideType: String) -> RideFareBreakdown {
        let pricing = RydrPricing.config(for: rideType)
        let perMile = pricing.clampedPerMile(driver.perMile)
        let perMinute = pricing.clampedPerMinute(driver.perMinute)
        let distanceCost = estimate.distanceMiles * perMile
        let timeCost = estimate.durationMinutes * perMinute
        let calculatedSubtotal = distanceCost + timeCost

        // Platform minimum fare logic for short/low-cost rides. This raises the ride
        // subtotal used for rider pricing and driver payout without changing driver rates.
        let minimumFareAdjustment = max(0, pricing.minimumRideSubtotal - calculatedSubtotal)
        let rideSubtotal = calculatedSubtotal + minimumFareAdjustment
        let bookingFee = pricing.bookingFee(for: estimate.distanceMiles)
        let driverPayout = rideSubtotal * RydrPricing.driverPayoutShare
        let platformShare = (rideSubtotal - driverPayout) + bookingFee
        let finalRiderTotal = rideSubtotal + bookingFee

        return RideFareBreakdown(
            distanceCost: (distanceCost * 100).rounded() / 100,
            timeCost: (timeCost * 100).rounded() / 100,
            calculatedSubtotal: (calculatedSubtotal * 100).rounded() / 100,
            minimumFareAdjustment: (minimumFareAdjustment * 100).rounded() / 100,
            rideSubtotal: (rideSubtotal * 100).rounded() / 100,
            bookingFee: bookingFee,
            finalRiderTotal: (finalRiderTotal * 100).rounded() / 100,
            driverPayout: (driverPayout * 100).rounded() / 100,
            platformShare: (platformShare * 100).rounded() / 100
        )
    }

    /// Raw fare BEFORE promo discounts (adjusted ride subtotal + booking fee).
    private func rawFare(estimate: RideEstimate, with driver: Driver, rideType: String) -> Double {
        Self.fareBreakdown(estimate: estimate, with: driver, rideType: rideType).finalRiderTotal
    }

    private static func cents(_ value: Double) -> Int {
        Int((value * 100).rounded())
    }

    private func pricingSnapshot(estimate: RideEstimate, with driver: Driver, rideType: String) -> RidePricingSnapshot {
        let pricing = RydrPricing.config(for: rideType)
        let perMile = pricing.clampedPerMile(driver.perMile)
        let perMinute = pricing.clampedPerMinute(driver.perMinute)
        let breakdown = Self.fareBreakdown(estimate: estimate, with: driver, rideType: rideType)
        let promoDiscount = currentAppliedRydrBankCode == nil ? 0 : breakdown.finalRiderTotal
        let authorizedCharge = max(0, breakdown.finalRiderTotal - promoDiscount)

        return RidePricingSnapshot(
            pricingVersion: RidePricingSnapshot.currentVersion,
            estimateSource: RidePricingSnapshot.estimateSource,
            driverRatePerMileCents: Self.cents(perMile),
            driverRatePerMinuteCents: Self.cents(perMinute),
            distanceCostCents: Self.cents(breakdown.distanceCost),
            timeCostCents: Self.cents(breakdown.timeCost),
            calculatedSubtotalCents: Self.cents(breakdown.calculatedSubtotal),
            minimumFareAdjustmentCents: Self.cents(breakdown.minimumFareAdjustment),
            rideSubtotalCents: Self.cents(breakdown.rideSubtotal),
            bookingFeeCents: Self.cents(breakdown.bookingFee),
            estimatedRiderTotalCents: Self.cents(breakdown.finalRiderTotal),
            estimatedDriverPayoutCents: Self.cents(breakdown.driverPayout),
            estimatedPlatformShareCents: Self.cents(breakdown.platformShare),
            promoDiscountCents: Self.cents(promoDiscount),
            authorizedRiderChargeCents: Self.cents(authorizedCharge)
        )
    }

    private func cancellationQuote(for ride: Ride, mode: RideCancellationMode) -> RideCancellationQuote {
        let breakdown = Self.fareBreakdown(estimate: ride.estimate, with: ride.driver, rideType: ride.rideType)
        let pickupEtaSeconds = currentPickupEtaSeconds(for: ride)
        let appliesFee = ride.status == .waitingForRider || pickupEtaSeconds <= cancellationFeeWindowSeconds
        let rideSubtotalCents = Self.cents(breakdown.rideSubtotal)
        let bookingFeeCents = appliesFee && mode == .cancelRide ? Self.cents(breakdown.bookingFee) : 0
        let cancellationFeeCents = appliesFee ? Int((Double(rideSubtotalCents) * 0.20).rounded()) : 0
        let totalChargeCents = bookingFeeCents + cancellationFeeCents

        return RideCancellationQuote(
            mode: mode,
            appliesFee: appliesFee,
            pickupEtaSeconds: pickupEtaSeconds,
            rideSubtotalCents: rideSubtotalCents,
            bookingFeeCents: bookingFeeCents,
            cancellationFeeCents: cancellationFeeCents,
            platformFeeCents: bookingFeeCents,
            driverPayoutCents: cancellationFeeCents,
            totalChargeCents: totalChargeCents
        )
    }

    private func currentPickupEtaSeconds(for ride: Ride) -> Int {
        if ride.status == .waitingForRider { return 0 }
        if let pickupCoordinate {
            return estimatedPickupEtaSeconds(from: liveDriverCoordinate, to: pickupCoordinate)
        }
        return max(0, pickupEtaSecondsRemaining)
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

    private func receiptChargeBreakdown(
        for ride: Ride,
        finalFare: Double,
        includeRideTimeAdjustment: Bool = false
    ) -> ReceiptChargeBreakdown {
        let fareBreakdown = Self.fareBreakdown(estimate: ride.estimate, with: ride.driver, rideType: ride.rideType)
        var receiptBreakdown = ReceiptChargeBreakdown(
            distanceCharge: fareBreakdown.distanceCost,
            timeCharge: fareBreakdown.timeCost,
            minimumFareAdjustment: fareBreakdown.minimumFareAdjustment,
            bookingFee: fareBreakdown.bookingFee,
            waitCharge: pickupWaitCharge,
            promoDiscount: currentAppliedRydrBankCode == nil ? 0 : -fareBreakdown.finalRiderTotal
        )

        let reconciliation = (finalFare - receiptBreakdown.calculatedTotal).currencyRounded
        if abs(reconciliation) >= 0.01 {
            if includeRideTimeAdjustment {
                receiptBreakdown.timeAdjustment = reconciliation
            } else {
                receiptBreakdown.otherAdjustment = reconciliation
            }
        }

        return receiptBreakdown
    }

    func markRiderPickedUp() {
        guard currentRide?.status == .waitingForRider else { return }
        destinationEtaSecondsRemaining = max(60, Int(((currentRide?.estimate.durationMinutes ?? cachedEstimate.durationMinutes) * 0.6 * 60).rounded()))
        persistActiveRideSnapshot()
    }

    private func updatePaidPickupWait(seconds: Int) {
        paidPickupWaitSeconds = max(0, seconds)
        let minutes = Double(paidPickupWaitSeconds) / 60.0
        pickupWaitCharge = ((minutes * currentWaitChargePerMinute) * 100).rounded() / 100
        currentRide?.fare = ((currentBaseFare + pickupWaitCharge) * 100).rounded() / 100
    }

    private func cancelBeforePickupAndReturnToSelection(
        mode: RideCancellationMode = .findAnotherDriver,
        notifyBackend: Bool = true
    ) {
        rideLifecycleTask?.cancel()
        decisionTask?.cancel()
        pickupWaitCountdownTask?.cancel()
        let chatContext = activeRideChatContext
        let cancellationQuote: RideCancellationQuote?
        if let ride = currentRide {
            cancellationQuote = self.cancellationQuote(for: ride, mode: mode)
        } else {
            cancellationQuote = nil
        }

        if let selectedDriver {
            attemptedDriverIDs.insert(selectedDriver.id)
            availableDrivers.removeAll { $0.id == selectedDriver.id }
        }

        let cancelledServiceRideId = currentServiceRideId
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

        Task {
            if notifyBackend, let id = cancelledServiceRideId {
                try? await rideService.cancelRide(rideId: id, mode: mode, quote: cancellationQuote)
                if (cancellationQuote?.totalChargeCents ?? 0) > 0 {
                    await chargeCancellationFee(rideId: id)
                }
            }
        }
        closeRideChatIfNeeded(chatContext)
    }

    private func cancelRideWithoutReassignment(mode: RideCancellationMode) {
        rideLifecycleTask?.cancel()
        decisionTask?.cancel()
        pickupWaitCountdownTask?.cancel()
        let chatContext = activeRideChatContext
        let cancelledServiceRideId = currentServiceRideId
        let cancellationQuote: RideCancellationQuote?
        if let ride = currentRide {
            cancellationQuote = self.cancellationQuote(for: ride, mode: mode)
        } else {
            cancellationQuote = nil
        }

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
        resetMatchmakingAttempt()
        state = .cancelled

        Task {
            if let id = cancelledServiceRideId {
                try? await rideService.cancelRide(rideId: id, mode: mode, quote: cancellationQuote)
                if (cancellationQuote?.totalChargeCents ?? 0) > 0 {
                    await chargeCancellationFee(rideId: id)
                }
            }
        }
        closeRideChatIfNeeded(chatContext)
    }

    private func cancelMidRideAndComplete() {
        guard let ride = currentRide else { return }
        let chatContext = activeRideChatContext
        let backendRideId = currentServiceRideId ?? ride.id.uuidString

        rideLifecycleTask?.cancel()
        decisionTask?.cancel()

        let totalSeconds = max(1, Int((ride.estimate.durationMinutes * 0.6 * 60).rounded()))
        let traveledFraction = max(0.1, min(0.95, 1.0 - (Double(destinationEtaSecondsRemaining) / Double(totalSeconds))))
        let proratedDistance = ((ride.estimate.distanceMiles * traveledFraction) * 10).rounded() / 10
        let proratedMinutes = max(1, (ride.estimate.durationMinutes * 0.6 * traveledFraction).rounded())
        let proratedFare = ((ride.fare * traveledFraction) * 100).rounded() / 100
        let card = selectedCard
        let chargeBreakdown = receiptChargeBreakdown(
            for: ride,
            finalFare: proratedFare,
            includeRideTimeAdjustment: true
        )
        let proratedChargeCents = Self.cents(proratedFare)
        let proratedPlatformFeeCents = Int((Double(proratedChargeCents) * 0.30).rounded())
        let proratedDriverPayoutCents = max(0, proratedChargeCents - proratedPlatformFeeCents)
        let proratedQuote = ProratedRideCancellationQuote(
            chargeCents: proratedChargeCents,
            distanceMiles: proratedDistance,
            driverPayoutCents: proratedDriverPayoutCents,
            platformFeeCents: proratedPlatformFeeCents,
            cancelledByRole: "rider"
        )

        lastReceipt = Receipt(
            rideId: ride.id,
            date: Date(),
            driverName: ride.driver.name,
            pickup: ride.pickup,
            dropoff: ride.dropoff,
            distanceMiles: proratedDistance,
            durationMinutes: proratedMinutes,
            fare: proratedFare,
            cardMasked: card.map { "\($0.brand) ••\($0.last4)" } ?? "No card on file",
            chargeBreakdown: chargeBreakdown,
            backendRideId: backendRideId
        )
        if let lastReceipt {
            history.insert(lastReceipt, at: 0)
        }

        currentRide = nil
        selectedDriver = nil
        currentServiceRideId = nil
        currentAppliedRydrBankCode = nil
        currentBaseFare = 0
        currentWaitChargePerMinute = 0
        hasPlayedTripStartedSoundForCurrentRide = false
        releaseAppliedRydrBankCodeIfNeeded()
        clearActiveRideSnapshot()
        resetMatchmakingAttempt()
        state = .completed
        closeRideChatIfNeeded(chatContext)

        Task {
            try? await rideService.cancelMidRide(rideId: backendRideId, quote: proratedQuote)
            await chargeCancellationFee(rideId: backendRideId)
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
                completeRide()
                return
            case .cancelled:
                if snapshot.rawStatus == "driverCancelled" {
                    if let chargeCents = snapshot.proratedCancellationChargeCents,
                       chargeCents > 0,
                       let rideId = currentServiceRideId,
                       !chargedProratedCancellationRideIDs.contains(rideId) {
                        chargedProratedCancellationRideIDs.insert(rideId)
                        Task { await chargeCancellationFee(rideId: rideId) }
                    }
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

    private func cappedWaitRate(for driver: Driver, rideType: String) -> Double {
        Self.pricingConfig(for: rideType).clampedPerMinute(driver.perMinute)
    }

    private func awaitDriverDecisionWithTimeout(rideId: String) async throws -> DriverDecision {
        try await withThrowingTaskGroup(of: DriverDecision.self) { group in
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
        let coordinate: CoordinateSnapshot
        let score: Int
        let ratingCount: Int?
        let completedRideCount: Int?
        let acceptanceRate: Int?

        init(_ driver: Driver) {
            id = driver.id
            name = driver.name
            carMakeModel = driver.carMakeModel
            rating = driver.rating
            compliments = driver.compliments
            perMinute = driver.perMinute
            perMile = driver.perMile
            coordinate = CoordinateSnapshot(driver.coordinate)
            score = driver.score
            ratingCount = driver.ratingCount
            completedRideCount = driver.completedRideCount
            acceptanceRate = driver.acceptanceRate
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
                coordinate: coordinate.coordinate,
                score: score,
                ratingCount: ratingCount ?? 0,
                completedRideCount: completedRideCount,
                acceptanceRate: acceptanceRate
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

    // MARK: - Stripe (real wallet + ride charge with driver 70/30 destination split)

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

    private func chargeCancellationFee(rideId: String) async {
        await performChargeRequest(path: "create-payment-intent", body: ["rideId": rideId, "currency": "usd"])
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

    /// Off-session charges the rider for a completed (or prorated-cancelled) ride.
    /// The backend re-derives the customerId, the driver's Connect account, and the
    /// platform's fee share server-side from `rideId` — this client never sends a
    /// customerId/driverAccountId/applicationFeeAmount it could tamper with.
    /// Publishes `paymentStatus`/`paymentFailureReason` so the UI can show
    /// "Payment Failed — Retry Payment" per the Phase 2 spec.
    private func chargeRiderForRide(_ ride: Ride, rideId: String, totalAmount: Double) async {
        let body: [String: Any] = ["rideId": rideId, "currency": "usd"]
        await performChargeRequest(path: "create-payment-intent", body: body)
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
