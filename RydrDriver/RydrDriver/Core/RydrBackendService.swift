import Foundation
import FirebaseAuth

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
        guard let request = try await makeAuthenticatedRequest(path: "/driver/account-deletion-requests", method: "POST", body: requestBody) else {
            throw URLError(.badURL)
        }
        _ = try await URLSession.shared.data(for: request)
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
        let uid: String
        let role: String
        let email: String?
        let reason: String?
        let requestedAt: String
    }

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

    struct RideTransitionResponse: Decodable {
        let ok: Bool
        let status: String
        let duplicate: Bool
    }

    private struct BackendError: Decodable { let error: String }
}
