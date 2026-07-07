import CoreLocation
import FirebaseFirestore
import MapKit

struct DriverVisibleRidePreferences: Equatable, Identifiable {
    let summaryItems: [String]
    let summaryText: String

    var id: String { summaryText }

    nonisolated var isEmpty: Bool {
        summaryItems.isEmpty && summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated init?(data: Any?) {
        guard let data = data as? [String: Any] else { return nil }
        let items = data["summaryItems"] as? [String] ?? []
        let text = data["summaryText"] as? String ?? items.joined(separator: "\n")
        summaryItems = items
        summaryText = text
        if isEmpty { return nil }
    }
}

struct DriverRideRequest: Identifiable, Equatable {
    let id: String
    let riderId: String
    let riderName: String
    let riderPhotoURL: String?
    let riderRating: Double?
    let riderVerified: Bool
    let pickup: String
    let dropoff: String
    let rideType: String
    let estimatedFare: Double?
    let estimatedDriverPayout: Double?
    let estimatedDistanceMiles: Double?
    let estimatedDurationMinutes: Double?
    let pickupCoordinate: CLLocationCoordinate2D?
    let stop: String?
    let stopCoordinate: CLLocationCoordinate2D?
    let dropoffCoordinate: CLLocationCoordinate2D?
    let createdAt: Date?
    let ridePreferences: DriverVisibleRidePreferences?

    init(
        id: String,
        riderId: String,
        riderName: String,
        riderPhotoURL: String? = nil,
        riderRating: Double? = nil,
        riderVerified: Bool = false,
        pickup: String,
        dropoff: String,
        rideType: String,
        estimatedFare: Double? = nil,
        estimatedDriverPayout: Double? = nil,
        estimatedDistanceMiles: Double? = nil,
        estimatedDurationMinutes: Double? = nil,
        pickupCoordinate: CLLocationCoordinate2D? = nil,
        stop: String? = nil,
        stopCoordinate: CLLocationCoordinate2D? = nil,
        dropoffCoordinate: CLLocationCoordinate2D? = nil,
        createdAt: Date? = nil,
        ridePreferences: DriverVisibleRidePreferences? = nil
    ) {
        self.id = id
        self.riderId = riderId
        self.riderName = riderName
        self.riderPhotoURL = riderPhotoURL
        self.riderRating = riderRating
        self.riderVerified = riderVerified
        self.pickup = pickup
        self.dropoff = dropoff
        self.rideType = rideType
        self.estimatedFare = estimatedFare
        self.estimatedDriverPayout = estimatedDriverPayout
        self.estimatedDistanceMiles = estimatedDistanceMiles
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.pickupCoordinate = pickupCoordinate
        self.stop = stop
        self.stopCoordinate = stopCoordinate
        self.dropoffCoordinate = dropoffCoordinate
        self.createdAt = createdAt
        self.ridePreferences = ridePreferences
    }

    nonisolated init(document: QueryDocumentSnapshot) {
        let data = document.data()
        id = document.documentID
        riderId = data["riderId"] as? String ?? ""
        riderName = data["riderName"] as? String ?? "Rydr rider"
        riderPhotoURL = data["riderPhotoURL"] as? String ?? data["riderProfilePhotoURL"] as? String
        riderRating = Self.doubleValue(data["riderRating"] ?? data["riderAverageRating"])
        riderVerified = data["riderVerified"] as? Bool ?? data["verifiedRider"] as? Bool ?? false
        pickup = data["pickup"] as? String ?? "Pickup location"
        dropoff = data["dropoff"] as? String ?? "Drop-off location"
        rideType = data["rideType"] as? String ?? "Rydr"
        estimatedFare = Self.doubleValue(data["estimatedFare"] ?? data["upfrontFare"])
        estimatedDriverPayout = Self.dollarsFromCents(data["estimatedDriverPayoutCents"] ?? data["driverPayoutCents"])
            ?? Self.doubleValue(data["estimatedDriverPayout"] ?? data["driverPayout"])
            ?? estimatedFare
        estimatedDistanceMiles = Self.doubleValue(data["estimatedDistanceMiles"] ?? data["distanceMiles"])
        estimatedDurationMinutes = Self.doubleValue(data["estimatedDurationMinutes"] ?? data["durationMinutes"])
        pickupCoordinate = Self.coordinate(from: data["pickupCoordinate"] ?? data["pickupLocation"] ?? data["pickupGeoPoint"])
        stop = data["stop"] as? String ?? data["addedStop"] as? String ?? data["stopAddress"] as? String
        stopCoordinate = Self.coordinate(from: data["stopCoordinate"] ?? data["addedStopCoordinate"] ?? data["stopLocation"] ?? data["stopGeoPoint"])
        dropoffCoordinate = Self.coordinate(from: data["dropoffCoordinate"] ?? data["dropoffLocation"] ?? data["dropoffGeoPoint"])
        createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        ridePreferences = DriverVisibleRidePreferences(data: data["ridePreferences"])
    }

    static func == (lhs: DriverRideRequest, rhs: DriverRideRequest) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated private static func coordinate(from value: Any?) -> CLLocationCoordinate2D? {
        if let point = value as? GeoPoint {
            return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        }
        guard let data = value as? [String: Any] else { return nil }
        let lat = doubleValue(data["lat"] ?? data["latitude"])
        let lng = doubleValue(data["lng"] ?? data["longitude"])
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    nonisolated private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    nonisolated private static func dollarsFromCents(_ value: Any?) -> Double? {
        guard let cents = doubleValue(value) else { return nil }
        return cents / 100.0
    }
}

struct DriverRideRadarBlip: Identifiable, Equatable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }

    static func == (lhs: DriverRideRadarBlip, rhs: DriverRideRadarBlip) -> Bool {
        lhs.id == rhs.id
    }
}

enum DriverDemandLevel {
    case low
    case moderate
    case high
}

struct DriverDemandSnapshot {
    var level: DriverDemandLevel = .low
    var paceText: String = "5+ min since last request"
    var nearbyRequestCount: Int = 0
    var radiusMiles: Double = 5

    var title: String {
        switch level {
        case .low: return "Low demand nearby"
        case .moderate: return "Moderate demand nearby"
        case .high: return "High demand nearby"
        }
    }
}

struct DriverActiveRide: Identifiable, Equatable {
    static let pickupComplimentaryWaitSeconds = DriverRideLifecyclePolicy.pickupComplimentaryWaitSeconds

    let id: String
    let riderId: String
    let riderName: String
    let riderRating: Double?
    let pickup: String
    let dropoff: String
    let rideType: String
    let status: String
    let estimatedFare: Double?
    let estimatedDistanceMiles: Double?
    let estimatedDurationMinutes: Double?
    let pickupCoordinate: CLLocationCoordinate2D?
    let stop: String?
    let stopCoordinate: CLLocationCoordinate2D?
    let dropoffCoordinate: CLLocationCoordinate2D?
    let arrivedAtPickupAt: Date?
    let pickupWaitStartedAt: Date?
    let pickupPaidWaitStartedAt: Date?
    let rideStartedAt: Date?
    let arrivedAtStopAt: Date?
    let stopWaitStartedAt: Date?
    let headedToDropoffAt: Date?
    /// Backend-owned (stripe-backend), never written by the driver app.
    /// "pending" | "processing" | "succeeded" | "failed" | "refunded" — see
    /// PAYMENT_STATUSES in stripe-backend/index.js. Lets the driver-facing
    /// completion screen show "Awaiting Rider Payment" instead of implying
    /// the fare has already settled.
    let paymentStatus: String?
    let paymentFailureReason: String?
    let paymentFailureCode: String?
    let paymentRetryCount: Int
    let ridePreferences: DriverVisibleRidePreferences?

    var normalizedStatus: String {
        DriverRideLifecyclePolicy.normalizedStatus(status)
    }

    var isPickupStage: Bool {
        ["accepted", "enRouteToPickup", "navigatingToPickup", "arrived", "arrivedAtPickup", "waitingForRider"].contains(status)
    }

    var hasAddedStop: Bool {
        stop?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || stopCoordinate != nil
    }

    static func == (lhs: DriverActiveRide, rhs: DriverActiveRide) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
    }

    nonisolated init(id: String, data: [String: Any]) {
        self.id = id
        riderId = data["riderId"] as? String ?? ""
        riderName = data["riderName"] as? String ?? "Rydr rider"
        riderRating = Self.doubleValue(data["riderRating"] ?? data["riderAverageRating"])
        pickup = data["pickup"] as? String ?? "Pickup location"
        dropoff = data["dropoff"] as? String ?? "Drop-off location"
        rideType = data["rideType"] as? String ?? "Rydr"
        status = data["status"] as? String ?? "accepted"
        estimatedFare = Self.doubleValue(data["estimatedFare"] ?? data["upfrontFare"] ?? data["fare"])
            ?? Self.dollarsFromCents(data["estimatedDriverPayoutCents"] ?? data["driverPayoutCents"])
        estimatedDistanceMiles = Self.doubleValue(data["estimatedDistanceMiles"] ?? data["distanceMiles"])
        estimatedDurationMinutes = Self.doubleValue(data["estimatedDurationMinutes"] ?? data["durationMinutes"])
        pickupCoordinate = Self.coordinate(from: data["pickupCoordinate"] ?? data["pickupLocation"] ?? data["pickupGeoPoint"])
        stop = data["stop"] as? String ?? data["addedStop"] as? String ?? data["stopAddress"] as? String
        stopCoordinate = Self.coordinate(from: data["stopCoordinate"] ?? data["addedStopCoordinate"] ?? data["stopLocation"] ?? data["stopGeoPoint"])
        dropoffCoordinate = Self.coordinate(from: data["dropoffCoordinate"] ?? data["dropoffLocation"] ?? data["dropoffGeoPoint"])
        arrivedAtPickupAt = Self.dateValue(data["arrivedAtPickupAt"])
        pickupWaitStartedAt = Self.dateValue(data["pickupWaitStartedAt"])
        pickupPaidWaitStartedAt = Self.dateValue(data["pickupPaidWaitStartedAt"])
        rideStartedAt = Self.dateValue(data["rideStartedAt"] ?? data["startedAt"])
        arrivedAtStopAt = Self.dateValue(data["arrivedAtStopAt"])
        stopWaitStartedAt = Self.dateValue(data["stopWaitStartedAt"])
        headedToDropoffAt = Self.dateValue(data["headedToDropoffAt"])
        paymentStatus = data["paymentStatus"] as? String
        paymentFailureReason = data["failureReason"] as? String
        paymentFailureCode = data["failureCode"] as? String
        paymentRetryCount = Self.intValue(data["retryCount"]) ?? 0
        ridePreferences = DriverVisibleRidePreferences(data: data["ridePreferences"])
    }

    nonisolated private static func coordinate(from value: Any?) -> CLLocationCoordinate2D? {
        if let point = value as? GeoPoint {
            return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        }
        guard let data = value as? [String: Any] else { return nil }
        let lat = doubleValue(data["lat"] ?? data["latitude"])
        let lng = doubleValue(data["lng"] ?? data["longitude"])
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    nonisolated private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    nonisolated private static func dollarsFromCents(_ value: Any?) -> Double? {
        guard let cents = doubleValue(value) else { return nil }
        return cents / 100.0
    }

    nonisolated private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let double = value as? Double { return Int(double) }
        return nil
    }

    nonisolated private static func dateValue(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let date = value as? Date { return date }
        return nil
    }
}

enum DriverMapDefaults {
    static let pilotCoordinate = CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880)
    static let pilotRegion = MKCoordinateRegion(
        center: pilotCoordinate,
        span: .init(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )
    static let pilotLocation = CLLocation(latitude: pilotCoordinate.latitude, longitude: pilotCoordinate.longitude)
}
