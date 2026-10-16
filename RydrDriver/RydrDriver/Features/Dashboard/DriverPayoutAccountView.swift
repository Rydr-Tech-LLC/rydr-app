import SwiftUI
import FirebaseAuth
import StripePayments
@_spi(PreviewConnect) import StripeConnect

/// Sensitive account details go directly through Stripe's embedded component.
/// Rydr controls the session, navigation, and payout policy; no Express dashboard link.
struct DriverPayoutAccountView: View {
    enum Purpose: String { case onboarding; case payoutMethods = "payout_methods" }
    let purpose: Purpose
    @Environment(\.dismiss) private var dismiss
    @State private var manager: EmbeddedComponentManager?
    @State private var errorMessage: String?
    @State private var attempt = UUID()
    var body: some View {
        NavigationStack {
            Group {
                if let manager {
                    EmbeddedDriverAccount(manager: manager, purpose: purpose, onExit: { dismiss() }, onError: { self.manager = nil; errorMessage = $0 }).id(attempt)
                } else if let errorMessage {
                    VStack(spacing: 16) {
                        Text(errorMessage).multilineTextAlignment(.center)
                        Button("Try again") { Task { await prepare() } }.accessibilityIdentifier("securePayoutRetry")
                    }.padding()
                } else { ProgressView("Loading payout setup…") }
            }
            .navigationTitle(purpose == .onboarding ? "Payout setup" : "Bank accounts & cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.accessibilityIdentifier("securePayoutDone") } }

        }
        .task { await prepare() }
    }
    @MainActor private func prepare() async {
        errorMessage = nil
        manager = nil
        attempt = UUID()
        do {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("-DriverPayoutMethodsUITest") { throw URLError(.notConnectedToInternet) }
            #endif
            guard let workspace = RydrWorkspace.identifier, let uid = RydrWorkspace.auth.currentUser?.uid else { throw URLError(.userAuthenticationRequired) }
            let config: Config = try await DriverConnectAPI.get("config")
            guard config.publishableKey.hasPrefix(workspace == "test" ? "pk_test_" : "pk_live_") else { throw URLError(.badServerResponse) }
            guard config.mode == (workspace == "test" ? "test" : "live") else { throw URLError(.badServerResponse) }
            let apiClient = STPAPIClient(publishableKey: config.publishableKey)
            // Preflight makes backend/session errors visible instead of leaving a spinner.
            let first: Session = try await DriverConnectAPI.session(purpose: purpose.rawValue)
            guard RydrWorkspace.identifier == workspace, RydrWorkspace.auth.currentUser?.uid == uid, first.workspace == workspace, first.mode == config.mode else { throw URLError(.badServerResponse) }
            let secrets = DriverAccountSessionLoader(first: first.clientSecret, purpose: purpose.rawValue, workspace: workspace, uid: uid)
            var appearance = EmbeddedComponentManager.Appearance()
            appearance.colors.primary = UIColor(red: 0.85, green: 0.04, blue: 0.20, alpha: 1)
            appearance.colors.background = .systemBackground
            appearance.colors.text = .label
            appearance.colors.secondaryText = .secondaryLabel
            manager = EmbeddedComponentManager(apiClient: apiClient, appearance: appearance, fetchClientSecret: {
                await secrets.next()
            })
        } catch { errorMessage = error is DriverConnectServiceError ? error.localizedDescription : "Couldn't load secure payout setup. Check your connection and try again." }
    }
    private struct Config: Decodable { let publishableKey: String; let mode: String }
    fileprivate struct Session: Decodable { let clientSecret: String; let mode: String; let workspace: String }
}

private actor DriverAccountSessionLoader {
    var first: String?
    let purpose: String
    let workspace: String
    let uid: String?
    init(first: String, purpose: String, workspace: String, uid: String?) { self.first = first; self.purpose = purpose; self.workspace = workspace; self.uid = uid }
    func next() async -> String? {
        guard RydrWorkspace.identifier == workspace, let uid, RydrWorkspace.auth.currentUser?.uid == uid else { return nil }
        if let first { self.first = nil; return first }
        guard let session = try? await DriverConnectAPI.session(purpose: purpose),
              session.workspace == workspace, session.mode == (workspace == "test" ? "test" : "live"),
              RydrWorkspace.identifier == workspace, RydrWorkspace.auth.currentUser?.uid == uid else { return nil }
        return session.clientSecret
    }
}

private struct EmbeddedDriverAccount: UIViewControllerRepresentable {
    let manager: EmbeddedComponentManager
    let purpose: DriverPayoutAccountView.Purpose
    let onExit: () -> Void
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onExit: onExit, onError: onError) }
    func makeUIViewController(context: Context) -> UIViewController {
        if purpose == .payoutMethods {
            let controller = manager.createPayoutsViewController()
            controller.delegate = context.coordinator
            return controller
        }
        let host = OnboardingHost()
        let onboarding = manager.createAccountOnboardingController()
        onboarding.title = "Rydr payout setup"
        onboarding.delegate = context.coordinator
        host.onboarding = onboarding
        return host
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
    final class Coordinator: NSObject, AccountOnboardingControllerDelegate, PayoutsViewControllerDelegate {
        let onExit: () -> Void
        let onError: (String) -> Void
        init(onExit: @escaping () -> Void, onError: @escaping (String) -> Void) { self.onExit = onExit; self.onError = onError }
        func accountOnboardingDidExit(_ accountOnboarding: AccountOnboardingController) { onExit() }
        func accountOnboarding(_ accountOnboarding: AccountOnboardingController, didFailLoadWithError error: Error) { onError("Payout setup couldn't load. Close this screen and try again.") }
        func payouts(_ payouts: PayoutsViewController, didFailLoadWithError error: Error) { onError("Bank accounts and cards couldn't load. Close this screen and try again.") }
    }
    final class OnboardingHost: UIViewController {
        var onboarding: AccountOnboardingController?
        private var presented = false
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !presented else { return }
            presented = true
            onboarding?.present(from: self)
        }
    }
}

enum DriverConnectAPI {
    static let base = URL(string: "https://rydr-stripe-backend.onrender.com")!
    static func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(RydrWorkspace.urlRequest(url: base.appendingPathComponent(path)))
    }
    fileprivate static func session(purpose: String) async throws -> DriverPayoutAccountView.Session {
        var request = RydrWorkspace.urlRequest(url: base.appendingPathComponent("connect/account-session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["purpose": purpose])
        return try await send(request)
    }
    private static func send<T: Decodable>(_ original: URLRequest) async throws -> T {
        guard let workspace = RydrWorkspace.identifier, let user = RydrWorkspace.auth.currentUser else { throw URLError(.userAuthenticationRequired) }
        var request = original
        request.setValue("Bearer \(try await user.getIDToken())", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard RydrWorkspace.identifier == workspace, RydrWorkspace.auth.currentUser?.uid == user.uid else { throw URLError(.userAuthenticationRequired) }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DriverConnectServiceError.response(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
