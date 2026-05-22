//
//  SignupCoordinator.swift
//  RydrSignupFlow
//
import SwiftUI
import PhotosUI
import FirebaseFirestore
import FirebaseAuth

enum SignupStep: Hashable {
    case nameEntry
    case emailPassword
    case addressEntry
    case paymentMethod
    case termsAndVerification
    case done
}

struct SignupCoordinator: View {
    @EnvironmentObject private var session: UserSessionManager

    @State private var path: [SignupStep] = []

    // Shared user data across steps
    @State private var phoneNumber = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var preferredName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword: String = ""
    @State private var streetAddress = ""
    @State private var addressLine2 = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    @State private var agreedToTerms = false
    @State private var isVerifiedUser = false
    @State private var stateIDFront: PhotosPickerItem?
    @State private var stateIDBack: PhotosPickerItem?
    @State private var selfieImage: PhotosPickerItem?

    // Navigate to main app
    @State private var showMainApp = false

    var body: some View {
        NavigationStack(path: $path) {
            // Your PhoneVerificationView should return a verified E.164 phone string
            PhoneVerificationView { verifiedPhone in
                phoneNumber = verifiedPhone
                upsertRider([
                    "phoneNumber": verifiedPhone,
                    "createdAt": FieldValue.serverTimestamp()
                ])
                Task { @MainActor in
                    path.append(.nameEntry)
                }
            }
            .navigationDestination(for: SignupStep.self) { step in
                switch step {

                case .nameEntry:
                    NameEntryView(
                        firstName: $firstName,
                        lastName: $lastName,
                        preferredName: $preferredName,
                        onContinueWithForm: {
                            upsertRider([
                                "firstName": firstName,
                                "lastName": lastName,
                                "preferredName": preferredName
                            ])
                            Task { @MainActor in
                                path.append(.emailPassword)
                            }
                        },
                        onContinueWithSocial: {
                            upsertRider([
                                "firstName": firstName,
                                "lastName": lastName,
                                "preferredName": preferredName
                            ])
                            Task { @MainActor in
                                path.append(.addressEntry)
                            }
                        }
                    )

                case .emailPassword:
                    EmailAndPasswordView(
                        email: $email,
                        password: $password,
                        confirmPassword: $confirmPassword,
                        onNext: {
                            Auth.auth().createUser(withEmail: email, password: password) { result, error in
                                if let error = error as NSError? {
                                    if error.code == AuthErrorCode.emailAlreadyInUse.rawValue {
                                        upsertRider(["email": email])
                                        // (Optional) Sign the user in here if you aren’t already, then call provisionStripeCustomerIfNeeded()
                                        Task { @MainActor in
                                            path.append(.addressEntry)
                                        }
                                    } else {
                                        print("❌ Firebase signup failed: \(error.localizedDescription)")
                                    }
                                    return
                                }

                                upsertRider([
                                    "uid": result?.user.uid ?? "",
                                    "email": email,
                                    "firstName": firstName,
                                    "lastName": lastName,
                                    "preferredName": preferredName,
                                    "phoneNumber": phoneNumber
                                ])

                                // 🔽 Add this line:
                                provisionStripeCustomerIfNeeded()

                                Task { @MainActor in
                                    path.append(.addressEntry)
                                }
                            }
                        }
                    )

                case .addressEntry:
                    AddressInfoView(
                        street: $streetAddress,
                        addressLine2: $addressLine2,
                        city: $city,
                        state: $state,
                        zipCode: $zip,
                        onNext: {
                            upsertRider([
                                "address": [
                                    "street": streetAddress,
                                    "line2": addressLine2,
                                    "city": city,
                                    "state": state,
                                    "zip": zip
                                ]
                            ])
                            Task { @MainActor in
                                path.append(.paymentMethod)
                            }
                        }
                    )

                case .paymentMethod:
                    PaymentScreenView(
                        onComplete: { Task { @MainActor in path.append(.termsAndVerification) } },
                        onSkip:     { Task { @MainActor in path.append(.termsAndVerification) } }   // ✅ optional
                    )

                case .termsAndVerification:
                    TermsAndVerificationView(
                        termsAccepted: $agreedToTerms,
                        wantsVerification: $isVerifiedUser,
                        idFront: $stateIDFront,
                        idBack: $stateIDBack,
                        selfie: $selfieImage,
                        onSubmit: {
                            saveUserToFirestore()
                        }
                    )

                case .done:
                    EmptyView()
                }
            }
        }
        .fullScreenCover(isPresented: $showMainApp) {
            MainTabView()
                .environmentObject(session)
        }
    }

    // MARK: - Firestore helpers

    /// Merge-writes into `riders/{uid}` so the document exists early and stays current.
    private func upsertRider(_ fields: [String: Any]) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore()
            .collection("riders").document(uid)
            .setData(fields, merge: true) { err in
                if let err = err { print("❌ upsertRider error: \(err)") }
            }
    }

    /// Final save (still uses merge so it’s idempotent), then load profile & go to app.
    private func saveUserToFirestore() {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("❌ No authenticated user to save.")
            return
        }

        let riderData: [String: Any] = [
            "uid": uid,
            "firstName": firstName,
            "lastName": lastName,
            "preferredName": preferredName,
            "email": email,
            "phoneNumber": phoneNumber,
            "address": [
                "street": streetAddress,
                "line2": addressLine2,
                "city": city,
                "state": state,
                "zip": zip
            ],
            "agreedToTerms": agreedToTerms,
            "verifiedUser": isVerifiedUser,
            "createdAt": FieldValue.serverTimestamp()
        ]

        Firestore.firestore()
            .collection("riders").document(uid)
            .setData(riderData, merge: true) { error in
                if let error = error {
                    print("❌ Error saving rider: \(error.localizedDescription)")
                } else {
                    print("✅ Rider saved to Firestore.")
                    Task { @MainActor in
                        // 🔁 Pull name/preferred so Profile greeting updates immediately
                        session.loadUserProfile()
                        showMainApp = true
                    }
                }
            }
    }

    // MARK: - Stripe customer provisioning (as requested)

    func provisionStripeCustomerIfNeeded(
        backendBase: URL = URL(string: "https://rydr-stripe-backend.onrender.com")!
    ) {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid
        let doc = Firestore.firestore().collection("riders").document(uid)

        doc.getDocument { snap, _ in
            if let cid = snap?.data()?["stripeCustomerId"] as? String, !cid.isEmpty {
                print("✅ Stripe customer already provisioned:", cid)
                return
            }

            user.getIDToken { token, _ in
                var req = URLRequest(url: backendBase.appendingPathComponent("create-customer"))
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                // (Optional) If you later secure the backend, send the ID token:
                if let token = token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

                let body: [String: Any] = [
                    "email": user.email ?? "user-\(uid)@example.com",
                    "name":  user.displayName ?? "Rydr User",
                    "uid":   uid
                ]
                req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

                URLSession.shared.dataTask(with: req) { data, _, _ in
                    guard
                        let data = data,
                        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let cid = json["customerId"] as? String
                    else { print("❌ Failed to provision Stripe customer"); return }

                    doc.setData(["stripeCustomerId": cid], merge: true)
                    print("✅ Provisioned Stripe customer:", cid)
                }.resume()
            }
        }
    }
}
