//
//  DriverSignupStep.swift
//  Rydr Driver
//
//  Created by Khris Nunnally on 9/1/25.
//

//
//  DriverSignupCoordinator.swift
//  Rydr Driver
//
//  Driver signup flow with verification steps, Checkr invite, and Stripe Connect onboarding.
//  This file is self-contained with lightweight placeholder views and network stubs you can
//  wire to your Render backend. It reuses your existing EmailAndPasswordView and AddressInfoView
//  types if they are in this target/module; otherwise, replace with equivalents.
//
//  Created by ChatGPT on 2025-09-01.
//

//
//  DriverSignupCoordinator.swift
//  Rydr Driver
//
//  Driver signup flow with verification steps, Checkr invite, and Stripe Connect onboarding.
//  This file is self-contained with lightweight placeholder views and network stubs you can
//  wire to your Render backend. It reuses your existing EmailAndPasswordView and AddressInfoView
//  types if they are in this target/module; otherwise, replace with equivalents.
//
//  
//

import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import SafariServices

// MARK: - Coordinator

enum DriverSignupStep: Hashable {
    case phone
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
    @State private var backgroundCheckStarted = false
    @State private var connectOnboarded = false

    // Errors
    @State private var errorText: String = ""
    @State private var existingAccountAlert = false

    var body: some View {
        NavigationStack(path: $path) {
            PhoneVerificationView_Driver { verifiedE164 in
                phoneNumber = verifiedE164
                // Check for an existing driver by phone before allowing signup to proceed
                driverExists(phoneE164: verifiedE164) { exists in
                    if exists {
                        errorText = "An account with this phone number already exists. Please sign in."
                        existingAccountAlert = true
                    } else {
                        upsertDriver([
                            "phoneNumber": verifiedE164,
                            "phoneE164": verifiedE164,
                            "createdAt": FieldValue.serverTimestamp()
                        ])
                        path.append(.nameDOB)
                    }
                }
            }
            .navigationDestination(for: DriverSignupStep.self) { step in
                switch step {
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
                        Auth.auth().createUser(withEmail: email, password: password) { result, error in
                            if let error = error {
                                print("❌ createUser: \(error.localizedDescription)")
                                return
                            }
                            upsertDriver([
                                "uid": Auth.auth().currentUser?.uid ?? "",
                                "email": email,
                                "firstName": firstName,
                                "lastName": lastName
                            ])
                            path.append(.address)
                        }
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
                        started: $backgroundCheckStarted
                    ) {
                        if backgroundCheckStarted {
                            upsertDriver(["backgroundCheckStatus": "pending"]) // backend will later set to "passed" or "failed"
                            session.canGoOnline = false
                            path.append(.payouts)
                        }
                    }

                case .payouts:
                    PayoutsSetupView(connectOnboarded: $connectOnboarded) {
                        if connectOnboarded { path.append(.done) }
                    }

                case .done:
                    SignupCompleteView(onFinish: {
                        // Mark the session as logged in and keep Go Online disabled until the check passes
                        session.login(name: "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces), email: email)
                        session.canGoOnline = false
                        dismiss()
                    })
                case .phone:
                    EmptyView()
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

    // MARK: - Firestore helper
    private func upsertDriver(_ fields: [String: Any]) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("drivers").document(uid).setData(fields, merge: true) { err in
            if let err = err { errorText = err.localizedDescription }
        }
    }

    private func driverExists(phoneE164: String, completion: @escaping (Bool) -> Void) {
        let db = Firestore.firestore()
        let drivers = db.collection("drivers")

        // Try a direct document lookup (in case you keyed by phone)
        drivers.document(phoneE164).getDocument { snapshot, _ in
            if let snapshot = snapshot, snapshot.exists {
                completion(true)
                return
            }

            // Query by standardized E.164 field first
            drivers.whereField("phoneE164", isEqualTo: phoneE164)
                .limit(to: 1)
                .getDocuments { querySnapshot, _ in
                    if let querySnapshot = querySnapshot, !querySnapshot.documents.isEmpty {
                        completion(true)
                        return
                    }

                    // Fallback for legacy data that used `phoneNumber`
                    drivers.whereField("phoneNumber", isEqualTo: phoneE164)
                        .limit(to: 1)
                        .getDocuments { qs2, _ in
                            if let qs2 = qs2, !qs2.documents.isEmpty {
                                completion(true)
                            } else {
                                completion(false)
                            }
                        }
                }
        }
    }
}

// MARK: - Step 1: Phone (placeholder using simple OTP feel)
struct PhoneVerificationView_Driver: View {
    var onVerified: (String) -> Void
    @State private var phone: String = ""
    @State private var sent = false
    @State private var code: String = ""
    @State private var error: String = ""

    // Phone helpers
    private func digitsOnly(_ s: String) -> String { s.filter { "0123456789".contains($0) } }
    private var sanitizedDigits: String { digitsOnly(phone) }
    private var isPhoneValid: Bool { sanitizedDigits.count >= 10 }
    private var e164Phone: String { "+1" + sanitizedDigits }

    var body: some View {
        VStack(spacing: 16) {
            Text("Verify your phone").font(.title).bold()
            HStack(spacing: 8) {
                Text("+1")
                    .fontWeight(.semibold)
                    .foregroundStyle(Styles.rydrGradient)
                    .padding(.leading, 12)
                    .accessibilityHidden(true)

                Divider()
                    .frame(height: 20)

                TextField("Phone number", text: $phone)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Styles.rydrGradient, lineWidth: 2)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Phone Number Field")
            .onChange(of: phone, initial: false) { _, newValue in
                let digits = digitsOnly(newValue)
                if digits != newValue { phone = digits }
            }
            if !sent {
                Button("Send Code") { sent = true /* Plug Firebase PhoneAuth here */ }
                    .disabled(!isPhoneValid)
                    .buttonStyle(.borderedProminent).tint(.red)
            } else {
                SecureField("6-digit code", text: $code).textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                Button("Verify") { onVerified(e164Phone) }
                    .buttonStyle(.borderedProminent).tint(.red)
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            Spacer()
        }
        .padding()
    }
}

// MARK: - Step 2: Name + DOB
struct NameDOBView: View {
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var dob: Date
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Your details").font(.title).bold()
            TextField("First name", text: $firstName).textFieldStyle(.roundedBorder)
            TextField("Last name", text: $lastName).textFieldStyle(.roundedBorder)
            DatePicker("Date of birth", selection: $dob, displayedComponents: .date)
                .datePickerStyle(.compact)
            Button("Continue", action: onNext)
                .buttonStyle(.borderedProminent).tint(.red)
            Spacer()
        }.padding()
    }
}

// MARK: - Step 3 already provided by your EmailAndPasswordView (reused)
// MARK: - Step 4 already provided by your AddressInfoView (reused)

// MARK: - Step 5: License capture
struct DriverLicenseView: View {
    @Binding var licenseNumber: String
    @Binding var licenseState: String
    @Binding var front: PhotosPickerItem?
    @Binding var back: PhotosPickerItem?
    var onNext: () -> Void

    private let states = ["AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID","IL","IN","IA","KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Driver's license").font(.title).bold()
                TextField("License number", text: $licenseNumber).textFieldStyle(.roundedBorder)
                Menu {
                    ForEach(states, id: \.self) { abbr in Button(abbr) { licenseState = abbr } }
                } label: {
                    HStack {
                        Text(licenseState.isEmpty ? "State" : licenseState)
                        Spacer(); Image(systemName: "chevron.up.chevron.down").font(.footnote)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.3)))
                }

                PhotosPicker(selection: $front, matching: .images) { UploadBox(label: "Upload license (front)") }
                PhotosPicker(selection: $back, matching: .images) { UploadBox(label: "Upload license (back)") }

                Button("Continue", action: onNext)
                    .buttonStyle(.borderedProminent).tint(.red)
            }
            .padding()
        }
    }
}

// MARK: - Step 6: Vehicle & docs
struct VehicleInfoView: View {
    @Binding var make: String
    @Binding var model: String
    @Binding var year: String
    @Binding var fuelType: String
    @Binding var plate: String
    @Binding var registrationDoc: PhotosPickerItem?
    @Binding var insuranceCard: PhotosPickerItem?
    var onNext: () -> Void

    private var eligibility: DriverVehicleEligibility {
        DriverVehicleEligibility.evaluate(make: make, model: model, year: year, fuelType: fuelType)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Vehicle & documents").font(.title).bold()
                HStack { TextField("Make", text: $make).textFieldStyle(.roundedBorder) }
                HStack { TextField("Model", text: $model).textFieldStyle(.roundedBorder) }
                HStack { TextField("Year", text: $year).keyboardType(.numberPad).textFieldStyle(.roundedBorder) }
                Picker("Fuel type", selection: $fuelType) {
                    ForEach(DriverVehicleFuelType.allCases) { type in
                        Text(type.rawValue).tag(type.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                HStack { TextField("Plate number", text: $plate).textFieldStyle(.roundedBorder) }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Eligible ride types")
                        .font(.headline)
                    if eligibility.eligibleRideTypes.isEmpty {
                        Text("Manual review required before this vehicle can receive standard Rydr requests.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            ForEach(eligibility.eligibleRideTypes, id: \.self) { rideType in
                                Text(rideType)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.red.opacity(0.14)))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

                PhotosPicker(selection: $registrationDoc, matching: .images) { UploadBox(label: "Upload registration") }
                PhotosPicker(selection: $insuranceCard, matching: .images) { UploadBox(label: "Upload insurance card") }

                Button("Continue", action: onNext)
                    .buttonStyle(.borderedProminent).tint(.red)
            }
            .padding()
        }
    }
}

// MARK: - Step 7: Identity (Stripe Identity via hosted link)
struct IdentityVerificationView: View {
    @Binding var isVerified: Bool
    var onNext: () -> Void

    @State private var isPresenting = false
    @State private var url: URL?
    @State private var message: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Verify identity").font(.title).bold()
            Text("You will be redirected to a secure verification flow to scan your ID and selfie.")
                .font(.footnote).foregroundStyle(.secondary)

            Button("Start Identity Verification") {
                // TODO: Call backend to create Stripe Identity verification session and return hosted link URL
                #if DEBUG
                url = URL(string: "https://verify.stripe.com/demo")
                isPresenting = true
                #else
                message = "Stripe Identity is waiting on backend configuration. For beta testing, an admin can mark this account as manually reviewed."
                #endif
            }
            .buttonStyle(.borderedProminent).tint(.red)
            .sheet(isPresented: $isPresenting) {
                if let url { SafariView(url: url) }
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Toggle("I completed verification", isOn: $isVerified)
                .toggleStyle(SwitchToggleStyle(tint: .red))

            Button("Continue") { onNext() }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(!isVerified)
            Spacer()
        }.padding()
    }
}

// MARK: - Step 8: Background check (Checkr hosted Apply)
struct BackgroundCheckView: View {
    let firstName: String
    let lastName: String
    let email: String
    let phone: String
    let dob: Date
    let licenseNumber: String
    let licenseState: String

    @Binding var started: Bool
    var onNext: () -> Void

    @State private var showConsent = false
    @State private var presentingApply = false
    @State private var applyURL: URL?
    @State private var message: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Background check").font(.title).bold()
            Text("We use a secure partner to run a criminal and driving record screen. You’ll review disclosures & provide additional info on their site.")
                .font(.footnote).foregroundStyle(.secondary)

            Toggle("I consent to a background check (FCRA)", isOn: $showConsent)
                .toggleStyle(SwitchToggleStyle(tint: .red))

            Button("Start Background Check") {
                guard showConsent else { return }
                // TODO: Call backend to create Checkr Candidate + Invitation, return hosted Apply URL.
                #if DEBUG
                applyURL = URL(string: "https://apply.checkr.com/apply/demo")
                presentingApply = true
                #else
                message = "Background checks are manually bypassed only for approved beta testers. No production Checkr invitation was created."
                #endif
                started = true
            }
            .buttonStyle(.borderedProminent).tint(.red)
            .disabled(!showConsent)
            .sheet(isPresented: $presentingApply) {
                if let url = applyURL { SafariView(url: url) }
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Continue") { onNext() }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(!started)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Step 9: Payouts (Stripe Connect Express onboarding)
struct PayoutsSetupView: View {
    @Binding var connectOnboarded: Bool
    var onNext: () -> Void

    @State private var isPresenting = false
    @State private var onboardingURL: URL?
    @State private var message: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Set up payouts").font(.title).bold()
            Text("Link a bank account for ACH deposits, and optionally add a debit card for Instant Payouts.")
                .font(.footnote).foregroundStyle(.secondary)

            Button("Open Stripe Onboarding") {
                // TODO: Call backend to create or fetch Express account then create Account Link URL
                #if DEBUG
                onboardingURL = URL(string: "https://connect.stripe.com/express/onboarding")
                isPresenting = true
                #else
                message = "Stripe Connect onboarding needs the Stripe backend account-link route configured before live payouts. For beta testing, payouts should remain alpha-only."
                #endif
            }
            .buttonStyle(.borderedProminent).tint(.red)
            .sheet(isPresented: $isPresenting) {
                if let onboardingURL { SafariView(url: onboardingURL) }
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Toggle("I completed payout setup", isOn: $connectOnboarded)
                .toggleStyle(SwitchToggleStyle(tint: .red))

            Button("Finish") { onNext() }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(!connectOnboarded)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Done
struct SignupCompleteView: View {
    var onFinish: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)

            Text("Application submitted")
                .font(.title).bold()

            Text("We’ll notify you when your background check is complete. You can continue exploring the app in the meantime.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button(action: { onFinish?() }) {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.top, 8)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Small UI helpers
struct UploadBox: View {
    var label: String
    var body: some View {
        HStack { Image(systemName: "tray.and.arrow.up"); Text(label); Spacer() }
            .padding()
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.3)))
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
