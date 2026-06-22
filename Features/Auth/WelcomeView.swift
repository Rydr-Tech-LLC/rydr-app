//
//  WelcomeView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/14/25.
//
import SwiftUI

struct WelcomeView: View {
    @State private var showSignup = false
    @State private var contentVisible = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let safeTop = proxy.safeAreaInsets.top
                let safeBottom = proxy.safeAreaInsets.bottom
                let viewportHeight = proxy.size.height

                ScrollView(showsIndicators: false) {
                    ZStack(alignment: .top) {
                        WelcomeBackground()

                        VStack(spacing: 0) {
                            topBar(safeTop: safeTop)

                            VStack(spacing: 22) {
                                LogoSection()
                                    .padding(.top, 0)
                                    .opacity(contentVisible ? 1 : 0)
                                    .offset(y: contentVisible ? 0 : 18)

                                HeroSection()
                                    .opacity(contentVisible ? 1 : 0)
                                    .offset(y: contentVisible ? 0 : 24)

                                FeatureHighlights()
                                    .opacity(contentVisible ? 1 : 0)
                                    .offset(y: contentVisible ? 0 : 30)

                                VStack(spacing: 14) {
                                    Button {
                                        showSignup = true
                                    } label: {
                                        PrimaryCTAButton()
                                    }
                                    .buttonStyle(WelcomePressStyle())

                                    NavigationLink(destination: CashHubSignupView()) {
                                        ActionCard(
                                            icon: .asset("RydrLogo"),
                                            title: "Ride with CashRydr",
                                            subtitle: "Post. Negotiate. Ride."
                                        )
                                    }
                                    .buttonStyle(WelcomePressStyle())

                                    NavigationLink(destination: LoginView()) {
                                        ActionCard(
                                            icon: .system("person.crop.circle.fill"),
                                            title: "Log Into Your Existing Ride Account",
                                            subtitle: "Access your account"
                                        )
                                    }
                                    .buttonStyle(WelcomePressStyle())
                                }
                                .padding(.top, 2)
                                .opacity(contentVisible ? 1 : 0)
                                .offset(y: contentVisible ? 0 : 36)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, safeBottom + 28)
                            .frame(maxWidth: 560)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(minHeight: max(viewportHeight, 860))
                }
                .background(WelcomePalette.background)
                .ignoresSafeArea(edges: [.top, .bottom])
                .onAppear {
                    withAnimation(.spring(response: 0.85, dampingFraction: 0.88).delay(0.12)) {
                        contentVisible = true
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showSignup) {
            SignupCoordinator()
        }
        .preferredColorScheme(.light)
        .environment(\.colorScheme, .light)
    }

    private func topBar(safeTop: CGFloat) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WelcomePalette.ink)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.86), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.82), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(WelcomePressStyle(scale: 0.92))
            .accessibilityLabel("Back")

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, safeTop + 6)
        .padding(.bottom, 0)
    }
}

private enum WelcomePalette {
    static let red = Color(red: 0.96, green: 0.02, blue: 0.19)
    static let redDeep = Color(red: 0.66, green: 0.0, blue: 0.15)
    static let redSoft = Color(red: 1.0, green: 0.89, blue: 0.92)
    static let ink = Color(red: 0.035, green: 0.055, blue: 0.11)
    static let navy = Color(red: 0.025, green: 0.045, blue: 0.105)
    static let slate = Color(red: 0.36, green: 0.38, blue: 0.47)
    static let lightGray = Color(red: 0.957, green: 0.963, blue: 0.975)
    static let background = Color(red: 0.988, green: 0.99, blue: 0.996)

    static let rydrGradient = LinearGradient(
        colors: [red, Color(red: 0.88, green: 0.0, blue: 0.24), redDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let horizontalRydrGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.12, blue: 0.28), red, redDeep],
        startPoint: .leading,
        endPoint: .trailing
    )
}

private struct WelcomeBackground: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [.white, WelcomePalette.lightGray, .white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    WelcomePalette.red.opacity(0.14),
                    WelcomePalette.red.opacity(0.05),
                    .clear
                ],
                center: .top,
                startRadius: 18,
                endRadius: 220
            )
            .frame(height: 360)
            .offset(y: 20)
            .blur(radius: 8)

            AtlantaSkylineBackground()
                .frame(height: 300)
                .padding(.top, 72)
                .opacity(0.72)

            SpeedTrailBackground()
                .ignoresSafeArea()

            HalftoneAccent()
                .frame(width: 170, height: 170)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .offset(x: -72, y: 54)
                .opacity(0.26)
        }
    }
}

struct AtlantaSkylineBackground: View {
    var body: some View {
        Canvas { context, size in
            let baseY = size.height * 0.76
            let startX = size.width * 0.40
            let strokeColor = WelcomePalette.navy.opacity(0.105)
            let fillColor = WelcomePalette.navy.opacity(0.026)

            func tower(x: CGFloat, width: CGFloat, height: CGFloat, crown: CGFloat = 0, spire: CGFloat = 0) {
                let topY = baseY - height
                var body = Path()
                body.move(to: CGPoint(x: x, y: baseY))
                body.addLine(to: CGPoint(x: x, y: topY + crown))
                if crown > 0 {
                    body.addLine(to: CGPoint(x: x + width * 0.5, y: topY))
                    body.addLine(to: CGPoint(x: x + width, y: topY + crown))
                } else {
                    body.addLine(to: CGPoint(x: x + width, y: topY))
                }
                body.addLine(to: CGPoint(x: x + width, y: baseY))
                body.closeSubpath()

                context.fill(body, with: .color(fillColor))
                context.stroke(body, with: .color(strokeColor), lineWidth: 1.1)

                guard spire > 0 else { return }
                var spirePath = Path()
                spirePath.move(to: CGPoint(x: x + width * 0.5, y: topY))
                spirePath.addLine(to: CGPoint(x: x + width * 0.5, y: topY - spire))
                context.stroke(spirePath, with: .color(strokeColor.opacity(0.85)), lineWidth: 0.9)
            }

            tower(x: startX, width: 24, height: 72, crown: 10)
            tower(x: startX + 34, width: 35, height: 104)
            tower(x: startX + 80, width: 27, height: 88, crown: 20, spire: 18)
            tower(x: startX + 118, width: 46, height: 142)
            tower(x: startX + 174, width: 34, height: 102, crown: 24, spire: 14)
            tower(x: startX + 218, width: 48, height: 190, crown: 16, spire: 54)
            tower(x: startX + 276, width: 34, height: 112)
            tower(x: startX + 320, width: 42, height: 150, crown: 12, spire: 24)

            var wheel = Path()
            let wheelCenter = CGPoint(x: startX + 70, y: baseY - 30)
            let wheelRadius: CGFloat = 24
            wheel.addEllipse(in: CGRect(
                x: wheelCenter.x - wheelRadius,
                y: wheelCenter.y - wheelRadius,
                width: wheelRadius * 2,
                height: wheelRadius * 2
            ))
            for index in 0..<12 {
                let angle = CGFloat(index) * .pi / 6
                wheel.move(to: wheelCenter)
                wheel.addLine(to: CGPoint(
                    x: wheelCenter.x + cos(angle) * wheelRadius,
                    y: wheelCenter.y + sin(angle) * wheelRadius
                ))
            }
            context.stroke(wheel, with: .color(strokeColor.opacity(0.72)), lineWidth: 0.8)

            var horizon = Path()
            horizon.move(to: CGPoint(x: startX - 24, y: baseY))
            horizon.addCurve(
                to: CGPoint(x: size.width + 20, y: baseY - 6),
                control1: CGPoint(x: startX + 80, y: baseY + 8),
                control2: CGPoint(x: size.width * 0.78, y: baseY - 10)
            )
            context.stroke(horizon, with: .color(strokeColor.opacity(0.42)), lineWidth: 1)
        }
        .blur(radius: 0.25)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.45), location: 0.18),
                    .init(color: .black, location: 0.48),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SpeedTrailBackground: View {
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    SpeedTrailShape(offset: CGFloat(index) * 36)
                        .trim(from: 0.05, to: 0.96)
                        .stroke(
                            WelcomePalette.horizontalRydrGradient,
                            style: StrokeStyle(lineWidth: CGFloat(9 - index), lineCap: .round)
                        )
                        .opacity(0.16 - Double(index) * 0.018)
                        .blur(radius: CGFloat(index) * 0.6)
                        .frame(width: width * 1.28, height: height * 0.48)
                        .offset(x: drift ? -18 : 10, y: height * 0.18 + CGFloat(index * 18))
                        .animation(
                            .easeInOut(duration: 3.4 + Double(index) * 0.24).repeatForever(autoreverses: true),
                            value: drift
                        )
                }

                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(WelcomePalette.red.opacity(0.13))
                        .frame(width: width * 0.74, height: CGFloat(3 + index))
                        .blur(radius: 0.8)
                        .rotationEffect(.degrees(-38))
                        .offset(x: width * 0.28 + (drift ? 24 : -12), y: height * (0.15 + CGFloat(index) * 0.035))
                        .animation(
                            .easeInOut(duration: 2.8 + Double(index) * 0.18).repeatForever(autoreverses: true),
                            value: drift
                        )
                }
            }
            .onAppear { drift = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SpeedTrailShape: Shape {
    let offset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -rect.width * 0.05, y: rect.height * 0.84 - offset))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.52, y: rect.height * 0.58 - offset * 0.32),
            control1: CGPoint(x: rect.width * 0.18, y: rect.height * 0.86 - offset * 0.6),
            control2: CGPoint(x: rect.width * 0.34, y: rect.height * 0.58 - offset * 0.25)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 1.04, y: rect.height * 0.28 - offset * 0.08),
            control1: CGPoint(x: rect.width * 0.74, y: rect.height * 0.56 - offset * 0.2),
            control2: CGPoint(x: rect.width * 0.82, y: rect.height * 0.34 - offset * 0.1)
        )
        return path
    }
}

private struct HalftoneAccent: View {
    var body: some View {
        Canvas { context, size in
            for row in 0..<16 {
                for column in 0..<16 {
                    let progress = CGFloat(row + column) / 32
                    let radius = max(0.8, 4.8 * (1 - progress))
                    let point = CGPoint(
                        x: CGFloat(column) * size.width / 15,
                        y: CGFloat(row) * size.height / 15
                    )
                    let rect = CGRect(x: point.x, y: point.y, width: radius, height: radius)
                    context.fill(Path(ellipseIn: rect), with: .color(WelcomePalette.red.opacity(0.42)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct LogoSection: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                AnimatedLogoRing()
                    .frame(width: 152, height: 152)

                Image("RydrWelcomeLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 136, height: 136)
                    .shadow(color: WelcomePalette.red.opacity(0.18), radius: 18, x: 0, y: 10)
            }
            .frame(width: 152, height: 152)
            .accessibilityLabel("Rydr. Ride Different.")
            .accessibilityAddTraits(.isImage)
        }
    }
}

struct AnimatedLogoRing: View {
    @State private var pulse = false
    @State private var rotate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [WelcomePalette.red.opacity(0.12), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 82
                    )
                )
                .scaleEffect(pulse ? 1.03 : 0.95)

            Circle()
                .stroke(
                    WelcomePalette.red.opacity(pulse ? 0.34 : 0.52),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [1.6, 6.4])
                )
                .padding(4)
                .rotationEffect(.degrees(rotate ? 360 : 0))

            Circle()
                .stroke(
                    WelcomePalette.red.opacity(pulse ? 0.12 : 0.22),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [0.8, 9])
                )
                .padding(10)
                .rotationEffect(.degrees(rotate ? -220 : 0))
                .scaleEffect(pulse ? 1.018 : 0.992)
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

struct HeroSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: -6) {
                Text("RIDE")
                    .font(.system(size: 66, weight: .black, design: .default))
                    .italic()
                    .foregroundStyle(WelcomePalette.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text("DIFFERENT")
                    .font(.system(size: 54, weight: .black, design: .default))
                    .italic()
                    .foregroundStyle(WelcomePalette.horizontalRydrGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 4) {
                Text("Your ride. Your way.")
                    .foregroundStyle(WelcomePalette.navy)
                Text("Anytime, anywhere.")
                    .foregroundStyle(WelcomePalette.red)
            }
            .font(.system(size: 26, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .padding(.top, 0)
    }
}

private struct FeatureHighlights: View {
    private let features: [FeatureCard.Model] = [
        .init(icon: "checkmark.shield.fill", title: "Safe & Reliable", subtitle: "Your safety is our priority"),
        .init(icon: "bolt.fill", title: "Rides in Minutes", subtitle: "Get there stress free"),
        .init(icon: "star.fill", title: "Top Rated", subtitle: "Great experiences every time")
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(features) { feature in
                FeatureCard(model: feature)
            }
        }
    }
}

struct FeatureCard: View {
    struct Model: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
    }

    let model: Model
    @State private var visible = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(WelcomePalette.redSoft.opacity(0.95))
                    .frame(width: 54, height: 54)
                    .shadow(color: WelcomePalette.red.opacity(0.14), radius: 18, x: 0, y: 8)

                Image(systemName: model.icon)
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(WelcomePalette.horizontalRydrGradient)
            }

            VStack(spacing: 6) {
                Text(model.title)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WelcomePalette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(model.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WelcomePalette.slate)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }

            Capsule()
                .fill(WelcomePalette.horizontalRydrGradient)
                .frame(width: 26, height: 4)
                .padding(.top, 2)
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity)
        .frame(height: 152)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.white.opacity(0.58))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.86), lineWidth: 1)
                }
        }
        .shadow(color: WelcomePalette.red.opacity(0.08), radius: 22, x: 0, y: 16)
        .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 10)
        .scaleEffect(visible ? 1 : 0.96)
        .animation(.spring(response: 0.7, dampingFraction: 0.84), value: visible)
        .onAppear { visible = true }
    }
}

struct PrimaryCTAButton: View {
    @State private var glow = false
    @State private var streak = false

    var body: some View {
        ZStack(alignment: .leading) {
            ButtonSpeedStreaks(active: streak)
                .frame(width: 94)
                .offset(x: -54)

            HStack(spacing: 12) {
                Circle()
                    .fill(.white)
                    .frame(width: 58, height: 58)
                    .overlay {
                        Image(systemName: "car.fill")
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(WelcomePalette.horizontalRydrGradient)
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text("SIGN UP & RIDE")
                        .font(.system(size: 23, weight: .black))
                        .tracking(0)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text("Take your first ride in minutes")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                Circle()
                    .fill(.white)
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(WelcomePalette.red)
                    }
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .frame(height: 98)
            .background(WelcomePalette.horizontalRydrGradient, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.26), lineWidth: 1)
            }
            .shadow(color: WelcomePalette.red.opacity(glow ? 0.44 : 0.28), radius: glow ? 30 : 20, x: 0, y: glow ? 18 : 12)
        }
        .padding(.leading, 14)
        .onAppear {
            glow = true
            streak = true
        }
        .animation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true), value: glow)
        .animation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true), value: streak)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sign up and ride. Take your first ride in minutes.")
    }
}

private struct ButtonSpeedStreaks: View {
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.85), WelcomePalette.red.opacity(0.76)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: CGFloat(92 - index * 7), height: CGFloat(max(3, 9 - index)))
                    .offset(x: active ? CGFloat(index * 4) : CGFloat(-8 - index * 3))
                    .opacity(0.72 - Double(index) * 0.06)
            }
        }
        .blur(radius: 0.4)
    }
}

enum ActionCardIcon {
    case system(String)
    case asset(String)
}

struct ActionCard: View {
    let icon: ActionCardIcon
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(WelcomePalette.redSoft.opacity(0.82))
                .frame(width: 60, height: 60)
                .overlay {
                    switch icon {
                    case .system(let name):
                        Image(systemName: name)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(WelcomePalette.horizontalRydrGradient)
                    case .asset(let name):
                        Image(name)
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                    }
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WelcomePalette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WelcomePalette.slate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 23, weight: .black))
                .foregroundStyle(WelcomePalette.red)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 92)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(.white.opacity(0.72))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.07), radius: 18, x: 0, y: 10)
        .shadow(color: WelcomePalette.red.opacity(0.06), radius: 24, x: 0, y: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct WelcomePressStyle: ButtonStyle {
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

#Preview {
    WelcomeView()
        .environmentObject(UserSessionManager())
}
