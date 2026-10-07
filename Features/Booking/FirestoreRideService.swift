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
import FirebaseAppCheck
import FirebaseFirestore

final class FirestoreRideService: RideService, @unchecked Sendable {
    private let db = Firestore.firestore()
    private var activeMatchSessionId: String?
    private var activeQuoteFingerprints: [String: String] = [:]

    func fetchNearbyDrivers(
        pickup: String,
        dropoff: String,
        rideType: String,
        near center: CLLocationCoordinate2D,
        pickupCoordinate: CLLocationCoordinate2D?,
        dropoffCoordinate: CLLocationCoordinate2D?,
        estimatedDistanceMiles: Double?,
        riderPreferences: RiderRidePreferences?
    ) async throws -> [Driver] {
        guard try await rideTypeAvailableForBeta(rideType) else { return [] }

        let snapshot = try await db.collection("publicDriverProfiles")
            .whereField("isOnline", isEqualTo: true)
            .getDocuments()

        let candidates = snapshot.documents
            .compactMap { document in
                driverCandidate(
                    from: document,
                    rideType: rideType,
                    near: center,
                    pickupCoordinate: pickupCoordinate,
                    dropoffCoordinate: dropoffCoordinate,
                    estimatedDistanceMiles: estimatedDistanceMiles,
                    riderPreferences: riderPreferences
                )
            }
            .filter { $0.driver.score > 0 }

        let strictMatches = candidates
            .filter { $0.preferenceMatch == .strict }
            .sorted(by: sortDriverCandidates)

        let fallbackMatches = candidates
            .filter { $0.preferenceMatch == .fallback }
            .sorted(by: sortDriverCandidates)

        let displayedDrivers = Array((strictMatches + fallbackMatches).prefix(3)).map(\.driver)
        let match = try await createBackendMatchSession(
            rideType: rideType,
            pickupCoordinate: pickupCoordinate ?? center,
            dropoffCoordinate: dropoffCoordinate,
            riderPreferences: riderPreferences
        )
        activeMatchSessionId = match.sessionId
        activeQuoteFingerprints = match.quoteFingerprints
        return displayedDrivers.filter { match.quoteFingerprints[$0.id] != nil }
    }

    func requestRide(
        driverId: String,
        pickup: String,
        dropoff: String,
        rideType: String,
        pickupCoordinate: CLLocationCoordinate2D?,
        dropoffCoordinate: CLLocationCoordinate2D?,
        estimate: RideEstimate?,
        pricingSnapshot: RidePriceEstimateSnapshot,
        rydrBankCode: String?,
        replacementForRideId: String?,
        riderPreferences: RiderRidePreferences?,
        riderVerified: Bool,
        candidateDriverIds: [String]
    ) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw RideDispatchError.notSignedIn
        }
        guard let matchSessionId = activeMatchSessionId,
              let quoteFingerprint = activeQuoteFingerprints[driverId] else {
            throw NSError(
                domain: "RydrRideBackend",
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "Driver availability expired. Refresh nearby drivers and try again."]
            )
        }
        guard let rawBase = Bundle.main.object(forInfoDictionaryKey: "RYDR_BACKEND_BASE_URL") as? String,
              let base = URL(string: rawBase),
              let url = URL(string: "/rides/request", relativeTo: base) else {
            throw URLError(.badURL)
        }

        let idempotencyKey = "match_\(matchSessionId)"
        var payload: [String: Any] = [
            "idempotencyKey": idempotencyKey,
            "matchSessionId": matchSessionId,
            "quoteFingerprint": quoteFingerprint,
            "selectedCandidateId": driverId,
            "candidateDriverIds": candidateDriverIds,
            "pickup": pickup,
            "dropoff": dropoff,
            "rideType": rideType,
            "source": "standardRydr"
        ]
        if let pickupCoordinate {
            payload["pickupCoordinate"] = [
                "lat": pickupCoordinate.latitude,
                "lng": pickupCoordinate.longitude
            ]
        }
        if let dropoffCoordinate {
            payload["dropoffCoordinate"] = [
                "lat": dropoffCoordinate.latitude,
                "lng": dropoffCoordinate.longitude
            ]
        }
        if let estimate {
            payload["displayEstimatedDistanceMiles"] = estimate.distanceMiles
            payload["displayEstimatedDurationMinutes"] = estimate.durationMinutes
        }
        payload["displayEstimatedRiderTotalCents"] = pricingSnapshot.estimatedRiderTotalCents
        payload["displayEstimatedDriverPayoutCents"] = pricingSnapshot.estimatedDriverPayoutCents
        if let rydrBankCode, !rydrBankCode.isEmpty {
            payload["rydrBankCode"] = rydrBankCode
        }
        if let replacementForRideId, !replacementForRideId.isEmpty {
            payload["replacementForRideId"] = replacementForRideId
        }
        if let preferencePayload = riderPreferences?.rideRequestPayload {
            payload["ridePreferences"] = preferencePayload
        }

        let token = try await user.getIDToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(try await appCheckToken(), forHTTPHeaderField: "X-Firebase-AppCheck")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rideId = result["rideId"] as? String, !rideId.isEmpty else {
            let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw NSError(
                domain: "RydrRideBackend",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: result?["error"] as? String ?? result?["message"] as? String ?? "Could not create the ride request."]
            )
        }
        return rideId
    }

    private struct BackendMatchSession {
        let sessionId: String
        let quoteFingerprints: [String: String]
    }

    private func createBackendMatchSession(
        rideType: String,
        pickupCoordinate: CLLocationCoordinate2D,
        dropoffCoordinate: CLLocationCoordinate2D?,
        riderPreferences: RiderRidePreferences?
    ) async throws -> BackendMatchSession {
        guard let dropoffCoordinate else { throw RideRequestError.routeEstimateRequired }
        guard let user = Auth.auth().currentUser else { throw RideDispatchError.notSignedIn }
        guard let rawBase = Bundle.main.object(forInfoDictionaryKey: "RYDR_BACKEND_BASE_URL") as? String,
              let base = URL(string: rawBase),
              let url = URL(string: "/rides/match-session", relativeTo: base) else { throw URLError(.badURL) }
        var body: [String: Any] = [
            "rideType": rideType,
            "pickupCoordinate": ["lat": pickupCoordinate.latitude, "lng": pickupCoordinate.longitude],
            "dropoffCoordinate": ["lat": dropoffCoordinate.latitude, "lng": dropoffCoordinate.longitude]
        ]
        if let preferences = riderPreferences?.rideRequestPayload { body["riderPreferences"] = preferences }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        request.setValue(try await appCheckToken(), forHTTPHeaderField: "X-Firebase-AppCheck")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let sessionId = payload["matchSessionId"] as? String,
              let candidates = payload["candidates"] as? [[String: Any]] else {
            throw NSError(
                domain: "RydrRideBackend",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: payload["error"] as? String ?? "Could not validate nearby drivers."]
            )
        }
        let fingerprints = Dictionary(uniqueKeysWithValues: candidates.compactMap { candidate -> (String, String)? in
            guard let driverId = candidate["driverId"] as? String,
                  let fingerprint = candidate["quoteFingerprint"] as? String else { return nil }
            return (driverId, fingerprint)
        })
        return BackendMatchSession(sessionId: sessionId, quoteFingerprints: fingerprints)
    }

    private func appCheckToken() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            AppCheck.appCheck().token(forcingRefresh: false) { token, error in
                if let error { continuation.resume(throwing: error) }
                else if let token { continuation.resume(returning: token.token) }
                else { continuation.resume(throwing: URLError(.userAuthenticationRequired)) }
            }
        }
    }

    func awaitDriverDecision(rideId: String) async throws -> DriverDecision {
        let stream = AsyncThrowingStream<DriverDecision, Error> { continuation in
            let listener = db.collection("rideRequests").document(rideId)
                .addSnapshotListener { snapshot, error in
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }

                    let data = snapshot?.data() ?? [:]
                    let status = (data["status"] as? String ?? "").lowercased()
                    switch status {
                    case "accepted":
                        continuation.yield(.accepted(driverId: data["driverId"] as? String))
                        continuation.finish()
                    case "declined", "drivercancelled", "cancelled", "nodriversavailable":
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

    func refreshRideDispatch(rideId: String) async throws -> RideDispatchRefresh {
        guard let user = Auth.auth().currentUser else { throw RideDispatchError.notSignedIn }
        guard let rawBase = Bundle.main.object(forInfoDictionaryKey: "RYDR_BACKEND_BASE_URL") as? String,
              let base = URL(string: rawBase),
              let url = URL(string: "/rides/\(rideId)/dispatch/refresh", relativeTo: base) else {
            throw URLError(.badURL)
        }
        let token = try await user.getIDToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["requestId": UUID().uuidString])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw NSError(
                domain: "RydrRideBackend",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: payload?["error"] as? String ?? "Dispatch refresh failed."]
            )
        }
        return RideDispatchRefresh(
            status: payload["status"] as? String ?? "pending",
            dispatchStatus: payload["dispatchStatus"] as? String,
            driverId: payload["driverId"] as? String
        )
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
                    let rawStatus = data["status"] as? String
                    let snapshot = RideLifecycleSnapshot(
                        status: Self.rideStatus(from: rawStatus),
                        rawStatus: rawStatus,
                        driverCoordinate: Self.coordinate(from: data["driverLocation"]),
                        pickupCoordinate: Self.coordinate(from: data["pickupCoordinate"]) ?? Self.coordinate(from: data["pickupGeoPoint"]),
                        dropoffCoordinate: Self.coordinate(from: data["dropoffCoordinate"]) ?? Self.coordinate(from: data["dropoffGeoPoint"]),
                        pickupWaitStartedAt: Self.date(from: data["pickupWaitStartedAt"] ?? data["arrivedAtPickupAt"]),
                        pickupComplimentaryWaitSeconds: Self.intValue(data["pickupComplimentaryWaitSeconds"]),
                        financialOutcome: Self.financialOutcome(from: data),
                        backendDistanceMiles: Self.doubleValue(data["backendDistanceMiles"]),
                        backendDurationMinutes: Self.doubleValue(data["backendDurationMinutes"]),
                        proratedCancellationChargeCents: Self.intValue(data["proratedCancellationChargeCents"]),
                        proratedCancellationDistanceMiles: Self.doubleValue(data["proratedCancellationDistanceMiles"])
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

    func cancelRide(rideId: String, mode: RideCancellationMode) async throws -> BackendRideFinancialOutcome? {
        let reason = mode == .findAnotherDriver ? "Rider cancelled to find another driver" : "Rider cancelled"
        return try await sendRideTransition(rideId: rideId, action: "rider_cancel", reason: reason)
    }

    func cancelMidRide(rideId: String) async throws -> BackendRideFinancialOutcome {
        guard let outcome = try await sendRideTransition(
            rideId: rideId,
            action: "rider_cancel",
            reason: "Rider cancelled mid-ride"
        ) else {
            throw NSError(
                domain: "RydrRideBackend",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "The backend did not return a finalized cancellation fare."]
            )
        }
        return outcome
    }

    private func sendRideTransition(rideId: String, action: String, reason: String) async throws -> BackendRideFinancialOutcome? {
        guard let user = Auth.auth().currentUser else { throw RideDispatchError.notSignedIn }
        guard let rawBase = Bundle.main.object(forInfoDictionaryKey: "RYDR_BACKEND_BASE_URL") as? String,
              let base = URL(string: rawBase),
              let url = URL(string: "/rides/\(rideId)/transition", relativeTo: base) else { throw URLError(.badURL) }
        let token = try await user.getIDToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["action": action, "reason": reason, "requestId": UUID().uuidString])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw NSError(domain: "RydrRideBackend", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: payload?["error"] as? String ?? "Ride cancellation failed."])
        }
        return try JSONDecoder().decode(RideTransitionPayload.self, from: data).outcome
    }

    private struct RideTransitionPayload: Decodable {
        let outcome: BackendRideFinancialOutcome?
    }

    private func driverCandidate(
        from document: QueryDocumentSnapshot,
        rideType: String,
        near center: CLLocationCoordinate2D,
        pickupCoordinate: CLLocationCoordinate2D?,
        dropoffCoordinate: CLLocationCoordinate2D?,
        estimatedDistanceMiles: Double?,
        riderPreferences: RiderRidePreferences?
    ) -> DriverCandidate? {
        let data = document.data()
        let enabled = data["standardDispatchEnabled"] as? Bool ?? true
        guard enabled else { return nil }
        guard !isRideTypeTemporarilyDisabled(rideType, data: data) else { return nil }

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
        let preferenceMatch = matchesDriverRideFilters(
            data["rideFilters"] as? [String: Any],
            driverCoordinate: coordinate,
            pickupCoordinate: pickupCoordinate ?? center,
            dropoffCoordinate: dropoffCoordinate,
            estimatedDistanceMiles: estimatedDistanceMiles
        )
        guard preferenceMatch != .rejected else { return nil }

        let rating = Self.doubleValue(data["rating"]) ?? 5.0
        let ratingCount = Self.intValue(data["ratingCount"]) ?? 0
        let completedRideCount = Self.intValue(data["completedRideCount"] ?? data["lifetimeRideCount"])
        let acceptanceRate = Self.intValue(data["acceptanceRate"])
        let pricing = RydrPricing.config(for: rideType)
        let rate = driverRate(from: data, rideType: rideType, pricing: pricing)
        let gender = driverGender(from: data)
        let score = max(1, min(100, Int(100 - (distance * 6) + ((rating - 4.5) * 18) + genderPreferenceBoost(driverGender: gender, riderPreferences: riderPreferences))))

        return DriverCandidate(
            driver: Driver(
                id: document.documentID,
                name: driverName(from: data),
                profileImage: nonEmptyString(data["profilePhotoURL"]) ?? nonEmptyString(data["profileImage"]),
                // "vehicleImageURL" is written by the Vehicle Library System
                // (RydrDriver's DriverDashboardVM.publishPublicDriverProfile) —
                // the generic factory-style image matched from the driver's
                // decoded VIN + chosen color, never a photo of their actual car.
                // "carImage" is kept for backward compatibility with any older
                // writer of this field.
                carImage: nonEmptyString(data["vehicleImageURL"]) ?? nonEmptyString(data["carImage"]),
                carMakeModel: vehicleName(from: data),
                rating: rating,
                compliments: data["compliments"] as? [String] ?? [],
                perMinute: rate.perMinute,
                perMile: rate.perMile,
                minimumFare: rate.minimumFare,
                usesSuggestedPricing: rate.usesSuggestedPricing,
                coordinate: coordinate,
                score: score,
                ratingCount: ratingCount,
                completedRideCount: completedRideCount,
                acceptanceRate: acceptanceRate,
                stripeAccountId: data["stripeAccountId"] as? String,
                stripeChargesEnabled: data["stripeChargesEnabled"] as? Bool ?? false,
                gender: gender
            ),
            distanceMiles: distance,
            preferenceMatch: preferenceMatch
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
        case "cancelled", "riderCancelled", "driverCancelled", "adminCancelled":
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

    private static func date(from raw: Any?) -> Date? {
        if let timestamp = raw as? Timestamp { return timestamp.dateValue() }
        if let date = raw as? Date { return date }
        return nil
    }

    private static func financialOutcome(from data: [String: Any]) -> BackendRideFinancialOutcome? {
        guard data["financialOutcomeStatus"] as? String == "finalized",
              let finalRiderChargeCents = intValue(data["finalRiderChargeCents"]),
              let driverPayoutCents = intValue(data["driverPayoutCents"]),
              let platformShareCents = intValue(data["platformShareCents"]) else {
            return nil
        }

        return BackendRideFinancialOutcome(
            pricingVersion: data["pricingVersion"] as? String,
            outcomeType: data["outcomeType"] as? String,
            currency: data["currency"] as? String ?? "usd",
            distanceChargeCents: intValue(data["distanceChargeCents"]) ?? 0,
            timeChargeCents: intValue(data["timeChargeCents"]) ?? 0,
            minimumFareAdjustmentCents: intValue(data["minimumFareAdjustmentCents"]) ?? 0,
            rideSubtotalCents: intValue(data["rideSubtotalCents"]) ?? 0,
            bookingFeeCents: intValue(data["bookingFeeCents"]) ?? 0,
            waitChargeCents: intValue(data["waitChargeCents"]) ?? 0,
            cancellationFeeCents: intValue(data["cancellationFeeCents"]) ?? 0,
            grossChargeCents: intValue(data["grossChargeCents"]) ?? finalRiderChargeCents,
            promotionDiscountCents: intValue(data["promotionDiscountCents"]) ?? 0,
            finalRiderChargeCents: finalRiderChargeCents,
            driverPayoutCents: driverPayoutCents,
            platformShareCents: platformShareCents,
            calculationInputs: nil
        )
    }

    private static func number(_ raw: Any?) -> CLLocationDegrees? {
        if let value = raw as? CLLocationDegrees { return value }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    private func nonEmptyString(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? Double { return Int(value) }
        if let value = raw as? String { return Int(value) }
        return nil
    }

    private func matchesDriverRideFilters(
        _ filters: [String: Any]?,
        driverCoordinate: CLLocationCoordinate2D,
        pickupCoordinate: CLLocationCoordinate2D,
        dropoffCoordinate: CLLocationCoordinate2D?,
        estimatedDistanceMiles: Double?
    ) -> DriverPreferenceMatch {
        guard let filters else { return .strict }

        if (filters["workZoneEnabled"] as? Bool) == true {
            let radiusMiles = Self.doubleValue(filters["workZoneRadiusMiles"]) ?? 0
            guard radiusMiles > 0 else { return .rejected }
            let driverLocation = CLLocation(latitude: driverCoordinate.latitude, longitude: driverCoordinate.longitude)
            let pickupMiles = driverLocation
                .distance(from: CLLocation(latitude: pickupCoordinate.latitude, longitude: pickupCoordinate.longitude)) / 1609.344
            guard pickupMiles <= radiusMiles else { return .rejected }
            guard let dropoffCoordinate else { return .rejected }
            let dropoffMiles = driverLocation
                .distance(from: CLLocation(latitude: dropoffCoordinate.latitude, longitude: dropoffCoordinate.longitude)) / 1609.344
            guard dropoffMiles <= radiusMiles else { return .rejected }
        }

        let tripMiles = estimatedDistanceMiles ?? estimatedTripMiles(pickupCoordinate: pickupCoordinate, dropoffCoordinate: dropoffCoordinate)
        let wantsLong = filters["prioritizeLongerRides"] as? Bool ?? false
        let wantsShort = filters["prioritizeShorterRides"] as? Bool ?? filters["avoidShortPickups"] as? Bool ?? false
        var preferenceMatch: DriverPreferenceMatch = .strict
        if wantsLong && !wantsShort, let tripMiles, tripMiles < 15 {
            return .rejected
        }
        if wantsShort && !wantsLong, let tripMiles {
            if tripMiles >= 15 { return .rejected }
            if tripMiles >= 11 { preferenceMatch = .fallback }
        }

        guard (filters["destinationModeEnabled"] as? Bool) == true,
              let destinationCoordinate = coordinate(from: filters["destinationCoordinate"] ?? filters["destinationGeoPoint"]) else {
            return preferenceMatch
        }

        guard let dropoffCoordinate else { return .rejected }
        let progress = projectedRouteProgress(point: dropoffCoordinate, start: driverCoordinate, end: destinationCoordinate)
        guard progress >= 0, progress <= 1 else { return .rejected }

        let pickupLocation = CLLocation(latitude: pickupCoordinate.latitude, longitude: pickupCoordinate.longitude)
        let dropoffLocation = CLLocation(latitude: dropoffCoordinate.latitude, longitude: dropoffCoordinate.longitude)
        let destinationLocation = CLLocation(latitude: destinationCoordinate.latitude, longitude: destinationCoordinate.longitude)
        let pickupToDestinationMiles = pickupLocation.distance(from: destinationLocation) / 1609.344
        let dropoffToDestinationMiles = dropoffLocation.distance(from: destinationLocation) / 1609.344
        let corridorMiles = distanceFromPointToSegmentMiles(point: dropoffCoordinate, start: driverCoordinate, end: destinationCoordinate)
        let allowedCorridorMiles = Self.doubleValue(filters["destinationCorridorMiles"]) ?? 5

        return dropoffToDestinationMiles <= pickupToDestinationMiles
            && corridorMiles <= allowedCorridorMiles
            ? preferenceMatch
            : .rejected
    }

    private func driverRate(
        from data: [String: Any],
        rideType: String,
        pricing: RideTierPricing
    ) -> (minimumFare: Double, perMile: Double, perMinute: Double, usesSuggestedPricing: Bool) {
        let tierRates = data["tierRates"] as? [String: Any]
        let canonical = canonicalRideType(rideType)
        let rawRate = tierRates?[canonical] as? [String: Any]
            ?? tierRates?[pricing.title] as? [String: Any]
        let usesSuggestedPricing = rawRate?["useSuggestedPricing"] as? Bool ?? false
        let resolvedRates = data["resolvedSuggestedRates"] as? [String: Any]
        let resolvedRate = resolvedRates?[canonical] as? [String: Any]
        let resolvedMinimumFare = Self.doubleValue(resolvedRate?["minimumFareCents"]).map { $0 / 100 }
        let resolvedPerMile = Self.doubleValue(resolvedRate?["perMileCents"]).map { $0 / 100 }
        let resolvedPerMinute = Self.doubleValue(resolvedRate?["perMinuteCents"]).map { $0 / 100 }
        let rawMinimumFare = usesSuggestedPricing
            ? resolvedMinimumFare ?? pricing.suggestedMinimumFare
            : Self.doubleValue(rawRate?["minimumFare"]) ?? pricing.suggestedMinimumFare
        let rawPerMile = usesSuggestedPricing
            ? resolvedPerMile ?? pricing.suggestedPerMile
            : Self.doubleValue(rawRate?["perMile"]) ?? Self.doubleValue(data["perMile"]) ?? pricing.suggestedPerMile
        let rawPerMinute = usesSuggestedPricing
            ? resolvedPerMinute ?? pricing.suggestedPerMinute
            : Self.doubleValue(rawRate?["perMinute"]) ?? Self.doubleValue(data["perMinute"]) ?? pricing.suggestedPerMinute
        return (
            minimumFare: max(0, rawMinimumFare),
            perMile: max(0, rawPerMile),
            perMinute: max(0, rawPerMinute),
            usesSuggestedPricing: usesSuggestedPricing
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
        let lat = Self.doubleValue(data["lat"] ?? data["latitude"])
        let lng = Self.doubleValue(data["lng"] ?? data["longitude"])
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
            return firstNameOnly(displayName)
        }
        let first = (data["firstName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty { return firstNameOnly(first) }
        let name = data["name"] as? String ?? ""
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rydr Driver" : firstNameOnly(name)
    }

    private func firstNameOnly(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Rydr Driver" }
        return trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? trimmed
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

    private func driverGender(from data: [String: Any]) -> String? {
        let raw = data["gender"] as? String
            ?? data["driverGender"] as? String
            ?? data["genderIdentity"] as? String
        let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "male" { return "Male" }
        if normalized == "female" { return "Female" }
        return nil
    }

    private func genderPreferenceBoost(driverGender: String?, riderPreferences: RiderRidePreferences?) -> Double {
        guard let preference = riderPreferences?.genderPreference,
              preference != RiderRidePreferences.defaultValue.genderPreference,
              let driverGender else {
            return 0
        }
        return driverGender.caseInsensitiveCompare(preference) == .orderedSame ? 28 : 0
    }

    private func matches(_ supported: String, _ requested: String) -> Bool {
        canonicalRideType(supported) == canonicalRideType(requested)
    }

    private func sortDriverCandidates(_ lhs: DriverCandidate, _ rhs: DriverCandidate) -> Bool {
        let leftDistance = (lhs.distanceMiles * 10).rounded() / 10
        let rightDistance = (rhs.distanceMiles * 10).rounded() / 10
        if leftDistance != rightDistance { return leftDistance < rightDistance }
        if lhs.driver.score != rhs.driver.score { return lhs.driver.score > rhs.driver.score }
        return lhs.driver.rating > rhs.driver.rating
    }

    private func isRideTypeTemporarilyDisabled(_ rideType: String, data: [String: Any]) -> Bool {
        let disabledRideTypes = data["temporarilyDisabledRideTypes"] as? [String] ?? []
        return disabledRideTypes.contains { canonicalRideType($0) == canonicalRideType(rideType) }
    }

    private func rideTypeAvailableForBeta(_ rideType: String) async throws -> Bool {
        guard canonicalRideType(rideType) == "executive" else { return true }
        let snap = try await db.collection("platformConfig").document("rydrExecutive").getDocument()
        return snap.data()?["enabled"] as? Bool == true
    }

    private func estimatedTripMiles(
        pickupCoordinate: CLLocationCoordinate2D,
        dropoffCoordinate: CLLocationCoordinate2D?
    ) -> Double? {
        guard let dropoffCoordinate else { return nil }
        return CLLocation(latitude: pickupCoordinate.latitude, longitude: pickupCoordinate.longitude)
            .distance(from: CLLocation(latitude: dropoffCoordinate.latitude, longitude: dropoffCoordinate.longitude)) / 1609.344
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

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }
}

private struct DriverCandidate {
    let driver: Driver
    let distanceMiles: Double
    let preferenceMatch: DriverPreferenceMatch
}

private enum DriverPreferenceMatch {
    case strict
    case fallback
    case rejected
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
