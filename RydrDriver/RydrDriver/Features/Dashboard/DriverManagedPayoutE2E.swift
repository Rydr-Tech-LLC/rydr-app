#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import FirebaseAuth

/// Real Test-workspace integration harness. No Stripe calls are mocked and no
/// secret is bundled. A short-lived Test-only sign-in token is supplied locally.
struct DriverManagedPayoutE2E: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var ready = false
    @State private var error: String?
    @State private var connected = false
    @State private var completed = false
    @State private var managing = false
    @State private var uid = ""
    private var dob: Date { Calendar.current.date(from: DateComponents(year: 1901, month: 1, day: 1))! }
    var body: some View {
        NavigationStack {
            if ready {
                VStack(spacing: 8) {
                    Text("TEST • Real Stripe test service").font(.caption.bold()).foregroundStyle(.purple)
                    Button("Manage bank accounts & cards") { managing = true }
                    if completed { Text("Payout setup complete").accessibilityIdentifier("managedPayoutE2EComplete") }
                    else {
                        PayoutsSetupView(uid: uid, email: "payout-qa-20261016@example.com", firstName: "Rydr", lastName: "Sandbox", phone: "+15555550199", dob: dob, street: "address_full_match", addressLine2: "", city: "Atlanta", state: "GA", zip: "30303", connectOnboarded: $connected, onNext: { _ in completed = true })
                    }
                }
                .sheet(isPresented: $managing) { DriverPayoutMethodsView() }
            } else if let error { Text(error).padding() }
            else { ProgressView("Signing in to Test driver…") }
        }
        .task {
            do {
                struct LocalAuth: Decodable { let customToken: String; let uid: String; let workspace: String }
                let data = try Data(contentsOf: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rydr-managed-e2e-auth.json"))
                let input = try JSONDecoder().decode(LocalAuth.self, from: data)
                guard input.workspace == "test", input.uid == "qa-managed-payouts-20261016" else { throw URLError(.userAuthenticationRequired) }
                UserDefaults.standard.set("test", forKey: RydrWorkspace.selectionKey)
                try await RydrWorkspace.bootstrap()
                guard RydrWorkspace.identifier == "test" else { throw URLError(.userAuthenticationRequired) }
                let result = try await RydrWorkspace.auth.signIn(withCustomToken: input.customToken)
                guard result.user.uid == input.uid else { throw URLError(.userAuthenticationRequired) }
                uid = input.uid
                UserDefaults.standard.set(0, forKey: "rydrManagedE2E.backgroundTransitions")
                ready = true
            } catch { self.error = "Test sign-in failed: \(error.localizedDescription)" }
        }
        .onChange(of: scenePhase) { _, phase in
            guard ready, phase == .background else { return }
            let count = UserDefaults.standard.integer(forKey: "rydrManagedE2E.backgroundTransitions")
            UserDefaults.standard.set(count + 1, forKey: "rydrManagedE2E.backgroundTransitions")
        }
    }
}
#endif
