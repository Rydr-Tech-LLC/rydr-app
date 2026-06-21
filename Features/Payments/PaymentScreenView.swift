import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import StripePayments
import StripePaymentsUI

/// Signup-only screen: lets the user add a card now, or (optionally) **Add Payment Later**.
/// It does NOT list existing cards.
struct PaymentScreenView: View {
    var onComplete: () -> Void = {}
    var onSkip: () -> Void = {}
    var showSkip: Bool = false   // ⬅️ default OFF; pass true only during signup

    // Backend base
    private let backendBase = URL(string: "https://rydr-stripe-backend.onrender.com")!

    // State
    @State private var customerId: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAddCard = false

    var body: some View {
        ZStack {
            SignupPalette.background.ignoresSafeArea()
            SignupRoadHero()
                .frame(height: 280)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .accessibilityHidden(true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 4) {
                        HStack(spacing: 7) {
                            Text("Add Your")
                                .foregroundStyle(SignupPalette.ink)
                            Text("Card")
                                .foregroundStyle(SignupPalette.red)
                        }
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                        Text("Secure payments. Smooth rides.")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(SignupPalette.muted)
                    }
                    .padding(.top, 74)

                    SignupCardPreview()
                        .padding(.top, 2)

                    VStack(spacing: 12) {
                        StaticSignupField(icon: "creditcard", text: customerId == nil ? "Preparing secure card form..." : "Card Number", trailing: "viewfinder")
                        HStack(spacing: 10) {
                            StaticSignupField(icon: "calendar", text: "MM / YY")
                            StaticSignupField(icon: "lock", text: "CVV", trailing: "questionmark.circle")
                        }
                        StaticSignupField(icon: "person", text: "Name on Card")
                    }
                    .redacted(reason: customerId == nil ? .placeholder : [])

                    Button(isLoading ? "Working..." : "Save Card") {
                        showAddCard = true
                    }
                    .buttonStyle(SignupPrimaryButtonStyle())
                    .disabled(customerId == nil || isLoading)
                    .opacity(customerId == nil || isLoading ? 0.56 : 1)

                    if showSkip {
                        Button("Add Payment Later") { onSkip() }
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(SignupPalette.muted)
                    }

                    if isLoading {
                        ProgressView("Working...")
                            .font(.footnote.weight(.semibold))
                    }

                    if let err = errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.footnote.weight(.semibold))
                            .multilineTextAlignment(.leading)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(SignupPalette.red)
                        Text("Your card information is encrypted\nand stored securely.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(SignupPalette.muted)
                    }
                    .padding(.top, 8)

                    SignupProgressDots(active: 2)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { bootstrap() }
        .sheet(isPresented: $showAddCard) {
            if let cid = customerId {
                AddCardSheet_Signup(backendBase: backendBase, customerId: cid) { result in
                    showAddCard = false
                    switch result {
                    case .success: onComplete()
                    case .failure(let err): errorMessage = err.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: - Setup

    private func bootstrap() {
        guard let user = Auth.auth().currentUser else {
            error("You must be logged in.")
            return
        }
        ensureCustomer(for: user) { result in
            if case .success(let cid) = result {
                self.customerId = cid
            } else if case .failure(let e) = result {
                self.error(e.localizedDescription)
            }
        }
    }

    private func ensureCustomer(for user: User, completion: @escaping (Result<String, Error>) -> Void) {
        let uid = user.uid
        let doc = Firestore.firestore().collection("riders").document(uid)

        doc.getDocument { snap, _ in
            if let cid = snap?.data()?["stripeCustomerId"] as? String, !cid.isEmpty {
                completion(.success(cid)); return
            }
            let email = user.email ?? "user-\(uid)@example.com"
            let name  = user.displayName ?? "Rydr User"

            requestJSON(path: "create-customer", body: ["email": email, "name": name, "uid": uid]) { (resp: CreateCustomerResponse_Signup?) in
                guard let cid = resp?.customerId, !cid.isEmpty else {
                    completion(.failure(NSError(domain: "Stripe", code: -1,
                                                userInfo: [NSLocalizedDescriptionKey: "No customerId from server"]))); return
                }
                doc.setData(["stripeCustomerId": cid], merge: true) { _ in
                    completion(.success(cid))
                }
            }
        }
    }

    private func requestJSON<T: Decodable>(
        path: String,
        body: [String: Any],
        completion: @escaping (T?) -> Void
    ) {
        var req = URLRequest(url: backendBase.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        func send(_ r: URLRequest) {
            URLSession.shared.dataTask(with: r) { data, _, _ in
                guard let data = data else { completion(nil); return }
                let obj = try? JSONDecoder().decode(T.self, from: data)
                completion(obj)
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

    private func error(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.isLoading = false
        }
    }
}

private struct SignupCardPreview: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.02, blue: 0.20),
                            Color(red: 0.55, green: 0.00, blue: 0.12),
                            Color(red: 0.10, green: 0.02, blue: 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(CardPreviewTexture().opacity(0.34))
                .shadow(color: SignupPalette.red.opacity(0.32), radius: 16, x: 0, y: 10)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("VISA")
                        .font(.system(size: 20, weight: .black, design: .rounded).italic())
                    Spacer()
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.white)

                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.90, green: 0.77, blue: 0.44), Color(red: 0.57, green: 0.43, blue: 0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 28)

                Text("4242   4242   4242   4242")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 28) {
                    cardMeta("08/30", "EXP DATE")
                    cardMeta("424", "CVV")
                    cardMeta("30168", "ZIP CODE")
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
        .frame(height: 174)
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

// MARK: - Minimal Add-card sheet for signup (distinct type names to avoid clashes)

private struct AddCardSheet_Signup: View {
    let backendBase: URL
    let customerId: String
    let completion: (Result<Void, Error>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var canSubmit = false
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var cardParams: STPPaymentMethodParams?
    @State private var presentingVC: UIViewController?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                CardFormRepresentable_Signup(paymentMethodParams: $cardParams, onEditingChanged: { canSubmit = $0 })
                    .frame(height: 220)

                if let e = errorText {
                    Text(e).foregroundStyle(.red).font(.footnote)
                }

                Button {
                    addCard()
                } label: {
                    if isWorking { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Save Card").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || isWorking)

                Spacer()
            }
            .padding()
            .navigationTitle("Add Card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .background(PresenterResolver_Signup { vc in presentingVC = vc })
        }
    }

    private func addCard() {
        guard let pmParams = cardParams else { return }
        errorText = nil; isWorking = true

        var req = URLRequest(url: backendBase.appendingPathComponent("create-setup-intent"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["customerId": customerId])

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err { finish(.failure(err)); return }
            guard let data = data,
                  let si = try? JSONDecoder().decode(SetupIntentResponse_Signup.self, from: data)
            else { finish(.failure(simple("Failed to create SetupIntent"))); return }

            let confirm = STPSetupIntentConfirmParams(clientSecret: si.clientSecret)
            confirm.paymentMethodParams = pmParams

            let handler = STPPaymentHandler.shared()
            let ctx = AuthContext_Signup(presenting: presentingVC)

            handler.confirmSetupIntent(confirm, with: ctx) { status, _, error in
                switch status {
                case .succeeded: finish(.success(()))
                case .failed:    finish(.failure(error ?? simple("Confirmation failed")))
                case .canceled:  finish(.failure(simple("Canceled")))
                @unknown default:finish(.failure(simple("Unknown status")))
                }
            }
        }.resume()
    }

    private func finish(_ result: Result<Void, Error>) {
        DispatchQueue.main.async {
            isWorking = false
            if case .failure(let e) = result { errorText = e.localizedDescription }
            completion(result)
        }
    }
    private func simple(_ msg: String) -> NSError {
        NSError(domain: "AddCard", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
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
private struct CreateCustomerResponse_Signup: Decodable { let customerId: String }
private struct SetupIntentResponse_Signup: Decodable { let clientSecret: String }





