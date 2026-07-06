import SwiftUI
import FirebaseAuth
import StripePayments
import StripePaymentsUI

/// Signup-only screen: lets the user add a card now, or (optionally) **Add Payment Later**.
/// It does NOT list existing cards.
struct PaymentScreenView: View {
    var onComplete: () -> Void = {}
    var onSkip: () -> Void = {}
    var showSkip: Bool = false   // ⬅️ default OFF; pass true only during signup

    // Backend base
    private let backendBase = RydrStripeBackendConfig.baseURL

    // State
    @State private var customerId: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var canSubmitCard = false
    @State private var cardParams: STPPaymentMethodParams?
    @State private var presentingVC: UIViewController?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            SignupPalette.background.ignoresSafeArea()

            PaymentMotionHero()
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
                .accessibilityHidden(true)

            PaymentBottomSkyline()
                .frame(height: 126)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityHidden(true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    SignupBackButton(action: { dismiss() })
                        .frame(maxWidth: .infinity, alignment: .leading)

                    PaymentHeader()
                        .padding(.top, 34)

                    SignupStepHeader(active: 2)
                        .padding(.horizontal, 54)
                        .padding(.top, 2)

                    Image("SignupVisaCard")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 330)
                        .frame(height: 184)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: SignupPalette.red.opacity(0.26), radius: 24, x: 0, y: 16)
                        .accessibilityHidden(true)
                        .padding(.top, 6)

                    paymentForm

                    Button(isLoading ? "Working..." : "Save & Continue") {
                        addCard()
                    }
                    .buttonStyle(SignupPrimaryButtonStyle())
                    .disabled(customerId == nil || !canSubmitCard || isLoading)
                    .opacity(customerId == nil || !canSubmitCard || isLoading ? 0.56 : 1)
                    .padding(.top, 4)

                    if showSkip {
                        Button("Add Payment Later") { onSkip() }
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(SignupPalette.muted)
                    }

                    if isLoading {
                        ProgressView("Preparing secure payment setup...")
                            .font(.footnote.weight(.semibold))
                            .tint(SignupPalette.red)
                    }

                    if let err = errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(SignupPalette.red)
                            .font(.footnote.weight(.semibold))
                            .multilineTextAlignment(.leading)
                    }

                    SignupSecurityFooter(text: "Your payment details are 100% secure.")
                        .padding(.bottom, 108)
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .frame(maxWidth: 430)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .onAppear { bootstrap() }
        .background(PresenterResolver_Signup { vc in presentingVC = vc })
        .hideKeyboardOnTap()
    }

    private var paymentForm: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(SignupPalette.red)
                Text("Card Information")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(SignupPalette.ink)
                Spacer()
                Label("Secured by Stripe", systemImage: "lock.fill")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(SignupPalette.muted)
                    .labelStyle(.titleAndIcon)
            }

            SignupStripeCardEntry(
                paymentMethodParams: $cardParams,
                canSubmit: $canSubmitCard,
                isReady: customerId != nil
            )

            PaymentSecurityStrip()
        }
        .padding(.top, 4)
    }

    // MARK: - Setup

    private func bootstrap() {
        guard customerId == nil else { return }
        guard let user = Auth.auth().currentUser else {
            error("You must be logged in.")
            return
        }
        isLoading = true
        Task { @MainActor in
            await RydrStripeBackendConfig.configureStripePublishableKeyIfNeeded()
            guard RydrStripeBackendConfig.hasConfiguredPublishableKey else {
                isLoading = false
                error("Stripe is not configured. Check the Stripe backend publishable key.")
                return
            }

            ensureCustomer(for: user) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    if case .success(let cid) = result {
                        self.customerId = cid
                    } else if case .failure(let e) = result {
                        self.error(e.localizedDescription)
                    }
                }
            }
        }
    }

    private func ensureCustomer(for user: User, completion: @escaping (Result<String, Error>) -> Void) {
        let name  = user.displayName ?? "Rydr User"

        requestJSON(path: "create-customer", body: ["name": name]) { (result: Result<CreateCustomerResponse_Signup, Error>) in
            switch result {
            case .success(let resp):
                guard !resp.customerId.isEmpty else {
                    completion(.failure(simple("No customerId from server")))
                    return
                }
                completion(.success(resp.customerId))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func requestJSON<T: Decodable>(
        path: String,
        body: [String: Any],
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        var req = URLRequest(url: backendBase.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        func send(_ r: URLRequest) {
            URLSession.shared.dataTask(with: r) { data, response, requestError in
                if let requestError {
                    completion(.failure(requestError))
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(simple("Payment server did not return a valid response.")))
                    return
                }

                let responseData = data ?? Data()
                if (200..<300).contains(http.statusCode) {
                    do {
                        completion(.success(try JSONDecoder().decode(T.self, from: responseData)))
                    } catch {
                        completion(.failure(simple("Payment server returned an unexpected response.")))
                    }
                    return
                }

                let backendError = (try? JSONDecoder().decode(BackendErrorResponse_Signup.self, from: responseData))?.error
                let message = backendError.map { "Payment server error (\(http.statusCode)): \($0)" }
                    ?? "Payment server error (\(http.statusCode))."
                completion(.failure(simple(message)))
            }.resume()
        }

        guard let user = Auth.auth().currentUser else {
            completion(.failure(simple("You must be logged in.")))
            return
        }

        user.getIDTokenForcingRefresh(true) { token, tokenError in
            guard let token, tokenError == nil else {
                let message = tokenError?.localizedDescription ?? "Could not get a Firebase session token."
                completion(.failure(simple(message)))
                return
            }

            var r = req
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            send(r)
        }
    }

    private func error(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.isLoading = false
        }
    }

    private func addCard() {
        guard RydrStripeBackendConfig.hasConfiguredPublishableKey else {
            error("Payment setup is still loading. Try again in a moment.")
            Task { @MainActor in
                await RydrStripeBackendConfig.configureStripePublishableKeyIfNeeded()
            }
            return
        }
        guard customerId != nil else {
            error("Payment setup is still loading.")
            return
        }
        guard let pmParams = cardParams else {
            error("Enter a valid card before saving.")
            return
        }

        errorMessage = nil
        isLoading = true

        requestJSON(path: "create-setup-intent", body: ["requestId": UUID().uuidString]) { (result: Result<SetupIntentResponse_Signup, Error>) in
            let setupIntent: SetupIntentResponse_Signup
            switch result {
            case .success(let response):
                setupIntent = response
            case .failure(let error):
                finishCardSave(.failure(error))
                return
            }

            let confirm = STPSetupIntentConfirmParams(clientSecret: setupIntent.clientSecret)
            confirm.paymentMethodParams = pmParams

            let handler = STPPaymentHandler.shared()
            let context = AuthContext_Signup(presenting: presentingVC)

            handler.confirmSetupIntent(confirm, with: context) { status, _, error in
                switch status {
                case .succeeded:
                    finishCardSave(.success(()))
                case .failed:
                    finishCardSave(.failure(error ?? simple("Confirmation failed")))
                case .canceled:
                    finishCardSave(.failure(simple("Canceled")))
                @unknown default:
                    finishCardSave(.failure(simple("Unknown payment status")))
                }
            }
        }
    }

    private func finishCardSave(_ result: Result<Void, Error>) {
        DispatchQueue.main.async {
            isLoading = false
            switch result {
            case .success:
                onComplete()
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func simple(_ message: String) -> NSError {
        NSError(domain: "PaymentScreen", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private struct SignupCardPreview: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            SignupPalette.coral,
                            SignupPalette.red,
                            SignupPalette.wine
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(CardPreviewTexture().opacity(0.34))
                .shadow(color: SignupPalette.red.opacity(0.30), radius: 20, x: 0, y: 14)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.92, green: 0.78, blue: 0.43), Color(red: 0.58, green: 0.44, blue: 0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 28)
                    Spacer()
                    Text("VISA")
                        .font(.system(size: 20, weight: .black, design: .rounded).italic())
                }
                .foregroundStyle(.white)

                Text("••••   ••••   ••••   4242")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 28) {
                    cardMeta("KHRIS NUNNALLY", "CARDHOLDER")
                    Spacer()
                    cardMeta("08/30", "EXPIRES")
                }
            }
            .padding(18)

            Image("RydrLogo")
                .resizable()
                .scaledToFit()
                .opacity(0.20)
                .frame(width: 120, height: 120)
                .offset(x: 42, y: -2)
        }
        .frame(height: 176)
        .accessibilityHidden(true)
    }

    private func cardMeta(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 7, weight: .black, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.88))
    }
}

private struct PaymentHeader: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("STEP ")
                .foregroundStyle(SignupPalette.muted)
            + Text("3")
                .foregroundStyle(SignupPalette.red)
            + Text(" OF 4")
                .foregroundStyle(SignupPalette.muted)

            VStack(spacing: 7) {
                Text("Add Payment Method")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(SignupPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text("Add a payment method to your Rydr wallet\nso you're ready to ride.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(SignupPalette.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .font(.system(size: 12, weight: .black, design: .rounded))
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.white.opacity(0.72), in: Capsule())
    }
}

private struct PaymentMotionHero: View {
    @State private var phase: CGFloat = -90
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 1.0, green: 0.96, blue: 0.97),
                    SignupPalette.background.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            PaymentRouteLines(phase: phase + dragOffset)
                .stroke(SignupPalette.red.opacity(0.18), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .blur(radius: 0.1)

            PaymentRouteLines(phase: phase * 0.65 + dragOffset)
                .stroke(SignupPalette.red.opacity(0.09), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .blur(radius: 1.2)

            Image(systemName: "car.fill")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(SignupPalette.redGradient)
                .shadow(color: SignupPalette.red.opacity(0.28), radius: 8, x: 0, y: 4)
                .offset(x: 114 + dragOffset * 0.06, y: 62)

            Circle()
                .stroke(SignupPalette.red.opacity(0.14), style: StrokeStyle(lineWidth: 1.3, dash: [2, 4]))
                .frame(width: 44, height: 44)
                .overlay {
                    Circle()
                        .fill(SignupPalette.red.opacity(0.34))
                        .frame(width: 8, height: 8)
                }
                .offset(x: 178, y: 48)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { dragOffset = $0.translation.width * 0.35 }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
        )
        .onAppear {
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                phase = 110
            }
        }
    }
}

private struct PaymentRouteLines: Shape {
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<7 {
            let y = rect.height * (0.44 + CGFloat(index) * 0.035)
            path.move(to: CGPoint(x: rect.minX - 70 + phase * 0.18, y: y))
            path.addCurve(
                to: CGPoint(x: rect.maxX + 70 + phase * 0.08, y: y + CGFloat(index - 3) * 3),
                control1: CGPoint(x: rect.width * 0.30 + phase, y: y - 58),
                control2: CGPoint(x: rect.width * 0.78 + phase * 0.25, y: y + 38)
            )
        }
        return path
    }
}

private struct PaymentBottomSkyline: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.clear,
                    SignupPalette.background.opacity(0.28),
                    SignupPalette.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Image("SignupAtlantaSkyline")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 126)
                .clipped()
                .opacity(0.54)
                .saturation(0.15)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            SignupPalette.red.opacity(0.05),
                            SignupPalette.background.opacity(0.26)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
    }
}

private struct PaymentSecurityStrip: View {
    var body: some View {
        HStack(spacing: 0) {
            PaymentSecurityItem(icon: "shield.checkered", title: "Bank-level", subtitle: "Security")
            Divider().frame(height: 28)
            PaymentSecurityItem(icon: "lock.fill", title: "Encrypted", subtitle: "Payments")
            Divider().frame(height: 28)
            PaymentSecurityItem(icon: "checkmark.circle", title: "Powered by", subtitle: "Stripe")
        }
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(SignupPalette.softLine, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.045), radius: 10, x: 0, y: 6)
    }
}

private struct PaymentSecurityItem: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(SignupPalette.muted)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle)
            }
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(SignupPalette.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CardPreviewTexture: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                for index in 0..<24 {
                    let y = proxy.size.height * (0.14 + CGFloat(index) * 0.032)
                    path.move(to: CGPoint(x: proxy.size.width * 0.35, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y + CGFloat(index - 12) * 1.8))
                }
            }
            .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
        }
    }
}

private struct StaticSignupField: View {
    let icon: String
    let text: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(SignupPalette.red)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(SignupPalette.muted.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer()
            if let trailing {
                Image(systemName: trailing)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SignupPalette.red.opacity(0.80))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(SignupPalette.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(SignupPalette.red.opacity(0.36), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 6)
    }
}

private struct SignupStripeCardEntry: View {
    @Binding var paymentMethodParams: STPPaymentMethodParams?
    @Binding var canSubmit: Bool
    let isReady: Bool

    var body: some View {
        HStack(spacing: 12) {
            CardFormRepresentable_Signup(
                paymentMethodParams: $paymentMethodParams,
                onEditingChanged: { canSubmit = $0 }
            )
            .frame(height: 58)
            .disabled(!isReady)
            .opacity(isReady ? 1 : 0.45)

            Image(systemName: canSubmit ? "checkmark.circle.fill" : "lock.fill")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(canSubmit ? SignupPalette.success : SignupPalette.muted.opacity(0.70))
        }
        .padding(.horizontal, 14)
        .frame(height: 72)
        .background(SignupPalette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(canSubmit ? SignupPalette.success.opacity(0.40) : SignupPalette.softLine, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 7)
    }
}

// MARK: - Small helpers (separate names to avoid duplicate-type compile errors)

private struct CardFormRepresentable_Signup: UIViewRepresentable {
    @Binding var paymentMethodParams: STPPaymentMethodParams?
    var onEditingChanged: (Bool) -> Void = { _ in }
    func makeUIView(context: Context) -> STPPaymentCardTextField {
        let v = STPPaymentCardTextField(); v.delegate = context.coordinator; return v
    }
    func updateUIView(_ uiView: STPPaymentCardTextField, context: Context) {}
    func makeCoordinator() -> Coord { Coord(self) }
    final class Coord: NSObject, STPPaymentCardTextFieldDelegate {
        var parent: CardFormRepresentable_Signup
        init(_ p: CardFormRepresentable_Signup) { parent = p }
        func paymentCardTextFieldDidChange(_ t: STPPaymentCardTextField) {
            parent.paymentMethodParams = t.paymentMethodParams
            parent.onEditingChanged(t.isValid)
        }
    }
}

private final class AuthContext_Signup: NSObject, STPAuthenticationContext {
    private weak var presenting: UIViewController?
    init(presenting: UIViewController?) { self.presenting = presenting }
    func authenticationPresentingViewController() -> UIViewController {
        presenting ?? (UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController ?? UIViewController())
    }
}
private struct PresenterResolver_Signup: UIViewControllerRepresentable {
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

// DTOs with unique names in this file
private struct BackendErrorResponse_Signup: Decodable { let error: String }
private struct CreateCustomerResponse_Signup: Decodable { let customerId: String }
private struct SetupIntentResponse_Signup: Decodable { let clientSecret: String }
