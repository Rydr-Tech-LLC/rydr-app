import SwiftUI
import FirebaseAuth
import StripePayments
import StripePaymentsUI

/// Raw bank/card details are held only by this form and sent directly to Stripe.
/// Rydr receives a single-use token and displays only the masked saved destination.
struct DriverPayoutEntryView: View {
    let kind: DriverPayoutMethodsView.Intent
    @Environment(\.dismiss) private var dismiss
    @State private var holder = ""
    @State private var routing = ""
    @State private var number = ""
    @State private var confirmation = ""
    @State private var card: STPCardParams?
    @State private var saving = false
    @State private var message: String?
    @State private var pendingToken: String?
    @State private var requestID = UUID().uuidString
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: kind == .bank ? "building.columns.fill" : "creditcard.fill").font(.largeTitle)
                        Text(kind == .bank ? "Your weekly earnings, delivered." : "Your earnings, on your terms.").font(.title2.bold())
                        Text(kind == .bank ? "Add a US checking account for Monday direct deposits." : "Add a debit card for eligible instant cash-outs.").font(.subheadline)
                    }.foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Styles.rydrGradient, in: RoundedRectangle(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: 18) {
                        if kind == .bank {
                            field("Account holder name", value: $holder, id: "payoutBankHolder")
                            field("ACH routing number", value: $routing, id: "payoutBankRouting", numeric: true)
                            field("Account number", value: $number, id: "payoutBankNumber", numeric: true, secure: true)
                            field("Confirm account number", value: $confirmation, id: "payoutBankConfirm", numeric: true, secure: true)
                        } else {
                            Text("Debit card details").font(.headline)
                            PayoutCardField(params: $card).frame(height: 58).padding(.horizontal, 10)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            Text("Credit cards are not supported. Instant cash-out availability depends on your card and account eligibility.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }.disabled(saving)
                    if let message { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.footnote).accessibilityIdentifier("payoutEntryError") }
                    Button { Task { await save() } } label: {
                        HStack { if saving { ProgressView().tint(.white) }; Text(saving ? "Saving securely…" : kind == .bank ? "Save bank account" : "Save debit card").font(.headline) }
                            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(18).background(Styles.rydrGradient, in: Capsule())
                    }.disabled(saving || !valid).accessibilityIdentifier("saveNativePayoutMethod")
                    Label("Encrypted details go directly to Stripe. Rydr stores only a secure reference and masked details.", systemImage: "lock.shield.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively)
                .navigationTitle(kind == .bank ? "Add bank account" : "Add debit card").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() }.disabled(saving) }; ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } } }
        }.interactiveDismissDisabled(saving)
            .onChange(of: holder + routing + number + confirmation) { _, _ in resetAttempt() }
            .onChange(of: (card?.number ?? "") + String(card?.expMonth ?? 0) + String(card?.expYear ?? 0) + (card?.cvc ?? "")) { _, _ in resetAttempt() }
            .onDisappear { holder = ""; routing = ""; number = ""; confirmation = ""; card = nil; pendingToken = nil }
    }
    private var valid: Bool { kind == .card ? card != nil : !holder.trimmingCharacters(in: .whitespaces).isEmpty && routing.count == 9 && routing.allSatisfy(\.isNumber) && number.count >= 4 && number.count <= 17 && number.allSatisfy(\.isNumber) && number == confirmation }
    private func resetAttempt() { guard !saving else { return }; pendingToken = nil; requestID = UUID().uuidString }
    private func field(_ label: String, value: Binding<String>, id: String, numeric: Bool = false, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.semibold))
            Group { if secure { SecureField(label, text: value) } else { TextField(label, text: value) } }
                .keyboardType(numeric ? .numberPad : .default).textInputAutocapitalization(numeric ? .never : .words).autocorrectionDisabled()
                .padding(16).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier(id)
        }
    }
    @MainActor private func save() async {
        guard !saving, valid, let workspace = RydrWorkspace.identifier, let uid = RydrWorkspace.auth.currentUser?.uid else { return }
        saving = true; message = nil
        defer { saving = false }
        do {
            struct Config: Decodable { let publishableKey: String; let mode: String }
            async let c: Config = DriverConnectAPI.get("config")
            async let a: DriverPayoutSetupConfiguration = DriverConnectAPI.get("connect/setup-configuration")
            let (config, account) = try await (c,a)
            guard account.managed, account.workspace == workspace, account.mode == config.mode,
                  config.mode == (workspace == "test" ? "test" : "live"), config.publishableKey.hasPrefix(workspace == "test" ? "pk_test_" : "pk_live_"),
                  let accountID = account.accountId, RydrWorkspace.identifier == workspace, RydrWorkspace.auth.currentUser?.uid == uid else { throw URLError(.userAuthenticationRequired) }
            if pendingToken == nil {
                let client = STPAPIClient(publishableKey: config.publishableKey)
                client.stripeAccount = accountID
                let token: STPToken
                if kind == .bank {
                    let bank = STPBankAccountParams(); bank.country = "US"; bank.currency = "usd"; bank.accountHolderType = .individual
                    bank.accountHolderName = holder; bank.routingNumber = routing; bank.accountNumber = number
                    token = try await client.createToken(withBankAccount: bank)
                } else {
                    guard let card else { return }; card.currency = "usd"
                    token = try await client.createToken(withCard: card)
                }
                pendingToken = token.tokenId
            }
            guard RydrWorkspace.identifier == workspace, RydrWorkspace.auth.currentUser?.uid == uid else { throw URLError(.userAuthenticationRequired) }
            struct Saved: Decodable { let method: DriverPayoutMethods.Method }
            let _: Saved = try await DriverConnectAPI.post("connect/payout-method", body: ["tokenId": pendingToken!, "kind": kind.rawValue, "requestId": requestID])
            dismiss()
        } catch { message = error is DriverConnectServiceError ? error.localizedDescription : "Couldn't save these details. Check the information and your connection, then try again." }
    }
}

private struct PayoutCardField: UIViewRepresentable {
    @Binding var params: STPCardParams?
    func makeCoordinator() -> Coordinator { Coordinator(params: $params) }
    func makeUIView(context: Context) -> STPPaymentCardTextField {
        let field = STPPaymentCardTextField(); field.delegate = context.coordinator
        field.postalCodeEntryEnabled = false; field.accessibilityIdentifier = "payoutDebitCardFields"
        field.backgroundColor = .clear; field.textColor = .label; field.borderColor = .clear
        return field
    }
    func updateUIView(_ field: STPPaymentCardTextField, context: Context) {}
    final class Coordinator: NSObject, STPPaymentCardTextFieldDelegate {
        var params: Binding<STPCardParams?>
        init(params: Binding<STPCardParams?>) { self.params = params }
        func paymentCardTextFieldDidChange(_ textField: STPPaymentCardTextField) {
            guard textField.isValid else { params.wrappedValue = nil; return }
            let input = textField.cardParams
            let card = STPCardParams(); card.number = input.number; card.cvc = input.cvc
            card.expMonth = input.expMonth?.uintValue ?? 0; card.expYear = input.expYear?.uintValue ?? 0
            params.wrappedValue = card
        }
    }
}
