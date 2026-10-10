import Foundation
import FirebaseAuth
import FirebaseAppCheck

enum RydrBackendService {
    private static let baseURLString = Bundle.main.object(forInfoDictionaryKey: "RYDR_BACKEND_BASE_URL") as? String

    static var isConfigured: Bool {
        guard let baseURLString else { return false }
        return URL(string: baseURLString) != nil
    }

    static func recordWaitTimeEvent(_ event: WaitTimeEvent) async {
        do {
            guard let request = try await makeAuthenticatedRequest(path: "/driver/wait-time-events", method: "POST", body: event) else {
                return
            }
            _ = try await URLSession.shared.data(for: request)
        } catch {
            RydrCrashReporter.record(error, context: "record_wait_time_event")
        }
    }

    static func requestAccountDeletion(_ requestBody: AccountDeletionRequest) async throws {
        guard let request = try await makeAuthenticatedRequest(path: "/account/deletion-requests", method: "POST", body: requestBody) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(BackendError.self, from: data).error) ?? "Account deletion request failed."
            throw NSError(domain: "RydrBackendService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func syncAccountIdentity(acceptBetaWaiver: Bool = false) async throws {
        let body = AccountIdentityRequest(role: "driver", betaWaiverAccepted: acceptBetaWaiver)
        guard let request = try await makeAuthenticatedRequest(path: "/account/identity/sync", method: "POST", body: body) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(BackendError.self, from: data).error) ?? "Account identity could not be synchronized."
            throw NSError(domain: "RydrBackendService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func finalizeDriverAccount() async throws {
        try await sendAuthenticatedJSON(path: "/account/profile/finalize", body: ["role": "driver"])
    }

    static func prepareDriverLicense(number: String, state: String) async throws {
        try await sendAuthenticatedJSON(
            path: "/driver/onboarding/license/prepare",
            body: ["licenseNumber": number, "licenseState": state]
        )
    }

    static func finalizeDriverLicenseDocuments(frontStoragePath: String, backStoragePath: String) async throws {
        try await sendAuthenticatedJSON(
            path: "/driver/onboarding/documents/license/finalize",
            body: ["frontStoragePath": frontStoragePath, "backStoragePath": backStoragePath]
        )
    }

    static func finalizeDriverVehicleDocuments(
        plate: String,
        registrationStoragePath: String,
        insuranceStoragePath: String
    ) async throws {
        try await sendAuthenticatedJSON(
            path: "/driver/onboarding/documents/vehicle/finalize",
            body: [
                "plate": plate,
                "registrationStoragePath": registrationStoragePath,
                "insuranceStoragePath": insuranceStoragePath
            ]
        )
    }

    static func updateVehiclePlate(_ plate: String) async throws {
        guard let request = try await makeAuthenticatedRequest(
            path: "/driver/vehicle/plate",
            method: "PUT",
            body: VehiclePlateRequest(plate: plate)
        ) else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(BackendError.self, from: data).error) ?? "Vehicle plate could not be saved."
            throw NSError(domain: "RydrBackendService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func transitionRide(rideId: String, action: String, reason: String? = nil, queued: Bool = false) async throws -> RideTransitionResponse {
        let body = RideTransitionRequest(action: action, requestId: UUID().uuidString, reason: reason, queued: queued)
        guard let request = try await makeAuthenticatedRequest(path: "/rides/\(rideId)/transition", method: "POST", body: body) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(BackendError.self, from: data).error) ?? "Backend ride transition failed."
            throw NSError(domain: "RydrBackendService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(RideTransitionResponse.self, from: data)
    }

    static func calculateRouteEstimate(rideId: String) async throws {
        let body = RideRouteEstimateRequest(departureDate: ISO8601DateFormatter().string(from: Date()))
        guard let request = try await makeAuthenticatedRequest(path: "/rides/\(rideId)/route-estimate", method: "POST", body: body) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(BackendError.self, from: data).error) ?? "Backend route estimate failed."
            throw NSError(domain: "RydrBackendService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func updateDriverPresence(_ body: DriverPresenceRequest) async throws -> DriverPresenceResponse {
        guard let request = try await makeAuthenticatedRequest(path: "/driver/presence", method: "POST", body: body) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(BackendError.self, from: data).error) ?? "Backend presence update failed."
            throw NSError(domain: "RydrBackendService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(DriverPresenceResponse.self, from: data)
    }

    static func fetchDriverDemand(_ body: DriverDemandRequest) async throws -> DriverDemandResponse {
        guard let request = try await makeAuthenticatedRequest(path: "/driver/demand", method: "POST", body: body) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(BackendError.self, from: data).error) ?? "Backend demand lookup failed."
            throw NSError(domain: "RydrBackendService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(DriverDemandResponse.self, from: data)
    }

    static func recordRideTelemetry(rideId: String, body: RideTelemetryRequest) async throws {
        guard let request = try await makeAuthenticatedRequest(path: "/rides/\(rideId)/telemetry", method: "POST", body: body) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(BackendError.self, from: data).error) ?? "Trip telemetry was not accepted."
            throw NSError(domain: "RydrBackendService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func submitRideRating(rideId: String, body: RideRatingRequest) async throws {
        guard let request = try await makeAuthenticatedRequest(path: "/rides/\(rideId)/rating", method: "POST", body: body) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(BackendError.self, from: data).error) ?? "Rating could not be saved."
            throw NSError(domain: "RydrBackendService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func promoteNextQueuedRide() async throws -> QueuePromotionResponse {
        let body = QueuePromotionRequest(requestId: UUID().uuidString)
        guard let request = try await makeAuthenticatedRequest(path: "/driver/queue/promote-next", method: "POST", body: body) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(BackendError.self, from: data).error) ?? "Queued ride could not be promoted."
            throw NSError(domain: "RydrBackendService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(QueuePromotionResponse.self, from: data)
    }

    static func recordBackgroundCheck(_ body: BackgroundCheckRequest, action: String) async throws {
        guard let request = try await makeAuthenticatedRequest(path: "/driver/background-check/\(action)", method: "POST", body: body) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(BackendError.self, from: data).error) ?? "Background-check status could not be saved."
            throw NSError(domain: "RydrBackendService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func updateRateCard(_ body: RateCardRequest) async throws -> RateCardResponse {
        guard let request = try await makeAuthenticatedRequest(path: "/driver/rate-card", method: "PUT", body: body) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(BackendError.self, from: data).error) ?? "Rate card could not be saved."
            throw NSError(domain: "RydrBackendService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(RateCardResponse.self, from: data)
    }

    static func loadRateCard() async throws -> RateCardLoadResponse {
        guard let request = try await makeAuthenticatedRequest(
            path: "/driver/rate-card",
            method: "GET",
            body: EmptyRequest()
        ) else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(BackendError.self, from: data).error) ?? "Rate card could not be loaded."
            throw NSError(domain: "RydrBackendService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(RateCardLoadResponse.self, from: data)
    }

    static func cashHubCommand(requestId: String, action: String, body: [String: Any] = [:]) async throws {
        var payload = body; payload["action"] = action; payload["idempotencyKey"] = UUID().uuidString
        try await sendAuthenticatedJSON(path: "/cash-hub/requests/\(requestId)/command", body: payload)
    }

    static func acceptCashHubTerms() async throws {
        try await sendAuthenticatedJSON(path: "/cash-hub/access/accept", body: ["role": "driver"])
    }

    static func optOutOfCashHub() async throws {
        try await sendAuthenticatedJSON(path: "/cash-hub/access/opt-out", body: ["role": "driver"])
    }

    static func cashHubOffer(requestId: String, body: [String: Any]) async throws {
        var payload = body; payload["idempotencyKey"] = UUID().uuidString
        try await sendAuthenticatedJSON(path: "/cash-hub/requests/\(requestId)/offers", body: payload)
    }

    static func cashHubMessage(conversationId: String, text: String, kind: String) async throws {
        try await sendAuthenticatedJSON(path: "/cash-hub/conversations/\(conversationId)/messages", body: ["message": text, "kind": kind, "idempotencyKey": UUID().uuidString])
    }

    static func cashHubConversationCommand(conversationId: String, action: String, body: [String: Any] = [:]) async throws {
        var payload = body; payload["action"] = action; payload["idempotencyKey"] = UUID().uuidString
        try await sendAuthenticatedJSON(path: "/cash-hub/conversations/\(conversationId)/command", body: payload)
    }

    static func cashHubRelationship(action: String, targetUid: String, conversationId: String? = nil) async throws {
        var payload: [String: Any] = ["action": action, "targetUid": targetUid, "idempotencyKey": UUID().uuidString]
        if let conversationId { payload["conversationId"] = conversationId }
        try await sendAuthenticatedJSON(path: "/cash-hub/relationships/command", body: payload)
    }

    static func respondToScheduledRide(requestId: String, response: String) async throws {
        try await sendAuthenticatedJSON(
            path: "/scheduled-rides/\(requestId)/respond",
            body: ["response": response]
        )
    }

    static func checkInScheduledRide(requestId: String, etaSeconds: Int) async throws {
        try await sendAuthenticatedJSON(
            path: "/scheduled-rides/\(requestId)/check-in",
            body: ["etaSeconds": etaSeconds]
        )
    }

    static func releaseScheduledRide(requestId: String, reason: String) async throws {
        try await sendAuthenticatedJSON(
            path: "/scheduled-rides/\(requestId)/cancel",
            body: ["reason": reason]
        )
    }

    static func submitSafetyReport(_ body: [String: Any]) async throws { try await sendAuthenticatedJSON(path: "/safety/reports", body: body) }
    static func submitSafetyAppeal(_ body: [String: Any]) async throws { try await sendAuthenticatedJSON(path: "/safety/appeals", body: body) }

    static func fetchReportableRides(limit: Int = 30) async throws -> [ReportableRide] {
        guard let baseURLString,
              let baseURL = URL(string: baseURLString),
              let endpoint = URL(string: "/safety/reportable-rides", relativeTo: baseURL),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true),
              let user = Auth.auth().currentUser else {
            throw URLError(.userAuthenticationRequired)
        }
        components.queryItems = [URLQueryItem(name: "limit", value: String(min(50, max(1, limit))))]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        request.setValue(try await appCheckToken(), forHTTPHeaderField: "X-Firebase-AppCheck")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(BackendError.self, from: data).error) ?? "Completed rides could not be loaded."
            throw NSError(domain: "RydrBackendService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(ReportableRidesResponse.self, from: data).rides
    }

    static func fetchDriverEarningsSummary() async throws -> EarningsSummaryResponse {
        guard let baseURLString,let base=URL(string:baseURLString),let url=URL(string:"/driver/earnings-summary",relativeTo:base),let user=Auth.auth().currentUser else{throw URLError(.userAuthenticationRequired)}
        var request=URLRequest(url:url);request.httpMethod="GET";request.setValue("Bearer \(try await user.getIDToken())",forHTTPHeaderField:"Authorization")
        let(data,response)=try await URLSession.shared.data(for:request);guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else{throw URLError(.badServerResponse)}
        return try JSONDecoder().decode(EarningsSummaryResponse.self,from:data)
    }

    private static func sendAuthenticatedJSON(path: String, body: [String: Any]) async throws {
        guard let baseURLString, let baseURL = URL(string: baseURLString), let url = URL(string: path, relativeTo: baseURL), let user = Auth.auth().currentUser else { throw URLError(.userAuthenticationRequired) }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        request.setValue(try await appCheckToken(), forHTTPHeaderField: "X-Firebase-AppCheck")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data,response)=try await URLSession.shared.data(for: request)
        guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else {
            let message=(try? JSONDecoder().decode(BackendError.self,from:data).error) ?? "Backend request failed."
            throw NSError(domain:"RydrBackendService",code:(response as? HTTPURLResponse)?.statusCode ?? -1,userInfo:[NSLocalizedDescriptionKey:message])
        }
    }

    private static func appCheckToken() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            AppCheck.appCheck().token(forcingRefresh: false) { token, error in
                if let error { continuation.resume(throwing: error) }
                else if let token { continuation.resume(returning: token.token) }
                else { continuation.resume(throwing: URLError(.userAuthenticationRequired)) }
            }
        }
    }

    /// Every rydr-backend `/driver/*` route now requires a verified Firebase
    /// ID token (see rydr-backend/src/middleware/firebaseAuth.js) and checks
    /// that the body's uid/driverId matches the token — so every call from
    /// this service must carry a fresh ID token, never just the raw uid.
    private static func makeAuthenticatedRequest<T: Encodable>(path: String, method: String, body: T) async throws -> URLRequest? {
        guard let baseURLString,
              let baseURL = URL(string: baseURLString),
              let url = URL(string: path, relativeTo: baseURL) else {
            return nil
        }

        guard let user = Auth.auth().currentUser else {
            throw URLError(.userAuthenticationRequired)
        }
        let idToken = try await user.getIDToken()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue(try await appCheckToken(), forHTTPHeaderField: "X-Firebase-AppCheck")
        request.timeoutInterval = 20
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    struct WaitTimeEvent: Encodable {
        let rideId: String
        let driverId: String
        let riderId: String
        let waitStage: String
        let complimentarySeconds: Int
        let paidWaitSeconds: Int
        let timestamp: String
    }

    struct AccountDeletionRequest: Encodable {
        let reason: String?
    }

    private struct AccountIdentityRequest: Encodable {
        let role: String
        let betaWaiverAccepted: Bool
    }
    private struct VehiclePlateRequest: Encodable { let plate: String }
    private struct EmptyRequest: Encodable {}

    private struct RideTransitionRequest: Encodable {
        let action: String
        let requestId: String
        let reason: String?
        let queued: Bool
    }

    private struct RideRouteEstimateRequest: Encodable {
        let departureDate: String
    }

    struct DriverPresenceRequest: Encodable {
        let online: Bool
        let selectedRideTypes: [String]
        let location: DriverPresenceLocation?
    }

    struct DriverPresenceLocation: Encodable {
        let lat: Double
        let lng: Double
        let speed: Double
        let course: Double
    }

    struct DriverPresenceResponse: Decodable {
        let ok: Bool
        let online: Bool
        let availabilityStatus: String
        let hasActiveRide: Bool
        let selectedRideTypes: [String]
    }

    struct DriverDemandRequest: Encodable {
        let rideTypes: [String]
    }

    struct DriverDemandResponse: Decodable {
        struct TierDemand: Decodable {
            struct SuggestedRates: Decodable {
                let minimumFareCents: Int
                let perMileCents: Int
                let perMinuteCents: Int
            }

            let level: String
            let paceText: String
            let nearbyRequestCount: Int
            let radiusMiles: Double
            let suggestedRates: SuggestedRates
        }

        let ok: Bool
        let level: String
        let paceText: String
        let nearbyRequestCount: Int
        let radiusMiles: Double
        let byRideType: [String: TierDemand]
    }

    struct RideTelemetryRequest: Encodable {
        let eventId: String
        let lat: Double
        let lng: Double
        let speed: Double
        let course: Double
        let horizontalAccuracy: Double
    }

    struct RideRatingRequest: Encodable {
        let rating: Int?
        let feedback: String
        let compliments: [String]
        let favoriteDriver: Bool
    }

    private struct QueuePromotionRequest: Encodable { let requestId: String }

    struct BackgroundCheckRequest: Encodable {
        let firstName: String
        let lastName: String
        let email: String
        let phone: String
        let dob: String
        let licenseLast4: String
        let licenseState: String
        let acknowledged: Bool
    }

    struct RateCardRequest: Encodable {
        let rideType: String
        let minimumFare: Double
        let perMile: Double
        let perMinute: Double
        let useSuggestedPricing: Bool
    }

    struct RateCardResponse: Decodable {
        struct SavedRate: Decodable {
            let minimumFare: Double
            let perMile: Double
            let perMinute: Double
            let useSuggestedPricing: Bool
        }

        let ok: Bool
        let rideType: String
        let rate: SavedRate
    }

    struct RateCardLoadResponse: Decodable {
        let ok: Bool
        let tierRates: [String: RateCardResponse.SavedRate]
    }

    struct EarningsSummaryResponse: Decodable {
        struct Trip: Decodable { let id:String;let pickup:String;let dropoff:String;let fareCents:Int;let completedAt:String? }
        let todayCents:Int;let weekCents:Int;let monthCents:Int;let acceptanceRate:Double?;let completionRate:Double?;let recentTrips:[Trip]
    }

    struct ReportableRide: Decodable, Identifiable, Hashable {
        let id: String
        let pickup: String
        let dropoff: String
        let rideType: String
        let riderName: String
        let completedAt: String?

        var completedDate: Date? {
            guard let completedAt else { return nil }
            return ISO8601DateFormatter().date(from: completedAt)
        }
    }

    private struct ReportableRidesResponse: Decodable {
        let rides: [ReportableRide]
    }

    struct QueuePromotionResponse: Decodable {
        let ok: Bool
        let promoted: Bool
        let rideId: String?
        let status: String?
    }

    struct RideTransitionResponse: Decodable {
        struct FinancialOutcome: Decodable {
            let driverPayoutCents: Int
        }

        let ok: Bool
        let status: String
        let duplicate: Bool
        let outcome: FinancialOutcome?
    }

    private struct BackendError: Decodable { let error: String }
}
