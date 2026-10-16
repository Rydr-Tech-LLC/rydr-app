import SwiftUI

/// Rydr owns navigation and masked summaries. Stripe's embedded component owns all
/// sensitive entry, verification and destination edits; no hosted account links.
struct DriverPayoutMethodsView: View {
    enum Intent: String, Identifiable {
        case bank, card, manage
        var id: String { rawValue }
        var title: String { self == .bank ? "Bank account (ACH)" : self == .card ? "Debit card" : "Manage payout methods" }
        var detail: String {
            self == .bank ? "Add or replace your bank account for Monday direct deposits. In the secure form, choose bank account."
            : self == .card ? "Add or replace an eligible debit card for instant cash-out. In the secure form, choose debit card. A bank account may be required first."
            : "Add, replace or choose your default payout destination in the secure form."
        }
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

                    if requiresSetup {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Finish setting up your payouts", systemImage: "info.circle.fill").font(.headline)
                            Text("Review the information needed to receive earnings.").font(.subheadline)
                            Button("Finish payout setup") { securePurpose = .onboarding; showingSecureForm = true }
                                .buttonStyle(.borderedProminent).tint(.red).accessibilityIdentifier("finishPayoutSetup")
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
                    if returnedFromEntry {
                        Text("Payout details refresh from Stripe. Closing the form does not confirm that a method was saved or verified.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let methods {
                        if methods.bankAccounts.isEmpty && methods.cards.isEmpty {
                            Text("No payout methods yet. Choose an option below to get started.").foregroundStyle(.secondary)
                        }
                        ForEach(methods.bankAccounts + methods.cards) { method in
                            Button { intent = .manage } label: {
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
                    Button("Manage all payout methods") { intent = .manage }.accessibilityIdentifier("manageAllPayoutMethods")
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
            .sheet(item: $intent, onDismiss: {
                if securePurpose != nil { showingSecureForm = true }
            }) { choice in
                NavigationStack {
                    VStack(alignment: .leading, spacing: 22) {
                        Image(systemName: choice == .card ? "creditcard.fill" : "building.columns.fill")
                            .font(.system(size: 48)).foregroundStyle(Styles.rydrGradient)
                        Text(choice.title).font(.title.bold())
                        Text(choice.detail)
                        Text("Stripe may ask you to confirm your identity before changing payout details. Bank authentication may open your bank's app or secure sign-in.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Continue to secure entry") {
                            // Presented on the sheet's dismissal, avoiding overlapping presentations.
                            securePurpose = .payoutMethods
                            intent = nil
                        }.buttonStyle(.borderedProminent).tint(.red).accessibilityIdentifier("securePayoutEntry")
                        Button("Complete payout verification") { securePurpose = .onboarding; intent = nil }
                            .accessibilityIdentifier("completePayoutVerification")
                        Spacer()
                    }.padding(24)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { intent = nil }.accessibilityIdentifier("cancelPayoutChoice") } }
                }.presentationDetents([.large])
            }
            .sheet(isPresented: $showingSecureForm, onDismiss: {
                securePurpose = nil
                returnedFromEntry = true
                Task { await refresh() }
            }) {
                DriverPayoutAccountView(purpose: securePurpose ?? .payoutMethods)
            }
        }
        .tint(.red)
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
