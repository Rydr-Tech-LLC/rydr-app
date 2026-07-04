//
//  PhoneVerificationView.swift
//  RydrSignupFlow
//
import SwiftUI
import FirebaseAuth

struct PhoneVerificationView: View {
    var initialPhoneNumber: String = ""
    var linkToCurrentUser = false
    var onVerified: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var nationalNumber: String = ""
    @State private var sending = false
    @State private var errorMessage = ""
    @State private var verificationSession: PhoneVerificationSession?
    @State private var contentVisible = false
    private let termsURL = URL(string: "https://rydr-go.com/terms.html")!
    private let privacyURL = URL(string: "https://rydr-go.com/privacy.html")!

    private var formattedPhoneNumber: String {
        let digits = nationalNumber.filter { $0.isNumber }.prefix(10)
        return "+1" + digits
    }

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom

            ScrollView(showsIndicators: false) {
                ZStack(alignment: .top) {
                    PhoneVerificationBackground()

                    VStack(alignment: .leading, spacing: 0) {
                        topBar(safeTop: safeTop)

                        VStack(spacing: 24) {
                            verificationLogo
                                .opacity(contentVisible ? 1 : 0)
                                .offset(y: contentVisible ? 0 : 14)

                            VStack(alignment: .leading, spacing: 18) {
                                headline

                                Text("Enter your phone number and we'll send you a verification code.")
                                    .font(.system(size: 21, weight: .medium))
                                    .foregroundStyle(PhoneVerificationPalette.slate)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(contentVisible ? 1 : 0)
                            .offset(y: contentVisible ? 0 : 22)

                            phoneField
                                .opacity(contentVisible ? 1 : 0)
                                .offset(y: contentVisible ? 0 : 26)

                            safetyRow
                                .opacity(contentVisible ? 1 : 0)
                                .offset(y: contentVisible ? 0 : 28)

                            if !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(PhoneVerificationPalette.red)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            Button {
                                sendCode()
                            } label: {
                                PhoneVerificationCTA(
                                    title: sending ? "Sending..." : "Send Code",
                                    isEnabled: nationalNumber.count == 10 && !sending
                                )
                            }
                            .buttonStyle(PhoneVerificationPressStyle())
                            .disabled(sending || nationalNumber.count != 10)
                            .opacity(contentVisible ? 1 : 0)
                            .offset(y: contentVisible ? 0 : 32)

                            Spacer(minLength: 58)

                            termsText
                                .padding(.bottom, safeBottom + 20)
                                .opacity(contentVisible ? 1 : 0)
                        }
                        .padding(.horizontal, 30)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(minHeight: max(proxy.size.height, 840))
            }
            .background(PhoneVerificationPalette.background)
            .ignoresSafeArea(edges: [.top, .bottom])
        }
        .onAppear {
            applyInitialPhoneNumber()
            withAnimation(.spring(response: 0.78, dampingFraction: 0.86).delay(0.08)) {
                contentVisible = true
            }
        }
        .onChange(of: initialPhoneNumber) { _, _ in
            applyInitialPhoneNumber()
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $verificationSession) { verificationSession in
            VerificationCodeView(
                verificationID: verificationSession.verificationID,
                phoneNumber: verificationSession.phoneNumber,
                linkToCurrentUser: linkToCurrentUser,
                onSuccess: { user in
                    onVerified(user.phoneNumber ?? "")
                },
                onResendCode: { sendCode(resend: true) }
            )
        }
        .preferredColorScheme(.light)
        .environment(\.colorScheme, .light)
    }

    private var phoneField: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Text("🇺🇸")
                    .font(.system(size: 24))
                    .accessibilityLabel("United States")

                Text("+1")
                    .font(.system(size: 25, weight: .bold))

                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .black))
            }
            .foregroundStyle(PhoneVerificationPalette.ink)

            Divider()
                .frame(height: 38)

            TextField("", text: Binding(
                get: { nationalNumber },
                set: { nationalNumber = String($0.filter { $0.isNumber }.prefix(10)) }
            ), prompt: Text("Phone number"))
            .keyboardType(.numberPad)
            .textContentType(.telephoneNumber)
            .font(.system(size: 23, weight: .medium))
            .foregroundStyle(PhoneVerificationPalette.ink)
            .tint(PhoneVerificationPalette.red)
            .accessibilityLabel("US Phone Number Field")
        }
        .padding(.horizontal, 24)
        .frame(height: 74)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.white.opacity(0.82))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.95), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.06), radius: 22, x: 0, y: 12)
        .shadow(color: PhoneVerificationPalette.red.opacity(0.05), radius: 24, x: 0, y: 14)
    }

    private func topBar(safeTop: CGFloat) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(PhoneVerificationPalette.ink)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(PhoneVerificationPressStyle(scale: 0.9))
            .accessibilityLabel("Back")

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, safeTop + 14)
        .padding(.bottom, 2)
    }

    private var verificationLogo: some View {
        ZStack {
            PhoneVerificationLogoRing()
                .frame(width: 178, height: 178)

            Image("RydrLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 86, height: 86)
                .shadow(color: PhoneVerificationPalette.red.opacity(0.18), radius: 18, x: 0, y: 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rydr logo")
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Let's get you")
                .font(.system(size: 48, weight: .black))
                .foregroundStyle(PhoneVerificationPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            (
                Text("your ")
                    .foregroundStyle(PhoneVerificationPalette.ink)
                + Text("first ride.")
                    .foregroundStyle(PhoneVerificationPalette.red)
            )
            .font(.system(size: 48, weight: .black))
            .lineLimit(1)
            .minimumScaleFactor(0.62)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var safetyRow: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(PhoneVerificationPalette.redSoft)
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(PhoneVerificationPalette.redGradient)
                }
                .shadow(color: PhoneVerificationPalette.red.opacity(0.13), radius: 18, x: 0, y: 10)

            VStack(alignment: .leading, spacing: 5) {
                Text("We keep your info safe and secure.")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(PhoneVerificationPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("We'll never share your number.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(PhoneVerificationPalette.slate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var termsText: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(PhoneVerificationPalette.slate.opacity(0.72))

            HStack(spacing: 3) {
                Text("By continuing, you agree to our")
                    .foregroundStyle(PhoneVerificationPalette.slate)
                Button("Terms") { openURL(termsURL) }
                    .foregroundStyle(PhoneVerificationPalette.red)
                Text("and")
                    .foregroundStyle(PhoneVerificationPalette.slate)
                Button("Privacy Policy.") { openURL(privacyURL) }
                    .foregroundStyle(PhoneVerificationPalette.red)
            }
            .font(.system(size: 13, weight: .medium))
            .buttonStyle(.plain)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyInitialPhoneNumber() {
        guard nationalNumber.isEmpty else { return }
        let digits = initialPhoneNumber.filter { $0.isNumber }
        nationalNumber = String(digits.suffix(10))
    }

    private func sendCode(resend: Bool = false) {
        errorMessage = ""
        sending = true
        let e164 = formattedPhoneNumber

        if linkToCurrentUser, Auth.auth().currentUser?.phoneNumber == e164 {
            sending = false
            onVerified(e164)
            return
        }

        // DEBUG/testing on simulator (don't ship enabled):
        // Auth.auth().settings?.isAppVerificationDisabledForTesting = true

        PhoneAuthProvider.provider().verifyPhoneNumber(e164, uiDelegate: nil) { id, error in
            Task { @MainActor in
                sending = false
                if let error = error {
                    let nsError = error as NSError
                    #if DEBUG
                    print("🔥 verifyPhoneNumber failed — domain: \(nsError.domain), code: \(nsError.code), localizedDescription: \(nsError.localizedDescription), userInfo: \(nsError.userInfo)")
                    #endif
                    errorMessage = "Failed to send code: \(error.localizedDescription)"
                    return
                }

                guard let id, !id.isEmpty else {
                    errorMessage = "Firebase did not return a verification session. Please resend the code."
                    return
                }

                verificationSession = PhoneVerificationSession(
                    verificationID: id,
                    phoneNumber: e164
                )
            }
        }
    }
}

private enum PhoneVerificationPalette {
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

private struct PhoneVerificationBackground: View {
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
                    PhoneVerificationPalette.red.opacity(0.12),
                    PhoneVerificationPalette.red.opacity(0.04),
                    .clear
                ],
                center: .top,
                startRadius: 18,
                endRadius: 250
            )
            .frame(height: 320)
            .offset(y: 20)
            .blur(radius: 10)

            PhoneVerificationSpeedLines()
                .opacity(0.82)
                .ignoresSafeArea()
        }
    }
}

private struct PhoneVerificationLogoRing: View {
    @State private var pulse = false
    @State private var rotate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [PhoneVerificationPalette.red.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 22,
                        endRadius: 92
                    )
                )
                .scaleEffect(pulse ? 1.03 : 0.95)

            Circle()
                .stroke(
                    PhoneVerificationPalette.red.opacity(pulse ? 0.34 : 0.52),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [1.6, 6.4])
                )
                .padding(4)
                .rotationEffect(.degrees(rotate ? 360 : 0))

            Circle()
                .stroke(
                    PhoneVerificationPalette.red.opacity(pulse ? 0.12 : 0.22),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [0.8, 9])
                )
                .padding(14)
                .rotationEffect(.degrees(rotate ? -220 : 0))
                .scaleEffect(pulse ? 1.018 : 0.992)

            Circle()
                .stroke(PhoneVerificationPalette.red.opacity(0.1), lineWidth: 1)
                .padding(24)
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

private struct PhoneVerificationSpeedLines: View {
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    PhoneVerificationWave(offset: CGFloat(index) * 14)
                        .trim(from: 0.03, to: 0.97)
                        .stroke(
                            PhoneVerificationPalette.red.opacity(0.22 - Double(index) * 0.012),
                            style: StrokeStyle(lineWidth: index == 0 ? 2.1 : 1.0, lineCap: .round)
                        )
                        .frame(width: width * 1.35, height: height * 0.34)
                        .offset(x: drift ? -28 : 14, y: height * 0.22 + CGFloat(index) * 2)
                        .animation(
                            .easeInOut(duration: 3.2 + Double(index) * 0.08).repeatForever(autoreverses: true),
                            value: drift
                        )
                }

                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(PhoneVerificationPalette.red.opacity(0.34))
                        .frame(width: 7, height: 7)
                        .blur(radius: 1)
                        .offset(
                            x: width * (0.30 + CGFloat(index) * 0.12) + (drift ? 16 : -8),
                            y: height * (0.14 + CGFloat(index % 3) * 0.08)
                        )
                        .animation(
                            .easeInOut(duration: 2.8 + Double(index) * 0.16).repeatForever(autoreverses: true),
                            value: drift
                        )
                }
            }
            .mask {
                LinearGradient(
                    colors: [.clear, .black, .black, .clear],
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

private struct PhoneVerificationWave: Shape {
    let offset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -rect.width * 0.08, y: rect.height * 0.76 + offset * 0.12))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.44, y: rect.height * 0.52 - offset * 0.08),
            control1: CGPoint(x: rect.width * 0.14, y: rect.height * 0.34 + offset * 0.16),
            control2: CGPoint(x: rect.width * 0.26, y: rect.height * 0.74 - offset * 0.1)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 1.08, y: rect.height * 0.16 + offset * 0.04),
            control1: CGPoint(x: rect.width * 0.62, y: rect.height * 0.28 - offset * 0.08),
            control2: CGPoint(x: rect.width * 0.78, y: rect.height * 0.0 + offset * 0.1)
        )
        return path
    }
}

private struct PhoneVerificationCTA: View {
    let title: String
    let isEnabled: Bool
    @State private var glow = false
    @State private var streak = false

    var body: some View {
        ZStack(alignment: .leading) {
            PhoneVerificationButtonStreaks(active: streak)
                .frame(width: 120)
                .offset(x: -68)
                .opacity(isEnabled ? 1 : 0.38)

            HStack(spacing: 14) {
                Spacer(minLength: 0)

                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Spacer(minLength: 0)

                Circle()
                    .fill(.white)
                    .frame(width: 58, height: 58)
                    .overlay {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(PhoneVerificationPalette.red)
                    }
            }
            .padding(.leading, 32)
            .padding(.trailing, 12)
            .frame(height: 88)
            .background(PhoneVerificationPalette.redGradient, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.28), lineWidth: 1)
            }
            .shadow(
                color: PhoneVerificationPalette.red.opacity(isEnabled ? (glow ? 0.4 : 0.24) : 0.08),
                radius: isEnabled ? (glow ? 28 : 18) : 8,
                x: 0,
                y: isEnabled ? (glow ? 18 : 12) : 4
            )
            .saturation(isEnabled ? 1 : 0.45)
            .opacity(isEnabled ? 1 : 0.62)
        }
        .padding(.leading, 24)
        .onAppear {
            glow = true
            streak = true
        }
        .animation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true), value: glow)
        .animation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true), value: streak)
        .accessibilityElement(children: .combine)
    }
}

private struct PhoneVerificationButtonStreaks: View {
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, PhoneVerificationPalette.red.opacity(0.34), PhoneVerificationPalette.red.opacity(0.72)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: CGFloat(105 - index * 8), height: CGFloat(max(3, 8 - index)))
                    .offset(x: active ? CGFloat(index * 5) : CGFloat(-8 - index * 3))
                    .opacity(0.74 - Double(index) * 0.06)
            }
        }
        .blur(radius: 0.35)
    }
}

private struct PhoneVerificationPressStyle: ButtonStyle {
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
