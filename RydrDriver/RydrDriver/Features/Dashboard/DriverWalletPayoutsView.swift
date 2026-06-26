import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct DriverWalletPayoutsView: View {
    @ObservedObject var vm: DriverDashboardVM

    @State private var wallet = DriverWalletSnapshot.placeholder
    @State private var message: String?
    @State private var isLoadingBalance = false
    @State private var isRequestingInstantPay = false

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
                    value: currency(wallet.earningsThisWeek),
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
                payoutMethodRow(icon: "building.columns.fill", title: wallet.bankName, detail: wallet.bankLast4, badge: "Default")
                Divider().padding(.leading, 58)
                payoutMethodRow(icon: "creditcard.fill", title: wallet.cardName, detail: wallet.cardLast4, badge: nil)
                Divider().padding(.leading, 58)
                Button {
                    message = "Open Stripe onboarding to add or update payout methods."
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(Color.rydrWalletRed)
                            .frame(width: 34, height: 34)
                            .background(Circle().stroke(Color.rydrWalletRed.opacity(0.45), lineWidth: 1.2))
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
                quickAction(icon: "building.columns.fill", title: "Add Bank\nAccount", fee: nil)
                quickAction(icon: "creditcard.fill", title: "Add Debit\nCard", fee: nil)
                quickAction(icon: "bolt.fill", title: "Instant Pay", fee: "1% Fee") {
                    Task { await requestInstantPayout() }
                }
                quickAction(icon: "calendar", title: "Payout\nSchedule", fee: nil)
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
                ForEach(wallet.history) { payout in
                    payoutHistoryRow(payout)
                    if payout.id != wallet.history.last?.id {
                        Divider().padding(.leading, 58)
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
            wallet = .placeholder
            return
        }

        do {
            let snapshot = try await Firestore.firestore().collection("drivers").document(uid).getDocument()
            wallet = DriverWalletSnapshot(driverData: snapshot.data() ?? [:], fallbackDailyEarnings: vm.earningsToday)
        } catch {
            wallet = .placeholder
            message = "Could not load wallet details."
        }
    }

    @MainActor
    private func refreshStripeBalance() async {
        guard let accountId = wallet.stripeAccountId, !accountId.isEmpty else { return }

        isLoadingBalance = true
        defer { isLoadingBalance = false }

        do {
            var components = URLComponents(url: stripeBackendBase.appendingPathComponent("connect/balance"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "accountId", value: accountId)]
            guard let url = components?.url else { throw URLError(.badURL) }

            let (data, response) = try await URLSession.shared.data(from: url)
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
        guard let accountId = wallet.stripeAccountId, !accountId.isEmpty else {
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
            request.httpBody = try JSONEncoder().encode(InstantPayoutRequest(
                accountId: accountId,
                amount: amountCents,
                currency: "usd",
                uid: Auth.auth().currentUser?.uid
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
                    title: "Instant Pay to \(wallet.cardName)",
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

private struct DriverWalletSnapshot {
    var availableBalance: Decimal
    var earningsThisWeek: Decimal
    var pendingPayouts: Decimal
    var balanceUpdatedText: String
    var bankName: String
    var bankLast4: String
    var cardName: String
    var cardLast4: String
    var stripeAccountId: String?
    var stripePayoutsEnabled: Bool
    var history: [DriverWalletPayout]

    var canInstantPay: Bool {
        stripePayoutsEnabled && availableBalance > 0
    }

    init(driverData: [String: Any], fallbackDailyEarnings: Decimal) {
        let daily = Self.decimal(driverData["earningsToday"]) ?? fallbackDailyEarnings
        availableBalance = Self.decimal(driverData["availableBalance"]) ?? daily
        earningsThisWeek = Self.decimal(driverData["earningsThisWeek"]) ?? max(daily, Decimal(842.78))
        pendingPayouts = Self.decimal(driverData["pendingPayouts"]) ?? Decimal(150)
        balanceUpdatedText = "Updated just now"
        bankName = Self.string(driverData["payoutBankName"]) ?? "Chase Checking"
        bankLast4 = Self.string(driverData["payoutBankLast4"]) ?? "4242"
        cardName = Self.string(driverData["payoutCardName"]) ?? "Visa Debit Card"
        cardLast4 = Self.string(driverData["payoutCardLast4"]) ?? "7381"
        stripeAccountId = Self.string(driverData["stripeAccountId"])
        stripePayoutsEnabled = (driverData["stripePayoutsEnabled"] as? Bool) ?? false
        history = [
            DriverWalletPayout(title: "Payout to \(bankName)", subtitle: "May 24, 2024 · 10:32 AM", amount: Decimal(312.45), status: "Completed"),
            DriverWalletPayout(title: "Payout to \(bankName)", subtitle: "May 17, 2024 · 10:15 AM", amount: Decimal(298.75), status: "Completed"),
            DriverWalletPayout(title: "Payout to \(bankName)", subtitle: "May 10, 2024 · 9:45 AM", amount: Decimal(275.20), status: "Completed")
        ]
    }

    static var placeholder: DriverWalletSnapshot {
        DriverWalletSnapshot(driverData: [:], fallbackDailyEarnings: Decimal(312.45))
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

private struct StripeConnectBalanceResponse: Decodable {
    let instantAvailableAmount: Int
    let pendingAmount: Int
    let payoutsEnabled: Bool
}

private struct InstantPayoutRequest: Encodable {
    let accountId: String
    let amount: Int
    let currency: String
    let uid: String?
}

private struct InstantPayoutResponse: Decodable {
    let payoutId: String
    let amount: Int
    let currency: String
    let status: String
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
