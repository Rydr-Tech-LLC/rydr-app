import FirebaseAuth
import StripeIdentity
import UIKit

enum DriverIdentityVerificationError: LocalizedError {
    case notSignedIn
    case invalidResponse
    case unsupportedOS

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in before starting identity verification."
        case .invalidResponse:
            return "The identity service returned an invalid response. Please try again."
        case .unsupportedOS:
            return "Identity verification requires iOS 14.3 or newer."
        }
    }
}

struct DriverIdentityStatus: Decodable {
    let identityVerified: Bool
    let identityStatus: String
}

private struct DriverIdentitySessionResponse: Decodable {
    let id: String
    let clientSecret: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case clientSecret = "client_secret"
        case status
    }
}

final class DriverIdentityVerificationService {
    static let shared = DriverIdentityVerificationService()

    private let backendBase = URL(string: "https://rydr-stripe-backend.onrender.com")!
    private var verificationSheet: IdentityVerificationSheet?

    private init() {}

    func createSession() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw DriverIdentityVerificationError.notSignedIn
        }
        let token = try await user.getIDToken()
        var request = URLRequest(url: backendBase.appendingPathComponent("identity/create-session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["role": "driver"])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DriverIdentityVerificationError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(DriverIdentitySessionResponse.self, from: data)
        return decoded.clientSecret
    }

    func fetchStatus() async throws -> DriverIdentityStatus {
        guard let user = Auth.auth().currentUser else {
            throw DriverIdentityVerificationError.notSignedIn
        }
        let token = try await user.getIDToken()
        var components = URLComponents(url: backendBase.appendingPathComponent("identity/status"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "role", value: "driver")]
        guard let url = components.url else { throw DriverIdentityVerificationError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DriverIdentityVerificationError.invalidResponse
        }
        return try JSONDecoder().decode(DriverIdentityStatus.self, from: data)
    }

    @MainActor
    func presentVerification(clientSecret: String) async throws -> IdentityVerificationSheet.VerificationFlowResult {
        guard #available(iOS 14.3, *) else {
            throw DriverIdentityVerificationError.unsupportedOS
        }
        guard let presenter = UIApplication.shared.rydrTopViewController() else {
            throw DriverIdentityVerificationError.invalidResponse
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
