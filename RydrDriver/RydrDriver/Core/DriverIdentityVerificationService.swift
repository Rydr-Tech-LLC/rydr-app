import FirebaseFunctions
import FirebaseStorage
import FirebaseCore
import SwiftUI
import FirebaseFirestore
import CryptoKit
import FirebaseAuth
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
        let options = FirebaseOptions(googleAppID: "1:59820296181:ios:25472dddf79d6fea72c2bc", gcmSenderID: "59820296181")
        options.apiKey = "AIzaSyAWqW20kJWVPB7do1kNbQKyubA3etJlnLQ"
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
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
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
                    Image("Rydr - Driver").resizable().scaledToFit().frame(height: 80)
                    Text("Choose your beta workspace").font(.largeTitle.bold())
                    Text("Use the same email and phone in both. Your accounts, rides and payments stay separate.").foregroundStyle(.secondary)
                    workspaceButton("Live Beta", detail: "Real rides and real payments", icon: "car.fill", value: "live-beta")
                    workspaceButton("Test", detail: "Simulated rides and payments", icon: "testtube.2", value: "test")
                }.padding(28).frame(maxWidth: 520)
            } else if ready {
                content().id(selection).safeAreaInset(edge: .top, spacing: 0) {
                    if selection == "test" {
                      HStack {
                        Text("TEST WORKSPACE · Simulated payments")
                            .font(.system(size: 10, weight: .semibold)).tracking(1)
                        Spacer()
                        if signedInUID == nil { Button("Switch") { clearSelection() }.font(.caption.bold()) }
                      }.padding(.horizontal, 16).padding(.vertical, 7).foregroundStyle(.white).background(gradient)
                    } else if signedInUID == nil {
                        HStack {
                            Spacer()
                            Button("Switch workspace") { clearSelection() }.font(.caption.bold()).tint(.red)
                        }.padding(.horizontal, 16).padding(.vertical, 7)
                    }
                }
            } else {
                VStack(spacing: 18) {
                    if failed {
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.red)
                        Text("Unable to verify your workspace").font(.headline)
                        Text("Check your connection and try again.").foregroundStyle(.secondary)
                        Button("Try again") { retry += 1 }.buttonStyle(.borderedProminent).tint(.red)
                        Button("Change workspace") { clearSelection() }
                    } else { RydrLoadingView() }
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

    var isVerified: Bool { identityVerified || identityStatus == "verified" }
    // Only a trusted backend status can unlock the rest of onboarding.
    // Processing is a submitted application, never permission to drive.
    var canContinueOnboarding: Bool { isVerified || identityStatus == "processing" }
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
        guard let user = RydrWorkspace.auth.currentUser else {
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
        guard let user = RydrWorkspace.auth.currentUser else {
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


/// Quiet app restoration screen using the same R mark and breathing ring as ride matching.
struct RydrLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false
    private let gradient = LinearGradient(colors: [.red, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            ZStack {
                Circle().stroke(Color.red.opacity(0.12), lineWidth: 6)
                    .frame(width: 108, height: 108)
                    .scaleEffect(animate && !reduceMotion ? 1.10 : 0.94)
                Circle().trim(from: 0.08, to: 0.78)
                    .stroke(gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 108, height: 108)
                    .rotationEffect(.degrees(animate && !reduceMotion ? 360 : 0))
                    .shadow(color: .red.opacity(0.2), radius: 10)
                    .animation(reduceMotion ? nil : .linear(duration: 1.2).repeatForever(autoreverses: false), value: animate)
                Image("RydrBankWalletR").resizable().scaledToFit().frame(width: 58, height: 58)
                    .scaleEffect(animate && !reduceMotion ? 1 : 0.88)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: animate)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading Rydr")
            .accessibilityIdentifier("rydrLoading")
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { animate = true }
    }
}
