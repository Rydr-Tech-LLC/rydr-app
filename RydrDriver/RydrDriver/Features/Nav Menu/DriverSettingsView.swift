import SwiftUI
import FirebaseAuth
import FirebaseFirestore

private enum CashHubDriverBillingStatus: String {
    case active
    case feePending
    case partiallyCollected
    case collected
    case unknown

    init(rawFirestoreValue: String?) {
        switch rawFirestoreValue {
        case "active": self = .active
        case "feePending", "fee_pending": self = .feePending
        case "partiallyCollected", "partially_collected": self = .partiallyCollected
        case "collected": self = .collected
        default: self = .unknown
        }
    }

    func title(periodLabel: String) -> String {
        switch self {
        case .active: return "Active"
        case .feePending: return "Fee pending"
        case .partiallyCollected: return "Partially collected"
        case .collected: return "Collected for \(periodLabel)"
        case .unknown: return "Not available"
        }
    }

    var systemImage: String {
        switch self {
        case .active: return "checkmark.seal.fill"
        case .feePending: return "clock.badge.exclamationmark.fill"
        case .partiallyCollected: return "chart.pie.fill"
        case .collected: return "checkmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .active, .collected: return .green
        case .feePending: return .orange
        case .partiallyCollected: return .blue
        case .unknown: return .secondary
        }
    }
}

struct DriverSettingsView: View {
    @ObservedObject var vm: DriverDashboardVM
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DriverNavigationHandoff.preferenceKey) private var defaultNavigationProvider = DriverNavigationProvider.rydr.rawValue

    @State private var showLinkPhoneSheet = false
    @State private var phoneProviderLinked = Auth.auth().currentUser?.providerData.contains { $0.providerID == PhoneAuthProviderID } ?? false
    @State private var cashHubTermsAccepted = false
    @State private var cashHubOptedOut = false
    @State private var isLoadingCashHubAccess = true
    @State private var isUpdatingCashHubAccess = false
    @State private var showCashHubOptOutConfirmation = false
    @State private var cashHubAccessAlert: CashHubAccessAlert?
    @State private var isLoadingCashHubBilling = false
    @State private var cashHubBillingStatus: CashHubDriverBillingStatus = .active
    @State private var cashHubBillingPeriodLabel = Self.currentCashHubBillingPeriod().label
    @State private var cashHubBillingFeeCents = 499
    @State private var cashHubBillingCollectedCents = 0
    @State private var cashHubBillingRemainingCents = 499

    var body: some View {
        List {
            accountSection
            cashRydrHubSection
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
        .confirmationDialog(
            "Opt out of CashRydr Hub?",
            isPresented: $showCashHubOptOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Opt Out", role: .destructive) {
                optOutOfCashRydrHub()
            }
            Button("Keep CashRydr Hub", role: .cancel) {}
        } message: {
            Text("Driver access will be turned off and CashRydr Hub will return to the terms screen. You can turn it back on later by accepting the driver terms again.")
        }
        .alert(item: $cashHubAccessAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            loadCashHubAccess()
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

    private var cashRydrHubSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CashRydr Hub Driver Access")
                        .font(.body.weight(.semibold))
                    Text(cashHubAccessSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: cashHubDriverAccessActive ? "checkmark.seal.fill" : "xmark.seal")
                    .foregroundStyle(cashHubDriverAccessActive ? Color.green : Color.secondary)
                    .frame(width: 28)
            }

            if cashHubDriverAccessActive || isLoadingCashHubBilling {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cashHubBillingStatus.title(periodLabel: cashHubBillingPeriodLabel))
                            .font(.body.weight(.semibold))
                        Text(cashHubBillingSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: cashHubBillingStatus.systemImage)
                        .foregroundStyle(cashHubBillingStatus.color)
                        .frame(width: 28)
                }
            }

            if cashHubDriverAccessActive {
                Button(role: .destructive) {
                    showCashHubOptOutConfirmation = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(isUpdatingCashHubAccess ? "Updating..." : "Opt Out of CashRydr Hub")
                                .font(.body.weight(.semibold))
                            Text("Turn off driver access and return CashRydr Hub to the terms screen.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        if isUpdatingCashHubAccess {
                            ProgressView()
                        }
                    }
                }
                .disabled(isUpdatingCashHubAccess)
            }
        } header: {
            Text("CashRydr Hub")
        } footer: {
            Text("CashRydr Hub is free for riders. Driver access includes a $4.99 monthly platform fee collected from eligible standard Rydr driver earnings, never from Cash Hub ride payments.")
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

    private var cashHubDriverAccessActive: Bool {
        cashHubTermsAccepted && !cashHubOptedOut
    }

    private var cashHubAccessSubtitle: String {
        if isLoadingCashHubAccess {
            return "Checking CashRydr Hub access..."
        }
        if cashHubDriverAccessActive {
            return "$4.99 monthly access fee acknowledged. CashRydr Hub driver access is active."
        }
        if cashHubOptedOut {
            return "Opted out. Open CashRydr Hub to review the terms and turn driver access back on."
        }
        return "Not active. Open CashRydr Hub to review the driver terms."
    }

    private var cashHubBillingSubtitle: String {
        if isLoadingCashHubBilling {
            return "Checking \(cashHubBillingPeriodLabel) billing..."
        }

        switch cashHubBillingStatus {
        case .active:
            return "CashRydr Hub access is active. No current monthly fee collection has been recorded for \(cashHubBillingPeriodLabel)."
        case .feePending:
            return "\(formatCents(cashHubBillingFeeCents)) fee pending for \(cashHubBillingPeriodLabel). It will be collected from eligible standard Rydr earnings."
        case .partiallyCollected:
            return "Collected \(formatCents(cashHubBillingCollectedCents)) of \(formatCents(cashHubBillingFeeCents)). Remaining \(formatCents(cashHubBillingRemainingCents))."
        case .collected:
            return "Monthly CashRydr Hub access fee is paid for \(cashHubBillingPeriodLabel)."
        case .unknown:
            return "Billing status is not available right now."
        }
    }

    private func loadCashHubAccess() {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoadingCashHubAccess = false
            return
        }
        isLoadingCashHubAccess = true
        let db = Firestore.firestore()
        db.collection("platformConfig").document("cashRydrHub").getDocument { configSnapshot, _ in
            db.collection("drivers").document(uid).getDocument { snapshot, error in
                DispatchQueue.main.async {
                    isLoadingCashHubAccess = false
                    if let error {
                        cashHubAccessAlert = CashHubAccessAlert(
                            title: "CashRydr Hub",
                            message: error.localizedDescription
                        )
                        return
                    }
                    let config = configSnapshot?.data() ?? [:]
                    let termsAcceptanceEnabled = config["termsAcceptanceEnabled"] as? Bool ?? false
                    let currentTermsVersion = config["cashHubTermsVersion"] as? String ?? "legacy"
                    let data = snapshot?.data() ?? [:]
                    let termsAccepted = data["cashHubTermsAccepted"] as? Bool ?? false
                    let acceptedVersion = data["cashHubTermsVersion"] as? String
                    let acceptedCurrentTerms = acceptedVersion == currentTermsVersion || (acceptedVersion == nil && currentTermsVersion == "legacy")
                    let optedOut = data["cashHubOptedOut"] as? Bool ?? false
                    cashHubTermsAccepted = termsAcceptanceEnabled && termsAccepted && acceptedCurrentTerms
                    cashHubOptedOut = optedOut
                    if cashHubTermsAccepted && !optedOut {
                        loadCashHubBilling(for: uid)
                    } else {
                        resetCashHubBilling()
                    }
                }
            }
        }
    }

    private func loadCashHubBilling(for uid: String) {
        let period = Self.currentCashHubBillingPeriod()
        cashHubBillingPeriodLabel = period.label
        isLoadingCashHubBilling = true

        Firestore.firestore().collection("drivers").document(uid)
            .collection("cashHubBilling").document(period.id)
            .getDocument { snapshot, _ in
                DispatchQueue.main.async {
                    isLoadingCashHubBilling = false
                    let data = snapshot?.data() ?? [:]
                    guard snapshot?.exists == true else {
                        cashHubBillingStatus = .active
                        cashHubBillingFeeCents = 499
                        cashHubBillingCollectedCents = 0
                        cashHubBillingRemainingCents = 499
                        return
                    }

                    cashHubBillingStatus = CashHubDriverBillingStatus(rawFirestoreValue: data["status"] as? String)
                    cashHubBillingFeeCents = intValue(data["feeCents"]) ?? 499
                    cashHubBillingCollectedCents = intValue(data["collectedCents"]) ?? 0
                    cashHubBillingRemainingCents = intValue(data["remainingCents"]) ?? max(0, cashHubBillingFeeCents - cashHubBillingCollectedCents)
                }
            }
    }

    private func resetCashHubBilling() {
        isLoadingCashHubBilling = false
        cashHubBillingStatus = .active
        cashHubBillingPeriodLabel = Self.currentCashHubBillingPeriod().label
        cashHubBillingFeeCents = 499
        cashHubBillingCollectedCents = 0
        cashHubBillingRemainingCents = 499
    }

    private func optOutOfCashRydrHub() {
        guard let uid = Auth.auth().currentUser?.uid else {
            cashHubAccessAlert = CashHubAccessAlert(title: "CashRydr Hub", message: "Sign in before changing CashRydr Hub access.")
            return
        }

        isUpdatingCashHubAccess = true
        let db = Firestore.firestore()
        let batch = db.batch()
        let driverRef = db.collection("drivers").document(uid)
        let cashHubProfileRef = db.collection("cashHubDriverProfiles").document(uid)

        batch.setData([
            "cashHubTermsAccepted": false,
            "cashHubOptedOut": true,
            "cashHubOptedOutAt": FieldValue.serverTimestamp(),
            "cashHubAccessStatus": "optedOut",
            "cashHubRole": "driver",
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: driverRef, merge: true)

        batch.setData([
            "isOnline": false,
            "cashHubOptedOut": true,
            "cashHubAccessStatus": "optedOut",
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: cashHubProfileRef, merge: true)

        batch.commit { error in
            DispatchQueue.main.async {
                isUpdatingCashHubAccess = false
                if let error {
                    cashHubAccessAlert = CashHubAccessAlert(title: "CashRydr Hub", message: error.localizedDescription)
                    return
                }
                cashHubTermsAccepted = false
                cashHubOptedOut = true
                resetCashHubBilling()
                cashHubAccessAlert = CashHubAccessAlert(
                    title: "CashRydr Hub",
                    message: "Driver access has been turned off. Open CashRydr Hub to review the terms and turn it back on."
                )
            }
        }
    }

    private static func currentCashHubBillingPeriod(from date: Date = Date()) -> (id: String, label: String) {
        let idFormatter = DateFormatter()
        idFormatter.calendar = Calendar(identifier: .gregorian)
        idFormatter.locale = Locale(identifier: "en_US_POSIX")
        idFormatter.dateFormat = "yyyy-MM"

        let labelFormatter = DateFormatter()
        labelFormatter.calendar = Calendar(identifier: .gregorian)
        labelFormatter.locale = Locale(identifier: "en_US_POSIX")
        labelFormatter.dateFormat = "MMMM"

        return (idFormatter.string(from: date), labelFormatter.string(from: date))
    }

    private func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return dollars.formatted(.currency(code: "USD"))
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}

private struct CashHubAccessAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
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
