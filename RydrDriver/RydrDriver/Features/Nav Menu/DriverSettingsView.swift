import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct DriverSettingsView: View {
    @ObservedObject var vm: DriverDashboardVM
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DriverNavigationHandoff.preferenceKey) private var defaultNavigationProvider = DriverNavigationProvider.rydr.rawValue

    @State private var showLinkPhoneSheet = false
    @State private var phoneProviderLinked = Auth.auth().currentUser?.providerData.contains { $0.providerID == PhoneAuthProviderID } ?? false

    var body: some View {
        List {
            accountSection
            navigationSection
            queuedRideSection
            driverAppSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLinkPhoneSheet) {
            DriverLinkPhoneView { linked in
                if linked { phoneProviderLinked = true }
            }
        }
    }

    /// Accounts created before phone sign-in was wired up only have an email/password
    /// provider on their Firebase Auth account, so phone login can never resolve to
    /// this uid. This lets a driver link their phone once, after which phone login
    /// works the same as it does for accounts created after the fix.
    private var accountSection: some View {
        Section {
            if phoneProviderLinked {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Phone Sign-In")
                            .font(.body.weight(.semibold))
                        Text("Your phone number is linked for sign-in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .frame(width: 28)
                }
            } else {
                Button {
                    showLinkPhoneSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "phone.badge.plus")
                            .foregroundStyle(Styles.rydrGradient)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Link Phone Number")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("Enable signing in with your phone number and a text code.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Account")
        }
    }

    private var navigationSection: some View {
        Section {
            ForEach(DriverNavigationProvider.allCases) { provider in
                Button {
                    defaultNavigationProvider = provider.rawValue
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: provider.icon)
                            .foregroundStyle(Styles.rydrGradient)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(provider.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(provider.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        if defaultNavigationProvider == provider.rawValue {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(provider.title), \(defaultNavigationProvider == provider.rawValue ? "selected" : "not selected")")
                .accessibilityHint(provider.subtitle)
            }
        } header: {
            Text("Navigation")
        } footer: {
            Text("Rydr Map is the default in-app driver map. External apps are optional handoffs for turn-by-turn navigation.")
        }
    }

    private var queuedRideSection: some View {
        Section {
            Toggle(isOn: $vm.autoAcceptQueuedRides) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Auto-Accept Queued Rides")
                        .font(.body.weight(.semibold))
                    Text("When a rider selects you during an active trip, add the request to your queue automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("Ride Queue")
        } footer: {
            Text("Queued rides wait until your current ride ends. If this is off, you can accept or decline queued requests manually.")
        }
    }

    private var driverAppSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Driver App")
                        .font(.body.weight(.semibold))
                    Text("Navigation settings apply only while driving rides.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "steeringwheel")
                    .foregroundStyle(Styles.rydrGradient)
                    .frame(width: 28)
            }
        } header: {
            Text("About")
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : Color(.systemGroupedBackground)
    }
}

// MARK: - Link phone number for sign-in (self-heal for pre-fix accounts)
private struct DriverLinkPhoneView: View {
    var onFinished: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var phoneNumber = ""
    @State private var code = ""
    @State private var verificationID: String?
    @State private var sent = false
    @State private var isSending = false
    @State private var isVerifying = false
    @State private var errorMessage = ""

    private func digitsOnly(_ s: String) -> String { s.filter { $0.isNumber } }
    private var sanitizedDigits: String { String(digitsOnly(phoneNumber).prefix(10)) }
    private var isPhoneValid: Bool { sanitizedDigits.count == 10 }
    private var e164Phone: String { "+1" + sanitizedDigits }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Link your phone number so you can sign in with a text code, not just email and password.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                HStack(spacing: 8) {
                    Text(verbatim: "+1")
                        .fontWeight(.semibold)
                        .foregroundStyle(Styles.rydrGradient)
                    Divider().frame(height: 20)
                    TextField("Phone number", text: $phoneNumber)
                        .keyboardType(.numberPad)
                        .textContentType(.telephoneNumber)
                        .disabled(sent)
                        .onChange(of: phoneNumber, initial: false) { _, newValue in
                            let digits = String(digitsOnly(newValue).prefix(10))
                            if digits != newValue { phoneNumber = digits }
                        }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Styles.rydrGradient, lineWidth: 2))

                if !sent {
                    Button(isSending ? "Sending..." : "Send Code") { sendCode() }
                        .disabled(!isPhoneValid || isSending)
                        .buttonStyle(.borderedProminent).tint(.red)
                } else {
                    TextField("6-digit code", text: Binding(
                        get: { code },
                        set: { code = String($0.filter { $0.isNumber }.prefix(6)) }
                    ))
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)

                    Button(isVerifying ? "Linking..." : "Link Phone") { verifyAndLink() }
                        .disabled(code.count != 6 || isVerifying)
                        .buttonStyle(.borderedProminent).tint(.red)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Link Phone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func sendCode() {
        guard isPhoneValid else { return }
        errorMessage = ""
        isSending = true
        PhoneAuthProvider.provider().verifyPhoneNumber(e164Phone, uiDelegate: nil) { id, error in
            Task { @MainActor in
                isSending = false
                if let error {
                    errorMessage = "Failed to send code: \(error.localizedDescription)"
                    return
                }
                guard let id, !id.isEmpty else {
                    errorMessage = "Firebase did not return a verification session. Please try again."
                    return
                }
                verificationID = id
                sent = true
            }
        }
    }

    private func verifyAndLink() {
        guard let verificationID, !verificationID.isEmpty else {
            errorMessage = "Verification session is missing. Please resend the code."
            return
        }
        guard let user = Auth.auth().currentUser else {
            errorMessage = "You're no longer signed in. Please log in again."
            return
        }

        isVerifying = true
        errorMessage = ""
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: code
        )

        user.link(with: credential) { result, error in
            Task { @MainActor in
                isVerifying = false
                if let error {
                    if let authCode = AuthErrorCode(rawValue: (error as NSError).code),
                       authCode == .credentialAlreadyInUse || authCode == .providerAlreadyLinked {
                        errorMessage = "That phone number is already linked to a different account."
                    } else {
                        errorMessage = "Linking failed: \(error.localizedDescription)"
                    }
                    return
                }

                indexPhone(e164Phone, uid: user.uid)
                onFinished(true)
                dismiss()
            }
        }
    }

    /// Keeps the driver doc's phone fields and the driverPhoneIndex pointer in sync
    /// with the number that's now linked, so phone-based lookups resolve correctly.
    private func indexPhone(_ phone: String, uid: String) {
        Firestore.firestore().collection("drivers").document(uid)
            .setData(["phoneNumber": phone, "phoneE164": phone], merge: true)
        Firestore.firestore().collection("driverPhoneIndex").document(phone)
            .setData(["uid": uid, "createdAt": FieldValue.serverTimestamp()], merge: true)
    }
}
