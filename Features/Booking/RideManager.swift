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

    static func == (lhs: Driver, rhs: Driver) -> Bool { lhs.id == rhs.id }
}

struct RideEstimate: Equatable, Codable {
    var distanceMiles: Double
    var durationMinutes: Double
}

enum RydrRideTier {
    case eco
    case go
    case xl
    case pristine
    case executive
}

struct RideTierPricing {
    let tier: RydrRideTier
    let title: String
    let minimumRideSubtotal: Double
    let bookingFeeUnderFiveMiles: Double
    let bookingFeeFiveMilesOrMore: Double
    let maxPerMile: Double
    let maxPerMinute: Double

    func bookingFee(for distanceMiles: Double) -> Double {
        distanceMiles < 5 ? bookingFeeUnderFiveMiles : bookingFeeFiveMilesOrMore
    }
}

enum RydrPricing {
    static let driverPayoutShare = 0.60

    static func config(for rideType: String) -> RideTierPricing {
        switch tier(for: rideType) {
        case .eco:
            return .init(
                tier: .eco,
                title: "Rydr Eco",
                minimumRideSubtotal: 7.00,
                bookingFeeUnderFiveMiles: 3.00,
                bookingFeeFiveMilesOrMore: 5.00,
                maxPerMile: 1.00,
                maxPerMinute: 0.50
            )
        case .go:
            return .init(
                tier: .go,
                title: "Rydr Go",
                minimumRideSubtotal: 7.00,
                bookingFeeUnderFiveMiles: 3.00,
                bookingFeeFiveMilesOrMore: 6.00,
                maxPerMile: 1.00,
                maxPerMinute: 0.50
            )
        case .xl:
            return .init(
                tier: .xl,
                title: "Rydr XL",
                minimumRideSubtotal: 9.00,
                bookingFeeUnderFiveMiles: 4.00,
                bookingFeeFiveMilesOrMore: 8.00,
                maxPerMile: 2.00,
                maxPerMinute: 0.50
            )
        case .pristine:
            return .init(
                tier: .pristine,
                title: "Rydr Pristine",
                minimumRideSubtotal: 12.00,
                bookingFeeUnderFiveMiles: 5.00,
                bookingFeeFiveMilesOrMore: 10.00,
                maxPerMile: 4.00,
                maxPerMinute: 1.00
            )
        case .executive:
            return .init(
                tier: .executive,
                title: "Rydr Executive",
                minimumRideSubtotal: 18.00,
                bookingFeeUnderFiveMiles: 8.00,
                bookingFeeFiveMilesOrMore: 15.00,
                maxPerMile: 4.00,
                maxPerMinute: 1.00
            )
        }
    }

    private static func tier(for rideType: String) -> RydrRideTier {
        let key = rideType.lowercased()
        if key.contains("eco") { return .eco }
        if key.contains("xl") { return .xl }
        if key.contains("prestine") || key.contains("pristine") { return .pristine }
        if key.contains("executive") { return .executive }
        return .go
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
}

struct Receipt: Identifiable, Equatable {
    let id = UUID()
    let rideId: UUID
    let date: Date
    let driverName: String
    let pickup: String
    let dropoff: String
    let distanceMiles: Double
    let durationMinutes: Double
    let fare: Double
    let cardMasked: String
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

enum RideRequestError: LocalizedError {
    case driverTimedOut
    case noDriversAvailable

    var errorDescription: String? {
        switch self {
        case .driverTimedOut:
            return "That driver did not respond in time. Pick another nearby driver."
        case .noDriversAvailable:
            return "No nearby drivers are available right now. Try again in a moment."
        }
    }
}

protocol RideService: Sendable {
    func fetchNearbyDrivers(pickup: String, dropoff: String, rideType: String, near: CLLocationCoordinate2D) async throws -> [Driver]
    func requestRide(driverId: String, pickup: String, dropoff: String, rideType: String) async throws -> String // returns rideId
    func awaitDriverDecision(rideId: String) async throws -> DriverDecision
    func driverLocationStream(rideId: String) -> AsyncStream<CLLocationCoordinate2D>
    func cancelRide(rideId: String) async throws
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
    @Published var rideRequestErrorMessage: String?
    @Published var hasRecoveredActiveRide = false

    // Payment
    @Published var savedCards: [PaymentCard] = [
        PaymentCard(last4: "4242", brand: "Visa"),
        PaymentCard(last4: "1881", brand: "Mastercard")
    ]
    @Published var selectedCardIndex: Int = 0

    // Live locations for in-progress map/route
    @Published var liveDriverCoordinate: CLLocationCoordinate2D = .init(latitude: 33.7490, longitude: -84.3880)
    @Published var pickupCoordinate: CLLocationCoordinate2D?
    @Published var dropoffCoordinate: CLLocationCoordinate2D?
    @Published var pickupEtaSecondsRemaining: Int = 0
    @Published var destinationEtaSecondsRemaining: Int = 0
    @Published var pickupWaitSecondsRemaining: Int = 180
    @Published var paidPickupWaitSeconds: Int = 0
    @Published var pickupWaitCharge: Double = 0

    // Mock movement driver
    private var movementTimer: Timer?

    // Dependencies & tasks
    private let rideService: RideService
    private var decisionTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?

    // Internals used across steps
    private var attemptedDriverIDs: Set<String> = []
    private var cachedEstimate: RideEstimate = .init(distanceMiles: 6.2, durationMinutes: 18)
    private var cachedPickup = ""
    private var cachedDropoff = ""
    private var cachedRideType = ""
    private var cachedPickupCoordinate: CLLocationCoordinate2D?
    private var cachedDropoffCoordinate: CLLocationCoordinate2D?
    private var currentServiceRideId: String?
    private var currentAppliedRydrBankCode: String?
    private var currentBaseFare: Double = 0
    private var currentWaitChargePerMinute: Double = 0
    private let activeRideSnapshotKey = "rydr.activeRideSnapshot.v1"
    private let driverDecisionTimeoutSeconds: UInt64 = 12

    init(rideService: RideService = MockRideService()) {
        self.rideService = rideService
        restoreActiveRideIfNeeded()
    }

    deinit {
        decisionTask?.cancel()
        locationTask?.cancel()
        // do NOT call stopMovement() here — deinit is not guaranteed on MainActor
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

    // MARK: - Public API used by the UI

    /// Step 1: fetch nearest drivers (via service)
    func requestDrivers(
        pickup: String,
        dropoff: String,
        rideType: String,
        near center: CLLocationCoordinate2D,
        pickupCoordinate: CLLocationCoordinate2D? = nil,
        dropoffCoordinate: CLLocationCoordinate2D? = nil,
        estimate: RideEstimate? = nil
    ) {
        cachedPickup = pickup
        cachedDropoff = dropoff
        cachedRideType = rideType
        cachedPickupCoordinate = pickupCoordinate
        cachedDropoffCoordinate = dropoffCoordinate
        cachedEstimate = estimate ?? estimateFor(pickup: pickup, dropoff: dropoff)

        attemptedDriverIDs.removeAll()
        selectedDriver = nil
        rideRequestErrorMessage = nil
        isLoadingDrivers = true
        state = .selecting

        Task {
            do {
                let drivers = try await rideService.fetchNearbyDrivers(pickup: pickup, dropoff: dropoff, rideType: rideType, near: center)
                self.availableDrivers = drivers
                self.isLoadingDrivers = false
                if drivers.isEmpty {
                    self.rideRequestErrorMessage = RideRequestError.noDriversAvailable.localizedDescription
                }
            } catch {
                self.availableDrivers = []
                self.isLoadingDrivers = false
                self.rideRequestErrorMessage = error.localizedDescription
            }
        }
    }

    /// Step 2: user taps a driver; send request, await accept/decline.
    func confirm(driver: Driver) {
        selectedDriver = driver
        attemptedDriverIDs.insert(driver.id)
        rideRequestErrorMessage = nil
        state = .awaitingDriver

        decisionTask?.cancel()
        decisionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let rideId = try await rideService.requestRide(
                    driverId: driver.id,
                    pickup: cachedPickup,
                    dropoff: cachedDropoff,
                    rideType: cachedRideType
                )
                self.currentServiceRideId = rideId
                let code = self.normalizedSavedPromoCode()
                self.currentAppliedRydrBankCode = code.isEmpty ? nil : code

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

    /// Driver accepted – seed an example route and start the mock movement.
    func handleAccept() {
        guard let driver = selectedDriver else { return }

        // Compute rider fare with caps, platform minimum subtotal, booking fee, and promo.
        let fareBeforePromo = rawFare(estimate: cachedEstimate, with: driver, rideType: cachedRideType)
        let fareAfterPromo = currentAppliedRydrBankCode == nil ? applyPromo(to: fareBeforePromo) : 0
        currentBaseFare = fareAfterPromo
        currentWaitChargePerMinute = cappedWaitRate(for: driver, rideType: cachedRideType)

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
        pickupEtaSecondsRemaining = max(60, Int((cachedEstimate.durationMinutes * 0.4 * 60).rounded()))
        destinationEtaSecondsRemaining = max(60, Int((cachedEstimate.durationMinutes * 0.6 * 60).rounded()))
        pickupWaitSecondsRemaining = 180
        paidPickupWaitSeconds = 0
        pickupWaitCharge = 0
        startDriverMovement()
        state = .inProgress
        persistActiveRideSnapshot()
    }

    /// If driver declines, take user back to selection (remove that driver).
    func handleDecline(message: String? = nil) {
        if let declined = selectedDriver {
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
        guard let ride = currentRide else { return }

        switch ride.status {
        case .enRouteToPickup, .waitingForRider:
            cancelBeforePickupAndReturnToSelection()
        case .enRouteToDropoff:
            cancelMidRideAndComplete()
        default:
            cancelAll()
        }
    }

    /// Complete ride -> create receipt + push to history.
    func completeRide() {
        locationTask?.cancel()
        locationTask = nil

        guard let ride = currentRide else { return }
        let card = savedCards[min(selectedCardIndex, savedCards.count - 1)]
        let receipt = Receipt(
            rideId: ride.id,
            date: Date(),
            driverName: ride.driver.name,
            pickup: ride.pickup,
            dropoff: ride.dropoff,
            distanceMiles: ride.estimate.distanceMiles,
            durationMinutes: ride.estimate.durationMinutes,
            fare: ride.fare,
            cardMasked: "\(card.brand) ••\(card.last4)"
        )
        lastReceipt = receipt
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
        stopMovement()
        clearActiveRideSnapshot()
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
        }
    }

    func cancelAll() {
        decisionTask?.cancel()
        locationTask?.cancel()
        let chatContext = activeRideChatContext
        stopMovement()
        currentRide = nil
        selectedDriver = nil
        currentServiceRideId = nil
        currentBaseFare = 0
        currentWaitChargePerMinute = 0
        releaseAppliedRydrBankCodeIfNeeded()
        clearActiveRideSnapshot()
        state = .cancelled
        closeRideChatIfNeeded(chatContext)
    }

    // MARK: - Mock movement & helpers

    /// Drive the marker along a two-leg route (start→pickup, pickup→dropoff).
    private func startDriverMovement() {
        stopMovement()
        guard let ride = currentRide,
              let pickup = pickupCoordinate,
              let drop   = dropoffCoordinate else { return }

        let start = ride.driver.coordinate
        let pickupDurationTicks = 28
        let waitDurationTicks = 8
        let paidWaitDurationTicks = 6
        let dropoffDurationTicks = 34
        let pickupEtaStart = max(60, pickupEtaSecondsRemaining)
        let destinationEtaStart = max(60, destinationEtaSecondsRemaining)
        var tick = 0

        movementTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { return }
            tick += 1

            // Ensure we mutate @Published state on the main actor.
            Task { @MainActor in
                if tick <= pickupDurationTicks {
                    let progress = Double(tick) / Double(pickupDurationTicks)
                    self.liveDriverCoordinate = self.interpolate(from: start, to: pickup, t: progress)
                    self.pickupEtaSecondsRemaining = max(0, Int(Double(pickupEtaStart) * (1 - progress)))
                } else if tick <= pickupDurationTicks + waitDurationTicks {
                    self.liveDriverCoordinate = pickup
                    self.pickupEtaSecondsRemaining = 0
                    self.currentRide?.status = .waitingForRider
                    let waitProgress = Double(tick - pickupDurationTicks) / Double(waitDurationTicks)
                    self.pickupWaitSecondsRemaining = max(0, Int(180.0 * (1 - waitProgress)))
                    self.updatePaidPickupWait(seconds: 0)
                    self.persistActiveRideSnapshot()
                } else if tick <= pickupDurationTicks + waitDurationTicks + paidWaitDurationTicks {
                    self.liveDriverCoordinate = pickup
                    self.pickupEtaSecondsRemaining = 0
                    self.currentRide?.status = .waitingForRider
                    self.pickupWaitSecondsRemaining = 0
                    let paidProgress = Double(tick - pickupDurationTicks - waitDurationTicks) / Double(paidWaitDurationTicks)
                    self.updatePaidPickupWait(seconds: Int((paidProgress * 120.0).rounded()))
                    self.persistActiveRideSnapshot()
                } else {
                    if self.currentRide?.status == .waitingForRider {
                        self.markRiderPickedUp()
                    }
                    let dropoffTick = tick - pickupDurationTicks - waitDurationTicks
                    let progress = min(1.0, Double(dropoffTick) / Double(dropoffDurationTicks))
                    self.liveDriverCoordinate = self.interpolate(from: pickup, to: drop, t: progress)
                    self.destinationEtaSecondsRemaining = max(0, Int(Double(destinationEtaStart) * (1 - progress)))
                    self.persistActiveRideSnapshot()
                    if progress >= 1.0 {
                        timer.invalidate()
                        self.completeRide()
                    }
                }
            }
        }
        if let movementTimer { RunLoop.main.add(movementTimer, forMode: .common) }
    }

    private func stopMovement() {
        movementTimer?.invalidate()
        movementTimer = nil
    }

    private func interpolate(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, t: Double) -> CLLocationCoordinate2D {
        let clamped = max(0, min(1, t))
        let lat = a.latitude * (1 - clamped) + b.latitude * clamped
        let lon = a.longitude * (1 - clamped) + b.longitude * clamped
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: - Estimation / Pricing

    private func estimateFor(pickup: String, dropoff: String) -> RideEstimate {
        // Deterministic placeholder so the UI feels stable
        let base: Double = 5.0
        let pm = abs(pickup.hashValue  % 7)
        let dm = abs(dropoff.hashValue % 9)
        let miles   = base + Double(pm + dm) * 0.7       // ~5–15 mi
        let minutes = miles * 3.0                         // ~15–45 min
        return RideEstimate(distanceMiles: (miles * 10).rounded()/10, durationMinutes: round(minutes))
    }

    static func pricingConfig(for rideType: String) -> RideTierPricing {
        RydrPricing.config(for: rideType)
    }

    static func fareBreakdown(estimate: RideEstimate, with driver: Driver, rideType: String) -> RideFareBreakdown {
        let pricing = RydrPricing.config(for: rideType)
        let perMile = min(driver.perMile, pricing.maxPerMile)
        let perMinute = min(driver.perMinute, pricing.maxPerMinute)
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

    func markRiderPickedUp() {
        guard currentRide?.status == .waitingForRider else { return }
        currentRide?.status = .enRouteToDropoff
        destinationEtaSecondsRemaining = max(60, Int(((currentRide?.estimate.durationMinutes ?? cachedEstimate.durationMinutes) * 0.6 * 60).rounded()))
        persistActiveRideSnapshot()
    }

    private func updatePaidPickupWait(seconds: Int) {
        paidPickupWaitSeconds = max(0, seconds)
        let minutes = Double(paidPickupWaitSeconds) / 60.0
        pickupWaitCharge = ((minutes * currentWaitChargePerMinute) * 100).rounded() / 100
        currentRide?.fare = ((currentBaseFare + pickupWaitCharge) * 100).rounded() / 100
    }

    private func cancelBeforePickupAndReturnToSelection() {
        locationTask?.cancel()
        decisionTask?.cancel()
        let chatContext = activeRideChatContext
        stopMovement()

        if let selectedDriver {
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
        clearActiveRideSnapshot()

        if availableDrivers.isEmpty {
            requestDrivers(pickup: cachedPickup, dropoff: cachedDropoff, rideType: cachedRideType, near: liveDriverCoordinate)
        } else {
            state = .selecting
        }

        Task {
            if let id = cancelledServiceRideId {
                try? await rideService.cancelRide(rideId: id)
            }
        }
        closeRideChatIfNeeded(chatContext)
    }

    private func cancelMidRideAndComplete() {
        guard let ride = currentRide else { return }
        let chatContext = activeRideChatContext

        locationTask?.cancel()
        decisionTask?.cancel()
        stopMovement()

        let totalSeconds = max(1, Int((ride.estimate.durationMinutes * 0.6 * 60).rounded()))
        let traveledFraction = max(0.1, min(0.95, 1.0 - (Double(destinationEtaSecondsRemaining) / Double(totalSeconds))))
        let proratedDistance = ((ride.estimate.distanceMiles * traveledFraction) * 10).rounded() / 10
        let proratedMinutes = max(1, (ride.estimate.durationMinutes * 0.6 * traveledFraction).rounded())
        let proratedFare = ((ride.fare * traveledFraction) * 100).rounded() / 100
        let card = savedCards[min(selectedCardIndex, savedCards.count - 1)]

        lastReceipt = Receipt(
            rideId: ride.id,
            date: Date(),
            driverName: ride.driver.name,
            pickup: ride.pickup,
            dropoff: ride.dropoff,
            distanceMiles: proratedDistance,
            durationMinutes: proratedMinutes,
            fare: proratedFare,
            cardMasked: "\(card.brand) ••\(card.last4)"
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
        releaseAppliedRydrBankCodeIfNeeded()
        clearActiveRideSnapshot()
        state = .completed
        closeRideChatIfNeeded(chatContext)
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
        min(driver.perMinute, Self.pricingConfig(for: rideType).maxPerMinute)
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
                score: score
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
        state = .inProgress
        hasRecoveredActiveRide = true
    }
}
