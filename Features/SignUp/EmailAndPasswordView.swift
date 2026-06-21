//
//  EmailPasswordView.swift
//  RydrSignupFlow
//

import SwiftUI
import FirebaseAuth
import UIKit

enum SignupPalette {
    static let red = Color(red: 0.95, green: 0.02, blue: 0.19)
    static let wine = Color(red: 0.58, green: 0.02, blue: 0.23)
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
        : UIColor(red: 0.45, green: 0.46, blue: 0.53, alpha: 1)
    })
    static let field = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1)
        : UIColor.white
    })
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
            ("1 number", passwordValidations["1 number"] ?? false),
            ("1 special character", passwordValidations["1 special character"] ?? false),
            ("1 uppercase letter", passwordValidations["1 uppercase letter"] ?? false),
            ("At least 8 characters", passwordValidations["At least 8 characters"] ?? false)
        ]
    }

    private var allValid: Bool {
        passwordValidations.values.allSatisfy { $0 } && !confirmPassword.isEmpty && password == confirmPassword
    }

    var body: some View {
        ZStack {
            SignupPalette.background.ignoresSafeArea()
            SignupRoadHero()
                .frame(height: 310)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .accessibilityHidden(true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    SignupBackButton { dismiss() }
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image("RydrLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 76, height: 76)
                        .accessibilityLabel("Rydr")

                    VStack(spacing: 0) {
                        Text("Create Your")
                            .foregroundStyle(SignupPalette.ink)
                        Text("Account")
                            .foregroundStyle(SignupPalette.red)
                    }
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                    Text("Let's get you set up\nand on the road.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(SignupPalette.muted)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 13) {
                        SignupInputRow(icon: "envelope", placeholder: "Email Address") {
                            TextField("Email Address", text: $email)
                                .keyboardType(.emailAddress)
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
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: password) { _, newValue in
                                validatePassword(newValue)
                            }
                        } trailingAction: {
                            showPassword.toggle()
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(orderedRules, id: \.0) { rule, passed in
                                HStack(spacing: 7) {
                                    Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(rule)
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(passed ? SignupPalette.red : SignupPalette.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 64)

                        SignupInputRow(icon: "lock", placeholder: "Confirm Password", trailingIcon: showConfirmPassword ? "eye.slash" : "eye") {
                            Group {
                                if showConfirmPassword {
                                    TextField("Confirm Password", text: $confirmPassword)
                                } else {
                                    SecureField("Confirm Password", text: $confirmPassword)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        } trailingAction: {
                            showConfirmPassword.toggle()
                        }
                    }
                    .padding(.top, 10)

                    if !confirmPassword.isEmpty && password != confirmPassword {
                        Text("Passwords do not match.")
                            .foregroundStyle(SignupPalette.red)
                            .font(.caption.weight(.bold))
                    }

                    Button("Continue") {
                        onNext()
                    }
                    .buttonStyle(SignupPrimaryButtonStyle())
                    .disabled(!allValid)
                    .opacity(allValid ? 1 : 0.56)

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundStyle(SignupPalette.red)
                            .font(.caption.weight(.bold))
                    }

                    SignupProgressDots(active: 0)
                        .padding(.top, 8)
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
    }

    private func validatePassword(_ text: String) {
        passwordValidations["At least 8 characters"] = text.count >= 8
        passwordValidations["1 uppercase letter"] = text.rangeOfCharacter(from: .uppercaseLetters) != nil
        passwordValidations["1 number"] = text.rangeOfCharacter(from: .decimalDigits) != nil
        passwordValidations["1 special character"] = text.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+{}|:<>?-=[];,./")) != nil
    }
}

struct SignupInputRow<Content: View>: View {
    let icon: String
    let placeholder: String
    var trailingIcon: String?
    @ViewBuilder var content: Content
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(SignupPalette.red)
                .frame(width: 18)
            content
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(SignupPalette.ink)
                .tint(SignupPalette.red)
            if let trailingIcon {
                Button {
                    trailingAction?()
                } label: {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(SignupPalette.muted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(trailingIcon == "eye" ? "Show \(placeholder)" : "Hide \(placeholder)")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(SignupPalette.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(SignupPalette.red.opacity(0.50), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 7)
    }
}

struct SignupPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [SignupPalette.red, SignupPalette.wine],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: SignupPalette.red.opacity(0.24), radius: 12, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SignupBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(SignupPalette.ink)
                .frame(width: 42, height: 42)
                .background(SignupPalette.panel, in: Circle())
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
        }
        .accessibilityLabel("Back")
    }
}

struct SignupProgressDots: View {
    let active: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index == active ? SignupPalette.red : SignupPalette.muted.opacity(0.30))
                    .frame(width: index == active ? 18 : 14, height: 4)
            }
        }
    }
}

struct SignupRoadHero: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    SignupPalette.background,
                    Color(red: 1, green: 0.90, blue: 0.93).opacity(0.34),
                    SignupPalette.background.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
                .offset(x: 80, y: 42)
            SignupMiniCity()
                .fill(SignupPalette.red.opacity(0.13))
                .frame(width: 160, height: 110)
                .offset(x: -120, y: 120)
        }
    }
}

struct SignupSpeedLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<20 {
            let y = rect.height * (0.18 + CGFloat(index) * 0.034)
            path.move(to: CGPoint(x: rect.minX - 30, y: y))
            path.addLine(to: CGPoint(x: rect.maxX + 40, y: y + CGFloat(index - 10) * 3))
        }
        return path
    }
}

struct SignupMiniCity: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let widths: [CGFloat] = [18, 24, 16, 28, 20, 32]
        var x = rect.minX
        for (index, width) in widths.enumerated() {
            let height = CGFloat([62, 94, 48, 78, 104, 70][index])
            path.addRoundedRect(
                in: CGRect(x: x, y: rect.maxY - height, width: width, height: height),
                cornerSize: CGSize(width: 2, height: 2)
            )
            x += width + 10
        }
        return path
    }
}
