import FirebaseAuth
import StripeIdentity
import UIKit

enum RiderIdentityVerificationError: LocalizedError {
    case notSignedIn
    case invalidResponse
    case serviceError(String)
    case unsupportedOS

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in before starting identity verification."
        case .invalidResponse:
            return "The identity service returned an invalid response. Please try again."
        case .serviceError(let message):
            return message
        case .unsupportedOS:
            return "Identity verification requires iOS 14.3 or newer."
        }
    }
}

struct RiderIdentityStatus: Decodable {
    let identityVerified: Bool
    let verifiedRider: Bool
    let verifiedBadge: Bool
    let identityStatus: String
}

private struct RiderIdentitySessionResponse: Decodable {
    let id: String
    let clientSecret: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case clientSecret = "client_secret"
        case status
    }
}

private struct RiderIdentityBackendError: Decodable {
    let error: String?
    let message: String?
}

final class RiderIdentityVerificationService {
    static let shared = RiderIdentityVerificationService()

    private let backendBase = URL(string: "https://rydr-stripe-backend.onrender.com")!
    private var verificationSheet: IdentityVerificationSheet?

    private init() {}

    func createSession() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw RiderIdentityVerificationError.notSignedIn
        }
        let token = try await refreshedIDToken(for: user)
        var request = URLRequest(url: backendBase.appendingPathComponent("identity/create-session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "role": "verified_rider",
            "requestId": UUID().uuidString
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(RiderIdentitySessionResponse.self, from: data)
        return decoded.clientSecret
    }

    func fetchStatus() async throws -> RiderIdentityStatus {
        guard let user = Auth.auth().currentUser else {
            throw RiderIdentityVerificationError.notSignedIn
        }
        let token = try await refreshedIDToken(for: user)
        var components = URLComponents(url: backendBase.appendingPathComponent("identity/status"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "role", value: "verified_rider")]
        guard let url = components.url else { throw RiderIdentityVerificationError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(RiderIdentityStatus.self, from: data)
    }

    @MainActor
    func presentVerification(clientSecret: String) async throws -> IdentityVerificationSheet.VerificationFlowResult {
        guard #available(iOS 14.3, *) else {
            throw RiderIdentityVerificationError.unsupportedOS
        }
        guard let presenter = UIApplication.shared.rydrTopViewController() else {
            throw RiderIdentityVerificationError.invalidResponse
        }

        return await withCheckedContinuation { continuation in
            let sheet = IdentityVerificationSheet(verificationSessionClientSecret: clientSecret)
            verificationSheet = sheet
            sheet.present(from: presenter) { [weak self] result in
                self?.verificationSheet = nil
                continuation.resume(returning: result)
            }
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw RiderIdentityVerificationError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw RiderIdentityVerificationError.serviceError(message(for: http.statusCode, data: data))
        }
    }

    private func message(for statusCode: Int, data: Data) -> String {
        let backendError = try? JSONDecoder().decode(RiderIdentityBackendError.self, from: data)
        let rawMessage = backendError?.message ?? backendError?.error

        switch rawMessage {
        case "identity_flow_not_configured":
            return "Rydr's Stripe Identity flow is not configured yet. Add STRIPE_RIDER_VERIFICATION_FLOW_ID on the Stripe backend, then redeploy."
        case "identity_verification_flow_invalid":
            return backendError?.message ?? "Stripe could not find the configured rider verification flow. Confirm STRIPE_RIDER_VERIFICATION_FLOW_ID in the Stripe backend environment."
        case "stripe_identity_auth_failed":
            return backendError?.message ?? "Stripe rejected the backend API key. Check STRIPE_SECRET_KEY on the Stripe backend."
        case "firebase_admin_misconfigured":
            return backendError?.message ?? "The Stripe backend Firebase Admin credentials are not configured correctly."
        case "unauthorized":
            return "Your session expired. Sign in again before starting verification."
        case let message? where !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return "Identity verification could not start: \(message)"
        default:
            return "Identity verification could not start. The service returned HTTP \(statusCode)."
        }
    }

    private func refreshedIDToken(for user: User) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(true) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: RiderIdentityVerificationError.notSignedIn)
                }
            }
        }
    }
}

private extension UIApplication {
    func rydrTopViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return rydrTopViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return rydrTopViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return rydrTopViewController(base: presented)
        }
        return base
    }
}
