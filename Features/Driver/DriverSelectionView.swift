//
//  DriverSelectionView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/21/25.
//
import SwiftUI
import MapKit

struct DriverSelectionView: View {
    @ObservedObject var rideManager: RideManager

    let rideType: String
    let pickup: String
    let dropoff: String
    let region: MKCoordinateRegion
    let estimate: RideEstimate
    let onAccepted: () -> Void
    let onClose: () -> Void

    // UI state
    @State private var showConnecting = false
    @State private var showUnavailableBanner = false

    // RydrBank reservations cover the eligible ride, so cards show FREE once applied.
    private var promoApplied: Bool {
        let code = UserDefaults.standard.string(forKey: "appliedRydrBankCode") ?? ""
        return !code.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Capsule()
                        .fill(Color.black.opacity(0.12))
                        .frame(width: 44, height: 5)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                    HStack(spacing: 8) {
                        Image(systemName: "hand.draw.fill")
                            .foregroundStyle(Styles.rydrGradient)
                        Text("Swipe")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Styles.rydrGradient)
                        Text("to view nearby drivers")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    if rideManager.isLoadingDrivers {
                        TabView {
                            ForEach(0..<rideManager.driverSearchTargetCount, id: \.self) { index in
                                if index < rideManager.availableDrivers.count {
                                    let driver = rideManager.availableDrivers[index]
                                    DriverCard(
                                        rideManager: rideManager,
                                        driver: driver,
                                        rideType: rideType,
                                        estimate: estimate,
                                        promoAppliedDevFree: promoApplied
                                    ) {
                                        confirm(driver)
                                    }
                                    .padding(.horizontal)
                                } else {
                                    DriverMatchmakingCard(slotNumber: index + 1)
                                        .padding(.horizontal)
                                }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .automatic))
                        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                    } else if rideManager.availableDrivers.isEmpty {
                        EmptyDriverState(message: rideManager.rideRequestErrorMessage ?? "No nearby drivers are available right now.") {
                            rideManager.requestDrivers(
                                pickup: pickup,
                                dropoff: dropoff,
                                rideType: rideType,
                                near: region.center,
                                estimate: estimate
                            )
                        }
                        .padding(.horizontal)
                    } else {
                        // Paged cards with dots
                        TabView {
                            ForEach(rideManager.availableDrivers) { d in
                                DriverCard(
                                    rideManager: rideManager,
                                    driver: d,
                                    rideType: rideType,
                                    estimate: estimate,
                                    promoAppliedDevFree: promoApplied
                                ) {
                                    confirm(d)   // ← show overlay, wait for accept/decline
                                }
                                .padding(.horizontal)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .automatic))
                        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                    }
                }

                // Decline banner
                if showUnavailableBanner {
                    UnavailableBanner(text: "Looks like the driver isn’t available. Let’s find you another driver!")
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Nearby Drivers")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                    }
                }
            }
        }
        // React to RideManager state to drive overlay + transitions
        .onChange(of: rideManager.state, initial: false) { _, newState in
            switch newState {
            case .awaitingDriver:
                withAnimation { showConnecting = true }
            case .inProgress:
                withAnimation { showConnecting = false }
                onAccepted() // navigate/present RideInProgressView from parent
            case .selecting:
                // If we were connecting and bounced back, show banner
                if showConnecting {
                    withAnimation { showUnavailableBanner = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation { showUnavailableBanner = false }
                    }
                }
                showConnecting = false
            default:
                break
            }
        }
        // Full-screen connecting animation while we wait
        .fullScreenCover(isPresented: $showConnecting) {
            ConnectingOverlay(
                title: "Connecting with \(rideManager.selectedDriver?.name ?? "driver")…",
                subtitle: "Confirming your ride request"
            )
            .ignoresSafeArea()
        }
    }

    private func confirm(_ driver: Driver) {
        rideManager.confirm(driver: driver)
        // state change to .awaitingDriver will trigger overlay via onChange
    }
}

private struct DriverMatchmakingCard: View {
    let slotNumber: Int

    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Match \(slotNumber)", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Styles.rydrGradient)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.red.opacity(0.08)))
                Spacer()
                ProgressView()
                    .tint(.red)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Finding a nearby driver")
                    .font(.title3.weight(.black))
                Text("Checking availability, ride type, distance, and driver filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.red.opacity(0.10), Color(.secondarySystemGroupedBackground)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 14) {
                    RydrPulseIndicator(size: 96, markSize: 24, ringWidth: 8)

                    Text("Matchmaking")
                        .font(.headline.weight(.black))
                    Text("This spot will become a driver card when a match is ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(22)
            }
            .frame(height: 190)

            VStack(spacing: 10) {
                skeletonLine(width: 220, height: 13)
                skeletonLine(width: 170, height: 11)
                HStack {
                    skeletonPill()
                    skeletonPill()
                    skeletonPill()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 430, alignment: .topLeading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 20, y: 10)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }

    private func skeletonLine(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(Color.gray.opacity(shimmer ? 0.22 : 0.11))
            .frame(width: width, height: height)
    }

    private func skeletonPill() -> some View {
        Capsule()
            .fill(Color.gray.opacity(shimmer ? 0.18 : 0.10))
            .frame(maxWidth: .infinity)
            .frame(height: 34)
    }
}

private struct RydrPulseIndicator: View {
    let size: CGFloat
    let markSize: CGFloat
    let ringWidth: CGFloat

    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.red.opacity(0.12), lineWidth: ringWidth)
                .frame(width: size, height: size)
                .scaleEffect(pulse ? 1.10 : 0.94)
                .opacity(pulse ? 0.35 : 0.18)

            Circle()
                .trim(from: 0.08, to: 0.78)
                .stroke(Styles.rydrGradient, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .scaleEffect(pulse ? 1.02 : 0.96)
                .shadow(color: Color.red.opacity(0.24), radius: 10, y: 0)

            Circle()
                .fill(Color(.systemBackground))
                .frame(width: markSize + 14, height: markSize + 14)
                .shadow(color: Color.red.opacity(0.14), radius: 8, y: 2)

            Image("RydrBankWalletR")
                .resizable()
                .scaledToFit()
                .frame(width: markSize, height: markSize)
                .scaleEffect(pulse ? 1.0 : 0.82)
        }
        .accessibilityLabel("Rydr is connecting")
        .onAppear {
            spin = true
            pulse = true
        }
        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: spin)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
    }
}

private struct DriverCard: View {
    @ObservedObject var rideManager: RideManager
    let driver: Driver
    let rideType: String
    let estimate: RideEstimate
    let promoAppliedDevFree: Bool
    let onConfirm: () -> Void

    @State private var isFavorite = false

    private var fareBreakdown: RideFareBreakdown {
        RideManager.fareBreakdown(estimate: estimate, with: driver, rideType: rideType)
    }

    private var baseFare: Double {
        fareBreakdown.finalRiderTotal
    }

    private var distanceText: String {
        String(format: "%.1f mi", estimate.distanceMiles)
    }

    private var finalFare: Double {
        // Show FREE when any promo is present during testing;
        // otherwise honor RideManager’s applyPromo for %/cap logic.
        if promoAppliedDevFree { return 0 }
        return rideManager.applyPromo(to: baseFare)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                rideBadge
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        isFavorite.toggle()
                    }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(isFavorite ? Color.red : .primary)
                        .frame(width: 42, height: 42)
                        .background(Color(.systemBackground), in: Circle())
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "Remove favorite driver" : "Favorite driver")
            }

            driverHeader

            vehicleHero

            HStack(spacing: 0) {
                driverMetric(systemName: "mappin.circle.fill", value: distanceText, label: "away")
                Divider().frame(height: 30)
                driverMetric(systemName: "timer", value: "\(Int(estimate.durationMinutes)) min", label: "arrival")
                Divider().frame(height: 30)
                driverMetric(systemName: "person.badge.shield.checkmark.fill", value: "\(acceptanceRate)%", label: "accept rate")
            }
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(displayCompliments, id: \.self) { c in
                        complimentChip(c)
                    }
                }
            }

            if fareBreakdown.minimumFareAdjustment > 0 {
                HStack {
                    Text("Minimum fare adjustment")
                    Spacer()
                    Text("$\(fareBreakdown.minimumFareAdjustment, specifier: "%.2f")")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button(action: onConfirm) {
                Text("Confirm \(rideTypeDisplay) with \(driver.name)")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RydrGradientButton())
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 20, y: 10)
    }

    private var driverAvatar: some View {
        Group {
            if let imgName = driver.profileImage, !imgName.isEmpty, UIImage(named: imgName) != nil {
                Image(imgName)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(Text(String(driver.name.prefix(1))).font(.title3.weight(.black)))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(Circle().stroke(Styles.rydrGradient, lineWidth: 3))
    }

    private var driverHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            driverAvatar
            driverIdentity
            Spacer()
            fareBadge
        }
    }

    private var driverIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(driver.name)
                    .font(.title3.weight(.black))
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(Color.blue)
            }
            HStack(spacing: 5) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                Text(String(format: "%.1f", driver.rating))
                    .font(.subheadline.weight(.semibold))
                Text("(\(tripCountText) trips)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(driver.carMakeModel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var fareBadge: some View {
        VStack(alignment: .trailing, spacing: 6) {
            fareText
            Text(rideTypeDisplay)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Styles.rydrGradient)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.red.opacity(0.08)))
        }
    }

    @ViewBuilder
    private var fareText: some View {
        if finalFare < baseFare - 0.009 {
            Text("$\(baseFare, specifier: "%.2f")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .strikethrough()
            Text(finalFare == 0 ? "FREE" : "$\(finalFare, specifier: "%.2f")")
                .font(.headline.weight(.black))
        } else {
            Text("$\(baseFare, specifier: "%.2f")")
                .font(.headline.weight(.black))
        }
    }

    private var vehicleHero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(vehicleBackground)

            vehicleImage
                .frame(maxWidth: .infinity)
                .frame(height: 176)

            HStack(spacing: 6) {
                Image(systemName: vehicleFeatureIcon)
                Text(vehicleFeatureText)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.72)))
            .padding(10)

            Button {} label: {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(Color(.systemBackground), in: Circle())
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(10)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var vehicleImage: some View {
        VehicleOrDriverImage(source: driver.carImage, contentMode: .fit) {
            Image(defaultVehicleAssetName)
                .resizable()
                .scaledToFit()
        }
        .padding(.horizontal, 12)
    }

    private var rideBadge: some View {
        Label(rideTypeDisplay, systemImage: rideBadgeIcon)
            .font(.caption.weight(.bold))
            .foregroundStyle(rideAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(rideAccent.opacity(0.12)))
    }

    private func driverMetric(systemName: String, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Styles.rydrGradient)
            Text(value)
                .font(.subheadline.weight(.black))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func complimentChip(_ text: String) -> some View {
        Label(text, systemImage: complimentIcon(for: text))
            .font(.caption.weight(.semibold))
            .foregroundStyle(complimentTint(for: text))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(complimentTint(for: text).opacity(0.10)))
    }

    private var rideTypeDisplay: String {
        switch rideType.lowercased() {
        case "go":        return "Rydr Go"
        case "eco":       return "Rydr Eco"
        case "xl":        return "Rydr XL"
        case "prestine":  return "Rydr Prestine"
        default:          return rideType
        }
    }

    private var defaultVehicleAssetName: String {
        let lower = rideTypeDisplay.lowercased()
        if lower.contains("eco") { return "RydrEcoVehicle" }
        if lower.contains("xl") { return "RydrXLVehicle" }
        if lower.contains("executive") { return "RydrExecutiveVehicle" }
        if lower.contains("prestine") { return "RydrPrestineVehicle" }
        return "RydrGoVehicle"
    }

    private var rideAccent: Color {
        let lower = rideTypeDisplay.lowercased()
        if lower.contains("xl") { return .purple }
        if lower.contains("eco") { return .green }
        if lower.contains("executive") { return .black }
        return .red
    }

    private var vehicleBackground: LinearGradient {
        let lower = rideTypeDisplay.lowercased()
        if lower.contains("xl") {
            return LinearGradient(colors: [Color.purple.opacity(0.12), Color.white], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if lower.contains("eco") {
            return LinearGradient(colors: [Color.green.opacity(0.12), Color.white], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        if lower.contains("executive") {
            return LinearGradient(colors: [Color.black.opacity(0.16), Color.yellow.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [Color.red.opacity(0.12), Color.white], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var rideBadgeIcon: String {
        let lower = rideTypeDisplay.lowercased()
        if lower.contains("eco") { return "leaf.fill" }
        if lower.contains("xl") { return "car.2.fill" }
        if lower.contains("executive") { return "briefcase.fill" }
        if lower.contains("prestine") { return "sparkles" }
        return "car.fill"
    }

    private var vehicleFeatureIcon: String {
        rideTypeDisplay.lowercased().contains("eco") ? "bolt.fill" : "sparkles"
    }

    private var vehicleFeatureText: String {
        let lower = rideTypeDisplay.lowercased()
        if lower.contains("eco") { return "100% Electric" }
        if lower.contains("xl") { return "Spacious" }
        if lower.contains("executive") { return "Premium SUV" }
        if lower.contains("prestine") { return "Premium" }
        return "Verified Vehicle"
    }

    private var displayCompliments: [String] {
        let base = driver.compliments.isEmpty ? ["Great Navigation", "Clean Car", "Friendly"] : driver.compliments
        return Array(base.prefix(4))
    }

    private var tripCountText: String {
        let seed = abs(driver.id.hashValue % 900) + 100
        return "\(seed)"
    }

    private var acceptanceRate: Int {
        92 + abs(driver.id.hashValue % 8)
    }

    private func complimentIcon(for text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("clean") { return "sparkles" }
        if lower.contains("navigation") { return "location.north.fill" }
        if lower.contains("friendly") { return "face.smiling" }
        if lower.contains("review") { return "star.fill" }
        return "checkmark.seal.fill"
    }

    private func complimentTint(for text: String) -> Color {
        let lower = text.lowercased()
        if lower.contains("clean") { return .green }
        if lower.contains("friendly") { return .orange }
        if lower.contains("navigation") { return .blue }
        return .purple
    }
}

// MARK: - Helpers

private struct RydrGradientButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 14)
            .background(Styles.rydrGradient)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct ConnectingOverlay: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 22) {
                RydrPulseIndicator(size: 120, markSize: 28, ringWidth: 10)

                VStack(spacing: 6) {
                    Text(title).font(.title3).bold()
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("This usually takes only a moment…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
            .padding()
        }
    }
}

private struct UnavailableBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Styles.rydrGradient)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }
}

private struct EmptyDriverState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "car.2")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("For testing, this keeps the ride request from looking stuck when no driver is available or the mock service fails.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: onRetry)
                .buttonStyle(RydrGradientButton())
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06), lineWidth: 1))
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let p = pow(10.0, Double(places))
        return (self * p).rounded() / p
    }
}
