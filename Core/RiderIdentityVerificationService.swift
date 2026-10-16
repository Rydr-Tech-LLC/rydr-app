import FirebaseFunctions
import FirebaseStorage
import FirebaseCore
import SwiftUI
import FirebaseFirestore
import CryptoKit
import FirebaseAuth
import Stripe
import StripeIdentity
import UIKit

// Account environment is derived from signed-in Firebase identity and server policy.
private struct RydrWorkspaceBootstrap: Decodable {
    let authenticationVersion: Int
    let authProjects: [String: String]
}
private final class RydrWorkspacePolicyCache: @unchecked Sendable {
    private let lock = NSLock()
    private var value: RydrWorkspaceBootstrap?
    func read() -> RydrWorkspaceBootstrap? { lock.lock(); defer { lock.unlock() }; return value }
    func write(_ value: RydrWorkspaceBootstrap) { lock.lock(); defer { lock.unlock() }; self.value = value }
}
enum RydrWorkspace {
    private static let cache = RydrWorkspacePolicyCache()
    static let selectionKey = "rydr.authWorkspace.v2"
    static let testProject = "rydr-test-c7ec1"
    static let liveProject = "rydrapp-c7ec1"
    static var selected: String? {
        guard let value = UserDefaults.standard.string(forKey: selectionKey), ["test", "live-beta"].contains(value) else { return nil }
        return value
    }
    static var isReady: Bool {
        guard selected != nil, let policy = cache.read() else { return false }
        return policy.authenticationVersion == 2 && policy.authProjects["test"] == testProject && policy.authProjects["live-beta"] == liveProject
    }
    static var identifier: String? { isReady ? selected : nil }
    static var firebaseApp: FirebaseApp {
        guard selected == "test" else { return FirebaseApp.app()! }
        if let existing = FirebaseApp.app(name: "RydrTest") { return existing }
        let options = FirebaseOptions(googleAppID: "1:59820296181:ios:ecc469ffeeeba4d872c2bc", gcmSenderID: "59820296181")
        options.apiKey = "AIzaSyDdAMCp20nBnSlgw6XzZ9G5n_8LlMz4QK8"
        options.projectID = testProject
        options.storageBucket = testProject + ".firebasestorage.app"
        FirebaseApp.configure(name: "RydrTest", options: options)
        return FirebaseApp.app(name: "RydrTest")!
    }
    static var auth: Auth {
        let service = Auth.auth(app: firebaseApp)
        if selected == "test" { service.settings?.isAppVerificationDisabledForTesting = true }
        return service
    }
    static var firestore: Firestore { Firestore.firestore(app: firebaseApp, database: identifier == "test" ? "(default)" : identifier == "live-beta" ? "live-beta" : "workspace-unresolved") }
    static var storage: Storage { Storage.storage(app: firebaseApp) }
    static func functions(region: String = "us-central1") -> Functions { Functions.functions(app: firebaseApp, region: region) }
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
        guard policy.authenticationVersion == 2, policy.authProjects["test"] == testProject, policy.authProjects["live-beta"] == liveProject else { throw URLError(.cannotParseResponse) }
        cache.write(policy)
    }
}
struct RydrWorkspaceGate<Content: View>: View {
    @AppStorage(RydrWorkspace.selectionKey) private var selection = ""
    @State private var ready = false
    @State private var failed = false
    @State private var retry = 0
    @State private var signedInUID: String?
    @State private var observedAuth: Auth?
    @State private var authListener: AuthStateDidChangeListenerHandle?
    @ViewBuilder let content: () -> Content
    private let gradient = LinearGradient(colors: [.red, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    var body: some View {
        Group {
            if selection.isEmpty {
                VStack(alignment: .leading, spacing: 24) {
                    Image("RydrWelcomeLogo").resizable().scaledToFit().frame(height: 80)
                    Text("Choose your beta workspace").font(.largeTitle.bold())
                    Text("Use the same email and phone in both. Your accounts, rides and payments stay separate.").foregroundStyle(.secondary)
                    workspaceButton("Live Beta", detail: "Real rides and real payments", icon: "car.fill", value: "live-beta")
                    workspaceButton("Test", detail: "Simulated rides and payments", icon: "testtube.2", value: "test")
                }.padding(28).frame(maxWidth: 520)
            } else if ready {
                content().id(selection).safeAreaInset(edge: .top, spacing: 0) {
                    HStack {
                        Text(selection == "test" ? "TEST WORKSPACE · Simulated payments" : "LIVE BETA · Real payments")
                            .font(.system(size: 10, weight: .semibold)).tracking(1)
                        Spacer()
                        if signedInUID == nil { Button("Switch") { clearSelection() }.font(.caption.bold()) }
                    }.padding(.horizontal, 16).padding(.vertical, 7).foregroundStyle(.white).background(gradient)
                }
            } else {
                VStack(spacing: 18) {
                    if failed {
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.red)
                        Text("Unable to verify your workspace").font(.headline)
                        Text("Check your connection and try again.").foregroundStyle(.secondary)
                        Button("Try again") { retry += 1 }.buttonStyle(.borderedProminent).tint(.red)
                        Button("Change workspace") { clearSelection() }
                    } else { ProgressView("Connecting securely…") }
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: selection + String(retry)) {
            ready = false; failed = false
            if let authListener { observedAuth?.removeStateDidChangeListener(authListener) }
            guard !selection.isEmpty else { return }
            do {
                try await RydrWorkspace.bootstrap()
                observedAuth = RydrWorkspace.auth
                signedInUID = observedAuth?.currentUser?.uid
                authListener = observedAuth?.addStateDidChangeListener { _, user in signedInUID = user?.uid }
                ready = true
            } catch { failed = true }
        }
        .onDisappear { if let authListener { observedAuth?.removeStateDidChangeListener(authListener) } }
    }
    private func clearSelection() {
        try? RydrWorkspace.auth.signOut()
        UserDefaults.standard.set(false, forKey: "isLoggedIn")
        UserDefaults.standard.set(false, forKey: "rydr.session.\(RydrWorkspace.selected ?? "unresolved").isLoggedIn")
        signedInUID = nil
        selection = ""
    }
    private func workspaceButton(_ title: String, detail: String, icon: String, value: String) -> some View {
        Button {
            try? RydrWorkspace.auth.signOut()
            UserDefaults.standard.set(false, forKey: "isLoggedIn")
        UserDefaults.standard.set(false, forKey: "rydr.session.\(RydrWorkspace.selected ?? "unresolved").isLoggedIn")
            UserDefaults.standard.set(false, forKey: "rydr.session.\(value).isLoggedIn")
            selection = value
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.title2).foregroundStyle(gradient)
                VStack(alignment: .leading, spacing: 5) { Text(title).font(.title3.bold()); Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                Spacer()
                Image(systemName: "arrow.right.circle.fill").foregroundStyle(gradient)
            }.padding(20).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityIdentifier("authWorkspace-" + value)
    }
}

enum RydrStripeBackendConfig {
    private struct StripeRuntimeConfig: Decodable {
        let publishableKey: String
        let mode: String?
    }

    @MainActor private static var configuredPublishableKey: String?
    @MainActor private static var configuredUID: String?

    static var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "RYDR_STRIPE_BACKEND_BASE_URL") as? String,
           let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return url
        }
        return URL(string: "https://rydr-stripe-backend.onrender.com")!
    }

    @MainActor
    static var hasConfiguredPublishableKey: Bool {
        configuredPublishableKey != nil && configuredUID == RydrWorkspace.auth.currentUser.map { (RydrWorkspace.identifier ?? "unresolved") + ":" + $0.uid }
    }

    @MainActor
    static func configureStripePublishableKeyIfNeeded() async {
        guard let uid = RydrWorkspace.auth.currentUser?.uid else { configuredPublishableKey = nil; configuredUID = nil; StripeAPI.defaultPublishableKey = nil; return }
        let accountKey = (RydrWorkspace.identifier ?? "unresolved") + ":" + uid
        if configuredPublishableKey != nil && configuredUID == accountKey { return }
        configuredPublishableKey = nil
        configuredUID = nil
        StripeAPI.defaultPublishableKey = nil

        do {
            let config = try await fetchRuntimeConfig()
            guard isValidPublishableKey(config.publishableKey),
                  config.mode == (RydrWorkspace.identifier == "test" ? "test" : "live"),
                  config.publishableKey.hasPrefix(RydrWorkspace.identifier == "test" ? "pk_test_" : "pk_live_") else {
                print("⚠️ Stripe config endpoint returned an invalid publishable key.")
                return
            }

            guard RydrWorkspace.auth.currentUser?.uid == uid else { return }
            StripeAPI.defaultPublishableKey = config.publishableKey
            configuredPublishableKey = config.publishableKey
            configuredUID = accountKey
            print("💳 Stripe \(config.mode ?? "unknown") publishable key loaded from backend")
        } catch {
            // No bundled-key fallback: an unverified account must never inherit another environment.
            configuredPublishableKey = nil
            configuredUID = nil
            StripeAPI.defaultPublishableKey = nil
        }
    }

    private static func fetchRuntimeConfig() async throws -> StripeRuntimeConfig {
        guard let user = RydrWorkspace.auth.currentUser else { throw URLError(.userAuthenticationRequired) }
        var request = URLRequest(url: baseURL.appendingPathComponent("account-config"))
        request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(StripeRuntimeConfig.self, from: data)
    }

    private static func bundledPublishableKey() -> String? {
        (Bundle.main.object(forInfoDictionaryKey: "STRIPE_PUBLISHABLE_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isValidPublishableKey(_ key: String) -> Bool {
        key.hasPrefix("pk_test_") || key.hasPrefix("pk_live_")
    }
}

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

    private let backendBase = RydrStripeBackendConfig.baseURL
    private var verificationSheet: IdentityVerificationSheet?

    private init() {}

    func createSession() async throws -> String {
        guard let user = RydrWorkspace.auth.currentUser else {
            throw RiderIdentityVerificationError.notSignedIn
        }
        let token = try await refreshedIDToken(for: user)
        var request = RydrWorkspace.urlRequest(url: backendBase.appendingPathComponent("identity/create-session"))
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
        guard let user = RydrWorkspace.auth.currentUser else {
            throw RiderIdentityVerificationError.notSignedIn
        }
        let token = try await refreshedIDToken(for: user)
        var components = URLComponents(url: backendBase.appendingPathComponent("identity/status"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "role", value: "verified_rider")]
        guard let url = components.url else { throw RiderIdentityVerificationError.invalidResponse }

        var request = RydrWorkspace.urlRequest(url: url)
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
