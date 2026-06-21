//
//  RideTypeSelectionView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/11/25.
//
import SwiftUI

struct RideTypeSelectionView: View {
    @Environment(\.colorScheme) private var colorScheme
    var userName: String = "Rydr User" // Replace with actual user data in future

    private let options: [RideTypeOption] = [
        .standard(
            title: "Rydr Go",
            badge: "Everyday",
            subtitle: "Standard Everyday Rides",
            icon: "car.fill",
            vehicle: .sedan
        ),
        .standard(
            title: "Rydr Eco",
            badge: "Eco-Friendly",
            subtitle: "Eco-Friendly EV Rides",
            icon: "leaf.fill",
            vehicle: .eco
        ),
        .standard(
            title: "Rydr XL",
            badge: "Spacious",
            subtitle: "Spacious SUV Rides",
            icon: "bus.fill",
            vehicle: .suv
        ),
        .prestine(
            title: "Rydr Prestine",
            badge: "Premium",
            subtitle: "Luxury Rides",
            icon: "sparkles",
            vehicle: .prestine
        ),
        .executive(
            title: "Rydr Executive",
            badge: "Luxury",
            subtitle: "Black Car Service Rides",
            icon: "briefcase.fill",
            vehicle: .executive
        ),
        .cashHub(
            title: "Cash Rydr Hub",
            badge: "Cash Rides",
            subtitle: "Cash Rides",
            icon: "banknote.fill",
            vehicle: .cash
        )
    ]

    var body: some View {
        ZStack {
            pageBackground
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header

                    VStack(spacing: 14) {
                        ForEach(options) { option in
                            if option.kind == .cashHub {
                                NavigationLink(destination: CashRydrHubView()) {
                                    RideOptionCard(option: option)
                                }
                                .buttonStyle(.plain)
                            } else {
                                let pricing = RideManager.pricingConfig(for: option.title)
                                NavigationLink(destination: BookingView(rideType: pricing.title, userName: userName)) {
                                    RideOptionCard(option: option)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var pageBackground: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.055, green: 0.045, blue: 0.05),
                    Color(red: 0.10, green: 0.035, blue: 0.045)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [
                Color.white,
                Color(red: 0.995, green: 0.985, blue: 0.988),
                Color(red: 1.0, green: 0.95, blue: 0.955)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Choose Your")
                        .foregroundColor(colorScheme == .dark ? .white : Color(red: 0.05, green: 0.08, blue: 0.14))
                    Text("Ride")
                        .foregroundStyle(Styles.rydrGradient)
                }
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.82)

                Text("Find the perfect ride for your needs.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.headline.weight(.bold))
                        .foregroundColor(colorScheme == .dark ? .white : Color(red: 0.05, green: 0.08, blue: 0.14))
                        .frame(width: 48, height: 48)
                        .background(Color(.secondarySystemGroupedBackground).opacity(0.94))
                        .clipShape(Circle())
                        .shadow(color: Color.red.opacity(0.10), radius: 16, x: 0, y: 8)

                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                        .offset(x: -9, y: 9)
                }
            }
            .accessibilityLabel("Notifications")
        }
        .padding(.top, 4)
    }
}

private struct RideTypeOption: Identifiable {
    enum Kind {
        case standard
        case prestine
        case executive
        case cashHub
    }

    let id = UUID()
    let title: String
    let badge: String
    let subtitle: String
    let icon: String
    let vehicle: RideVehicleStyle
    let kind: Kind

    static func standard(title: String, badge: String, subtitle: String, icon: String, vehicle: RideVehicleStyle) -> RideTypeOption {
        RideTypeOption(title: title, badge: badge, subtitle: subtitle, icon: icon, vehicle: vehicle, kind: .standard)
    }

    static func prestine(title: String, badge: String, subtitle: String, icon: String, vehicle: RideVehicleStyle) -> RideTypeOption {
        RideTypeOption(title: title, badge: badge, subtitle: subtitle, icon: icon, vehicle: vehicle, kind: .prestine)
    }

    static func executive(title: String, badge: String, subtitle: String, icon: String, vehicle: RideVehicleStyle) -> RideTypeOption {
        RideTypeOption(title: title, badge: badge, subtitle: subtitle, icon: icon, vehicle: vehicle, kind: .executive)
    }

    static func cashHub(title: String, badge: String, subtitle: String, icon: String, vehicle: RideVehicleStyle) -> RideTypeOption {
        RideTypeOption(title: title, badge: badge, subtitle: subtitle, icon: icon, vehicle: vehicle, kind: .cashHub)
    }
}

private struct RideOptionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let option: RideTypeOption

    private var isExecutive: Bool { option.kind == .executive }
    private var isPrestine: Bool { option.kind == .prestine }
    private var darkMode: Bool { colorScheme == .dark }
    private var executiveGold: Color { Color(red: 0.96, green: 0.73, blue: 0.32) }

    var body: some View {
        HStack(spacing: 15) {
            RideVehicleArt(style: option.vehicle, kind: option.kind)
                .frame(width: 78, height: 78)

            VStack(alignment: .leading, spacing: 6) {
                Text(option.title)
                    .font(.title3.weight(.heavy))
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(option.subtitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(subtitleColor)
                    .lineLimit(1)

                Text(option.badge)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(badgeForeground)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(badgeBackground)
                    .clipShape(Capsule())
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.headline.weight(.bold))
                .foregroundStyle(chevronForeground)
                .frame(width: 38, height: 38)
                .background(chevronBackground)
                .clipShape(Circle())
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardBorder)
        .shadow(color: shadowColor, radius: 16, x: 0, y: 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(option.title), \(option.badge). \(option.subtitle)")
    }

    private var cardBackground: some View {
        Group {
            if isExecutive {
                if darkMode {
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.80, blue: 0.36),
                            Color(red: 0.90, green: 0.63, blue: 0.20),
                            Color(red: 0.70, green: 0.45, blue: 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    LinearGradient(
                        colors: [
                            Color(red: 0.02, green: 0.02, blue: 0.025),
                            Color(red: 0.10, green: 0.085, blue: 0.045),
                            Color.black
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            } else {
                Color(.secondarySystemGroupedBackground).opacity(darkMode ? 0.94 : 0.96)
            }
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(
                isExecutive
                ? LinearGradient(colors: [darkMode ? Color.black.opacity(0.72) : executiveGold, Color.white.opacity(darkMode ? 0.32 : 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                : LinearGradient(colors: [Color.white.opacity(darkMode ? 0.14 : 0.9), Color.red.opacity(isPrestine ? 0.22 : 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: isExecutive ? 1.2 : 1
            )
    }

    private var titleColor: Color {
        if isExecutive {
            return darkMode ? .black : .white
        }
        return darkMode ? .white : Color(red: 0.05, green: 0.08, blue: 0.14)
    }

    private var subtitleColor: Color {
        if isExecutive {
            return darkMode ? Color.black.opacity(0.72) : Color.white.opacity(0.86)
        }
        return darkMode ? Color.white.opacity(0.72) : Color(red: 0.33, green: 0.35, blue: 0.43)
    }

    private var badgeForeground: some ShapeStyle {
        if isExecutive {
            return AnyShapeStyle(darkMode ? Color.black : executiveGold)
        }
        if isPrestine {
            return AnyShapeStyle(LinearGradient(colors: [Color.red, Color(red: 0.93, green: 0.68, blue: 0.22)], startPoint: .leading, endPoint: .trailing))
        }
        return AnyShapeStyle(Styles.rydrGradient)
    }

    private var badgeBackground: some ShapeStyle {
        if isExecutive {
            return AnyShapeStyle(darkMode ? Color.black.opacity(0.12) : executiveGold.opacity(0.16))
        }
        if isPrestine {
            return AnyShapeStyle(Color(red: 0.96, green: 0.72, blue: 0.28).opacity(0.16))
        }
        return AnyShapeStyle(Color.red.opacity(0.09))
    }

    private var chevronForeground: some ShapeStyle {
        if isExecutive {
            return AnyShapeStyle(darkMode ? Color.black : executiveGold)
        }
        if isPrestine {
            return AnyShapeStyle(LinearGradient(colors: [Color.red, Color(red: 0.93, green: 0.68, blue: 0.22)], startPoint: .leading, endPoint: .trailing))
        }
        return AnyShapeStyle(Styles.rydrGradient)
    }

    private var chevronBackground: some ShapeStyle {
        if isExecutive {
            return AnyShapeStyle(darkMode ? Color.black.opacity(0.14) : executiveGold.opacity(0.14))
        }
        return AnyShapeStyle(Color.red.opacity(0.08))
    }

    private var shadowColor: Color {
        isExecutive ? Color.black.opacity(0.20) : Color.red.opacity(0.08)
    }
}

private enum RideVehicleStyle {
    case sedan
    case eco
    case suv
    case prestine
    case executive
    case cash
}

private struct RideVehicleArt: View {
    let style: RideVehicleStyle
    let kind: RideTypeOption.Kind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tileBackground)

            decorativeBackdrop

            Image(assetName)
                .resizable()
                .scaledToFit()
                .padding(.horizontal, style == .cash ? 3 : 1)
                .padding(.vertical, style == .executive ? 3 : 6)
                .offset(y: style == .cash ? 4 : 6)

            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(iconStyle)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(kind == .executive ? 0.16 : 0.82))
                .clipShape(Circle())
                .offset(x: -29, y: -29)
        }
        .accessibilityHidden(true)
    }

    private var tileBackground: some ShapeStyle {
        switch kind {
        case .executive:
            return AnyShapeStyle(LinearGradient(colors: [Color.black, Color(red: 0.23, green: 0.18, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .prestine:
            return AnyShapeStyle(LinearGradient(colors: [Color.red.opacity(0.10), Color(red: 0.98, green: 0.78, blue: 0.36).opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .cashHub:
            return AnyShapeStyle(LinearGradient(colors: [Color.red.opacity(0.12), Color.white], startPoint: .topLeading, endPoint: .bottomTrailing))
        default:
            return AnyShapeStyle(LinearGradient(colors: [Color.red.opacity(0.09), Color.white], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private var icon: String {
        switch style {
        case .sedan: return "car.fill"
        case .eco: return "leaf.fill"
        case .suv: return "bus.fill"
        case .prestine: return "sparkles"
        case .executive: return "briefcase.fill"
        case .cash: return "banknote.fill"
        }
    }

    private var assetName: String {
        switch style {
        case .sedan: return "RydrGoVehicle"
        case .eco: return "RydrEcoVehicle"
        case .suv: return "RydrXLVehicle"
        case .prestine: return "RydrPrestineVehicle"
        case .executive: return "RydrExecutiveVehicle"
        case .cash: return "CashRydrFleet"
        }
    }

    private var iconStyle: some ShapeStyle {
        if kind == .executive {
            return AnyShapeStyle(Color(red: 0.98, green: 0.80, blue: 0.42))
        }
        if kind == .prestine {
            return AnyShapeStyle(LinearGradient(colors: [Color.red, Color(red: 0.93, green: 0.68, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return AnyShapeStyle(Styles.rydrGradient)
    }

    private var decorativeBackdrop: some View {
        ZStack {
            Circle()
                .fill(backdropColor.opacity(0.20))
                .frame(width: 72, height: 72)
                .offset(x: 20, y: -18)
            Circle()
                .fill(backdropColor.opacity(0.10))
                .frame(width: 54, height: 54)
                .offset(x: -24, y: 22)
        }
    }

    private var backdropColor: Color {
        switch kind {
        case .executive: return Color(red: 0.98, green: 0.80, blue: 0.42)
        case .prestine: return Color(red: 0.95, green: 0.66, blue: 0.20)
        default: return .red
        }
    }
}

#Preview {
    NavigationStack {
        RideTypeSelectionView()
    }
}
