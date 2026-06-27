//
//  DriverSignupCoordinator.swift
//  Rydr Driver
//
//  Top-level driver signup flow coordinator. Owns shared step state and the
//  NavigationStack path; each step's UI now lives in its own file under
//  Features/SignUp/ (see the "Step screens" note below) so this file stays
//  focused on navigation, Firebase/Firestore writes, and account linking.
//

import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Coordinator

enum DriverSignupStep: Hashable {
    case phoneCode
    case nameDOB
    case emailPassword
    case address
    case license
    case vehicle
    case identity
    case backgroundCheck
    case payouts
    case done
}

struct DriverSignupCoordinator: View {
    @EnvironmentObject var session: DriverSessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var path: [DriverSignupStep] = []

    // Shared state
    @State private var phoneNumber: String = ""
    @State private var pendingVerificationID: String = ""
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var dob: Date = Calendar.current.date(byAdding: .year, value: -26, to: Date()) ?? Date()

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""

    @State private var street: String = ""
    @State private var addressLine2: String = ""
    @State private var city: String = ""
    @State private var state: String = "GA"
    @State private var zip: String = ""

    // License
    @State private var licenseNumber: String = ""
    @State private var licenseState: String = "GA"
    @State private var licenseFront: PhotosPickerItem?
    @State private var licenseBack: PhotosPickerItem?

    // Vehicle
    @State private var vehicleMake: String = ""
    @State private var vehicleModel: String = ""
    @State private var vehicleYear: String = ""
    @State private var vehicleFuelType: String = DriverVehicleFuelType.gas.rawValue
    @State private var plateNumber: String = ""
    @State private var registrationDoc: PhotosPickerItem?
    @State private var insuranceCard: PhotosPickerItem?

    // Progress flags
    @State private var identityVerified = false
    @State private var backgroundCheckAcknowledged = false
    @State private var connectOnboarded = false

    // Errors
    @State private var errorText: String = ""
    @State private var existingAccountAlert = false

    var body: some View {
        NavigationStack(path: $path) {
            DriverPhoneEntryView(
                onCodeSent: { verificationID, e164Phone in
                    phoneNumber = e164Phone
                    pendingVerificationID = verificationID
                    path.append(.phoneCode)
                }
            )
            .navigationDestination(for: DriverSignupStep.self) { step in
                switch step {
                case .phoneCode:
                    DriverPhoneCodeEntryView(
                        verificationID: $pendingVerificationID,
                        phoneNumber: phoneNumber,
                        onEditNumber: {
                            if !path.isEmpty { path.removeLast() }
                        },
                        onResendCode: {
                            PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil) { id, error in
                                Task { @MainActor in
                                    guard let id, !id.isEmpty, error == nil else { return }
                                    pendingVerificationID = id
                                }
                            }
                        },
                        onVerify: { credential, completion in
                            // Signing in here establishes this phone number as the Firebase
                            // Auth identity for the account. Every later phone-based driver
                            // login resolves to this same uid, and the email/password step
                            // that follows links onto this account instead of creating a
                            // second, disconnected one.
                            Auth.auth().signIn(with: credential) { result, error in
                                Task { @MainActor in
                                    if let error {
                                        completion(.failure(error))
                                        return
                                    }
                                    guard let user = result?.user else {
                                        completion(.failure(NSError(domain: "DriverSignup", code: -1, userInfo: [NSLocalizedDescriptionKey: "Verification failed: missing user."])))
                                        return
                                    }
                                    completion(.success(user))

                                    // Check for an existing driver by phone before allowing
                                    // signup to proceed.
                                    let verifiedE164 = phoneNumber
                                    driverExists(phoneE164: verifiedE164) { exists in
                                        if exists {
                                            try? Auth.auth().signOut()
                                            errorText = "An account with this phone number already exists. Please sign in."
                                            existingAccountAlert = true
                                        } else {
                                            path.append(.nameDOB)
                                        }
                                    }
                                }
                            }
                        }
                    )

                case .nameDOB:
                    NameDOBView(firstName: $firstName, lastName: $lastName, dob: $dob) {
                        upsertDriver(["firstName": firstName, "lastName": lastName, "dob": Timestamp(date: dob)])
                        path.append(.emailPassword)
                    }

                case .emailPassword:
                    EmailAndPasswordView(
                        email: $email,
                        password: $password,
                        confirmPassword: $confirmPassword
                    ) {
                        completeEmailPasswordStep()
                    }

                case .address:
                    AddressInfoView(
                        street: $street,
                        addressLine2: $addressLine2,
                        city: $city,
                        state: $state,
                        zipCode: $zip
                    ) {
                        upsertDriver(["address": [
                            "street": street,
                            "line2": addressLine2,
                            "city": city,
                            "state": state,
                            "zip": zip
                        ]])
                        path.append(.license)
                    }

                case .license:
                    DriverLicenseView(
                        licenseNumber: $licenseNumber,
                        licenseState: $licenseState,
                        front: $licenseFront,
                        back: $licenseBack
                    ) {
                        upsertDriver([
                            "license": [
                                "number": licenseNumber,
                                "state": licenseState
                            ]
                        ])
                        path.append(.vehicle)
                    }

                case .vehicle:
                    VehicleInfoView(
                        make: $vehicleMake,
                        model: $vehicleModel,
                        year: $vehicleYear,
                        fuelType: $vehicleFuelType,
                        plate: $plateNumber,
                        registrationDoc: $registrationDoc,
                        insuranceCard: $insuranceCard
                    ) {
                        let eligibility = DriverVehicleEligibility.evaluate(
                            make: vehicleMake,
                            model: vehicleModel,
                            year: vehicleYear,
                            fuelType: vehicleFuelType
                        )
                        let eligibleRideTypes = eligibility.eligibleRideTypes
                        var tierRates: [String: Any] = [:]
                        for rideType in eligibleRideTypes {
                            let key = RydrRideTierCatalog.canonicalRideType(rideType)
                            tierRates[key] = DriverRateSetting.defaultValue(for: rideType).dictionary(for: rideType)
                        }
                        upsertDriver([
                            "vehicle": [
                                "make": vehicleMake,
                                "model": vehicleModel,
                                "year": vehicleYear,
                                "fuelType": vehicleFuelType,
                                "class": eligibility.vehicleClass,
                                "plate": plateNumber
                            ],
                            "vehicleEligibility": [
                                "rideTypes": eligibleRideTypes,
                                "requiresManualReview": eligibility.requiresManualReview,
                                "vehicleClass": eligibility.vehicleClass,
                                "evaluatedAt": FieldValue.serverTimestamp()
                            ],
                            "qualifiedRideTypes": eligibleRideTypes,
                            "supportedRideTypes": eligibleRideTypes,
                            "selectedRideTypes": eligibleRideTypes,
                            "rideTypes": eligibleRideTypes,
                            "tierRates": tierRates
                        ])
                        path.append(.identity)
                    }

                case .identity:
                    IdentityVerificationView(isVerified: $identityVerified) {
                        if identityVerified { path.append(.backgroundCheck) }
                    }

                case .backgroundCheck:
                    BackgroundCheckView(
                        firstName: firstName,
                        lastName: lastName,
                        email: email,
                        phone: phoneNumber,
                        dob: dob,
                        licenseNumber: licenseNumber,
                        licenseState: licenseState,
                        acknowledged: $backgroundCheckAcknowledged
                    ) {
                        if backgroundCheckAcknowledged {
                            recordDriverApprovalRequest(type: "backgroundCheck")
                            session.canGoOnline = false
                            path.append(.payouts)
                        }
                    }

                case .payouts:
                    PayoutsSetupView(
                        uid: Auth.auth().currentUser?.uid ?? "",
                        email: email,
                        firstName: firstName,
                        lastName: lastName,
                        phone: phoneNumber,
                        dob: dob,
                        street: street,
                        addressLine2: addressLine2,
                        city: city,
                        state: state,
                        zip: zip,
                        connectOnboarded: $connectOnboarded
                    ) { accountId in
                        if let accountId {
                            upsertDriver(["stripeAccountId": accountId])
                        }
                        if connectOnboarded { path.append(.done) }
                    }

                case .done:
                    SignupCompleteView(onFinish: {
                        // Mark the session as logged in and keep Go Online disabled until the check passes
                        session.login(name: "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces), email: email)
                        session.canGoOnline = false
                        dismiss()
                    })
                }
            }
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Close") { dismiss() } } }
            .alert("Account already exists", isPresented: $existingAccountAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text(errorText)
            }
        }
    }

    // MARK: - Email/password step

    /// Handles the email/password step by linking the email/password credential onto
    /// the phone-authenticated account created in the previous step (rather than
    /// creating a separate account), so phone login and email login resolve to the
    /// same Firebase Auth uid. Also handles the case where the driver tapped
    /// "Continue" once already, navigated back, and returned here unchanged --
    /// re-linking the same credential would error, so we detect that and just
    /// continue instead of erroring out.
    private func completeEmailPasswordStep() {
        // The phone step already signed this driver into Firebase via phone auth, so
        // Auth.auth().currentUser is the phone-authenticated account. We LINK the
        // email/password credential onto that same account (rather than calling
        // createUser, which would mint a second, unrelated UID) so that phone login
        // and email login both resolve to the same driver going forward.
        guard let phoneUser = Auth.auth().currentUser else {
            errorText = "Your phone verification session expired. Please restart signup."
            existingAccountAlert = true
            return
        }

        if phoneUser.email == email {
            // Driver tapped Continue once already, navigated back, and returned here
            // without changing anything -- already linked, just continue.
            finishEmailPasswordStep(uid: phoneUser.uid)
            return
        }

        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        phoneUser.link(with: credential) { result, error in
            if let error = error as NSError? {
                if let code = AuthErrorCode(rawValue: error.code) {
                    switch code {
                    case .emailAlreadyInUse, .credentialAlreadyInUse:
                        errorText = "That email is already in use by another account. Please sign in instead or use a different email."
                        existingAccountAlert = true
                        return
                    case .providerAlreadyLinked:
                        // This phone account already has an email/password provider attached.
                        finishEmailPasswordStep(uid: phoneUser.uid)
                        return
                    default:
                        break
                    }
                }
                print("❌ link email credential: \(error.localizedDescription)")
                errorText = error.localizedDescription
                return
            }
            guard let uid = result?.user.uid else { return }
            finishEmailPasswordStep(uid: uid)
        }
    }

    private func finishEmailPasswordStep(uid: String) {
        upsertDriver([
            "uid": uid,
            "email": email,
            "firstName": firstName,
            "lastName": lastName,
            "phoneNumber": phoneNumber,
            "phoneE164": phoneNumber,
            "createdAt": FieldValue.serverTimestamp()
        ])
        writePhoneIndex(phoneE164: phoneNumber, uid: uid)
        path.append(.address)
    }

    // MARK: - Firestore helper
    private func upsertDriver(_ fields: [String: Any]) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("drivers").document(uid).setData(fields, merge: true) { err in
            if let err = err { errorText = err.localizedDescription }
        }
    }

    private func driverExists(phoneE164: String, completion: @escaping (Bool) -> Void) {
        // Pre-auth (no Firebase Auth user exists yet at this step), so we can't run any
        // query against /drivers — that collection disallows `list` entirely to prevent
        // phone-number enumeration. Instead check the dedicated phone->uid pointer doc,
        // which is readable by anyone via `get` (it exposes nothing but a uid).
        Firestore.firestore()
            .collection("driverPhoneIndex")
            .document(phoneE164)
            .getDocument { snapshot, _ in
                completion(snapshot?.exists == true)
            }
    }

    private func writePhoneIndex(phoneE164: String, uid: String) {
        Firestore.firestore()
            .collection("driverPhoneIndex")
            .document(phoneE164)
            .setData([
                "uid": uid,
                "createdAt": FieldValue.serverTimestamp()
            ]) { err in
                if let err = err {
                    print("⚠️ writePhoneIndex failed: \(err.localizedDescription)")
                }
            }
    }

    private func recordDriverApprovalRequest(type: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("driverApprovalRequests").document(uid).setData([
            "uid": uid,
            "requestType": type,
            "source": "driver-ios-signup",
            "requested": true,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true) { err in
            if let err = err { errorText = err.localizedDescription }
        }
    }
}

// MARK: - Step screens
//
// Every step screen now lives in its own file under Features/SignUp/, each
// with a default `currentStep`/`totalSteps` matching its position below, and
// each rendering the shared DriverOnboardingStepIndicator "flow bubble"
// tracker:
//   1. NameDOBView.swift            — name + date of birth
//   2. EmailAndPasswordView.swift   — login credentials
//   3. AddressInfoView.swift        — home address
//   4. DriverLicenseView.swift      — license capture
//   5. VehicleInfoView.swift        — vehicle & documents
//   6. IdentityVerificationView.swift — Stripe Identity launch screen
//   7. BackgroundCheckView.swift    — Checkr launch screen
//   8. PayoutsSetupView.swift       — Stripe Connect payouts launch screen
//
// Shared helpers (UploadBox, SafariView, SignupInfoCard, SignupContinueButton)
// live in SignupSharedUI.swift, and the final SignupCompleteView.swift caps
// off the flow.
