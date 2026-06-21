//
//  WelcomeView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/14/25.
//
import SwiftUI
import UIKit

private enum WelcomePalette {
    static let rydrRed = Color(red: 0.95, green: 0.02, blue: 0.19)
    static let deepRed = Color(red: 0.70, green: 0.00, blue: 0.14)

    static let background = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.025, green: 0.025, blue: 0.032, alpha: 1)
        : UIColor.white
    })

    static let heroTop = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)
        : UIColor.white
    })

    static let heroMid = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.10, green: 0.03, blue: 0.05, alpha: 1)
        : UIColor(red: 1.00, green: 0.97, blue: 0.98, alpha: 1)
    })

    static let heroBottom = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.025, green: 0.025, blue: 0.032, alpha: 1)
        : UIColor.white
    })

    static let ink = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.97, green: 0.97, blue: 0.99, alpha: 1)
        : UIColor(red: 0.06, green: 0.07, blue: 0.12, alpha: 1)
    })

    static let cardInk = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1)
        : UIColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 1)
    })

    static let muted = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.72, green: 0.73, blue: 0.78, alpha: 1)
        : UIColor(red: 0.42, green: 0.43, blue: 0.50, alpha: 1)
    })

    static let secondaryMuted = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.66, green: 0.67, blue: 0.73, alpha: 1)
        : UIColor(red: 0.46, green: 0.47, blue: 0.54, alpha: 1)
    })

    static let cardFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.105, green: 0.105, blue: 0.125, alpha: 1)
        : UIColor.white
    })

    static let medallionFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.065, green: 0.065, blue: 0.078, alpha: 1)
        : UIColor.white
    })

    static let softRedFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.26, green: 0.02, blue: 0.07, alpha: 1)
        : UIColor(red: 1.0, green: 0.91, blue: 0.94, alpha: 1)
    })
}

struct WelcomeView: View {
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let safeTop = proxy.safeAreaInsets.top

                ZStack(alignment: .bottom) {
                    WelcomePalette.background.ignoresSafeArea()

                    VStack(spacing: 0) {
                        hero
                            .frame(height: min(proxy.size.height * 0.54, 470))
                            .padding(.top, max(0, safeTop - 6))
                        Spacer(minLength: 0)
                    }
                    .ignoresSafeArea(edges: .top)

                    BottomSpeedRibbon()
                        .frame(height: 120)
                        .opacity(0.88)
                        .ignoresSafeArea(edges: .bottom)
                        .accessibilityHidden(true)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 14) {
                            Spacer()
                                .frame(height: min(proxy.size.height * 0.36, 320))

                            headline
                            benefits
                                .padding(.top, 8)

                            VStack(spacing: 12) {
                                NavigationLink(destination: SignupCoordinator()) {
                                    WelcomeActionCard(
                                        icon: "car.fill",
                                        title: "Ride with Rydr",
                                        subtitle: "Sign up to take your first ride",
                                        isPrimary: true
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink(destination: CashHubSignupView()) {
                                    WelcomeActionCard(
                                        icon: "stylizedR",
                                        title: "Ride with CashRydr Hub",
                                        subtitle: "Post. Negotiate. Ride.",
                                        isPrimary: false
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink(destination: LoginView()) {
                                    WelcomeActionCard(
                                        icon: "person.fill",
                                        title: "Log Into Existing Ride Account",
                                        subtitle: "Access Your Account",
                                        isPrimary: false
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.top, 12)

                            Spacer(minLength: 96)
                        }
                        .padding(.horizontal, 28)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var hero: some View {
        ZStack(alignment: .top) {
            RydrCityHeroBackground()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                LogoMedallion()
                    .frame(width: 186, height: 186)
                    .padding(.top, 74)
                Spacer()
            }
        }
    }

    private var headline: some View {
        VStack(spacing: 0) {
            Text("RIDE")
                .font(.system(size: 56, weight: .black, design: .rounded).italic())
                .foregroundStyle(WelcomePalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 62)

            HStack(spacing: 8) {
                SpeedWordMark()
                    .frame(width: 86, height: 34)
                    .offset(y: 3)

                Text("DIFFERENT")
                    .font(.system(size: 48, weight: .black, design: .rounded).italic())
                    .foregroundStyle(WelcomePalette.rydrRed)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 36)

            Text("Your ride. Your way. Anytime, anywhere.")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(WelcomePalette.muted)
                .padding(.top, 8)
        }
        .accessibilityElement(children: .combine)
    }

    private var benefits: some View {
        HStack(spacing: 0) {
            BenefitBadge(
                icon: "shield.fill",
                accentIcon: "checkmark",
                title: "Safe & Reliable",
                subtitle: "Your safety is\nour priority"
            )
            Divider().frame(height: 54)
            BenefitBadge(
                icon: "timer",
                accentIcon: nil,
                title: "Rides in Minutes",
                subtitle: "Get there,\nstress free"
            )
            Divider().frame(height: 54)
            BenefitBadge(
                icon: "person.fill",
                accentIcon: "stars",
                title: "Top Rated",
                subtitle: "Great experiences\nevery time"
            )
        }
    }
}

private struct LogoMedallion: View {
    private let red = Color(red: 0.95, green: 0.02, blue: 0.19)

    var body: some View {
        ZStack {
            ParticleRing()
                .foregroundStyle(red)

            Circle()
                .fill(WelcomePalette.medallionFill)
                .shadow(color: red.opacity(0.10), radius: 18, x: 0, y: 10)

            VStack(spacing: 4) {
                Image("RydrLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)
                    .accessibilityLabel("Rydr logo")

                Text("Rydr")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(red)

                Text("Ride Different")
                    .font(.system(size: 12, weight: .medium, design: .serif).italic())
                    .foregroundStyle(red)
            }
            .offset(y: 8)
        }
    }
}

private struct ParticleRing: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 2)
                .padding(22)

            ForEach(0..<150, id: \.self) { index in
                let angle = Double(index) * 2.399963
                let radius = 77.0 + Double((index * 37) % 22)
                let dotSize = CGFloat(1.2 + Double((index * 11) % 5) * 0.45)

                Circle()
                    .frame(width: dotSize, height: dotSize)
                    .offset(
                        x: CGFloat(cos(angle) * radius),
                        y: CGFloat(sin(angle) * radius)
                    )
                    .opacity(0.22 + Double((index * 13) % 8) * 0.08)
            }
        }
    }
}

private struct RydrCityHeroBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    WelcomePalette.heroTop,
                    WelcomePalette.heroMid,
                    WelcomePalette.heroBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            CitySkyline()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.64, green: 0.66, blue: 0.72).opacity(0.35),
                            Color(red: 0.12, green: 0.13, blue: 0.18).opacity(0.16)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blur(radius: 1.2)
                .offset(y: 54)

            SpeedLines()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.02, blue: 0.19).opacity(0.0),
                            Color(red: 1.0, green: 0.02, blue: 0.19).opacity(0.86),
                            Color(red: 1.0, green: 0.55, blue: 0.64).opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .blur(radius: 0.7)
                .offset(y: 58)

            RoadGlow()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color(red: 1.0, green: 0.02, blue: 0.19).opacity(0.18),
                            WelcomePalette.background.opacity(0.95)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .offset(y: 118)

            SedanIllustration()
                .frame(width: 255, height: 150)
                .offset(x: 88, y: 248)
        }
        .clipped()
    }
}

private struct CitySkyline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let base = rect.maxY * 0.76
        let widths: [CGFloat] = [34, 52, 30, 44, 28, 56, 38, 46, 30, 62, 38, 46]
        var x = rect.minX - 28

        for (index, width) in widths.enumerated() {
            let height = CGFloat([148, 214, 108, 168, 84, 190, 124, 166, 96, 226, 132, 172][index])
            let top = base - height
            path.addRoundedRect(
                in: CGRect(x: x, y: top, width: width, height: height),
                cornerSize: CGSize(width: 2, height: 2)
            )

            let antennaX = x + width * 0.56
            path.move(to: CGPoint(x: antennaX, y: top))
            path.addLine(to: CGPoint(x: antennaX + 5, y: top - 18))

            x += width + CGFloat([18, 26, 16, 22][index % 4])
        }

        return path
    }
}

private struct SpeedLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let vanishing = CGPoint(x: rect.midX, y: rect.maxY * 0.58)

        for index in 0..<18 {
            let y = rect.maxY * (0.30 + CGFloat(index) * 0.030)
            let startsLeft = index % 2 == 0
            let startX = startsLeft ? rect.minX - 48 : rect.maxX + 48
            path.move(to: CGPoint(x: startX, y: y))
            path.addLine(to: CGPoint(x: vanishing.x + CGFloat(index - 9) * 3, y: vanishing.y))
        }

        for index in 0..<7 {
            let y = rect.maxY * (0.64 + CGFloat(index) * 0.028)
            path.move(to: CGPoint(x: rect.minX - 40, y: y))
            path.addLine(to: CGPoint(x: rect.maxX * 0.45, y: y - CGFloat(index) * 9))
        }

        return path
    }
}

private struct RoadGlow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.midY * 0.56))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.84))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY * 0.84))
        path.closeSubpath()
        return path
    }
}

private struct SedanIllustration: View {
    private let red = Color(red: 0.95, green: 0.02, blue: 0.19)

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 26, y: 96))
                path.addCurve(to: CGPoint(x: 78, y: 53), control1: CGPoint(x: 42, y: 68), control2: CGPoint(x: 58, y: 56))
                path.addCurve(to: CGPoint(x: 132, y: 42), control1: CGPoint(x: 96, y: 50), control2: CGPoint(x: 114, y: 43))
                path.addCurve(to: CGPoint(x: 224, y: 72), control1: CGPoint(x: 172, y: 39), control2: CGPoint(x: 205, y: 54))
                path.addCurve(to: CGPoint(x: 238, y: 108), control1: CGPoint(x: 236, y: 84), control2: CGPoint(x: 242, y: 96))
                path.addCurve(to: CGPoint(x: 178, y: 124), control1: CGPoint(x: 219, y: 121), control2: CGPoint(x: 198, y: 125))
                path.addLine(to: CGPoint(x: 54, y: 122))
                path.addCurve(to: CGPoint(x: 26, y: 96), control1: CGPoint(x: 42, y: 120), control2: CGPoint(x: 30, y: 111))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        Color.white,
                        Color(red: 0.78, green: 0.80, blue: 0.86),
                        Color(red: 0.18, green: 0.18, blue: 0.23)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: Color.black.opacity(0.26), radius: 12, x: 4, y: 9)

            Path { path in
                path.move(to: CGPoint(x: 80, y: 58))
                path.addCurve(to: CGPoint(x: 134, y: 48), control1: CGPoint(x: 96, y: 52), control2: CGPoint(x: 116, y: 49))
                path.addCurve(to: CGPoint(x: 182, y: 62), control1: CGPoint(x: 154, y: 48), control2: CGPoint(x: 169, y: 53))
                path.addLine(to: CGPoint(x: 154, y: 75))
                path.addLine(to: CGPoint(x: 92, y: 74))
                path.closeSubpath()
            }
            .fill(Color(red: 0.12, green: 0.13, blue: 0.18).opacity(0.78))

            RoundedRectangle(cornerRadius: 5)
                .fill(red)
                .frame(width: 78, height: 10)
                .offset(x: 68, y: 15)
                .shadow(color: red.opacity(0.55), radius: 8, x: -10, y: 0)

            RoundedRectangle(cornerRadius: 4)
                .fill(red.opacity(0.88))
                .frame(width: 34, height: 8)
                .offset(x: -92, y: 6)

            Circle()
                .fill(Color(red: 0.06, green: 0.06, blue: 0.08))
                .frame(width: 39, height: 39)
                .offset(x: -64, y: 45)
            Circle()
                .stroke(Color.white.opacity(0.45), lineWidth: 4)
                .frame(width: 24, height: 24)
                .offset(x: -64, y: 45)

            Circle()
                .fill(Color(red: 0.06, green: 0.06, blue: 0.08))
                .frame(width: 43, height: 43)
                .offset(x: 74, y: 44)
            Circle()
                .stroke(Color.white.opacity(0.45), lineWidth: 4)
                .frame(width: 26, height: 26)
                .offset(x: 74, y: 44)

            Text("R")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(red)
                .offset(x: 103, y: 6)
        }
        .opacity(0.96)
    }
}

private struct SpeedWordMark: View {
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(Color(red: 0.95, green: 0.02, blue: 0.19).opacity(0.95 - Double(index) * 0.08))
                    .frame(height: 4)
                    .padding(.leading, CGFloat(index) * 10)
            }
        }
    }
}

private struct BenefitBadge: View {
    let icon: String
    let accentIcon: String?
    let title: String
    let subtitle: String

    private let red = Color(red: 0.95, green: 0.02, blue: 0.19)

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(WelcomePalette.softRedFill)
                    .frame(width: 43, height: 43)
                    .shadow(color: red.opacity(0.20), radius: 14, x: 0, y: 8)

                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(red)
                    .frame(width: 43, height: 43)

                if accentIcon == "checkmark" {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .offset(x: -10, y: 14)
                } else if accentIcon == "stars" {
                    HStack(spacing: 1) {
                        ForEach(0..<3, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 6, weight: .black))
                                .foregroundStyle(red)
                        }
                    }
                    .offset(x: 4, y: -5)
                }
            }

            Text(title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(WelcomePalette.cardInk)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(subtitle)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(WelcomePalette.secondaryMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(-1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct WelcomeActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isPrimary: Bool

    private let red = Color(red: 0.95, green: 0.02, blue: 0.19)

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isPrimary ? Color.white.opacity(0.18) : WelcomePalette.softRedFill)
                    .frame(width: 64, height: 64)

                if icon == "stylizedR" {
                    Image("RydrLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 29, weight: .heavy))
                        .foregroundStyle(isPrimary ? .white : red)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(isPrimary ? Color.white : WelcomePalette.cardInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Text(subtitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(isPrimary ? Color.white.opacity(0.88) : WelcomePalette.secondaryMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(isPrimary ? Color.white : red)
        }
        .padding(.horizontal, 18)
        .frame(height: 78)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: isPrimary ? red.opacity(0.30) : Color.black.opacity(0.12), radius: 13, x: 0, y: 8)
        .overlay {
            if isPrimary {
                PrimaryCardSpeedTexture()
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isPrimary {
            LinearGradient(
                colors: [red, Color(red: 0.88, green: 0.00, blue: 0.18), Color(red: 0.72, green: 0.00, blue: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            WelcomePalette.cardFill
        }
    }
}

private struct PrimaryCardSpeedTexture: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                for index in 0..<22 {
                    let y = proxy.size.height * (0.18 + CGFloat(index) * 0.032)
                    path.move(to: CGPoint(x: proxy.size.width * 0.48, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width + 20, y: y + CGFloat(index % 3) * 2))
                }
            }
            .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct BottomSpeedRibbon: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.clear,
                    WelcomePalette.background.opacity(0.94),
                    WelcomePalette.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Path { path in
                path.move(to: CGPoint(x: -30, y: 74))
                path.addCurve(to: CGPoint(x: 150, y: 64), control1: CGPoint(x: 48, y: 20), control2: CGPoint(x: 94, y: 98))
                path.addCurve(to: CGPoint(x: 360, y: 54), control1: CGPoint(x: 238, y: 10), control2: CGPoint(x: 278, y: 92))
                path.addCurve(to: CGPoint(x: 540, y: 24), control1: CGPoint(x: 418, y: 18), control2: CGPoint(x: 468, y: 36))
            }
            .stroke(
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.02, blue: 0.19).opacity(0.75),
                        Color(red: 1.0, green: 0.55, blue: 0.63).opacity(0.35),
                        Color(red: 0.95, green: 0.02, blue: 0.19).opacity(0.85)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 14, lineCap: .round)
            )
            .blur(radius: 0.6)

            Path { path in
                path.move(to: CGPoint(x: -40, y: 104))
                path.addCurve(to: CGPoint(x: 180, y: 76), control1: CGPoint(x: 56, y: 46), control2: CGPoint(x: 112, y: 128))
                path.addCurve(to: CGPoint(x: 410, y: 70), control1: CGPoint(x: 260, y: 22), control2: CGPoint(x: 326, y: 108))
                path.addCurve(to: CGPoint(x: 560, y: 36), control1: CGPoint(x: 456, y: 46), control2: CGPoint(x: 506, y: 52))
            }
            .stroke(Color(red: 0.64, green: 0.00, blue: 0.13).opacity(0.24), lineWidth: 8)
        }
    }
}

#Preview {
    WelcomeView()
        .environmentObject(UserSessionManager())
}
