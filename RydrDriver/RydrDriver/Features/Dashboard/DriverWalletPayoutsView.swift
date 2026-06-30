import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct DriverWalletPayoutsView: View {
    @ObservedObject var vm: DriverDashboardVM

    @State private var wallet = DriverWalletSnapshot.empty
    @State private var message: String?
    @State private var isLoadingBalance = false
    @State private var isRequestingInstantPay = false
    @State private var isOpeningPayoutMethodLink = false
    @State private var payoutMethodLinkURL: IdentifiableURL?

    private let stripeBackendBase = URL(string: "https://rydr-stripe-backend.onrender.com")!
    private let instantPayoutFeeRate = Decimal(string: "0.01")!

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                balanceCard
                payoutMethodsSection
                quickActionsSection
                payoutHistorySection
                instantPayBanner
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .background(walletBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadWallet()
            await refreshStripeBalance()
            await refreshPayoutMethodsAndHistory()
            vm.refreshEarningsSummary()
        }
        .sheet(item: $payoutMethodLinkURL) { wrapped in
            SafariView(url: wrapped.url)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    // The sheet's swipe affordance still owns dismissal; this mirrors the design header.
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .disabled(true)

                Spacer()

                Image(systemName: "questionmark.circle")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }

            HStack(spacing: 0) {
                Text("Wallet & ")
                Text("Payouts")
                    .foregroundStyle(Color.rydrWalletRed)
            }
            Text("Manage your payout methods, track earnings, and view payout history.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.title.weight(.heavy))
        .foregroundStyle(.primary)
    }

    private var balanceCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color.rydrWalletRed,
                        Color(red: 0.72, green: 0.03, blue: 0.22),
                        Color(red: 0.98, green: 0.16, blue: 0.36)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                WalletWave()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.88),
                                Color.white.opacity(0.44),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 72)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Available Balance", systemImage: "eye")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))

                        Text(currency(wallet.availableBalance))
                            .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.82)

                        Text(wallet.balanceUpdatedText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.76))
                    }

                    Spacer(minLength: 12)

                    Button {
                        Task { await requestInstantPayout() }
                    } label: {
                        HStack(spacing: 7) {
                            if isRequestingInstantPay {
                                ProgressView().tint(.black)
                            } else {
                                Text("Cash out")
                                Image(systemName: "bolt.fill")
                            }
                        }
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(.plain)
                    .disabled(!wallet.canInstantPay || isRequestingInstantPay)
                    .opacity(wallet.canInstantPay ? 1 : 0.55)
                }
                .padding(20)
            }
            .frame(height: 178)

            HStack(spacing: 0) {
                walletMetric(
                    title: "Earnings this week",
                    value: currency(vm.earningsSummary.weekEarnings),
                    icon: "chart.line.uptrend.xyaxis",
                    tint: .rydrWalletRed
                )

                Divider()
                    .frame(height: 54)

                walletMetric(
                    title: "Pending Payouts",
                    value: currency(wallet.pendingPayouts),
                    icon: "clock",
                    tint: .rydrWalletRed
                )
            }
            .padding(.vertical, 14)
            .background(Color(.systemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 9)
        .overlay(alignment: .bottomLeading) {
            if let message {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(message.localizedCaseInsensitiveContains("could") ? .red : .green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(.systemBackground)))
                    .offset(x: 12, y: 18)
            }
        }
    }

    private func walletMetric(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            Spacer()
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(tint.opacity(0.10)))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    private var payoutMethodsSection: some View {
        walletSection(title: "Payout Methods", trailing: "Manage") {
            VStack(spacing: 0) {
                if wallet.bankName == nil && wallet.cardName == nil {
                    Text("No payout method on file yet. Add a bank account or debit card to receive payouts.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(14)
                } else {
                    if let bankName = wallet.bankName, let bankLast4 = wallet.bankLast4 {
                        payoutMethodRow(icon: "building.columns.fill", title: bankName, detail: bankLast4, badge: "Default")
                        Divider().padding(.leading, 58)
                    }
                    if let cardName = wallet.cardName, let cardLast4 = wallet.cardLast4 {
                        payoutMethodRow(icon: "creditcard.fill", title: cardName, detail: cardLast4, badge: nil)
                        Divider().padding(.leading, 58)
                    }
                }
                Button {
                    Task { await openPayoutMethodManagement() }
                } label: {
                    HStack(spacing: 12) {
                        if isOpeningPayoutMethodLink {
                            ProgressView()
                                .frame(width: 34, height: 34)
                        } else {
                            Image(systemName: "plus")
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(Color.rydrWalletRed)
                                .frame(width: 34, height: 34)
                                .background(Circle().stroke(Color.rydrWalletRed.opacity(0.45), lineWidth: 1.2))
                        }
                        Text("Add bank account or card")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                    }
                    .padding(14)
                    .foregroundStyle(Color.rydrWalletRed)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(.separator).opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isOpeningPayoutMethodLink)
                .padding(10)
            }
            .background(walletPanelBackground)
        }
    }

    private func payoutMethodRow(icon: String, title: String, detail: String, badge: String?) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.rydrWalletRed))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.rydrWalletRed))
                    }
                }
                Text("•••• \(detail)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var quickActionsSection: some View {
        walletSection(title: "Quick Actions") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                quickAction(icon: "building.columns.fill", title: "Add Bank\nAccount", fee: nil) {
                    Task { await openPayoutMethodManagement() }
                }
                quickAction(icon: "creditcard.fill", title: "Add Debit\nCard", fee: nil) {
                    Task { await openPayoutMethodManagement() }
                }
                quickAction(icon: "bolt.fill", title: "Instant Pay", fee: "1% Fee") {
                    Task { await requestInstantPayout() }
                }
                quickAction(icon: "calendar", title: "Payout\nSchedule", fee: nil) {
                    Task { await openPayoutMethodManagement() }
                }
            }
        }
    }

    private func quickAction(icon: String, title: String, fee: String?, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.rydrWalletRed)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.rydrWalletRed.opacity(0.10))
                    )

                Text(title)
                    .font(.caption2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let fee {
                    Text(fee)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.rydrWalletRed))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .background(walletPanelBackground)
        }
        .buttonStyle(.plain)
    }

    private var payoutHistorySection: some View {
        walletSection(title: "Payout History", trailing: "View all") {
            VStack(spacing: 0) {
                if wallet.history.isEmpty {
                    Text("No payouts yet. Completed payouts will show up here.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(14)
                } else {
                    ForEach(wallet.history) { payout in
                        payoutHistoryRow(payout)
                        if payout.id != wallet.history.last?.id {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
            }
            .background(walletPanelBackground)
        }
    }

    private func payoutHistoryRow(_ payout: DriverWalletPayout) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "building.columns.fill")
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.rydrWalletRed))

            VStack(alignment: .leading, spacing: 4) {
                Text(payout.title)
                    .font(.subheadline.weight(.bold))
                Text(payout.subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(currency(payout.amount))
                    .font(.subheadline.weight(.heavy).monospacedDigit())
                Text(payout.status)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.13)))
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var instantPayBanner: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Get paid instantly")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)
                Text("Transfer your earnings to your card in minutes with Instant Pay.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await requestInstantPayout() }
                } label: {
                    Label("Try Instant Pay", systemImage: "bolt.fill")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Color.rydrWalletRed)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.white))
                }
                .disabled(!wallet.canInstantPay || isRequestingInstantPay)
            }

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.black, Color(red: 0.18, green: 0.18, blue: 0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 112, height: 72)
                    .rotationEffect(.degrees(13))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                Text("RYDR\n\nVISA")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(width: 92, height: 54, alignment: .topLeading)
                    .rotationEffect(.degrees(13))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.rydrWalletRed, Color(red: 0.62, green: 0.02, blue: 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func walletSection<Content: View>(
        title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline.weight(.heavy))
                Spacer()
                if let trailing {
                    Button(trailing) {}
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.rydrWalletRed)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
    }

    private var walletPanelBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
    }

    private var walletBackground: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.secondarySystemBackground),
                Color.rydrWalletRed.opacity(0.05)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @MainActor
    private func loadWallet() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            wallet = .empty
            return
        }

        do {
            let snapshot = try await Firestore.firestore().collection("drivers").document(uid).getDocument()
            wallet = DriverWalletSnapshot(driverData: snapshot.data() ?? [:])
        } catch {
            wallet = .empty
            message = "Could not load wallet details."
        }
    }

    /// Pulls real linked bank/card info and real payout history from Stripe
    /// Connect via the backend — replaces the previously hardcoded
    /// "Chase Checking •••• 4242" / fake 3-row history.
    @MainActor
    private func refreshPayoutMethodsAndHistory() async {
        guard wallet.stripeAccountId?.isEmpty == false else { return }
        let idToken = try? await Auth.auth().currentUser?.getIDToken()

        var externalAccounts: ExternalAccountsResponse?
        do {
            var request = URLRequest(url: stripeBackendBase.appendingPathComponent("connect/external-accounts"))
            if let idToken {
                request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                externalAccounts = try JSONDecoder().decode(ExternalAccountsResponse.self, from: data)
            }
        } catch {
            externalAccounts = nil
        }

        var payouts: PayoutsResponse?
        do {
            var components = URLComponents(url: stripeBackendBase.appendingPathComponent("connect/payouts"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "limit", value: "10")]
            if let url = components?.url {
                var request = URLRequest(url: url)
                if let idToken {
                    request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
                }
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    payouts = try JSONDecoder().decode(PayoutsResponse.self, from: data)
                }
            }
        } catch {
            payouts = nil
        }

        if let bank = externalAccounts?.bankAccounts.first {
            wallet.bankName = bank.bankName
            wallet.bankLast4 = bank.last4
        }
        if let card = externalAccounts?.cards.first {
            wallet.cardName = card.brand
            wallet.cardLast4 = card.last4
        }

        if let payouts {
            wallet.history = payouts.payouts.map { payout in
                DriverWalletPayout(
                    title: "Payout to \(wallet.bankName ?? "your bank account")",
                    subtitle: Self.formattedPayoutDate(payout.arrivalDate ?? payout.created),
                    amount: Decimal(payout.amount) / 100,
                    status: payout.status.capitalized
                )
            }
        }
    }

    private static func formattedPayoutDate(_ unixSeconds: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Opens the Stripe Express dashboard (via a fresh login link) so the
    /// driver can add or update a real linked bank account / debit card.
    /// Express accounts manage external accounts in that dashboard rather
    /// than through another onboarding link.
    @MainActor
    private func openPayoutMethodManagement() async {
        guard wallet.stripeAccountId?.isEmpty == false else {
            message = "Finish Stripe payouts setup before adding a payout method."
            return
        }

        isOpeningPayoutMethodLink = true
        defer { isOpeningPayoutMethodLink = false }

        do {
            let url = stripeBackendBase.appendingPathComponent("connect/login-link")

            var request = URLRequest(url: url)
            if let token = try await Auth.auth().currentUser?.getIDToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(LoginLinkResponse.self, from: data)
            guard let linkURL = URL(string: decoded.url) else { throw URLError(.badURL) }
            payoutMethodLinkURL = IdentifiableURL(url: linkURL)
        } catch {
            message = "Could not open Stripe payout method management."
        }
    }

    @MainActor
    private func refreshStripeBalance() async {
        guard wallet.stripeAccountId?.isEmpty == false else { return }

        isLoadingBalance = true
        defer { isLoadingBalance = false }

        do {
            var request = URLRequest(url: stripeBackendBase.appendingPathComponent("connect/balance"))
            if let token = try await Auth.auth().currentUser?.getIDToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(StripeConnectBalanceResponse.self, from: data)
            wallet.availableBalance = Decimal(decoded.instantAvailableAmount) / 100
            wallet.pendingPayouts = Decimal(decoded.pendingAmount) / 100
            wallet.stripePayoutsEnabled = decoded.payoutsEnabled
            wallet.balanceUpdatedText = "Updated just now"
        } catch {
            message = "Could not refresh Stripe balance."
        }
    }

    @MainActor
    private func requestInstantPayout() async {
        guard wallet.stripeAccountId?.isEmpty == false else {
            message = "Finish Stripe payouts setup before using Instant Pay."
            return
        }
        guard wallet.canInstantPay else {
            message = "Instant Pay is unavailable until Stripe payouts are enabled and funds are available."
            return
        }

        isRequestingInstantPay = true
        message = nil
        defer { isRequestingInstantPay = false }

        do {
            let amountCents = max(1, NSDecimalNumber(decimal: wallet.availableBalance * 100).intValue)
            var request = URLRequest(url: stripeBackendBase.appendingPathComponent("connect/instant-payout"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = try await Auth.auth().currentUser?.getIDToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONEncoder().encode(InstantPayoutRequest(
                amount: amountCents,
                currency: "usd",
                requestId: UUID().uuidString
            ))

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode(InstantPayoutResponse.self, from: data)
            let paidAmount = Decimal(decoded.amount) / 100
            let fee = paidAmount * instantPayoutFeeRate
            wallet.availableBalance = 0
            wallet.pendingPayouts += paidAmount
            wallet.history.insert(
                DriverWalletPayout(
                    title: "Instant Pay to \(wallet.cardName ?? wallet.bankName ?? "your account")",
                    subtitle: "Just now",
                    amount: paidAmount,
                    status: decoded.status.capitalized
                ),
                at: 0
            )
            message = "Instant Pay started. Stripe fee: \(currency(fee))."
        } catch {
            message = "Could not start Instant Pay."
        }
    }

    private func currency(_ value: Decimal) -> String {
        currencyFormatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

/// Driver wallet snapshot — every field is sourced from real data (the
/// driver's Firestore doc and Stripe Connect) with no hardcoded prefill
/// values. Fields with no real data yet (no linked bank/card, no payout
/// history, no Stripe account at all) are left nil/empty and the UI shows an
/// explicit "nothing here yet" state rather than a fabricated placeholder.
private struct DriverWalletSnapshot {
    var availableBalance: Decimal
    var earningsThisWeek: Decimal
    var pendingPayouts: Decimal
    var balanceUpdatedText: String
    var bankName: String?
    var bankLast4: String?
    var cardName: String?
    var cardLast4: String?
    var stripeAccountId: String?
    var stripePayoutsEnabled: Bool
    var history: [DriverWalletPayout]

    var canInstantPay: Bool {
        stripePayoutsEnabled && availableBalance > 0
    }

    init(driverData: [String: Any]) {
        availableBalance = Self.decimal(driverData["availableBalance"]) ?? 0
        earningsThisWeek = Self.decimal(driverData["earningsThisWeek"]) ?? 0
        pendingPayouts = Self.decimal(driverData["pendingPayouts"]) ?? 0
        balanceUpdatedText = "Updated just now"
        bankName = Self.string(driverData["payoutBankName"])
        bankLast4 = Self.string(driverData["payoutBankLast4"])
        cardName = Self.string(driverData["payoutCardName"])
        cardLast4 = Self.string(driverData["payoutCardLast4"])
        stripeAccountId = Self.string(driverData["stripeAccountId"])
        stripePayoutsEnabled = (driverData["stripePayoutsEnabled"] as? Bool) ?? false
        history = []
    }

    static var empty: DriverWalletSnapshot {
        DriverWalletSnapshot(driverData: [:])
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        if let value = value as? Decimal { return value }
        if let value = value as? Double { return Decimal(value) }
        if let value = value as? Int { return Decimal(value) }
        if let value = value as? NSNumber { return value.decimalValue }
        if let value = value as? String { return Decimal(string: value) }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }
}

private struct DriverWalletPayout: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let amount: Decimal
    let status: String
}

/// Wraps a URL so it can be used with SwiftUI's `.sheet(item:)`.
private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct StripeConnectBalanceResponse: Decodable {
    let instantAvailableAmount: Int
    let pendingAmount: Int
    let payoutsEnabled: Bool
}

private struct InstantPayoutRequest: Encodable {
    let amount: Int
    let currency: String
    let requestId: String
}

private struct InstantPayoutResponse: Decodable {
    let payoutId: String
    let amount: Int
    let currency: String
    let status: String
}

private struct ExternalAccountsResponse: Decodable {
    struct Bank: Decodable {
        let id: String
        let bankName: String
        let last4: String
        let isDefault: Bool
    }
    struct Card: Decodable {
        let id: String
        let brand: String
        let last4: String
        let isDefault: Bool
    }
    let bankAccounts: [Bank]
    let cards: [Card]
}

private struct PayoutsResponse: Decodable {
    struct Payout: Decodable {
        let id: String
        let amount: Int
        let currency: String
        let status: String
        let method: String
        let arrivalDate: Int?
        let created: Int
    }
    let payouts: [Payout]
}

private struct LoginLinkResponse: Decodable {
    let url: String
}

private struct WalletWave: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.60))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.38),
            control1: CGPoint(x: rect.width * 0.16, y: rect.height * 0.78),
            control2: CGPoint(x: rect.width * 0.25, y: rect.height * 0.10)
        )
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.28),
            control1: CGPoint(x: rect.width * 0.66, y: rect.height * 0.70),
            control2: CGPoint(x: rect.width * 0.76, y: rect.height * -0.05)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

private extension Color {
    static let rydrWalletRed = Color(red: 1.0, green: 0.05, blue: 0.23)
}
