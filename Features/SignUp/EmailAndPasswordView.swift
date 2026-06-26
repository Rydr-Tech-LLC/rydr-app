//
//  EmailPasswordView.swift
//  RydrSignupFlow
//

import SwiftUI
import FirebaseAuth
import UIKit

enum SignupPalette {
    static let red = Color(red: 0.96, green: 0.02, blue: 0.19)
    static let coral = Color(red: 1.00, green: 0.28, blue: 0.29)
    static let wine = Color(red: 0.62, green: 0.00, blue: 0.16)
    static let background = Color(red: 0.985, green: 0.988, blue: 0.992)
    static let panel = Color.white
    static let ink = Color(red: 0.035, green: 0.045, blue: 0.075)
    static let muted = Color(red: 0.43, green: 0.45, blue: 0.52)
    static let softLine = Color(red: 0.88, green: 0.89, blue: 0.93)
    static let field = Color.white
    static let success = Color(red: 0.20, green: 0.72, blue: 0.27)

    static let redGradient = LinearGradient(
        colors: [coral, red, wine],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct EmailAndPasswordView: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var confirmPassword: String
    var onNext: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false

    @State private var passwordValidations: [String: Bool] = [
        "1 number": false,
        "1 special character": false,
        "1 uppercase letter": false,
        "At least 8 characters": false
    ]

    private var orderedRules: [(String, Bool)] {
        [
            ("At least 8 characters", passwordValidations["At least 8 characters"] ?? false),
            ("1 uppercase letter", passwordValidations["1 uppercase letter"] ?? false),
            ("1 number", passwordValidations["1 number"] ?? false),
            ("1 special character", passwordValidations["1 special character"] ?? false)
        ]
    }

    private var passedRuleCount: Int {
        orderedRules.filter(\.1).count
    }

    private var passwordStrength: String {
        switch passedRuleCount {
        case 0...1: return "Weak"
        case 2...3: return "Good"
        default: return "Strong"
        }
    }

    private var allValid: Bool {
        passwordValidations.values.allSatisfy { $0 } && !confirmPassword.isEmpty && password == confirmPassword
    }

    var body: some View {
        SignupScreenScaffold(
            activeStep: 0,
            hero: {
                SignupAtlantaHero()
            },
            content: {
                VStack(spacing: 18) {
                    SignupBrandHeader()

                    SignupFormPanel {
                        SignupStepHeader(active: 0)

                        VStack(spacing: 8) {
                            Text("Create Your Account")
                                .font(.system(size: 25, weight: .black, design: .rounded))
                                .foregroundStyle(SignupPalette.ink)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)

                            Text("Let's get started. It takes less than a minute.")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(SignupPalette.muted)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 12) {
                            SignupInputRow(icon: "envelope", placeholder: "Email Address") {
                                TextField("Email Address", text: $email)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }

                            SignupInputRow(icon: "lock", placeholder: "Create Password", trailingIcon: showPassword ? "eye.slash" : "eye") {
                                Group {
                                    if showPassword {
                                        TextField("Create Password", text: $password)
                                    } else {
                                        SecureField("Create Password", text: $password)
                                    }
                                }
                                .textContentType(.newPassword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: password) { _, newValue in
                                    validatePassword(newValue)
                                }
                            } trailingAction: {
                                showPassword.toggle()
                            }

                            PasswordStrengthView(strength: passwordStrength, passedCount: passedRuleCount, rules: orderedRules)

                            SignupInputRow(icon: "lock.rotation", placeholder: "Confirm Password", trailingIcon: showConfirmPassword ? "eye.slash" : "eye") {
                                Group {
                                    if showConfirmPassword {
                                        TextField("Confirm Password", text: $confirmPassword)
                                    } else {
                                        SecureField("Confirm Password", text: $confirmPassword)
                                    }
                                }
                                .textContentType(.newPassword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            } trailingAction: {
                                showConfirmPassword.toggle()
                            }
                        }
                        .padding(.top, 4)

                        if !confirmPassword.isEmpty && password != confirmPassword {
                            Text("Passwords do not match.")
                                .foregroundStyle(SignupPalette.red)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button("Continue") {
                            onNext()
                        }
                        .buttonStyle(SignupPrimaryButtonStyle())
                        .disabled(!allValid)
                        .opacity(allValid ? 1 : 0.56)
                        .padding(.top, 2)

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundStyle(SignupPalette.red)
                                .font(.caption.weight(.bold))
                        }

                        Text("Already have an account? Log in")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(SignupPalette.muted)
                            .padding(.top, 2)
                    }
                }
            },
            onBack: { dismiss() }
        )
    }

    private func validatePassword(_ text: String) {
        passwordValidations["At least 8 characters"] = text.count >= 8
        passwordValidations["1 uppercase letter"] = text.rangeOfCharacter(from: .uppercaseLetters) != nil
        passwordValidations["1 number"] = text.rangeOfCharacter(from: .decimalDigits) != nil
        passwordValidations["1 special character"] = text.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+{}|:<>?-=[];,./")) != nil
    }
}

struct SignupScreenScaffold<Hero: View, Content: View>: View {
    let activeStep: Int
    @ViewBuilder var hero: Hero
    @ViewBuilder var content: Content
    let onBack: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            SignupPalette.background.ignoresSafeArea()
            hero
                .frame(height: 330)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
                .accessibilityHidden(true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    SignupBackButton(action: onBack)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    content
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: 430)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .hideKeyboardOnTap()
    }
}

struct SignupBrandHeader: View {
    var body: some View {
        VStack(spacing: 7) {
            Image("RydrLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 148, height: 74)
                .shadow(color: SignupPalette.red.opacity(0.16), radius: 14, x: 0, y: 8)
                .accessibilityLabel("Rydr")

            Text("RIDE DIFFERENT")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(5)
                .foregroundStyle(SignupPalette.ink.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.top, 12)
        .padding(.bottom, 118)
    }
}

struct SignupFormPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 18) {
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background(SignupPalette.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.92), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 24, x: 0, y: 18)
    }
}

struct SignupStepHeader: View {
    let active: Int

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                ForEach(0..<4, id: \.self) { index in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(index == active ? SignupPalette.red : Color.white)
                            .frame(width: index == active ? 19 : 15, height: index == active ? 19 : 15)
                            .overlay {
                                Circle()
                                    .stroke(index == active ? SignupPalette.red.opacity(0.20) : SignupPalette.softLine, lineWidth: 3)
                            }
                            .shadow(color: index == active ? SignupPalette.red.opacity(0.26) : .clear, radius: 8, x: 0, y: 4)
                        if index < 3 {
                            Capsule()
                                .fill(index < active ? SignupPalette.red : SignupPalette.softLine)
                                .frame(width: 34, height: 3)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            Text("STEP \(active + 1) OF 4")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(SignupPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

struct SignupProgressDots: View {
    let active: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index == active ? SignupPalette.red : SignupPalette.softLine)
                    .frame(width: index == active ? 20 : 14, height: 4)
            }
        }
    }
}

struct PasswordStrengthView: View {
    let strength: String
    let passedCount: Int
    let rules: [(String, Bool)]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                Text("Password Strength")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(SignupPalette.ink.opacity(0.88))
                Spacer()
                Text(strength)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(passedCount == 4 ? SignupPalette.success : SignupPalette.red)
                Image(systemName: passedCount == 4 ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(passedCount == 4 ? SignupPalette.success : SignupPalette.red)
            }

            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index < max(passedCount, 1) ? SignupPalette.red : SignupPalette.softLine)
                        .frame(height: 5)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(rules, id: \.0) { rule, passed in
                    HStack(spacing: 8) {
                        Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13, weight: .bold))
                        Text(rule)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(passed ? SignupPalette.success : SignupPalette.muted)
                }
            }
        }
        .padding(.horizontal, 10)
    }
}

struct SignupInputRow<Content: View>: View {
    let icon: String
    let placeholder: String
    var trailingIcon: String?
    @ViewBuilder var content: Content
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(SignupPalette.red)
                .frame(width: 22)
            content
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(SignupPalette.ink)
                .tint(SignupPalette.red)
            if let trailingIcon {
                Button {
                    trailingAction?()
                } label: {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(SignupPalette.muted)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(trailingIcon == "eye" ? "Show \(placeholder)" : "Hide \(placeholder)")
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 58)
        .background(SignupPalette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SignupPalette.softLine, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.045), radius: 10, x: 0, y: 5)
    }
}

struct SignupPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            configuration.label
                .font(.system(size: 17, weight: .black, design: .rounded))
            Spacer(minLength: 0)
            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .black))
                .frame(width: 30, height: 30)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(SignupPalette.redGradient, in: Capsule())
        .shadow(color: SignupPalette.red.opacity(0.28), radius: 18, x: 0, y: 12)
        .scaleEffect(configuration.isPressed ? 0.975 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct SignupBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(SignupPalette.ink)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .background(SignupPalette.panel.opacity(0.92), in: Circle())
                .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 8)
        }
        .accessibilityLabel("Back")
    }
}

struct SignupSecurityFooter: View {
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(SignupPalette.muted)
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(SignupPalette.muted)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SignupRoadHero: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 1, green: 0.93, blue: 0.94).opacity(0.70),
                    SignupPalette.background.opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            SignupSkyline()
                .fill(SignupPalette.red.opacity(0.16))
                .frame(width: 220, height: 150)
                .offset(x: -94, y: 88)
                .blur(radius: 0.2)
            SignupSpeedLines()
                .stroke(
                    LinearGradient(
                        colors: [SignupPalette.red.opacity(0), SignupPalette.red.opacity(0.48), SignupPalette.red.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .blur(radius: 0.5)
                .offset(x: 82, y: 52)
        }
    }
}

struct SignupAtlantaHero: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 1.0, green: 0.94, blue: 0.92),
                    SignupPalette.background.opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Image("SignupAtlantaSkyline")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 330)
                .clipped()
                .opacity(0.82)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.06),
                    Color.white.opacity(0.12),
                    SignupPalette.background.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct LocationHero: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 0.97, green: 0.98, blue: 1.0),
                    Color(red: 1.0, green: 0.92, blue: 0.94).opacity(0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RoadGrid()
                .stroke(SignupPalette.muted.opacity(0.13), lineWidth: 1)
                .offset(y: 8)
            SignupSpeedLines()
                .stroke(SignupPalette.red.opacity(0.18), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .offset(y: 112)
                .blur(radius: 0.5)
            ZStack {
                Circle()
                    .fill(SignupPalette.red.opacity(0.10))
                    .frame(width: 130, height: 130)
                Circle()
                    .fill(SignupPalette.red.opacity(0.10))
                    .frame(width: 88, height: 88)
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 74, weight: .black))
                    .foregroundStyle(SignupPalette.redGradient)
                    .shadow(color: SignupPalette.red.opacity(0.30), radius: 18, x: 0, y: 12)
            }
            .offset(y: 18)
        }
    }
}

struct SignupMapPingHero: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white,
                    Color(red: 0.98, green: 0.985, blue: 1.0),
                    SignupPalette.background.opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Image("SignupMapPing")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 330)
                .clipped()
                .opacity(0.92)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.02),
                    Color.white.opacity(0.12),
                    SignupPalette.background.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct PaymentHero: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.white, SignupPalette.background], startPoint: .top, endPoint: .bottom)
            SignupSpeedLines()
                .stroke(SignupPalette.red.opacity(0.14), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .offset(x: 86, y: 30)
        }
    }
}

struct SignupSpeedLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<22 {
            let y = rect.height * (0.16 + CGFloat(index) * 0.033)
            path.move(to: CGPoint(x: rect.minX - 40, y: y))
            path.addCurve(
                to: CGPoint(x: rect.maxX + 50, y: y + CGFloat(index - 10) * 3.5),
                control1: CGPoint(x: rect.width * 0.30, y: y - 40),
                control2: CGPoint(x: rect.width * 0.70, y: y + 50)
            )
        }
        return path
    }
}

struct SignupSkyline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let buildings: [(CGFloat, CGFloat)] = [
            (0.06, 0.48), (0.16, 0.72), (0.28, 0.54), (0.40, 0.86),
            (0.54, 0.62), (0.66, 0.96), (0.80, 0.70), (0.90, 0.82)
        ]
        for (xRatio, heightRatio) in buildings {
            let width = rect.width * 0.085
            let x = rect.minX + rect.width * xRatio
            let height = rect.height * heightRatio
            path.addRoundedRect(
                in: CGRect(x: x, y: rect.maxY - height, width: width, height: height),
                cornerSize: CGSize(width: 2, height: 2)
            )
        }
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

struct SignupMiniCity: Shape {
    func path(in rect: CGRect) -> Path {
        SignupSkyline().path(in: rect)
    }
}

struct RoadGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<12 {
            let x = rect.width * CGFloat(index) / 11
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX + (x - rect.midX) * 1.8, y: rect.maxY))
        }
        for index in 0..<10 {
            let y = rect.height * CGFloat(index) / 9
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}
