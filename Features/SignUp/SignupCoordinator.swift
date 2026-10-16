//
//  SignupCoordinator.swift
//  RydrSignupFlow
//
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

enum SignupStep: Hashable {
    case betaWaiver
    case nameEntry
    case emailPassword
    case addressEntry
    case paymentMethod
    case termsAndVerification
    case done
    static func resumeStep(_ key: String) -> SignupStep? {
        switch key {
        case "betaWaiver": return .betaWaiver
        case "nameEntry": return .nameEntry
        case "emailPassword": return .emailPassword
        case "addressEntry": return .addressEntry
        case "paymentMethod": return .paymentMethod
        case "termsAndVerification": return .termsAndVerification
        default: return nil
        }
    }
}

struct SignupCoordinator: View {
    @EnvironmentObject private var session: UserSessionManager
    @Environment(\.dismiss) private var dismiss
    let upgradingCashHubAccount: Bool
    private let resumeSnapshot: RiderOnboardingSnapshot?
    private let onCompleted: (() -> Void)?

    @State private var path: [SignupStep] = []
    @State private var hasLoadedExistingProfile = false

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
    @State private var betaWaiverAccepted = false
    @State private var verificationRequested = false
    @State private var betaAccessError = ""
    @State private var showBetaAccessAlert = false
    @State private var accountSubmissionError = ""
    @State private var isCreatingAccount = false

    // Navigate to main app
    @State private var showMainApp = false

    init(upgradingCashHubAccount: Bool = false, resumeSnapshot: RiderOnboardingSnapshot? = nil, onCompleted: (() -> Void)? = nil) {
        self.upgradingCashHubAccount = upgradingCashHubAccount
        self.resumeSnapshot = resumeSnapshot
        self.onCompleted = onCompleted
        guard let saved = resumeSnapshot else { return }
        let p = saved.profile
        _path = State(initialValue: saved.nextStep.flatMap(SignupStep.resumeStep).map { [$0] } ?? [])
        _phoneNumber = State(initialValue: p.phoneNumber ?? "")
        _firstName = State(initialValue: p.firstName ?? "")
        _lastName = State(initialValue: p.lastName ?? "")
        _preferredName = State(initialValue: p.preferredName ?? "")
        _email = State(initialValue: p.email ?? "")
        _streetAddress = State(initialValue: p.address?.street ?? "")
        _addressLine2 = State(initialValue: p.address?.line2 ?? "")
        _city = State(initialValue: p.address?.city ?? "")
        _state = State(initialValue: p.address?.state ?? "")
        _zip = State(initialValue: p.address?.zip ?? "")
        _betaWaiverAccepted = State(initialValue: p.betaWaiverAccepted ?? false)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if upgradingCashHubAccount && !hasLoadedExistingProfile {
                    ProgressView("Loading your information...")
                } else {
                    // Your PhoneVerificationView should return a verified E.164 phone string
                    PhoneVerificationView(
                        initialPhoneNumber: phoneNumber,
                        linkToCurrentUser: upgradingCashHubAccount || resumeSnapshot != nil
                    ) { verifiedPhone in
                        phoneNumber = verifiedPhone
                        betaInviteApproved(phoneE164: verifiedPhone) { approved in
                            Task { @MainActor in
                                if approved {
                                    writePhoneIndex(phoneE164: verifiedPhone, uid: RydrWorkspace.auth.currentUser?.uid ?? "")
                                    if resumeSnapshot != nil { onCompleted?() }
                                    else { path.append(.betaWaiver) }
                                } else {
                                    try? RydrWorkspace.auth.signOut()
                                    betaAccessError = "This phone number has not been approved for the Rydr rider beta yet. Join the waitlist or use the phone number from your beta approval."
                                    showBetaAccessAlert = true
                                }
                            }
                        }
                    }
                }
            }
            .task {
                if upgradingCashHubAccount && !hasLoadedExistingProfile {
                    loadExistingProfile()
                }
            }
            .navigationDestination(for: SignupStep.self) { step in
                Group {
                switch step {
                case .betaWaiver:
                    BetaWaiverView(
                        onAgree: {
                            Task { @MainActor in
                                do {
                                    try await RiderBackendIdentityService.sync(acceptBetaWaiver: true, beginOnboarding: true)
                                    betaWaiverAccepted = true
                                    path.append(.nameEntry)
                                } catch { betaAccessError = error.localizedDescription; showBetaAccessAlert = true }
                            }
                        },
                        onDecline: {
                            if resumeSnapshot != nil { session.logout() }
                            else { try? RydrWorkspace.auth.signOut(); dismiss() }
                        }
                    )

                case .nameEntry:
                    NameEntryView(
                        firstName: $firstName,
                        lastName: $lastName,
                        preferredName: $preferredName,
                        email: $email,
                        allowsSocialSignup: !upgradingCashHubAccount,
                        onContinueWithForm: {
                            upsertRider([
                                "firstName": firstName,
                                "lastName": lastName,
                                "preferredName": preferredName
                            ]) { path.append(upgradingCashHubAccount ? .addressEntry : .emailPassword) }
                        },
                        onContinueWithSocial: { socialProfile in
                            finishSocialAuthAccountSetup(profile: socialProfile)
                        }
                    )

                case .emailPassword:
                    EmailAndPasswordView(
                        email: $email,
                        password: $password,
                        confirmPassword: $confirmPassword,
                        isSubmitting: isCreatingAccount,
                        submissionError: accountSubmissionError,
                        onNext: {
                            createOrLinkFirebaseAccount()
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
                            ]) { path.append(.paymentMethod) }
                        }
                    )

                case .paymentMethod:
                    PaymentScreenView(
                        onComplete: { completePaymentStep() },
                        onSkip: { completePaymentStep() } // Optional, but save the choice for resume.
                    )

                case .termsAndVerification:
                    TermsAndVerificationView(
                        termsAccepted: $agreedToTerms,
                        wantsVerification: $verificationRequested,
                        onSubmit: {
                            saveUserToFirestore()
                        }
                    )

                case .done:
                    EmptyView()
                }
                }.navigationBarBackButtonHidden(resumeSnapshot != nil && path.count == 1)
            }
        }
        .toolbar {
            if resumeSnapshot != nil { ToolbarItem(placement: .topBarTrailing) { Button("Sign out") { session.logout() } } }
        }
        .fullScreenCover(isPresented: $showMainApp) {
            MainTabView()
                .environmentObject(session)
        }
        .alert("Unable to continue", isPresented: $showBetaAccessAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text(betaAccessError)
        }
    }

    private func completePaymentStep() {
        Task { @MainActor in
            do { try await RiderBackendIdentityService.completePaymentStep(); path.append(.termsAndVerification) }
            catch { betaAccessError = error.localizedDescription; showBetaAccessAlert = true }
        }
    }

    // MARK: - Firestore helpers

    private func normalizedE164Phone(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        if digits.count == 11, digits.first == "1" {
            return "+\(digits)"
        }
        return "+1\(String(digits.suffix(10)))"
    }

    /// Merge-writes into `riders/{uid}` so the document exists early and stays current.
    private func upsertRider(_ fields: [String: Any], onSaved: @escaping () -> Void = {}) {
        guard let uid = RydrWorkspace.auth.currentUser?.uid else { return }
        RydrWorkspace.firestore
            .collection("riders").document(uid)
            .setData(fields, merge: true) { err in
                if let err = err { betaAccessError = err.localizedDescription; showBetaAccessAlert = true }
                else { onSaved() }
            }
    }

    private func betaInviteApproved(phoneE164: String, completion: @escaping (Bool) -> Void) {
        RydrWorkspace.firestore
            .collection("betaInvites")
            .document("rider")
            .collection("phones")
            .document(phoneE164)
            .getDocument { snapshot, _ in
                completion(snapshot?.data()?["status"] as? String == "approved")
            }
    }

    @MainActor
    private func createOrLinkFirebaseAccount() {
        guard !isCreatingAccount else { return }
        isCreatingAccount = true
        accountSubmissionError = ""
        email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            defer { isCreatingAccount = false }
            do {
                let user: User
                if let current = RydrWorkspace.auth.currentUser {
                    if current.email?.caseInsensitiveCompare(email) == .orderedSame {
                        user = current
                    } else {
                        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
                        user = try await current.link(with: credential).user
                    }
                } else {
                    user = try await RydrWorkspace.auth.createUser(withEmail: email, password: password).user
                }
                finishAuthAccountSetup(for: user)
            } catch {
                switch (error as NSError).code {
                case AuthErrorCode.emailAlreadyInUse.rawValue, AuthErrorCode.credentialAlreadyInUse.rawValue:
                    accountSubmissionError = "That email is already linked to an account. Log in with that account, or use a different email for this phone number."
                case AuthErrorCode.providerAlreadyLinked.rawValue:
                    accountSubmissionError = "This phone account already has a different email. Log in with that email to continue."
                case AuthErrorCode.invalidEmail.rawValue:
                    accountSubmissionError = "Enter a valid email address, then try again."
                case AuthErrorCode.weakPassword.rawValue:
                    accountSubmissionError = "Choose a stronger password that meets all the requirements below."
                case AuthErrorCode.networkError.rawValue:
                    accountSubmissionError = "We couldn’t connect. Check your internet connection and try again."
                case AuthErrorCode.tooManyRequests.rawValue:
                    accountSubmissionError = "Too many attempts. Please wait a few minutes and try again."
                default:
                    accountSubmissionError = "We couldn’t create your account. Please try again. If this continues, contact Rydr support."
                }
            }
        }
    }

    private func finishAuthAccountSetup(for user: User) {
        let e164Phone = normalizedE164Phone(phoneNumber)
        upsertRider([
            "email": email,
            "firstName": firstName,
            "lastName": lastName,
            "preferredName": preferredName
        ])
        writePhoneIndex(phoneE164: e164Phone, uid: user.uid)

        provisionStripeCustomerIfNeeded()

        Task { @MainActor in
            path.append(.addressEntry)
        }
    }

    private func finishSocialAuthAccountSetup(profile: RiderSocialAuthProfile) {
        guard let user = RydrWorkspace.auth.currentUser else { return }
        let resolvedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? profile.firstName : firstName
        let resolvedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? profile.lastName : lastName
        let resolvedEmail = profile.email.isEmpty ? user.email ?? email : profile.email
        let e164Phone = normalizedE164Phone(phoneNumber)

        firstName = resolvedFirstName
        lastName = resolvedLastName
        email = resolvedEmail

        upsertRider([
            "email": resolvedEmail,
            "firstName": resolvedFirstName,
            "lastName": resolvedLastName,
            "preferredName": preferredName,
            "authProvider": profile.providerID,
            "socialAuthLinked": true,
            "socialAuthLinkedAt": FieldValue.serverTimestamp()
        ])
        writePhoneIndex(phoneE164: e164Phone, uid: user.uid)
        provisionStripeCustomerIfNeeded()

        Task { @MainActor in
            path.append(.addressEntry)
        }
    }

    /// Final save (still uses merge so it’s idempotent), then load profile & go to app.
    private func saveUserToFirestore() {
        guard RydrWorkspace.auth.currentUser != nil else {
            print("❌ No authenticated user to save.")
            return
        }
        Task { @MainActor in
            do {
                try await RiderBackendIdentityService.finalizeRiderProfile(
                    firstName: firstName,
                    lastName: lastName,
                    preferredName: preferredName,
                    email: email,
                    street: streetAddress,
                    line2: addressLine2,
                    city: city,
                    state: state,
                    zip: zip,
                    agreedToTerms: agreedToTerms,
                    betaWaiverAccepted: betaWaiverAccepted,
                    verificationRequested: verificationRequested
                )
                session.login(
                    name: preferredName.isEmpty ? "\(firstName) \(lastName)" : preferredName,
                    email: email,
                    startingTab: .ride,
                    access: .rider
                )
                if let onCompleted { onCompleted() }
                else { showMainApp = true }
            } catch {
                betaAccessError = error.localizedDescription
                showBetaAccessAlert = true
            }
        }
    }

    private func loadExistingProfile() {
        guard let uid = RydrWorkspace.auth.currentUser?.uid else {
            hasLoadedExistingProfile = true
            return
        }

        RydrWorkspace.firestore.collection("riders").document(uid).getDocument { snap, _ in
            let data = snap?.data() ?? [:]
            let address = data["address"] as? [String: Any] ?? [:]

            Task { @MainActor in
                firstName = data["firstName"] as? String ?? ""
                lastName = data["lastName"] as? String ?? ""
                preferredName = data["preferredName"] as? String ?? ""
                email = data["email"] as? String ?? RydrWorkspace.auth.currentUser?.email ?? ""
                phoneNumber = data["phoneNumber"] as? String ?? ""
                streetAddress = address["street"] as? String ?? ""
                addressLine2 = address["line2"] as? String ?? ""
                city = address["city"] as? String ?? ""
                state = address["state"] as? String ?? ""
                zip = address["zip"] as? String ?? ""
                hasLoadedExistingProfile = true
            }
        }
    }

    private func writePhoneIndex(phoneE164: String, uid: String) {
        Task {
            do { try await RiderBackendIdentityService.sync(beginOnboarding: true) }
            catch { print("⚠️ backend identity sync failed: \(error.localizedDescription)") }
        }
    }

    // MARK: - Stripe customer provisioning (as requested)

    func provisionStripeCustomerIfNeeded(
        backendBase: URL = RydrStripeBackendConfig.baseURL
    ) {
        guard let user = RydrWorkspace.auth.currentUser else { return }
        user.getIDTokenForcingRefresh(true) { token, _ in
            var req = RydrWorkspace.urlRequest(url: backendBase.appendingPathComponent("create-customer"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

            let body: [String: Any] = [
                "name": user.displayName ?? "Rydr User"
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

            URLSession.shared.dataTask(with: req) { data, _, _ in
                guard
                    let data = data,
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let cid = json["customerId"] as? String
                else { print("❌ Failed to provision Stripe customer"); return }

                print("✅ Stripe customer provisioned by backend:", cid)
            }.resume()
        }
    }
}
