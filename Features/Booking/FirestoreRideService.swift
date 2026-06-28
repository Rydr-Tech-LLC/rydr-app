//
//  FirestoreRideService.swift
//  RydrPlayground
//
//  Firestore-backed standard ride dispatch service.
//

import Foundation
import CoreLocation
import CoreGraphics
import FirebaseAuth
import FirebaseFirestore

final class FirestoreRideService: RideService, @unchecked Sendable {
    private let db = Firestore.firestore()

    func fetchNearbyDrivers(
        pickup: String,
        dropoff: String,
        rideType: String,
        near center: CLLocationCoordinate2D,
        pickupCoordinate: CLLocationCoordinate2D?,
        dropoffCoordinate: CLLocationCoordinate2D?
    ) async throws -> [Driver] {
        let snapshot = try await db.collection("publicDriverProfiles")
            .whereField("isOnline", isEqualTo: true)
            .getDocuments()

        return snapshot.documents
            .compactMap { document in
                driver(
                    from: document,
                    rideType: rideType,
                    near: center,
                    pickupCoordinate: pickupCoordinate,
                    dropoffCoordinate: dropoffCoordinate
                )
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.rating > rhs.rating }
                return lhs.score > rhs.score
            }
            .prefix(8)
            .map { $0 }
    }

    func requestRide(
        driverId: String,
        pickup: String,
        dropoff: String,
        rideType: String,
        pickupCoordinate: CLLocationCoordinate2D?,
        dropoffCoordinate: CLLocationCoordinate2D?,
        estimate: RideEstimate?
    ) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw RideDispatchError.notSignedIn
        }

        let id = UUID().uuidString
        let riderName = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        var payload: [String: Any] = [
            "id": id,
            "driverId": driverId,
            "riderId": user.uid,
            "riderName": riderName?.isEmpty == false ? riderName! : "Rydr rider",
            "riderPhotoURL": user.photoURL?.absoluteString ?? "",
            "pickup": pickup,
            "dropoff": dropoff,
            "rideType": rideType,
            "status": "pending",
            "source": "standardRydr",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let pickupCoordinate {
            payload["pickupCoordinate"] = [
                "lat": pickupCoordinate.latitude,
                "lng": pickupCoordinate.longitude
            ]
            payload["pickupGeoPoint"] = GeoPoint(latitude: pickupCoordinate.latitude, longitude: pickupCoordinate.longitude)
        }
        if let dropoffCoordinate {
            payload["dropoffCoordinate"] = [
                "lat": dropoffCoordinate.latitude,
                "lng": dropoffCoordinate.longitude
            ]
            payload["dropoffGeoPoint"] = GeoPoint(latitude: dropoffCoordinate.latitude, longitude: dropoffCoordinate.longitude)
        }
        if let estimate {
            payload["estimatedDistanceMiles"] = estimate.distanceMiles
            payload["estimatedDurationMinutes"] = estimate.durationMinutes
        }

        try await db.collection("rideRequests").document(id).setData(payload)
        return id
    }

    func awaitDriverDecision(rideId: String) async throws -> DriverDecision {
        let stream = AsyncThrowingStream<DriverDecision, Error> { continuation in
            let listener = db.collection("rideRequests").document(rideId)
                .addSnapshotListener { snapshot, error in
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }

                    let status = (snapshot?.data()?["status"] as? String ?? "").lowercased()
                    switch status {
                    case "accepted":
                        continuation.yield(.accepted)
                        continuation.finish()
                    case "declined", "drivercancelled", "cancelled":
                        continuation.yield(.declined)
                        continuation.finish()
                    default:
                        break
                    }
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }

        for try await decision in stream {
            return decision
        }
        throw CancellationError()
    }

    func driverLocationStream(rideId: String) -> AsyncStream<CLLocationCoordinate2D> {
        AsyncStream { continuation in
            let listener = db.collection("rides").document(rideId)
                .addSnapshotListener { snapshot, _ in
                    guard let data = snapshot?.data(),
                          let location = data["driverLocation"] as? [String: Any],
                          let lat = location["lat"] as? CLLocationDegrees,
                          let lng = location["lng"] as? CLLocationDegrees else {
                        return
                    }
                    continuation.yield(CLLocationCoordinate2D(latitude: lat, longitude: lng))
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func rideLifecycleStream(rideId: String) -> AsyncThrowingStream<RideLifecycleSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let listener = db.collection("rides").document(rideId)
                .addSnapshotListener { snapshot, error in
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }

                    guard let data = snapshot?.data() else { return }
                    let snapshot = RideLifecycleSnapshot(
                        status: Self.rideStatus(from: data["status"] as? String),
                        driverCoordinate: Self.coordinate(from: data["driverLocation"]),
                        pickupCoordinate: Self.coordinate(from: data["pickupCoordinate"]) ?? Self.coordinate(from: data["pickupGeoPoint"]),
                        dropoffCoordinate: Self.coordinate(from: data["dropoffCoordinate"]) ?? Self.coordinate(from: data["dropoffGeoPoint"])
                    )
                    continuation.yield(snapshot)

                    if snapshot.status == .completed || snapshot.status == .cancelled {
                        continuation.finish()
                    }
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func cancelRide(rideId: String) async throws {
        let update: [String: Any] = [
            "status": "riderCancelled",
            "cancelledAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        try await db.collection("rideRequests").document(rideId).setData(update, merge: true)
        try await db.collection("rides").document(rideId).setData(update, merge: true)
    }

    private func driver(
        from document: QueryDocumentSnapshot,
        rideType: String,
        near center: CLLocationCoordinate2D,
        pickupCoordinate: CLLocationCoordinate2D?,
        dropoffCoordinate: CLLocationCoordinate2D?
    ) -> Driver? {
        let data = document.data()
        let enabled = data["standardDispatchEnabled"] as? Bool ?? true
        guard enabled else { return nil }

        let supportedRideTypes = data["eligibleRideTypes"] as? [String]
            ?? data["selectedRideTypes"] as? [String]
            ?? data["rideTypes"] as? [String]
            ?? data["supportedRideTypes"] as? [String]
            ?? []
        if !supportedRideTypes.isEmpty, !supportedRideTypes.contains(where: { matches($0, rideType) }) {
            return nil
        }

        guard let coordinate = coordinate(from: data) else { return nil }
        let distance = CLLocation(latitude: center.latitude, longitude: center.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) / 1609.344
        guard distance <= 30 else { return nil }
        guard matchesDriverRideFilters(
            data["rideFilters"] as? [String: Any],
            driverCoordinate: coordinate,
            pickupCoordinate: pickupCoordinate ?? center,
            dropoffCoordinate: dropoffCoordinate
        ) else { return nil }

        let rating = data["rating"] as? Double ?? 4.85
        let pricing = RydrPricing.config(for: rideType)
        let rate = driverRate(from: data, rideType: rideType, pricing: pricing)
        let score = max(1, min(100, Int(100 - (distance * 6) + ((rating - 4.5) * 18))))

        return Driver(
            id: document.documentID,
            name: driverName(from: data),
            profileImage: data["profilePhotoURL"] as? String ?? data["profileImage"] as? String,
            // "vehicleImageURL" is written by the Vehicle Library System
            // (RydrDriver's DriverDashboardVM.publishPublicDriverProfile) —
            // the generic factory-style image matched from the driver's
            // decoded VIN + chosen color, never a photo of their actual car.
            // "carImage" is kept for backward compatibility with any older
            // writer of this field.
            carImage: data["carImage"] as? String ?? data["vehicleImageURL"] as? String,
            carMakeModel: vehicleName(from: data),
            rating: rating,
            compliments: data["compliments"] as? [String] ?? ["Professional", "Clean Car", "Reliable"],
            perMinute: rate.perMinute,
            perMile: rate.perMile,
            coordinate: coordinate,
            score: score,
            stripeAccountId: data["stripeAccountId"] as? String,
            stripeChargesEnabled: data["stripeChargesEnabled"] as? Bool ?? false
        )
    }

    private static func rideStatus(from rawStatus: String?) -> Ride.Status? {
        switch rawStatus?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "accepted", "enRouteToPickup", "navigatingToPickup":
            return .enRouteToPickup
        case "arrived", "arrivedAtPickup", "waitingForRider":
            return .waitingForRider
        case "inProgress", "navigatingToStop", "arrivedAtStop", "waitingAtStop":
            return .enRouteToDropoff
        case "completed":
            return .completed
        case "cancelled", "riderCancelled", "driverCancelled":
            return .cancelled
        default:
            return nil
        }
    }

    private static func coordinate(from raw: Any?) -> CLLocationCoordinate2D? {
        if let geoPoint = raw as? GeoPoint {
            return CLLocationCoordinate2D(latitude: geoPoint.latitude, longitude: geoPoint.longitude)
        }
        guard let data = raw as? [String: Any] else { return nil }
        let lat = number(data["lat"] ?? data["latitude"])
        let lng = number(data["lng"] ?? data["longitude"])
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private static func number(_ raw: Any?) -> CLLocationDegrees? {
        if let value = raw as? CLLocationDegrees { return value }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    private func matchesDriverRideFilters(
        _ filters: [String: Any]?,
        driverCoordinate: CLLocationCoordinate2D,
        pickupCoordinate: CLLocationCoordinate2D,
        dropoffCoordinate: CLLocationCoordinate2D?
    ) -> Bool {
        guard let filters else { return true }

        if (filters["workZoneEnabled"] as? Bool) == true {
            let radiusMiles = doubleValue(filters["workZoneRadiusMiles"]) ?? 0
            let pickupMiles = CLLocation(latitude: driverCoordinate.latitude, longitude: driverCoordinate.longitude)
                .distance(from: CLLocation(latitude: pickupCoordinate.latitude, longitude: pickupCoordinate.longitude)) / 1609.344
            guard radiusMiles > 0, pickupMiles <= radiusMiles else { return false }
        }

        guard (filters["destinationModeEnabled"] as? Bool) == true,
              let destinationCoordinate = coordinate(from: filters["destinationCoordinate"] ?? filters["destinationGeoPoint"]) else {
            return true
        }

        guard let dropoffCoordinate else { return false }
        let progress = projectedRouteProgress(point: dropoffCoordinate, start: driverCoordinate, end: destinationCoordinate)
        guard progress >= 0, progress <= 1 else { return false }

        let pickupLocation = CLLocation(latitude: pickupCoordinate.latitude, longitude: pickupCoordinate.longitude)
        let dropoffLocation = CLLocation(latitude: dropoffCoordinate.latitude, longitude: dropoffCoordinate.longitude)
        let destinationLocation = CLLocation(latitude: destinationCoordinate.latitude, longitude: destinationCoordinate.longitude)
        let pickupToDestinationMiles = pickupLocation.distance(from: destinationLocation) / 1609.344
        let dropoffToDestinationMiles = dropoffLocation.distance(from: destinationLocation) / 1609.344
        let corridorMiles = distanceFromPointToSegmentMiles(point: dropoffCoordinate, start: driverCoordinate, end: destinationCoordinate)
        let allowedCorridorMiles = doubleValue(filters["destinationCorridorMiles"]) ?? 5

        return dropoffToDestinationMiles <= pickupToDestinationMiles
            && corridorMiles <= allowedCorridorMiles
    }

    private func driverRate(
        from data: [String: Any],
        rideType: String,
        pricing: RideTierPricing
    ) -> (perMile: Double, perMinute: Double) {
        let tierRates = data["tierRates"] as? [String: Any]
        let canonical = canonicalRideType(rideType)
        let rawRate = tierRates?[canonical] as? [String: Any]
            ?? tierRates?[pricing.title] as? [String: Any]
        let rawPerMile = doubleValue(rawRate?["perMile"]) ?? doubleValue(data["perMile"]) ?? pricing.minPerMile
        let rawPerMinute = doubleValue(rawRate?["perMinute"]) ?? doubleValue(data["perMinute"]) ?? pricing.minPerMinute
        return (
            perMile: pricing.clampedPerMile(rawPerMile),
            perMinute: pricing.clampedPerMinute(rawPerMinute)
        )
    }

    private func coordinate(from data: [String: Any]) -> CLLocationCoordinate2D? {
        if let point = data["geoPoint"] as? GeoPoint {
            return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        }
        if let location = data["approximateLocation"] as? [String: Any],
           let lat = location["lat"] as? CLLocationDegrees,
           let lng = location["lng"] as? CLLocationDegrees {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        if let location = data["location"] as? [String: Any],
           let lat = location["lat"] as? CLLocationDegrees,
           let lng = location["lng"] as? CLLocationDegrees {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        if let lat = data["lat"] as? CLLocationDegrees,
           let lng = data["lng"] as? CLLocationDegrees {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return nil
    }

    private func coordinate(from value: Any?) -> CLLocationCoordinate2D? {
        if let point = value as? GeoPoint {
            return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        }
        guard let data = value as? [String: Any] else { return nil }
        let lat = doubleValue(data["lat"] ?? data["latitude"])
        let lng = doubleValue(data["lng"] ?? data["longitude"])
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private func projectedRouteProgress(
        point: CLLocationCoordinate2D,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> Double {
        let centerLatitude = start.latitude * .pi / 180
        func xy(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(
                x: coordinate.longitude * 69.0 * cos(centerLatitude),
                y: coordinate.latitude * 69.0
            )
        }

        let p = xy(point)
        let a = xy(start)
        let b = xy(end)
        let dx = b.x - a.x
        let dy = b.y - a.y
        guard dx != 0 || dy != 0 else { return 0 }
        return ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)
    }

    private func distanceFromPointToSegmentMiles(
        point: CLLocationCoordinate2D,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> Double {
        let progress = max(0, min(1, projectedRouteProgress(point: point, start: start, end: end)))
        let centerLatitude = start.latitude * .pi / 180
        func xy(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(
                x: coordinate.longitude * 69.0 * cos(centerLatitude),
                y: coordinate.latitude * 69.0
            )
        }

        let p = xy(point)
        let a = xy(start)
        let b = xy(end)
        let projected = CGPoint(
            x: a.x + (b.x - a.x) * progress,
            y: a.y + (b.y - a.y) * progress
        )
        return hypot(p.x - projected.x, p.y - projected.y)
    }

    private func driverName(from data: [String: Any]) -> String {
        if let displayName = data["displayName"] as? String, !displayName.isEmpty {
            return displayName
        }
        let first = data["firstName"] as? String ?? ""
        let last = data["lastName"] as? String ?? ""
        let combined = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? "Rydr Driver" : combined
    }

    private func vehicleName(from data: [String: Any]) -> String {
        if let summary = data["vehicleSummary"] as? String, !summary.isEmpty {
            return summary
        }
        if let car = data["carMakeModel"] as? String, !car.isEmpty {
            return car
        }
        guard let vehicle = data["vehicle"] as? [String: Any] else {
            return "Verified Rydr vehicle"
        }
        let year = vehicle["year"] as? String ?? ""
        let make = vehicle["make"] as? String ?? ""
        let model = vehicle["model"] as? String ?? ""
        let combined = "\(year) \(make) \(model)".trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? "Verified Rydr vehicle" : combined
    }

    private func matches(_ supported: String, _ requested: String) -> Bool {
        canonicalRideType(supported) == canonicalRideType(requested)
    }

    private func canonicalRideType(_ rideType: String) -> String {
        let key = rideType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key == "rydr" || key == "rydr go" { return "go" }
        if key == "rydr eco" { return "eco" }
        if key == "rydr xl" { return "xl" }
        if key == "rydr prestine" || key == "rydr pristine" { return "prestine" }
        if key == "rydr executive" { return "executive" }
        return key
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }
}

private enum RideDispatchError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in before requesting a ride."
        }
    }
}
