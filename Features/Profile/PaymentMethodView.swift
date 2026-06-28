import SwiftUI
import FirebaseAuth
import StripePayments
import StripePaymentsUI

private enum PaymentMethodsPalette {
    static let red = Color(red: 0.95, green: 0.02, blue: 0.19)
    static let deepRed = Color(red: 0.62, green: 0.00, blue: 0.13)

    static let background = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.025, green: 0.025, blue: 0.032, alpha: 1)
        : UIColor.white
    })

    static let panel = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.105, green: 0.105, blue: 0.125, alpha: 1)
        : UIColor.white
    })

    static let ink = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1)
        : UIColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)
    })

    static let muted = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.70, green: 0.71, blue: 0.77, alpha: 1)
        : UIColor(red: 0.43, green: 0.45, blue: 0.52, alpha: 1)
    })

    static let softRed = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.22, green: 0.03, blue: 0.07, alpha: 1)
        : UIColor(red: 1.00, green: 0.92, blue: 0.94, alpha: 1)
    })
}

/// Wallet-style management of a customer's saved cards (Profile screen)
struct PaymentMethodView: View {
    // If you present this view standalone and want it to draw its own title, set true.
    var showsHeader: Bool = false

    private let backendBase = URL(string: "https://rydr-stripe-backend.onrender.com")!

    @State private var customerId: String?
    @State private var cards: [CardPM] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showInfo = false

    // Add/Edit sheet
    @State private var showAddCard = false
    @State private var editingPMId: String? = nil       // when not nil we’re “editing” (replace flow)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            PaymentMethodsPalette.background.ignoresSafeArea()
            PaymentMethodsHero()
                .frame(height: 250)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .accessibilityHidden(true)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    headerBar
                        .padding(.bottom, 6)

                    heroCopy

                    if isLoading && cards.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(0..<3, id: \.self) { index in
                                LoadingPaymentCard(index: index)
                            }
                        }
                        .padding(.top, 4)
                    } else if cards.isEmpty {
                        EmptyWalletTile()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                            .onAppear { bootstrapIfNeeded() }
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(Array(cards.enumerated()), id: \.element.id) { index, pm in
                                CardTile(
                                    brand: pm.brand,
                                    last4: pm.last4,
                                    expMonth: pm.expMonth,
                                    expYear: pm.expYear,
                                    isDefault: pm.isDefault,
                                    index: index,
                                    onMakeDefault: { makeDefault(pm.id) },
                                    onEdit: {
                                        editingPMId = pm.id
                                        showAddCard = true
                                    },
                                    onDelete: { detach(pm.id) }
                                )
                            }
                        }
                        .padding(.top, 4)
                    }

                    addPaymentButton

                    if let err = errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.yellow)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 4)
                    }

                    securityNote
                        .padding(.top, 8)
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { bootstrapIfNeeded() }
        .alert("Secure Payments", isPresented: $showInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your payment information is encrypted and processed through Stripe. Rydr never stores your CVV.")
        }
        .sheet(isPresented: $showAddCard, onDismiss: { reloadIfPossible() }) {
            if let cid = customerId {
                if let editingPMId {
                    AddOrReplaceCardSheet(
                        backendBase: backendBase,
                        customerId: cid,
                        replacePaymentMethodId: editingPMId
                    ) { result in
                        showAddCard = false
                        switch result {
                        case .success(let newPMId):
                            setDefault(newPMId) { _ in
                                detach(editingPMId) { _ in reloadIfPossible() }
                            }
                        case .failure(let e):
                            errorMessage = e.localizedDescription
                        }
                    }
                } else {
                    PaymentScreenView(
                        onComplete: {
                            showAddCard = false
                            reloadIfPossible()
                        },
                        showSkip: false
                    )
                }
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(PaymentMethodsPalette.ink)
                    .frame(width: 48, height: 48)
                    .background(PaymentMethodsPalette.panel, in: Circle())
                    .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 7)
            }
            .accessibilityLabel("Back")

            Spacer()

            Text("Payment Methods")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(PaymentMethodsPalette.ink)
                .lineLimit(1)

            Spacer()

            Button {
                showInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(PaymentMethodsPalette.red)
                    .frame(width: 48, height: 48)
                    .background(PaymentMethodsPalette.panel, in: Circle())
                    .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 7)
            }
            .accessibilityLabel("Payment security information")
        }
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image("RydrLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)
                .accessibilityLabel("Rydr")

            VStack(alignment: .leading, spacing: 0) {
                Text("Pay your way.")
                    .foregroundStyle(PaymentMethodsPalette.ink)
                Text("Ride with ease.")
                    .foregroundStyle(PaymentMethodsPalette.red)
            }
            .font(.system(size: 34, weight: .black, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.74)

            Text("Manage your cards for faster,\nsafer payments.")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(PaymentMethodsPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addPaymentButton: some View {
        Button {
            editingPMId = nil
            showAddCard = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 22, weight: .bold))
                Text("Add Payment Method")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(PaymentMethodsPalette.red)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(PaymentMethodsPalette.background.opacity(0.001))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        PaymentMethodsPalette.red.opacity(customerId == nil || isLoading ? 0.28 : 0.55),
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 7], dashPhase: 1)
                    )
            }
        }
        .disabled(customerId == nil || isLoading)
        .opacity(customerId == nil || isLoading ? 0.55 : 1)
        .padding(.top, 8)
        .accessibilityLabel("Add payment method")
    }

    private var securityNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(PaymentMethodsPalette.red)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text("Your payment information is encrypted and secure.")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(PaymentMethodsPalette.ink)
                Text("We never store your CVV.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(PaymentMethodsPalette.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - First-time setup & data loading
private extension PaymentMethodView {
    func bootstrapIfNeeded() {
        guard customerId == nil else { return }
        guard let user = Auth.auth().currentUser else {
            errorMessage = "You must be logged in."
            return
        }
        isLoading = true
        ensureCustomer(for: user) { result in
            switch result {
            case .success(let cid):
                self.customerId = cid
                self.refreshPaymentMethods(for: cid)
            case .failure(let e):
                self.errorMessage = e.localizedDescription
                self.isLoading = false
            }
        }
    }

    func reloadIfPossible() {
        if let cid = customerId { refreshPaymentMethods(for: cid) }
    }

    func ensureCustomer(for user: User, completion: @escaping (Result<String, Error>) -> Void) {
        let name  = user.displayName ?? "Rydr User"

        requestJSON(
            backendBase: backendBase,
            path: "create-customer",
            body: ["name": name],
            decode: CreateCustomerResponse.self
        ) { resp in
            guard let cid = resp?.customerId, !cid.isEmpty else {
                completion(.failure(simple("Failed to create customer"))); return
            }
            completion(.success(cid))
        }
    }

    func refreshPaymentMethods(for customerId: String) {
        isLoading = true
        requestJSON(
            backendBase: backendBase,
            path: "list-payment-methods",
            body: [:],
            decode: ListPMsResponse.self
        ) { resp in
            DispatchQueue.main.async {
                self.cards = resp?.paymentMethods ?? []
                self.isLoading = false
            }
        }
    }
}

// MARK: - Actions
private extension PaymentMethodView {
    func makeDefault(_ pmId: String) {
        guard let cid = customerId else { return }
        setDefault(pmId) { _ in refreshPaymentMethods(for: cid) }
    }

    func setDefault(_ pmId: String, completion: @escaping (Bool) -> Void) {
        requestJSON(
            backendBase: backendBase,
            path: "set-default-payment-method",
            body: ["paymentMethodId": pmId],
            decode: SimpleOK.self
        ) { _ in completion(true) }
    }

    func detach(_ pmId: String, completion: ((Bool) -> Void)? = nil) {
        requestJSON(
            backendBase: backendBase,
            path: "detach-payment-method",
            body: ["paymentMethodId": pmId],
            decode: SimpleOK.self
        ) { _ in
            completion?(true)
            reloadIfPossible()
        }
    }
}

// MARK: - Networking helper
private func requestJSON<T: Decodable>(
    backendBase: URL,
    path: String,
    body: [String: Any],
    decode: T.Type,
    completion: @escaping (T?) -> Void
) {
    var req = URLRequest(url: backendBase.appendingPathComponent(path))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

    func send(_ r: URLRequest) {
        URLSession.shared.dataTask(with: r) { data, _, _ in
            guard let data else { completion(nil); return }
            completion(try? JSONDecoder().decode(T.self, from: data))
        }.resume()
    }

    if let user = Auth.auth().currentUser {
        user.getIDToken { token, _ in
            var r = req
            if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            send(r)
        }
    } else {
        send(req)
    }
}

private func simple(_ msg: String) -> NSError {
    NSError(domain: "PaymentMethods", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
}

// MARK: - Wallet-style card tile
private struct CardTile: View {
    let brand: String
    let last4: String
    let expMonth: Int
    let expYear: Int
    let isDefault: Bool
    let index: Int
    var onMakeDefault: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    @State private var showActions = false

    var body: some View {
        Button {
            showActions = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(brandGradient)
                    .overlay(CardSpeedTexture().opacity(0.22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(isDefault ? 0.38 : 0.08), lineWidth: isDefault ? 1.3 : 0.8)
                    }
                    .shadow(color: shadowColor, radius: 14, x: 0, y: 8)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        if isDefault {
                            HStack(spacing: 5) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Default")
                                    .font(.system(size: 10, weight: .black, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.16), in: Capsule())
                            .padding(.bottom, 14)
                        }

                        brandMark
                            .frame(height: 36, alignment: .leading)

                        Spacer()

                        Text(displayName)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Spacer(minLength: isDefault ? 30 : 16)
                        Text("•••• \(last4)")
                            .font(.system(size: 23, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text(String(format: "Expires %02d/%02d", expMonth, expYear % 100))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            .frame(height: isDefault ? 154 : 110)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(displayName), ending in \(last4), expires \(String(format: "%02d/%02d", expMonth, expYear % 100))\(isDefault ? ", default card" : "")")
        }
        .buttonStyle(.plain)
        .confirmationDialog("Manage \(displayName)", isPresented: $showActions, titleVisibility: .visible) {
            if !isDefault {
                Button("Make Default", action: onMakeDefault)
            }
            Button("Replace Card", action: onEdit)
            Button("Remove Card", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Card ending in \(last4)")
        }
    }

    private var normalizedBrand: String {
        brand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var displayName: String {
        switch normalizedBrand {
        case "visa": return "Visa Debit Card"
        case "mastercard": return "Mastercard"
        case "amex", "american express": return "Amex Card"
        case "discover": return "Discover Card"
        default:
            let clean = brand.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? "Payment Card" : "\(clean.capitalized) Card"
        }
    }

    @ViewBuilder
    private var brandMark: some View {
        switch normalizedBrand {
        case "visa":
            Text("VISA")
                .font(.system(size: 25, weight: .black, design: .rounded).italic())
                .foregroundStyle(.white)
        case "mastercard":
            ZStack {
                Circle()
                    .fill(Color(red: 0.92, green: 0.02, blue: 0.10))
                    .frame(width: 34, height: 34)
                    .offset(x: -10)
                Circle()
                    .fill(Color(red: 1.00, green: 0.67, blue: 0.12).opacity(0.92))
                    .frame(width: 34, height: 34)
                    .offset(x: 10)
            }
            .frame(width: 58, height: 36, alignment: .leading)
        case "amex", "american express":
            Text("AMERICAN\nEXPRESS")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineSpacing(-2)
        case "discover":
            HStack(spacing: 0) {
                Text("DISC")
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.yellow, .orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 15, height: 15)
                    .padding(.horizontal, 1)
                Text("VER")
            }
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(.white)
        default:
            HStack(spacing: 8) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 24, weight: .bold))
                Text(brand.isEmpty ? "CARD" : brand.uppercased())
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
        }
    }

    private var brandGradient: LinearGradient {
        let colors: [Color]
        switch normalizedBrand {
        case "visa":
            colors = [
                Color(red: 0.98, green: 0.01, blue: 0.20),
                Color(red: 0.72, green: 0.00, blue: 0.16),
                Color(red: 0.50, green: 0.00, blue: 0.12)
            ]
        case "mastercard":
            colors = [
                Color(red: 0.13, green: 0.14, blue: 0.15),
                Color(red: 0.055, green: 0.06, blue: 0.065)
            ]
        case "amex", "american express":
            colors = [
                Color(red: 0.18, green: 0.45, blue: 0.88),
                Color(red: 0.05, green: 0.12, blue: 0.42)
            ]
        case "discover":
            colors = [
                Color(red: 0.28, green: 0.28, blue: 0.29),
                Color(red: 0.08, green: 0.08, blue: 0.09)
            ]
        default:
            colors = [
                Color(red: 0.44, green: 0.45, blue: 0.50),
                Color(red: 0.12, green: 0.13, blue: 0.16)
            ]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var shadowColor: Color {
        normalizedBrand == "visa"
        ? PaymentMethodsPalette.red.opacity(0.34)
        : Color.black.opacity(0.22)
    }
}

private struct EmptyWalletTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(PaymentMethodsPalette.red)
            Text("No cards saved yet")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(PaymentMethodsPalette.ink)
            Text("Add a payment method to make ride checkout faster.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PaymentMethodsPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(PaymentMethodsPalette.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PaymentMethodsPalette.red.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 7)
    }
}

private struct LoadingPaymentCard: View {
    let index: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        PaymentMethodsPalette.panel.opacity(0.92),
                        PaymentMethodsPalette.panel.opacity(0.62)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PaymentMethodsPalette.muted.opacity(0.24))
                        .frame(width: 92, height: 18)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PaymentMethodsPalette.muted.opacity(0.18))
                        .frame(width: 160, height: 14)
                }
                .padding(22)
            }
            .frame(height: index == 0 ? 154 : 110)
            .redacted(reason: .placeholder)
            .shadow(color: Color.black.opacity(0.09), radius: 12, x: 0, y: 7)
    }
}

private struct PaymentMethodsHero: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    PaymentMethodsPalette.background,
                    PaymentMethodsPalette.softRed.opacity(0.74),
                    PaymentMethodsPalette.background.opacity(0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            PaymentCitySkyline()
                .fill(
                    LinearGradient(
                        colors: [
                            PaymentMethodsPalette.red.opacity(0.08),
                            PaymentMethodsPalette.red.opacity(0.24)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 220, height: 160)
                .offset(x: 145, y: 60)
                .blur(radius: 0.8)

            PaymentSpeedLines()
                .stroke(
                    LinearGradient(
                        colors: [
                            PaymentMethodsPalette.red.opacity(0.0),
                            PaymentMethodsPalette.red.opacity(0.55),
                            PaymentMethodsPalette.red.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .blur(radius: 0.5)
                .offset(x: 68, y: 62)

            LinearGradient(
                colors: [
                    PaymentMethodsPalette.background.opacity(0.0),
                    PaymentMethodsPalette.background.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
    }
}

private struct PaymentCitySkyline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let base = rect.maxY
        let widths: [CGFloat] = [18, 30, 22, 38, 24, 42, 20, 34]
        let heights: [CGFloat] = [76, 112, 92, 136, 86, 154, 104, 124]
        var x = rect.minX

        for index in widths.indices {
            let top = base - heights[index]
            path.addRoundedRect(
                in: CGRect(x: x, y: top, width: widths[index], height: heights[index]),
                cornerSize: CGSize(width: 2, height: 2)
            )
            x += widths[index] + CGFloat(index % 2 == 0 ? 11 : 15)
        }

        return path
    }
}

private struct PaymentSpeedLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let vanishing = CGPoint(x: rect.maxX * 0.58, y: rect.midY)

        for index in 0..<24 {
            let y = rect.minY + CGFloat(index) * rect.height / 24
            let start = CGPoint(x: rect.minX - CGFloat(index % 4) * 16, y: y)
            let end = CGPoint(x: vanishing.x + CGFloat(index % 6) * 12, y: vanishing.y + CGFloat(index - 12) * 2)
            path.move(to: start)
            path.addLine(to: end)
        }

        for index in 0..<8 {
            let y = rect.maxY * (0.68 + CGFloat(index) * 0.034)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: y - 44),
                control1: CGPoint(x: rect.midX * 0.70, y: y + 16),
                control2: CGPoint(x: rect.midX * 1.28, y: y - 58)
            )
        }

        return path
    }
}

private struct CardSpeedTexture: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                for index in 0..<13 {
                    let y = proxy.size.height * (0.26 + CGFloat(index) * 0.045)
                    path.move(to: CGPoint(x: proxy.size.width * 0.22, y: y))
                    path.addCurve(
                        to: CGPoint(x: proxy.size.width * 0.96, y: y - CGFloat(index) * 2.2),
                        control1: CGPoint(x: proxy.size.width * 0.48, y: y + 20),
                        control2: CGPoint(x: proxy.size.width * 0.70, y: y - 24)
                    )
                }
            }
            .stroke(Color.white.opacity(0.25), lineWidth: 0.7)
        }
    }
}

// MARK: - Add / Replace card sheet
/// If `replacePaymentMethodId` is provided, this sheet behaves like “Edit”:
/// it confirms a new card, makes it default, then the caller can detach the old one.
private struct AddOrReplaceCardSheet: View {
    let backendBase: URL
    let customerId: String
    let replacePaymentMethodId: String?
    let completion: (Result<String, Error>) -> Void   // returns new PM id

    @Environment(\.dismiss) private var dismiss
    @State private var canSubmit = false
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var cardParams: STPPaymentMethodParams?
    @State private var presentingVC: UIViewController?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                CardFormRepresentable(paymentMethodParams: $cardParams, onEditingChanged: { canSubmit = $0 })
                    .frame(height: 220)

                if let e = errorText {
                    Text(e).foregroundStyle(.red).font(.footnote)
                }

                Button {
                    addCard()
                } label: {
                    if isWorking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(replacePaymentMethodId == nil ? "Save Card" : "Replace Card")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || isWorking)

                Spacer()
            }
            .padding()
            .navigationTitle(replacePaymentMethodId == nil ? "Add Card" : "Edit Card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .background(PresenterResolver { vc in presentingVC = vc })
        }
    }

    private func addCard() {
        guard let pmParams = cardParams else { return }
        errorText = nil; isWorking = true

        requestJSON(
            backendBase: backendBase,
            path: "create-setup-intent",
            body: ["requestId": UUID().uuidString],
            decode: SetupIntentResponse_Profile.self
        ) { si in
            guard let si else {
                finish(.failure(simple("Failed to create SetupIntent")))
                return
            }

            let confirm = STPSetupIntentConfirmParams(clientSecret: si.clientSecret)
            confirm.paymentMethodParams = pmParams

            let handler = STPPaymentHandler.shared()
            let ctx = AuthContext(presenting: presentingVC)

            handler.confirmSetupIntent(confirm, with: ctx) { status, setupIntent, error in
                switch status {
                case .succeeded:
                    // The new payment method should now be attached to the customer
                    let newPMId = setupIntent?.paymentMethodID ?? ""
                    if newPMId.isEmpty {
                        finish(.failure(simple("Card saved but could not resolve payment method id.")))
                    } else {
                        finish(.success(newPMId))
                    }
                case .failed:
                    finish(.failure(error ?? simple("Confirmation failed")))
                case .canceled:
                    finish(.failure(simple("Canceled")))
                @unknown default:
                    finish(.failure(simple("Unknown status")))
                }
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        DispatchQueue.main.async {
            isWorking = false
            if case .failure(let e) = result { errorText = e.localizedDescription }
            completion(result)
        }
    }
}

// MARK: - Card form wrapper
private struct CardFormRepresentable: UIViewRepresentable {
    @Binding var paymentMethodParams: STPPaymentMethodParams?
    var onEditingChanged: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> STPPaymentCardTextField {
        let view = STPPaymentCardTextField()
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ uiView: STPPaymentCardTextField, context: Context) {}
    func makeCoordinator() -> Coord { Coord(self) }

    final class Coord: NSObject, STPPaymentCardTextFieldDelegate {
        var parent: CardFormRepresentable
        init(_ parent: CardFormRepresentable) { self.parent = parent }
        func paymentCardTextFieldDidChange(_ textField: STPPaymentCardTextField) {
            parent.paymentMethodParams = textField.paymentMethodParams
            parent.onEditingChanged(textField.isValid)
        }
    }
}

// MARK: - Auth context helpers
private final class AuthContext: NSObject, STPAuthenticationContext {
    private weak var presenting: UIViewController?
    init(presenting: UIViewController?) { self.presenting = presenting }
    func authenticationPresentingViewController() -> UIViewController {
        presenting ?? (UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController ?? UIViewController())
    }
}
private struct PresenterResolver: UIViewControllerRepresentable {
    var onResolve: (UIViewController) -> Void
    func makeUIViewController(context: Context) -> UIViewController { Resolver(onResolve: onResolve) }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    private final class Resolver: UIViewController {
        var onResolve: (UIViewController) -> Void
        init(onResolve: @escaping (UIViewController) -> Void) { self.onResolve = onResolve; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); onResolve(self) }
    }
}

// MARK: - DTOs
private struct CreateCustomerResponse: Decodable { let customerId: String }
private struct SetupIntentResponse_Profile: Decodable { let clientSecret: String }
private struct SimpleOK: Decodable { let ok: Bool }
private struct ListPMsResponse: Decodable { let paymentMethods: [CardPM] }
private struct CardPM: Decodable, Identifiable {
    let id: String
    let brand: String
    let last4: String
    let expMonth: Int
    let expYear: Int
    let isDefault: Bool
}
