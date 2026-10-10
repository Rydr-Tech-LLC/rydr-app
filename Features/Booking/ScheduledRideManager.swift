import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseAppCheck
import FirebaseFirestore

@MainActor
final class ScheduledRideManager: ObservableObject {
    static let minimumLeadTime: TimeInterval = 60
    static let maximumLeadTime: TimeInterval = 30 * 24 * 60 * 60

    @Published var selectedMode: ScheduledRideMode = .quickSchedule
    @Published var requestedPickupDate = Date().addingTimeInterval(5 * 60)
    @Published private(set) var preview: ScheduledRidePreview?
    @Published private(set) var activeRequest: ScheduledRideRequest?
    @Published private(set) var scheduledRequests: [ScheduledRideRequest] = []
    @Published private(set) var activatedRideId: String?
    @Published private(set) var offers: [ScheduledDriverOffer] = []
    @Published private(set) var isWorking = false
    @Published private(set) var cancellingRequestIDs: Set<String> = []
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var requestListener: ListenerRegistration?
    private var offersListener: ListenerRegistration?
    private var scheduleListener: ListenerRegistration?
    private var creationIdempotencyKey = UUID().uuidString

    deinit {
        requestListener?.remove()
        offersListener?.remove()
        scheduleListener?.remove()
    }

    func validate(date: Date, now: Date = Date()) -> String? {
        let lead = date.timeIntervalSince(now)
        if lead < Self.minimumLeadTime { return "Choose a future pickup time." }
        if lead > Self.maximumLeadTime { return "Scheduled rides may be booked up to 30 days ahead." }
        return nil
    }

    func loadPreview(
        pickup: String,
        dropoff: String,
        pickupCoordinate: CLLocationCoordinate2D?,
        dropoffCoordinate: CLLocationCoordinate2D?,
        rideType: String
    ) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            guard let pickupCoordinate, let dropoffCoordinate else {
                throw ScheduledRideError.invalidResponse("Choose a valid pickup and drop-off first.")
            }
            let response = try await backendRequest(path: "/scheduled-rides/preview", body: basePayload(
                pickup: pickup,
                dropoff: dropoff,
                pickupCoordinate: pickupCoordinate,
                dropoffCoordinate: dropoffCoordinate,
                rideType: rideType
            ))
            guard let route = response["route"] as? [String: Any] else {
                throw ScheduledRideError.invalidResponse("The backend did not return a scheduled ride quote.")
            }
            preview = ScheduledRidePreview(
                distanceMiles: Self.double(route["distanceMiles"]),
                durationMinutes: Self.double(route["durationMinutes"]),
                suggestedLowCents: Self.int(response["suggestedLowCents"]),
                suggestedHighCents: Self.int(response["suggestedHighCents"]),
                eligibleDriverCount: Self.int(response["eligibleDriverCount"])
            )
        } catch {
            preview = nil
            errorMessage = error.localizedDescription
        }
    }

    func createRequest(
        pickup: String,
        dropoff: String,
        pickupCoordinate: CLLocationCoordinate2D?,
        dropoffCoordinate: CLLocationCoordinate2D?,
        rideType: String
    ) async throws -> String {
        if let message = validate(date: requestedPickupDate) { throw ScheduledRideError.invalidTime(message) }
        guard let pickupCoordinate, let dropoffCoordinate else {
            throw ScheduledRideError.invalidResponse("Choose a valid pickup and drop-off first.")
        }
        guard let preview else { throw ScheduledRideError.invalidResponse("Wait for the estimated fare range before scheduling.") }
        isWorking = true
        defer { isWorking = false }
        var payload = basePayload(
            pickup: pickup,
            dropoff: dropoff,
            pickupCoordinate: pickupCoordinate,
            dropoffCoordinate: dropoffCoordinate,
            rideType: rideType
        )
        payload["idempotencyKey"] = creationIdempotencyKey
        payload["riderApprovedMaxCents"] = preview.suggestedHighCents
        let response = try await backendRequest(path: "/scheduled-rides", body: payload)
        guard let requestId = response["requestId"] as? String else {
            throw ScheduledRideError.invalidResponse("The backend did not create the scheduled ride.")
        }
        creationIdempotencyKey = UUID().uuidString
        listen(requestId: requestId)
        return requestId
    }

    func select(_ offer: ScheduledDriverOffer) async throws {
        guard let requestId = activeRequest?.id else { return }
        _ = try await backendRequest(path: "/scheduled-rides/\(requestId)/select", body: ["driverId": offer.id])
    }

    func cancel(reason: String = "Rider cancelled scheduled ride") async throws {
        guard let requestId = activeRequest?.id else { return }
        try await cancel(requestId: requestId, reason: reason)
    }

    func cancel(requestId: String, reason: String = "Rider cancelled scheduled ride") async throws {
        guard !cancellingRequestIDs.contains(requestId) else { return }
        errorMessage = nil
        cancellingRequestIDs.insert(requestId)
        defer { cancellingRequestIDs.remove(requestId) }
        _ = try await backendRequest(path: "/scheduled-rides/\(requestId)/cancel", body: ["reason": reason])

        // Do not wait for the Firestore listener to remove a successful
        // cancellation. This makes swipe-to-remove deterministic even if the
        // listener is reconnecting or the expired record has no further writes.
        scheduledRequests.removeAll { $0.id == requestId }
    }

    func listen(requestId: String) {
        requestListener?.remove()
        offersListener?.remove()
        let requestRef = db.collection("scheduledRideRequests").document(requestId)
        requestListener = requestRef.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                if let error { self?.errorMessage = error.localizedDescription; return }
                guard let data = snapshot?.data() else { return }
                self?.activeRequest = Self.parseRequest(id: requestId, data: data)
            }
        }
        offersListener = requestRef.collection("offers")
            .whereField("status", isEqualTo: "available")
            .limit(to: 3)
            .addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                if let error { self?.errorMessage = error.localizedDescription; return }
                self?.offers = snapshot?.documents.compactMap(Self.parseOffer) ?? []
            }
        }
    }

    func startScheduleListener() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        scheduleListener?.remove()
        scheduleListener = db.collection("scheduledRideRequests")
            .whereField("riderId", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error { self?.errorMessage = error.localizedDescription; return }
                    let requests: [ScheduledRideRequest] = snapshot?.documents.compactMap { document -> ScheduledRideRequest? in
                        let data = document.data()
                        guard data["riderArchivedAt"] == nil else { return nil }
                        return Self.parseRequest(id: document.documentID, data: data)
                    } ?? []
                    self?.activatedRideId = requests
                        .filter { $0.status == .active && $0.activeRideId != nil }
                        .sorted { $0.scheduledPickupAt > $1.scheduledPickupAt }
                        .first?.activeRideId
                    self?.scheduledRequests = requests
                        // Once regular dispatch has created the live ride, it
                        // belongs in the normal ride flow rather than the
                        // scheduled-rides list. Completed and cancelled rides
                        // are historical records and should not remain here.
                        .filter { request in
                            request.activeRideId == nil
                                && ![.active, .completed, .cancelled].contains(request.status)
                        }
                        .sorted { $0.scheduledPickupAt > $1.scheduledPickupAt }
                }
            }
    }

    private func basePayload(
        pickup: String,
        dropoff: String,
        pickupCoordinate: CLLocationCoordinate2D,
        dropoffCoordinate: CLLocationCoordinate2D,
        rideType: String
    ) -> [String: Any] {
        [
            "pickup": pickup,
            "dropoff": dropoff,
            "pickupCoordinate": ["lat": pickupCoordinate.latitude, "lng": pickupCoordinate.longitude],
            "dropoffCoordinate": ["lat": dropoffCoordinate.latitude, "lng": dropoffCoordinate.longitude],
            "rideType": rideType,
            "mode": selectedMode.rawValue,
            "scheduledPickupAt": ISO8601DateFormatter().string(from: requestedPickupDate)
        ]
    }

    private func backendRequest(path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let user = Auth.auth().currentUser else { throw ScheduledRideError.notSignedIn }
        guard let rawBase = Bundle.main.object(forInfoDictionaryKey: "RYDR_BACKEND_BASE_URL") as? String,
              let base = URL(string: rawBase), let url = URL(string: path, relativeTo: base) else {
            throw URLError(.badURL)
        }
        let token = try await user.getIDToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(try await appCheckToken(), forHTTPHeaderField: "X-Firebase-AppCheck")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ScheduledRideError.invalidResponse(payload["error"] as? String ?? payload["message"] as? String ?? "Scheduled ride request failed.")
        }
        return payload
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

    private static func parseRequest(id: String, data: [String: Any]) -> ScheduledRideRequest? {
        guard let pickup = data["pickup"] as? String,
              let dropoff = data["dropoff"] as? String,
              let rideType = data["rideType"] as? String,
              let mode = ScheduledRideMode(rawValue: data["mode"] as? String ?? ""),
              let status = ScheduledRideStatus(rawValue: data["status"] as? String ?? "") else { return nil }
        return ScheduledRideRequest(
            id: id,
            pickup: pickup,
            dropoff: dropoff,
            rideType: rideType,
            mode: mode,
            scheduledPickupAt: (data["scheduledPickupAt"] as? Timestamp)?.dateValue() ?? Date(),
            status: status,
            riderApprovedMaxCents: optionalInt(data["riderApprovedMaxCents"]),
            lockedPriceCents: optionalInt(data["lockedPriceCents"]),
            assignedDriverId: data["assignedDriverId"] as? String,
            activeRideId: data["activeRideId"] as? String
        )
    }

    private static func parseOffer(_ document: QueryDocumentSnapshot) -> ScheduledDriverOffer? {
        let data = document.data()
        guard let quote = data["quote"] as? [String: Any] else { return nil }
        return ScheduledDriverOffer(
            id: document.documentID,
            driverName: data["driverName"] as? String ?? "Rydr Driver",
            driverPhotoURL: data["driverPhotoURL"] as? String,
            vehicleSummary: data["vehicleSummary"] as? String,
            rating: double(data["rating"]),
            ratingCount: int(data["ratingCount"]),
            totalCents: int(quote["totalCents"])
        )
    }

    private static func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? value as? Int ?? 0 }
    private static func optionalInt(_ value: Any?) -> Int? { value == nil ? nil : int(value) }
    private static func double(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? value as? Double ?? 0 }
}
