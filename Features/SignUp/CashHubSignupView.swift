//
//  CashHubSignupView.swift
//  RydrPlayground
//
//  Lightweight account creation for the independent Cash Rydr Hub marketplace.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct CashHubSignupView: View {
    @EnvironmentObject private var session: UserSessionManager

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phoneNumber = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var acceptedTerms = false
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var verificationSession: PhoneVerificationSession?

    private enum PasswordStrength {
        case weak
        case moderate
        case strong

        var label: String {
            switch self {
            case .weak: return "Weak"
            case .moderate: return "Moderate"
            case .strong: return "Strong"
            }
        }

        var color: Color {
            switch self {
            case .weak: return .red
            case .moderate: return .yellow
            case .strong: return .green
            }
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedPhone: String {
        "+1" + phoneNumber.filter(\.isNumber)
    }

    private var passwordRules: [(label: String, isSatisfied: Bool)] {
        [
            ("8 or more characters", password.count >= 8),
            ("1 uppercase letter", password.rangeOfCharacter(from: .uppercaseLetters) != nil),
            ("1 number", password.rangeOfCharacter(from: .decimalDigits) != nil),
            ("1 special character", password.rangeOfCharacter(from: CharacterSet.punctuationCharacters.union(.symbols)) != nil)
        ]
    }

    private var meetsPasswordMinimum: Bool {
        passwordRules.allSatisfy(\.isSatisfied)
    }

    private var passwordStrength: PasswordStrength {
        guard meetsPasswordMinimum else { return .weak }
        return password.count >= 12 ? .strong : .moderate
    }

    private var hasValidEmail: Bool {
        let pattern = "(?:[A-Z0-9a-z._%+-]+)@(?:[A-Z0-9a-z.-]+)\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: normalizedEmail)
    }

    private var missingRequirements: [String] {
        var requirements: [String] = []
        if firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            requirements.append("your first name")
        }
        if lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            requirements.append("your last name")
        }
        if !hasValidEmail {
            requirements.append("a valid email")
        }
        if phoneNumber.filter(\.isNumber).count != 10 {
            requirements.append("a 10-digit phone number")
        }
        if !meetsPasswordMinimum {
            requirements.append("a password meeting every password rule")
        }
        if !acceptedTerms {
            requirements.append("terms acknowledgment")
        }
        return requirements
    }

    private var canContinue: Bool {
        missingRequirements.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Use Cash Rydr Hub")
                    .font(.title.bold())
                    .foregroundStyle(Styles.rydrGradient)
                Text("Create an account to post ride requests and connect directly with independent drivers. No payment card is required.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("All fields below are required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    requiredFieldLabel("First Name")
                    TextField("First name", text: $firstName)
                        .textFieldStyle(.roundedBorder)

                    requiredFieldLabel("Last Name")
                    TextField("Last name", text: $lastName)
                        .textFieldStyle(.roundedBorder)

                    requiredFieldLabel("Email")
                    TextField("Email address", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)

                    requiredFieldLabel("Phone Number")
                    HStack {
                        Text("+1")
                        TextField("Phone number", text: Binding(
                            get: { phoneNumber },
                            set: { phoneNumber = String($0.filter(\.isNumber).prefix(10)) }
                        ))
                        .keyboardType(.numberPad)
                    }
                    .textFieldStyle(.roundedBorder)

                    requiredFieldLabel("Password")
                    HStack {
                        Group {
                            if isPasswordVisible {
                                TextField("Create password", text: $password)
                            } else {
                                SecureField("Create password", text: $password)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye" : "eye.slash")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                password.isEmpty ? Color.secondary.opacity(0.35) : passwordStrength.color,
                                lineWidth: password.isEmpty ? 1 : 2
                            )
                    }

                    if !password.isEmpty {
                        Text("Password strength: \(passwordStrength.label)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(passwordStrength.color)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(passwordRules, id: \.label) { rule in
                            Label(rule.label, systemImage: rule.isSatisfied ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                                .foregroundStyle(rule.isSatisfied ? .green : .secondary)
                        }
                    }
                }

                Label("Add a profile photo and verification badges later to help build trust.", systemImage: "person.crop.circle.badge.plus")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Cash Rydr Hub Terms")
                        .font(.headline)
                    Text("Cash Rydr Hub is a community marketplace. Rydr does not dispatch rides, set prices, process Cash Hub payments, guarantee driver availability, or guarantee user conduct. Users confirm ride details, payment, and safety expectations directly.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle(isOn: $acceptedTerms) {
                        HStack(spacing: 3) {
                            Text("I understand that Cash Rydr Hub is separate from standard Rydr rides.")
                            Text("*")
                                .foregroundStyle(.red)
                        }
                    }
                        .font(.footnote)
                        .tint(.red)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if !canContinue {
                    Text("To continue, enter \(missingRequirements.joined(separator: ", ")).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button(isSaving ? "Creating Account..." : "I Understand and Continue") {
                    createAccount()
                }
                .buttonStyle(GradientButtonStyle())
                .disabled(!canContinue || isSaving)
                .opacity(canContinue && !isSaving ? 1 : 0.55)
            }
            .padding()
        }
        .navigationTitle("Cash Rydr Hub")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $verificationSession) { verificationSession in
            VerificationCodeView(
                verificationID: verificationSession.verificationID,
                phoneNumber: verificationSession.phoneNumber,
                linkToCurrentUser: true,
                onSuccess: { user in
                    self.verificationSession = nil
                    saveCashHubProfile(uid: user.uid)
                },
                onResendCode: {
                    if Auth.auth().currentUser != nil {
                        sendCashHubPhoneVerification()
                    }
                }
            )
        }
    }

    private func requiredFieldLabel(_ label: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
            Text("*")
                .foregroundStyle(.red)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
    }

    private func createAccount() {
        guard canContinue else { return }
        errorMessage = ""
        isSaving = true

        checkContactAvailability { errorMessage in
            if let errorMessage {
                Task { @MainActor in
                    isSaving = false
                    self.errorMessage = errorMessage
                }
                return
            }
            createFirebaseAccount()
        }
    }

    private func checkContactAvailability(completion: @escaping (String?) -> Void) {
        let riders = Firestore.firestore().collection("riders")

        riders.whereField("email", isEqualTo: normalizedEmail).limit(to: 1).getDocuments { snapshot, error in
            if let error {
                completion("Unable to verify email availability: \(error.localizedDescription)")
                return
            }
            if snapshot?.documents.isEmpty == false {
                completion("That email address is already in use.")
                return
            }

            riders.whereField("phoneNumber", isEqualTo: normalizedPhone).limit(to: 1).getDocuments { snapshot, error in
                if let error {
                    completion("Unable to verify phone number availability: \(error.localizedDescription)")
                    return
                }
                if snapshot?.documents.isEmpty == false {
                    completion("That phone number is already in use.")
                    return
                }
                completion(nil)
            }
        }
    }

    private func createFirebaseAccount() {
        Auth.auth().createUser(withEmail: normalizedEmail, password: password) { result, error in
            if let error {
                Task { @MainActor in
                    isSaving = false
                    if (error as NSError).code == AuthErrorCode.emailAlreadyInUse.rawValue {
                        errorMessage = "That email address is already in use."
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
                return
            }
            guard result?.user != nil else {
                Task { @MainActor in
                    isSaving = false
                    errorMessage = "Account creation did not return a user."
                }
                return
            }

            sendCashHubPhoneVerification()
        }
    }

    private func sendCashHubPhoneVerification() {
        PhoneAuthProvider.provider().verifyPhoneNumber(normalizedPhone, uiDelegate: nil) { verificationID, error in
            Task { @MainActor in
                if let error {
                    isSaving = false
                    errorMessage = "Failed to send verification code: \(error.localizedDescription)"
                    return
                }

                guard let verificationID, !verificationID.isEmpty else {
                    isSaving = false
                    errorMessage = "Firebase did not return a verification session. Please resend the code."
                    return
                }

                isSaving = false
                verificationSession = PhoneVerificationSession(
                    verificationID: verificationID,
                    phoneNumber: normalizedPhone
                )
            }
        }
    }

    private func saveCashHubProfile(uid: String) {
        isSaving = true

        let cleanFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = "\(cleanFirstName) \(cleanLastName)"
        let fields: [String: Any] = [
            "uid": uid,
            "firstName": cleanFirstName,
            "lastName": cleanLastName,
            "preferredName": displayName,
            "email": normalizedEmail,
            "phoneNumber": normalizedPhone,
            "cashHubTermsAccepted": true,
            "cashHubTermsAcceptedAt": FieldValue.serverTimestamp(),
            "cashHubRole": CashHubRole.rider.rawValue,
            "hasRydrRiderAccess": false,
            "createdAt": FieldValue.serverTimestamp()
        ]
        Firestore.firestore().collection("riders").document(uid).setData(fields, merge: true) { error in
            Task { @MainActor in
                isSaving = false
                if let error {
                    errorMessage = error.localizedDescription
                    return
                }
                session.login(
                    name: displayName,
                    email: normalizedEmail,
                    startingTab: .cashHub,
                    access: .cashHubOnly
                )
            }
        }
    }
}
