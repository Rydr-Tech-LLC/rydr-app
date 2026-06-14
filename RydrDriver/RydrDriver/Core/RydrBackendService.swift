import Foundation

enum RydrBackendService {
    private static let baseURLString = Bundle.main.object(forInfoDictionaryKey: "RYDR_BACKEND_BASE_URL") as? String

    static var isConfigured: Bool {
        guard let baseURLString else { return false }
        return URL(string: baseURLString) != nil
    }

    static func recordWaitTimeEvent(_ event: WaitTimeEvent) async {
        guard let request = makeRequest(path: "/driver/wait-time-events", method: "POST", body: event) else {
            return
        }

        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            RydrCrashReporter.record(error, context: "record_wait_time_event")
        }
    }

    static func requestAccountDeletion(_ requestBody: AccountDeletionRequest) async throws {
        guard let request = makeRequest(path: "/driver/account-deletion-requests", method: "POST", body: requestBody) else {
            throw URLError(.badURL)
        }
        _ = try await URLSession.shared.data(for: request)
    }

    private static func makeRequest<T: Encodable>(path: String, method: String, body: T) -> URLRequest? {
        guard let baseURLString,
              let baseURL = URL(string: baseURLString),
              let url = URL(string: path, relativeTo: baseURL) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }

    struct WaitTimeEvent: Encodable {
        let rideId: String
        let driverId: String
        let riderId: String
        let stage: String
        let paidWaitSeconds: Int
        let complimentaryWaitSeconds: Int
        let recordedAtISO8601: String
    }

    struct AccountDeletionRequest: Encodable {
        let uid: String
        let email: String?
        let requestedAtISO8601: String
        let source: String
    }
}
