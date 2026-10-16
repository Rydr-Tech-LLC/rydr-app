import SwiftUI
import FirebaseFirestore
import CryptoKit
import FirebaseAuth
import StripeIdentity
import UIKit

// Account environment is derived from signed-in Firebase identity and server policy.
private struct RydrWorkspaceBootstrap: Decodable {
    let testUidHashes: [String]
    let testPhoneHashes: [String]
}
private final class RydrWorkspacePolicyCache: @unchecked Sendable {
    let lock = NSLock()
    var value: RydrWorkspaceBootstrap?
    func read() -> RydrWorkspaceBootstrap? { lock.lock(); defer { lock.unlock() }; return value }
    func write(_ value: RydrWorkspaceBootstrap) { lock.lock(); defer { lock.unlock() }; self.value = value }
}
enum RydrWorkspace {
    private static let cache = RydrWorkspacePolicyCache()
    static var isReady: Bool { cache.read() != nil }
    private static func hash(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    static var identifier: String? {
        guard let policy = cache.read(), let user = Auth.auth().currentUser else { return nil }
        return policy.testUidHashes.contains(hash(user.uid)) || policy.testPhoneHashes.contains(hash(user.phoneNumber ?? "")) ? "test" : "live-beta"
    }
    static var firestore: Firestore { Firestore.firestore(database: identifier == "test" ? "(default)" : identifier == "live-beta" ? "live-beta" : "workspace-unresolved") }
    static func functionName(_ name: String) -> String { identifier == "test" ? name : "liveBeta-" + name }
    static func scopedURL(_ url: URL) -> URL {
        guard ["rydr-stripe-backend.onrender.com", "rydr-backend-2cl9.onrender.com", "rydr-backend.onrender.com", "rydr-bank.onrender.com"].contains(url.host ?? "") else { return url }
        guard !["/workspace-bootstrap", "/account-config"].contains(url.path) else { return url }
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let path = parts.path.replacingOccurrences(of: "^/workspaces/(test|live-beta|unresolved)(?=/|$)", with: "", options: .regularExpression)
        parts.path = "/workspaces/\(identifier ?? "unresolved")" + (path.hasPrefix("/") ? path : "/" + path)
        return parts.url ?? url
    }
    static func urlRequest(url: URL, cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy, timeoutInterval: TimeInterval = 60) -> URLRequest {
        URLRequest(url: scopedURL(url), cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
    }
    static func bootstrap() async throws {
        var request = URLRequest(url: URL(string: "https://rydr-stripe-backend.onrender.com/workspace-bootstrap")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        let policy = try JSONDecoder().decode(RydrWorkspaceBootstrap.self, from: data)
        guard !policy.testPhoneHashes.isEmpty else { throw URLError(.cannotParseResponse) }
        cache.write(policy)
    }
}
struct RydrWorkspaceGate<Content: View>: View {
    @State private var ready = RydrWorkspace.isReady
    @State private var failed = false
    @State private var retry = 0
    @State private var signedInUID: String?
    @State private var authListener: AuthStateDidChangeListenerHandle?
    @ViewBuilder let content: () -> Content
    var body: some View {
        Group {
            if ready {
                content().safeAreaInset(edge: .top, spacing: 0) {
                    if signedInUID != nil && RydrWorkspace.identifier == "test" {
                        Text("TEST WORKSPACE · Simulated payments")
                            .font(.system(size: 10, weight: .semibold)).tracking(1)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .foregroundStyle(.white)
                            .background(LinearGradient(colors: [.red, .purple], startPoint: .leading, endPoint: .trailing))
                    }
                }
            } else {
                VStack(spacing: 18) {
                    if failed {
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.red)
                        Text("Unable to verify your workspace").font(.headline)
                        Text("Check your connection and try again.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Try again") { failed = false; retry += 1 }.buttonStyle(.borderedProminent).tint(.red)
                    } else { ProgressView("Connecting securely…") }
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: retry) { do { try await RydrWorkspace.bootstrap(); ready = true } catch { failed = true } }
        .onAppear { authListener = Auth.auth().addStateDidChangeListener { _, user in signedInUID = user?.uid } }
        .onDisappear { if let authListener { Auth.auth().removeStateDidChangeListener(authListener) } }
    }
}

enum DriverIdentityVerificationError: LocalizedError {
    case notSignedIn
    case invalidResponse
    case server(String)
    case unsupportedOS

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in before starting identity verification."
        case .invalidResponse:
            return "The identity service returned an invalid response. Please try again."
        case .server(let message):
            return message
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

private struct DriverIdentityBackendError: Decodable {
    let error: String
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
        let token = try await refreshedIDToken(for: user)
        var request = RydrWorkspace.urlRequest(url: backendBase.appendingPathComponent("identity/create-session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "role": "driver",
            "requestId": UUID().uuidString
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw backendError(from: data, response: response)
        }
        let decoded = try JSONDecoder().decode(DriverIdentitySessionResponse.self, from: data)
        return decoded.clientSecret
    }

    func fetchStatus() async throws -> DriverIdentityStatus {
        guard let user = Auth.auth().currentUser else {
            throw DriverIdentityVerificationError.notSignedIn
        }
        let token = try await refreshedIDToken(for: user)
        var components = URLComponents(url: backendBase.appendingPathComponent("identity/status"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "role", value: "driver")]
        guard let url = components.url else { throw DriverIdentityVerificationError.invalidResponse }

        var request = RydrWorkspace.urlRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw backendError(from: data, response: response)
        }
        return try JSONDecoder().decode(DriverIdentityStatus.self, from: data)
    }

    private func backendError(from data: Data, response: URLResponse) -> DriverIdentityVerificationError {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        if let decoded = try? JSONDecoder().decode(DriverIdentityBackendError.self, from: data) {
            return .server("Identity service error (\(statusCode)): \(decoded.error)")
        }
        return .invalidResponse
    }

    private func refreshedIDToken(for user: User) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(true) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: DriverIdentityVerificationError.notSignedIn)
                }
            }
        }
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
