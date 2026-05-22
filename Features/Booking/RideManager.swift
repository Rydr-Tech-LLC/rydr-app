//
//  Driver.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 8/24/25.
//
import SwiftUI
import MapKit
import CoreLocation

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

struct RideEstimate: Equatable {
    var distanceMiles: Double
    var durationMinutes: Double
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
    enum Status { case enRouteToPickup, enRouteToDropoff, completed, cancelled }
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

// MARK: - Service protocol
enum DriverDecision { case accepted, declined }

protocol RideService {
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
    private var currentServiceRideId: String?
    private var currentAppliedRydrBankCode: String?

    init(rideService: RideService = MockRideService()) {
        self.rideService = rideService
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
        case .enRouteToPickup:  return max(1, (ride.estimate.durationMinutes * 0.4).rounded())
        case .enRouteToDropoff: return max(1, (ride.estimate.durationMinutes * 0.6).rounded())
        default: return 0
        }
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
    func requestDrivers(pickup: String, dropoff: String, rideType: String, near center: CLLocationCoordinate2D) {
        cachedPickup = pickup
        cachedDropoff = dropoff
        cachedRideType = rideType
        cachedEstimate = estimateFor(pickup: pickup, dropoff: dropoff)

        attemptedDriverIDs.removeAll()
        selectedDriver = nil
        state = .selecting

        Task {
            do {
                let drivers = try await rideService.fetchNearbyDrivers(pickup: pickup, dropoff: dropoff, rideType: rideType, near: center)
                self.availableDrivers = drivers
            } catch {
                self.availableDrivers = []
            }
        }
    }

    /// Step 2: user taps a driver; send request, await accept/decline.
    func confirm(driver: Driver) {
        selectedDriver = driver
        attemptedDriverIDs.insert(driver.id)
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

                let decision = try await rideService.awaitDriverDecision(rideId: rideId)
                switch decision {
                case .accepted:
                    self.handleAccept()
                case .declined:
                    self.handleDecline()
                }
            } catch {
                self.handleDecline()
            }
        }
    }

    /// Driver accepted – seed an example route and start the mock movement.
    func handleAccept() {
        guard let driver = selectedDriver else { return }

        // Compute fare with caps/fee + promo
        let fareBeforePromo = rawFare(estimate: cachedEstimate, with: driver, rideType: cachedRideType)
        let fareAfterPromo = currentAppliedRydrBankCode == nil ? applyPromo(to: fareBeforePromo) : 0

        // Seed a simple two-leg path relative to driver's start
        let start  = driver.coordinate
        let pickup = CLLocationCoordinate2D(latitude: start.latitude + 0.02, longitude: start.longitude + 0.02)
        let drop   = CLLocationCoordinate2D(latitude: pickup.latitude + 0.03, longitude: pickup.longitude + 0.03)
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
        startDriverMovement()
        state = .inProgress
    }

    /// If driver declines, take user back to selection (remove that driver).
    func handleDecline() {
        if let declined = selectedDriver {
            availableDrivers.removeAll { $0.id == declined.id }
        }
        selectedDriver = nil
        state = .selecting
    }

    /// Rider cancels after acceptance → auto-bounce to next nearest (no manual selection).
    func riderCancelAndAutoReassign() {
        locationTask?.cancel()
        currentRide = nil

        Task {
            if let id = currentServiceRideId {
                try? await rideService.cancelRide(rideId: id)
            }
            currentServiceRideId = nil

            if let next = availableDrivers.first(where: { !attemptedDriverIDs.contains($0.id) }) {
                confirm(driver: next)
            } else {
                requestDrivers(pickup: cachedPickup, dropoff: cachedDropoff, rideType: cachedRideType, near: liveDriverCoordinate)
            }
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
        let appliedCode = currentAppliedRydrBankCode
        let rideType = ride.rideType
        let distance = ride.estimate.distanceMiles
        currentRide = nil
        currentServiceRideId = nil
        currentAppliedRydrBankCode = nil
        stopMovement()
        state = .completed

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
        stopMovement()
        currentRide = nil
        selectedDriver = nil
        currentServiceRideId = nil
        releaseAppliedRydrBankCodeIfNeeded()
        state = .cancelled
    }

    // MARK: - Mock movement & helpers

    /// Drive the marker along a two-leg route (start→pickup, pickup→dropoff).
    private func startDriverMovement() {
        stopMovement()
        guard let ride = currentRide,
              let pickup = pickupCoordinate,
              let drop   = dropoffCoordinate else { return }

        let start = ride.driver.coordinate
        var t: Double = 0

        movementTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { return }
            t += 0.02

            // Ensure we mutate @Published state on the main actor.
            Task { @MainActor in
                if t <= 0.5 {
                    // first leg
                    self.liveDriverCoordinate = self.interpolate(from: start, to: pickup, t: t / 0.5)
                    if t >= 0.5, self.currentRide?.status == .enRouteToPickup {
                        self.currentRide?.status = .enRouteToDropoff
                    }
                } else {
                    // second leg
                    let localT = min(1.0, (t - 0.5) / 0.5)
                    self.liveDriverCoordinate = self.interpolate(from: pickup, to: drop, t: localT)
                    if localT >= 1.0 {
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

    /// Booking fees and caps per ride type.
    private func caps(for rideType: String) -> (booking: Double, maxPerMile: Double, maxPerMinute: Double) {
        let key = rideType.lowercased()
        if key.contains("prestine") { return (8.0, 4.0, 1.0) }   // Rydr Prestine
        if key.contains("xl")       { return (5.0, 2.0, 0.5) }   // Rydr XL
        return (4.0, 1.0, 0.5)                                  // Rydr Go / Eco (default)
    }

    /// Raw fare BEFORE promo discounts (booking fee + capped variable).
    private func rawFare(estimate: RideEstimate, with driver: Driver, rideType: String) -> Double {
        let c = caps(for: rideType)
        let perMile   = min(driver.perMile,   c.maxPerMile)
        let perMinute = min(driver.perMinute, c.maxPerMinute)
        let variable = estimate.distanceMiles * perMile + estimate.durationMinutes * perMinute
        let total = c.booking + variable
        return (total * 100).rounded() / 100.0
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
}

