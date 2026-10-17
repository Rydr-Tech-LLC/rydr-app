import SwiftUI

/// Rydr owns native payout entry, navigation and masked summaries. Stripe handles
/// tokenization directly and supplies the remaining verification component.
struct DriverPayoutMethodsView: View {
    enum Intent: String, Identifiable {
        case bank, card, manage
        var id: String { rawValue }

    }
    var initialIntent: Intent = .manage
    var requiresSetup = false
    var loadMethods: () async throws -> DriverPayoutMethods = { try await DriverConnectAPI.get("connect/external-accounts") }
    @Environment(\.dismiss) private var dismiss
    @State private var methods: DriverPayoutMethods?
    @State private var loading = false
    @State private var message: String?
    @State private var intent: Intent?
    @State private var securePurpose: DriverPayoutAccountView.Purpose?
    @State private var showingSecureForm = false
    @State private var returnedFromEntry = false
    @State private var selectedMethod: DriverPayoutMethods.Method?
    @State private var showingActions = false
    @State private var updatingMethod = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "building.columns.circle.fill").font(.system(size: 42))
                        Text("Your money. Your destination.").font(.title2.bold())
                        Text("Manage your bank accounts and payout cards here in Rydr.").font(.subheadline)
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    .background(Styles.rydrGradient, in: RoundedRectangle(cornerRadius: 24))

                    if methods?.verificationPending == true && methods?.payoutsEnabled != true {
                        Label("Payout verification in progress. We’ll update your wallet when it’s ready.", systemImage: "clock.fill")
                            .font(.subheadline).padding().background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                    } else if methods?.setupRequired ?? requiresSetup {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Confirm your payout information", systemImage: "info.circle.fill").font(.headline)
                            Text(methods?.bankAccounts.isEmpty == false ? "Your payout methods are saved. Confirm the remaining information to finish setup." : "Add your bank account below, then confirm any remaining information needed to receive earnings.").font(.subheadline)
                            Button("Confirm payout information") { securePurpose = .onboarding; showingSecureForm = true }
                                .buttonStyle(.borderedProminent).tint(.red).disabled(methods?.bankAccounts.isEmpty != false).accessibilityIdentifier("finishPayoutSetup")
                        }.padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                    }
                    HStack {
                        Text("Saved payout methods").font(.headline)
                        Spacer()
                        if loading { ProgressView() }
                        else { Button("Refresh") { Task { await refresh() } }.accessibilityIdentifier("refreshPayoutMethods") }
                    }
                    if let message {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.red).accessibilityIdentifier("payoutMethodsError")
                    }
                    if returnedFromEntry && message == nil {
                        Text("Your saved payout methods are up to date.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let methods {
                        if methods.bankAccounts.isEmpty && methods.cards.isEmpty {
                            Text("No payout methods yet. Choose an option below to get started.").foregroundStyle(.secondary)
                        }
                        ForEach(methods.bankAccounts + methods.cards) { method in
                            Button { selectedMethod = method; showingActions = true } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: method.bankName == nil ? "creditcard.fill" : "building.columns.fill")
                                        .foregroundStyle(Styles.rydrGradient).font(.title2)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(method.bankName ?? method.brand ?? "Payout account").font(.headline)
                                        Text("•••• \(method.last4)").font(.subheadline).foregroundStyle(.secondary)
                                        if method.status == "errored" || method.status == "verification_failed" {
                                            Text("Needs attention — update this method").font(.caption).foregroundStyle(.red)
                                        } else if method.bankName == nil {
                                            Text(method.instantEligible == true ? "Eligible for instant cash-out" : "Instant eligibility not confirmed").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if method.isDefault { Text("Default").font(.caption.bold()).foregroundStyle(.red) }
                                    Image(systemName: "chevron.right").font(.caption)
                                }.padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain).accessibilityIdentifier("payoutMethod_\(method.id)")
                        }
                    }
                    action(.bank, icon: "building.columns.fill", subtitle: "Monday direct deposits")
                    action(.card, icon: "creditcard.fill", subtitle: "Eligible cards for instant cash-out")
                    Text("Tap a saved method to manage its default status or remove it. To replace account details, add the new method first.").font(.footnote).foregroundStyle(.secondary)
                    Label("Your bank and card details are securely collected by Stripe. Rydr displays only masked details.", systemImage: "lock.shield.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Monday payouts and instant cash-out stay in your Rydr wallet. A debit card must support Instant Payouts to receive an instant cash-out.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Bank accounts & cards").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.accessibilityIdentifier("payoutMethodsDone") } }
            .refreshable { await refresh() }
            .sheet(item: $intent, onDismiss: { returnedFromEntry = true; Task { await refresh() } }) { choice in
                DriverPayoutEntryView(kind: choice)
            }
            .confirmationDialog("Manage payout method", isPresented: $showingActions, titleVisibility: .visible) {
                if let selectedMethod, !selectedMethod.isDefault {
                    Button("Make default") { Task { await update(selectedMethod, action: "default") } }
                    Button("Remove payout method", role: .destructive) { Task { await update(selectedMethod, action: "remove") } }
                }
                if let selectedMethod, selectedMethod.isDefault {
                    Button("Add a replacement") { intent = selectedMethod.bankName == nil ? .card : .bank }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let selectedMethod {
                    Text(selectedMethod.isDefault ? "This is your default destination. Choose another default before removing it." : "Manage the account ending in \(selectedMethod.last4).")
                }
            }
            .fullScreenCover(isPresented: $showingSecureForm, onDismiss: {
                securePurpose = nil
                returnedFromEntry = true
                Task { await refresh() }
            }) {
                DriverPayoutAccountView(purpose: securePurpose ?? .onboarding)
            }
        }
        .tint(.red)
        .disabled(updatingMethod)
        .task {
            await refresh()
            if initialIntent != .manage { intent = initialIntent }
        }

    }

    private func action(_ choice: Intent, icon: String, subtitle: String) -> some View {
        Button { intent = choice } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title2).foregroundStyle(Styles.rydrGradient)
                VStack(alignment: .leading, spacing: 5) {
                    Text(choice == .bank ? "Add bank account" : "Add debit card").font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill").foregroundStyle(.red)
            }.padding(18).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityIdentifier(choice == .bank ? "addPayoutBank" : "addPayoutCard")
    }

    @MainActor private func update(_ method: DriverPayoutMethods.Method, action: String) async {
        guard !updatingMethod else { return }
        updatingMethod = true; message = nil
        defer { updatingMethod = false }
        do {
            struct Updated: Decodable { }
            let _: Updated = try await DriverConnectAPI.post("connect/payout-method-action", body: ["id": method.id, "action": action, "requestId": UUID().uuidString])
            await refresh()
        } catch { message = "Couldn't update this method. Check for pending payouts and choose another default before removing a default method." }
    }

    @MainActor private func refresh() async {
        guard !loading else { return }
        loading = true; message = nil
        defer { loading = false }
        do { methods = try await loadMethods() }
        catch { methods = nil; message = "Couldn't refresh payout methods. Try again before relying on these details." }
    }
}

struct DriverPayoutMethods: Decodable {
    struct Method: Decodable, Identifiable {
        let id: String
        let bankName: String?
        let brand: String?
        let last4: String
        let isDefault: Bool
        var status: String? = nil
        var instantEligible: Bool? = nil
    }
    let bankAccounts: [Method]
    let cards: [Method]
    var payoutsEnabled: Bool? = nil
    var setupRequired: Bool? = nil
    var verificationPending: Bool? = nil
}

#if DEBUG && targetEnvironment(simulator)
struct DriverPayoutMethodsUITestFixture: View {
    @State private var attempts = 0
    var body: some View {
        DriverPayoutMethodsView(loadMethods: {
            attempts += 1
            if ProcessInfo.processInfo.arguments.contains("-MethodsError"), attempts == 1 { throw URLError(.notConnectedToInternet) }
            return DriverPayoutMethods(bankAccounts: [.init(id: "ba_fixture", bankName: "Test bank", brand: nil, last4: "6789", isDefault: true)], cards: [.init(id: "card_fixture", bankName: nil, brand: "Visa debit", last4: "4242", isDefault: false, instantEligible: true)])
        })
    }
}
#endif
