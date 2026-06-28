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
}
