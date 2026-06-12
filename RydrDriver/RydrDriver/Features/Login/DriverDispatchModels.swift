import CoreLocation
import FirebaseFirestore
import MapKit

struct DriverRideRequest: Identifiable, Equatable {
    let id: String
    let riderId: String
    let riderName: String
    let riderPhotoURL: String?
    let riderRating: Double?
    let pickup: String
    let dropoff: String
    let rideType: String
    let estimatedFare: Double?
    let estimatedDistanceMiles: Double?
    let estimatedDurationMinutes: Double?
    let pickupCoordinate: CLLocationCoordinate2D?
    let dropoffCoordinate: CLLocationCoordinate2D?
    let createdAt: Date?

    init(
        id: String,
        riderId: String,
        riderName: String,
        riderPhotoURL: String? = nil,
        riderRating: Double? = nil,
        pickup: String,
        dropoff: String,
        rideType: String,
        estimatedFare: Double? = nil,
        estimatedDistanceMiles: Double? = nil,
        estimatedDurationMinutes: Double? = nil,
        pickupCoordinate: CLLocationCoordinate2D? = nil,
        dropoffCoordinate: CLLocationCoordinate2D? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.riderId = riderId
        self.riderName = riderName
        self.riderPhotoURL = riderPhotoURL
        self.riderRating = riderRating
        self.pickup = pickup
        self.dropoff = dropoff
        self.rideType = rideType
        self.estimatedFare = estimatedFare
        self.estimatedDistanceMiles = estimatedDistanceMiles
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.pickupCoordinate = pickupCoordinate
        self.dropoffCoordinate = dropoffCoordinate
        self.createdAt = createdAt
    }

    nonisolated init(document: QueryDocumentSnapshot) {
        let data = document.data()
        id = document.documentID
        riderId = data["riderId"] as? String ?? ""
        riderName = data["riderName"] as? String ?? "Rydr rider"
        riderPhotoURL = data["riderPhotoURL"] as? String ?? data["riderProfilePhotoURL"] as? String
        riderRating = Self.doubleValue(data["riderRating"] ?? data["riderAverageRating"])
        pickup = data["pickup"] as? String ?? "Pickup location"
        dropoff = data["dropoff"] as? String ?? "Drop-off location"
        rideType = data["rideType"] as? String ?? "Rydr"
        estimatedFare = Self.doubleValue(data["estimatedFare"] ?? data["upfrontFare"])
        estimatedDistanceMiles = Self.doubleValue(data["estimatedDistanceMiles"] ?? data["distanceMiles"])
        estimatedDurationMinutes = Self.doubleValue(data["estimatedDurationMinutes"] ?? data["durationMinutes"])
        pickupCoordinate = Self.coordinate(from: data["pickupCoordinate"] ?? data["pickupLocation"] ?? data["pickupGeoPoint"])
        dropoffCoordinate = Self.coordinate(from: data["dropoffCoordinate"] ?? data["dropoffLocation"] ?? data["dropoffGeoPoint"])
        createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
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

struct DriverActiveRide: Identifiable, Equatable {
    let id: String
    let riderId: String
    let riderName: String
    let pickup: String
    let dropoff: String
    let rideType: String
    let status: String
    let pickupCoordinate: CLLocationCoordinate2D?
    let dropoffCoordinate: CLLocationCoordinate2D?

    static func == (lhs: DriverActiveRide, rhs: DriverActiveRide) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
    }

    nonisolated init(id: String, data: [String: Any]) {
        self.id = id
        riderId = data["riderId"] as? String ?? ""
        riderName = data["riderName"] as? String ?? "Rydr rider"
        pickup = data["pickup"] as? String ?? "Pickup location"
        dropoff = data["dropoff"] as? String ?? "Drop-off location"
        rideType = data["rideType"] as? String ?? "Rydr"
        status = data["status"] as? String ?? "accepted"
        pickupCoordinate = Self.coordinate(from: data["pickupCoordinate"] ?? data["pickupLocation"] ?? data["pickupGeoPoint"])
        dropoffCoordinate = Self.coordinate(from: data["dropoffCoordinate"] ?? data["dropoffLocation"] ?? data["dropoffGeoPoint"])
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
}

enum DriverMapDefaults {
    static let pilotCoordinate = CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880)
    static let pilotRegion = MKCoordinateRegion(
        center: pilotCoordinate,
        span: .init(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )
    static let pilotLocation = CLLocation(latitude: pilotCoordinate.latitude, longitude: pilotCoordinate.longitude)
}
