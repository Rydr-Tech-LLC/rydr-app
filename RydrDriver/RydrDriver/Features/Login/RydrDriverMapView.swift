import SwiftUI
import MapKit
import CoreLocation

struct RydrDriverMapView: View {
    @Binding var position: MapCameraPosition
    @Binding var filterPreferences: DriverRideFilterPreferences

    let driverCoordinate: CLLocationCoordinate2D?
    let isOnline: Bool
    let pendingRequests: [DriverRideRadarBlip]
    let onRecenter: () -> Void

    var body: some View {
        Map(position: $position, interactionModes: [.all]) {
            if let driverCoordinate, filterPreferences.workZoneEnabled {
                MapCircle(center: driverCoordinate, radius: filterPreferences.effectivePickupMiles * 1609.344)
                    .foregroundStyle(Color.red.opacity(0.13))
                MapCircle(center: driverCoordinate, radius: filterPreferences.effectivePickupMiles * 1609.344)
                    .stroke(Styles.rydrGradient, lineWidth: 3)
            }

            if let driverCoordinate, filterPreferences.hasDestinationFilter, let destination = filterPreferences.destinationCoordinate {
                MapPolyline(coordinates: [driverCoordinate, destination])
                    .stroke(Color.red.opacity(0.15), style: StrokeStyle(lineWidth: 34, lineCap: .round, lineJoin: .round, dash: [8, 8]))
                MapPolyline(coordinates: [driverCoordinate, destination])
                    .stroke(Styles.rydrGradient, lineWidth: 6)

                Annotation("", coordinate: destination, anchor: .bottom) {
                    DestinationModePin(corridorMiles: filterPreferences.destinationCorridor.miles)
                }
            }

            if let driverCoordinate {
                Annotation("", coordinate: driverCoordinate, anchor: .center) {
                    DriverLocationDot(isOnline: isOnline)
                }

                if filterPreferences.workZoneEnabled {
                    Annotation("Work Zone", coordinate: driverCoordinate, anchor: .top) {
                        WorkZoneCenterLabel()
                    }

                    Annotation("", coordinate: workZoneHandleCoordinate(from: driverCoordinate), anchor: .center) {
                        WorkZoneRadiusHandle(miles: filterPreferences.effectivePickupMiles)
                    }
                }
            }

            ForEach(pendingRequests.filter { !$0.isExpired }) { blip in
                Annotation("Ride request nearby", coordinate: blip.coordinate, anchor: .center) {
                    RiderRequestBlip()
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .ignoresSafeArea()
        .overlay(alignment: .trailing) {
            FloatingCircleButton(systemName: "location.magnifyingglass", action: onRecenter)
                .padding(.trailing, 18)
                .padding(.bottom, 360)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .overlay(alignment: .bottom) {
            if filterPreferences.workZoneEnabled {
                WorkZoneRadiusAdjuster(
                    miles: Binding(
                        get: { filterPreferences.effectivePickupMiles },
                        set: { setWorkZoneMiles($0) }
                    ),
                    onStep: { stepWorkZone(by: $0) }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 286)
            }
        }
        .simultaneousGesture(
            MagnificationGesture()
                .onEnded { scale in
                    guard filterPreferences.workZoneEnabled else { return }
                    if scale > 1.08 {
                        stepWorkZone(by: DriverRideFilterPreferences.workZoneStepMiles)
                    } else if scale < 0.92 {
                        stepWorkZone(by: -DriverRideFilterPreferences.workZoneStepMiles)
                    }
                }
        )
    }

    private func workZoneHandleCoordinate(from center: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let miles = filterPreferences.effectivePickupMiles
        let longitudeOffset = miles / max(1, 69.0 * cos(center.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude + longitudeOffset)
    }

    private func stepWorkZone(by delta: Double) {
        setWorkZoneMiles(filterPreferences.effectivePickupMiles + delta)
    }

    private func setWorkZoneMiles(_ miles: Double) {
        let minMiles = DriverRideFilterPreferences.minimumWorkZoneMiles
        let maxMiles = DriverRideFilterPreferences.maximumWorkZoneMiles
        let step = DriverRideFilterPreferences.workZoneStepMiles
        let clamped = min(max(miles, minMiles), maxMiles)
        let snapped = (clamped / step).rounded() * step

        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            filterPreferences.workZoneEnabled = true
            filterPreferences.customPickupMiles = snapped
            switch snapped {
            case DriverWorkRadius.small.defaultMiles:
                filterPreferences.pickupRadius = .small
            case DriverWorkRadius.medium.defaultMiles:
                filterPreferences.pickupRadius = .medium
            case DriverWorkRadius.large.defaultMiles:
                filterPreferences.pickupRadius = .large
            default:
                filterPreferences.pickupRadius = .custom
            }
        }
    }
}

private struct WorkZoneRadiusAdjuster: View {
    @Binding var miles: Double
    var onStep: (Double) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onStep(-DriverRideFilterPreferences.workZoneStepMiles)
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.black))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Work Zone")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white.opacity(0.68))
                    Spacer()
                    Text("\(Int(miles.rounded())) mi")
                        .font(.caption.weight(.black))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Styles.rydrGradient))
                        .foregroundStyle(.white)
                }

                Slider(
                    value: $miles,
                    in: DriverRideFilterPreferences.minimumWorkZoneMiles...DriverRideFilterPreferences.maximumWorkZoneMiles,
                    step: DriverRideFilterPreferences.workZoneStepMiles
                )
                .tint(.red)
            }

            Button {
                onStep(DriverRideFilterPreferences.workZoneStepMiles)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.black))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
        )
        .foregroundStyle(.white)
        .shadow(color: Color.red.opacity(0.20), radius: 16, y: 8)
    }
}

private struct WorkZoneCenterLabel: View {
    var body: some View {
        Text("Work Zone")
            .font(.caption2.weight(.black))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.regularMaterial))
            .foregroundStyle(.primary)
            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
            .offset(y: -52)
    }
}

private struct WorkZoneRadiusHandle: View {
    let miles: Double

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.left")
            Image(systemName: "chevron.right")
        }
        .font(.caption2.weight(.black))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Capsule().fill(Styles.rydrGradient))
        .overlay(Capsule().stroke(Color.white.opacity(0.8), lineWidth: 1))
        .shadow(color: Color.red.opacity(0.38), radius: 10, y: 4)
        .accessibilityLabel("Work zone radius \(Int(miles.rounded())) miles")
    }
}

private struct DestinationModePin: View {
    let corridorMiles: Double

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "airplane.departure")
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Styles.rydrGradient))
                .overlay(Circle().stroke(Color.white.opacity(0.72), lineWidth: 2))
                .shadow(color: Color.red.opacity(0.38), radius: 12, y: 5)

            Text("\(Int(corridorMiles)) mi corridor")
                .font(.caption2.weight(.black))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(.regularMaterial))
        }
        .accessibilityLabel("Destination corridor")
    }
}

struct DriverLocationDot: View {
    let isOnline: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Styles.rydrGradient)
                .frame(width: 22, height: 22)
                .shadow(color: Color.red.opacity(0.36), radius: 10, y: 4)
            Circle()
                .stroke(Color.white, lineWidth: 3)
                .frame(width: 22, height: 22)
            if isOnline {
                Circle()
                    .stroke(Styles.rydrGradient, lineWidth: 2)
                    .frame(width: 34, height: 34)
                    .opacity(0.55)
            }
        }
        .accessibilityLabel("Current driver location")
    }
}

struct RiderRequestBlip: View {
    @State private var pulse = false
    @State private var sweep: Double = 0

    var body: some View {
        ZStack {
            ForEach([28.0, 48.0, 70.0], id: \.self) { size in
                Circle()
                    .stroke(Color.red.opacity(pulse ? 0.06 : 0.30), lineWidth: 2)
                    .frame(width: size, height: size)
                    .scaleEffect(pulse ? 1.22 : 0.86)
            }

            Circle()
                .fill(Color.red.opacity(0.78))
                .frame(width: 18, height: 18)
                .shadow(color: Color.red.opacity(0.45), radius: 12)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color.red.opacity(0.08), Color.red.opacity(0.38)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 28, height: 2)
                .offset(x: 14)
                .rotationEffect(.degrees(sweep))

            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        }
        .frame(width: 78, height: 78)
        .accessibilityLabel("Ride activity nearby")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                sweep = 360
            }
        }
    }
}

struct OnlineSearchIndicator: View {
    @State private var sweepDegrees: Double = -35
    @State private var ping = false

    var body: some View {
        HStack(spacing: 12) {
            SonarBlipView(sweepDegrees: sweepDegrees, ping: ping)

            VStack(alignment: .leading, spacing: 2) {
                Text("Standby")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.primary)
                Text("Scanning for nearby rides")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().stroke(Styles.rydrGradient.opacity(0.42), lineWidth: 1))
        )
        .shadow(color: Color.red.opacity(0.16), radius: 14, y: 6)
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                sweepDegrees = 325
            }
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                ping = true
            }
        }
    }
}

struct SonarBlipView: View {
    let sweepDegrees: Double
    let ping: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.82))
                .frame(width: 44, height: 44)

            ForEach([18.0, 30.0, 42.0], id: \.self) { size in
                Circle()
                    .stroke(Styles.rydrGradient.opacity(size == 42 ? 0.38 : 0.24), lineWidth: 1)
                    .frame(width: size, height: size)
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color.red.opacity(0.10), Color.red.opacity(0.72)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 20, height: 2)
                .offset(x: 10)
                .rotationEffect(.degrees(sweepDegrees))

            Circle()
                .fill(Styles.rydrGradient)
                .frame(width: 7, height: 7)
                .shadow(color: Color.red.opacity(0.5), radius: 6)

            Circle()
                .fill(Color.red.opacity(ping ? 0.95 : 0.26))
                .frame(width: 5, height: 5)
                .offset(x: 10, y: -8)

            Circle()
                .fill(Color.red.opacity(ping ? 0.32 : 0.86))
                .frame(width: 4, height: 4)
                .offset(x: -12, y: 7)
        }
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)
    }
}
