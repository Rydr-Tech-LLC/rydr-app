//
//  CashHubSignupView.swift
//  RydrPlayground
//
//  Lightweight account creation for the independent Cash Rydr Hub marketplace.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import UIKit

struct CashHubSignupView: View {
    @EnvironmentObject private var session: UserSessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phoneNumber = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var isPasswordVisible = false
    @State private var isPasswordConfirmationVisible = false
    @State private var acceptedTerms = false
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var verificationSession: PhoneVerificationSession?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedProfileImageData: Data?
    @State private var currentStep: CashHubSignupStep = .account
    @State private var contentVisible = false

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

    private var passwordsMatch: Bool {
        !password.isEmpty && password == passwordConfirmation
    }

    private var passwordStrength: PasswordStrength {
        guard meetsPasswordMinimum else { return .weak }
        return password.count >= 12 ? .strong : .moderate
    }

    private var hasValidEmail: Bool {
        let pattern = "(?:[A-Z0-9a-z._%+-]+)@(?:[A-Z0-9a-z.-]+)\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: normalizedEmail)
    }

    private var accountStepComplete: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && hasValidEmail
        && phoneNumber.filter(\.isNumber).count == 10
    }

    private var securityStepComplete: Bool {
        meetsPasswordMinimum && passwordsMatch
    }

    private var termsStepComplete: Bool {
        acceptedTerms
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
        if !meetsPasswordMinimum || !passwordsMatch {
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

    private var canAdvanceCurrentStep: Bool {
        switch currentStep {
        case .account:
            return accountStepComplete
        case .security:
            return securityStepComplete
        case .terms:
            return termsStepComplete && !isSaving
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom

            ScrollView(showsIndicators: false) {
                ZStack(alignment: .top) {
                    CashHubSignupBackground()

                    VStack(spacing: 0) {
                        topBar(safeTop: safeTop)

                        VStack(spacing: 22) {
                            heroHeader
                                .opacity(contentVisible ? 1 : 0)
                                .offset(y: contentVisible ? 0 : 16)

                            CashHubStepIndicator(currentStep: currentStep)
                                .opacity(contentVisible ? 1 : 0)
                                .offset(y: contentVisible ? 0 : 18)

                            stepContent
                                .opacity(contentVisible ? 1 : 0)
                                .offset(y: contentVisible ? 0 : 24)

                            if !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(CashHubSignupPalette.red)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            CashHubSignupCTA(
                                title: ctaTitle,
                                subtitle: ctaSubtitle,
                                isEnabled: canAdvanceCurrentStep
                            ) {
                                advanceFlow()
                            }
                            .disabled(!canAdvanceCurrentStep)
                            .opacity(contentVisible ? 1 : 0)

                            HStack(spacing: 9) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Your information is secure and will never be shared.")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(CashHubSignupPalette.slate.opacity(0.78))
                            .padding(.bottom, safeBottom + 20)
                        }
                        .padding(.horizontal, 22)
                        .frame(maxWidth: 620)
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(minHeight: max(proxy.size.height, 920))
            }
            .background(CashHubSignupPalette.background)
            .ignoresSafeArea(edges: [.top, .bottom])
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .environment(\.colorScheme, .light)
        .onAppear {
            withAnimation(.spring(response: 0.78, dampingFraction: 0.86).delay(0.06)) {
                contentVisible = true
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            loadProfileImage(from: newItem)
        }
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

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .account:
            accountStep
        case .security:
            securityStep
        case .terms:
            termsStep
        }
    }

    private var ctaTitle: String {
        switch currentStep {
        case .account, .security:
            return "Continue"
        case .terms:
            return isSaving ? "Creating Account..." : "Create CashRydr Account"
        }
    }

    private var ctaSubtitle: String {
        switch currentStep {
        case .account:
            return "Next: Security"
        case .security:
            return "Next: Terms"
        case .terms:
            return "Verify phone after signup"
        }
    }

    private func advanceFlow() {
        errorMessage = ""
        switch currentStep {
        case .account:
            guard accountStepComplete else {
                errorMessage = "Enter your name, a valid email, and a 10-digit phone number."
                return
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                currentStep = .security
            }
        case .security:
            guard securityStepComplete else {
                errorMessage = "Create a password that meets every rule and confirm it matches."
                return
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                currentStep = .terms
            }
        case .terms:
            createAccount()
        }
    }

    private func topBar(safeTop: CGFloat) -> some View {
        HStack {
            Button {
                if currentStep == .account {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                        currentStep = currentStep.previous
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(CashHubSignupPalette.ink)
                    .frame(width: 54, height: 54)
                    .background(.white.opacity(0.9), in: Circle())
                    .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(CashHubPressStyle(scale: 0.92))
            .accessibilityLabel(currentStep == .account ? "Back" : "Previous Step")

            Spacer()

            HStack(spacing: 9) {
                Circle()
                    .fill(CashHubSignupPalette.redSoft)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CashHubSignupPalette.red)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text("No card required")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(CashHubSignupPalette.ink)
                    Text("100% Free to join")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CashHubSignupPalette.slate)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white.opacity(0.86), in: Capsule())
            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
        }
        .padding(.horizontal, 22)
        .padding(.top, safeTop + 12)
        .padding(.bottom, 4)
    }

    private var heroHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                CashHubLogoRing()
                    .frame(width: 142, height: 142)

                Image("RydrLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 66, height: 66)
            }
            .accessibilityLabel("CashRydr Hub")

            (
                Text("Cash")
                    .foregroundStyle(CashHubSignupPalette.ink)
                + Text("Rydr")
                    .foregroundStyle(CashHubSignupPalette.red)
                + Text(" Hub")
                    .foregroundStyle(CashHubSignupPalette.ink)
            )
            .font(.system(size: 20, weight: .black))

            (
                Text("Join ")
                    .foregroundStyle(CashHubSignupPalette.ink)
                + Text("CashRydr Hub")
                    .foregroundStyle(CashHubSignupPalette.red)
            )
            .font(.system(size: 42, weight: .black))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.72)

            Text("Post ride requests and connect directly with independent drivers.")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(CashHubSignupPalette.slate)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            CashHubSectionTitle(icon: "person.fill", title: "Personal Information")

            HStack(spacing: 14) {
                CashHubTextField(
                    label: "First Name",
                    placeholder: "First name",
                    icon: "person",
                    text: $firstName
                )
                CashHubTextField(
                    label: "Last Name",
                    placeholder: "Last name",
                    icon: "person",
                    text: $lastName
                )
            }

            CashHubTextField(
                label: "Email Address",
                placeholder: "you@example.com",
                icon: "envelope",
                text: $email,
                keyboardType: .emailAddress,
                autocapitalization: .never
            )

            VStack(alignment: .leading, spacing: 8) {
                CashHubRequiredLabel("Phone Number")
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Text("🇺🇸")
                            .font(.system(size: 22))
                        Text("+1")
                            .font(.system(size: 18, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(CashHubSignupPalette.ink)
                    .padding(.horizontal, 12)
                    .frame(width: 116, height: 58)
                    .background(CashHubFieldBackground())

                    HStack(spacing: 10) {
                        Image(systemName: "phone")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CashHubSignupPalette.slate.opacity(0.72))

                        TextField("(201) 555-0123", text: Binding(
                            get: { phoneNumber },
                            set: { phoneNumber = String($0.filter(\.isNumber).prefix(10)) }
                        ))
                        .keyboardType(.numberPad)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(CashHubSignupPalette.ink)
                        .tint(CashHubSignupPalette.red)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 58)
                    .background(CashHubFieldBackground())
                }
            }

            profilePhotoPicker

            CashHubTrustCard()
        }
    }

    private var profilePhotoPicker: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(CashHubSignupPalette.redSoft)
                        .frame(width: 58, height: 58)

                    if let selectedProfileImageData,
                       let image = UIImage(data: selectedProfileImageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 58, height: 58)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(CashHubSignupPalette.red)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedProfileImageData == nil ? "Add a profile photo" : "Profile photo selected")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(CashHubSignupPalette.ink)

                    Text("Optional, but it helps build trust.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CashHubSignupPalette.slate)
                }

                Spacer()

                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(CashHubSignupPalette.red)
            }
            .padding(16)
            .background(CashHubGlassCard(cornerRadius: 22))
        }
        .buttonStyle(CashHubPressStyle())
    }

    private var securityStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            CashHubSectionTitle(icon: "lock.fill", title: "Create Password")

            CashHubPasswordField(
                label: "Password",
                placeholder: "Create a strong password",
                text: $password,
                isVisible: $isPasswordVisible
            )

            CashHubPasswordField(
                label: "Confirm Password",
                placeholder: "Re-enter your password",
                text: $passwordConfirmation,
                isVisible: $isPasswordConfirmationVisible
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(CashHubSignupPalette.slate)
                    Text("Password strength:")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CashHubSignupPalette.ink)
                    Text(passwordStrength.label)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(passwordStrength.color)
                    Spacer()
                }

                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule()
                            .fill(index < satisfiedPasswordRuleCount ? CashHubSignupPalette.red : Color.gray.opacity(0.2))
                            .frame(height: 5)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                    ForEach(passwordRules, id: \.label) { rule in
                        CashHubRulePill(label: rule.label, isSatisfied: rule.isSatisfied)
                    }
                    CashHubRulePill(label: "passwords match", isSatisfied: passwordsMatch)
                }
            }

            CashHubInfoBanner(
                icon: "checkmark.shield.fill",
                title: "Your login is protected.",
                message: "Use a password only you know. We will verify your phone number after signup."
            )
        }
    }

    private var termsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            CashHubSectionTitle(icon: "doc.text.fill", title: "CashRydr Hub Terms")

            VStack(alignment: .leading, spacing: 14) {
                CashHubTermRow(icon: "person.2.fill", title: "Community marketplace", message: "CashRydr Hub lets riders post ride requests and connect directly with independent drivers.")
                CashHubTermRow(icon: "dollarsign.circle.fill", title: "Your price, your agreement", message: "Rydr does not set CashRydr prices, collect Cash Hub payments, or guarantee driver availability.")
                CashHubTermRow(icon: "shield.lefthalf.filled", title: "Confirm before you ride", message: "Users confirm ride details, payment, and safety expectations directly before meeting.")
            }
            .padding(18)
            .background(CashHubGlassCard(cornerRadius: 24))

            Button {
                acceptedTerms.toggle()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: acceptedTerms ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(acceptedTerms ? CashHubSignupPalette.red : CashHubSignupPalette.slate.opacity(0.55))

                    Text("I understand and accept the CashRydr Hub terms.")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(CashHubSignupPalette.ink)
                        .multilineTextAlignment(.leading)

                    Spacer()
                }
                .padding(18)
                .background(CashHubGlassCard(cornerRadius: 22))
            }
            .buttonStyle(CashHubPressStyle())
        }
    }

    private var satisfiedPasswordRuleCount: Int {
        passwordRules.filter(\.isSatisfied).count
    }

    private func loadProfileImage(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    if let image = UIImage(data: data),
                       let jpegData = image.jpegData(compressionQuality: 0.82) {
                        selectedProfileImageData = jpegData
                    } else {
                        selectedProfileImageData = data
                    }
                }
            }
        }
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
        var fields: [String: Any] = [
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

        func writeProfile() {
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

        guard let selectedProfileImageData else {
            writeProfile()
            return
        }

        let photoRef = Storage.storage().reference().child("riders/\(uid)/cashHubProfilePhoto.jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        photoRef.putData(selectedProfileImageData, metadata: metadata) { _, error in
            if let error {
                Task { @MainActor in
                    isSaving = false
                    errorMessage = "Unable to upload profile photo: \(error.localizedDescription)"
                }
                return
            }

            photoRef.downloadURL { url, error in
                if let error {
                    Task { @MainActor in
                        isSaving = false
                        errorMessage = "Unable to finish profile photo upload: \(error.localizedDescription)"
                    }
                    return
                }

                if let url {
                    fields["profilePhotoURL"] = url.absoluteString
                    fields["cashHubProfilePhotoURL"] = url.absoluteString
                }
                writeProfile()
            }
        }
    }
}

private enum CashHubSignupStep: Int, CaseIterable {
    case account = 1
    case security = 2
    case terms = 3

    var title: String {
        switch self {
        case .account: return "Account"
        case .security: return "Security"
        case .terms: return "Terms"
        }
    }

    var previous: CashHubSignupStep {
        switch self {
        case .account: return .account
        case .security: return .account
        case .terms: return .security
        }
    }
}

private enum CashHubSignupPalette {
    static let red = Color(red: 0.96, green: 0.02, blue: 0.19)
    static let redDeep = Color(red: 0.66, green: 0.0, blue: 0.15)
    static let redSoft = Color(red: 1.0, green: 0.89, blue: 0.92)
    static let ink = Color(red: 0.035, green: 0.055, blue: 0.11)
    static let slate = Color(red: 0.42, green: 0.44, blue: 0.52)
    static let background = Color(red: 0.99, green: 0.992, blue: 0.998)

    static let redGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.12, blue: 0.28), red, redDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct CashHubSignupBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.white, Color(red: 0.965, green: 0.97, blue: 0.982), .white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    CashHubSignupPalette.red.opacity(0.12),
                    CashHubSignupPalette.red.opacity(0.04),
                    .clear
                ],
                center: .top,
                startRadius: 28,
                endRadius: 270
            )
            .frame(height: 340)
            .offset(y: 18)
            .blur(radius: 10)

            CashHubSignupSpeedLines()
                .ignoresSafeArea()
        }
    }
}

private struct CashHubSignupSpeedLines: View {
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                ForEach(0..<10, id: \.self) { index in
                    CashHubSignupWave(offset: CGFloat(index) * 13)
                        .trim(from: 0.04, to: 0.96)
                        .stroke(
                            CashHubSignupPalette.red.opacity(0.20 - Double(index) * 0.012),
                            style: StrokeStyle(lineWidth: index == 0 ? 2.2 : 1.0, lineCap: .round)
                        )
                        .frame(width: width * 1.42, height: height * 0.30)
                        .offset(x: drift ? -30 : 18, y: height * 0.14 + CGFloat(index) * 2)
                        .animation(
                            .easeInOut(duration: 3.0 + Double(index) * 0.08).repeatForever(autoreverses: true),
                            value: drift
                        )
                }
            }
            .mask {
                LinearGradient(
                    colors: [.clear, .black, .black.opacity(0.88), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .onAppear { drift = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CashHubSignupWave: Shape {
    let offset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -rect.width * 0.08, y: rect.height * 0.66 + offset * 0.08))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.46 - offset * 0.08),
            control1: CGPoint(x: rect.width * 0.10, y: rect.height * 0.28 + offset * 0.12),
            control2: CGPoint(x: rect.width * 0.24, y: rect.height * 0.74 - offset * 0.1)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 1.08, y: rect.height * 0.18 + offset * 0.04),
            control1: CGPoint(x: rect.width * 0.58, y: rect.height * 0.20 - offset * 0.08),
            control2: CGPoint(x: rect.width * 0.80, y: rect.height * 0.0 + offset * 0.1)
        )
        return path
    }
}

private struct CashHubLogoRing: View {
    @State private var pulse = false
    @State private var rotate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [CashHubSignupPalette.red.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 18,
                        endRadius: 78
                    )
                )
                .scaleEffect(pulse ? 1.03 : 0.95)

            Circle()
                .stroke(
                    CashHubSignupPalette.red.opacity(pulse ? 0.34 : 0.52),
                    style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [1.5, 6.2])
                )
                .padding(4)
                .rotationEffect(.degrees(rotate ? 360 : 0))

            Circle()
                .stroke(
                    CashHubSignupPalette.red.opacity(pulse ? 0.12 : 0.22),
                    style: StrokeStyle(lineWidth: 4.5, lineCap: .round, dash: [0.8, 8.6])
                )
                .padding(12)
                .rotationEffect(.degrees(rotate ? -220 : 0))
        }
        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: pulse)
        .animation(.linear(duration: 18).repeatForever(autoreverses: false), value: rotate)
        .onAppear {
            pulse = true
            rotate = true
        }
        .accessibilityHidden(true)
    }
}

private struct CashHubStepIndicator: View {
    let currentStep: CashHubSignupStep

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(CashHubSignupStep.allCases, id: \.rawValue) { step in
                VStack(spacing: 7) {
                    HStack(spacing: 0) {
                        if step != .account {
                            Rectangle()
                                .fill(lineColor(for: step))
                                .frame(height: 3)
                        }

                        Text("\(step.rawValue)")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(step.rawValue <= currentStep.rawValue ? .white : CashHubSignupPalette.slate)
                            .frame(width: 38, height: 38)
                            .background(step.rawValue <= currentStep.rawValue ? CashHubSignupPalette.red : Color.gray.opacity(0.25), in: Circle())

                        if step != .terms {
                            Rectangle()
                                .fill(step.rawValue < currentStep.rawValue ? CashHubSignupPalette.red : Color.gray.opacity(0.22))
                                .frame(height: 3)
                        }
                    }

                    Text(step.title)
                        .font(.system(size: 13, weight: step == currentStep ? .black : .semibold))
                        .foregroundStyle(step == currentStep ? CashHubSignupPalette.ink : CashHubSignupPalette.slate)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func lineColor(for step: CashHubSignupStep) -> Color {
        step.rawValue <= currentStep.rawValue ? CashHubSignupPalette.red : Color.gray.opacity(0.22)
    }
}

private struct CashHubSectionTitle: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CashHubSignupPalette.redSoft)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(CashHubSignupPalette.red)
                }

            Text(title)
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(CashHubSignupPalette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CashHubRequiredLabel: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
            Text("*")
                .foregroundStyle(CashHubSignupPalette.red)
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(CashHubSignupPalette.ink)
    }
}

private struct CashHubTextField: View {
    let label: String
    let placeholder: String
    let icon: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization? = .words

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CashHubRequiredLabel(label)

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(CashHubSignupPalette.slate.opacity(0.72))

                TextField(placeholder, text: $text)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(CashHubSignupPalette.ink)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .autocorrectionDisabled()
                    .tint(CashHubSignupPalette.red)
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .background(CashHubFieldBackground())
        }
    }
}

private struct CashHubPasswordField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @Binding var isVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CashHubRequiredLabel(label)

            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(CashHubSignupPalette.slate.opacity(0.72))

                Group {
                    if isVisible {
                        TextField(placeholder, text: $text)
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(CashHubSignupPalette.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .tint(CashHubSignupPalette.red)

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye" : "eye.slash")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(CashHubSignupPalette.slate)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isVisible ? "Hide password" : "Show password")
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .background(CashHubFieldBackground())
        }
    }
}

private struct CashHubFieldBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(.white.opacity(0.86))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 12, x: 0, y: 7)
    }
}

private struct CashHubGlassCard: View {
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(0.72))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.92), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 10)
    }
}

private struct CashHubTrustCard: View {
    var body: some View {
        CashHubInfoBanner(
            icon: "checkmark.shield.fill",
            title: "Add a profile photo and verification badges later to build trust in the community.",
            message: nil
        )
    }
}

private struct CashHubInfoBanner: View {
    let icon: String
    let title: String
    let message: String?

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(CashHubSignupPalette.redSoft)
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(CashHubSignupPalette.red)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CashHubSignupPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let message {
                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CashHubSignupPalette.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(CashHubGlassCard(cornerRadius: 22))
    }
}

private struct CashHubRulePill: View {
    let label: String
    let isSatisfied: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isSatisfied ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isSatisfied ? CashHubSignupPalette.red : CashHubSignupPalette.slate.opacity(0.55))

            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CashHubSignupPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(.white.opacity(0.82), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        }
    }
}

private struct CashHubTermRow: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Circle()
                .fill(CashHubSignupPalette.redSoft)
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CashHubSignupPalette.red)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(CashHubSignupPalette.ink)
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CashHubSignupPalette.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CashHubSignupCTA: View {
    let title: String
    let subtitle: String
    let isEnabled: Bool
    let action: () -> Void
    @State private var glow = false
    @State private var streak = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                CashHubButtonStreaks(active: streak)
                    .frame(width: 112)
                    .offset(x: -64)
                    .opacity(isEnabled ? 1 : 0.32)

                HStack(spacing: 14) {
                    Spacer(minLength: 0)

                    VStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Text(subtitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 0)

                    Circle()
                        .fill(.white)
                        .frame(width: 58, height: 58)
                        .overlay {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(CashHubSignupPalette.red)
                        }
                }
                .padding(.leading, 28)
                .padding(.trailing, 12)
                .frame(height: 88)
                .background(CashHubSignupPalette.redGradient, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                }
                .shadow(
                    color: CashHubSignupPalette.red.opacity(isEnabled ? (glow ? 0.4 : 0.24) : 0.08),
                    radius: isEnabled ? (glow ? 28 : 18) : 8,
                    x: 0,
                    y: isEnabled ? (glow ? 18 : 12) : 4
                )
                .saturation(isEnabled ? 1 : 0.45)
                .opacity(isEnabled ? 1 : 0.62)
            }
            .padding(.leading, 24)
        }
        .buttonStyle(CashHubPressStyle())
        .onAppear {
            glow = true
            streak = true
        }
        .animation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true), value: glow)
        .animation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true), value: streak)
    }
}

private struct CashHubButtonStreaks: View {
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, CashHubSignupPalette.red.opacity(0.34), CashHubSignupPalette.red.opacity(0.72)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: CGFloat(100 - index * 8), height: CGFloat(max(3, 8 - index)))
                    .offset(x: active ? CGFloat(index * 5) : CGFloat(-8 - index * 3))
                    .opacity(0.74 - Double(index) * 0.06)
            }
        }
        .blur(radius: 0.35)
    }
}

private struct CashHubPressStyle: ButtonStyle {
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
