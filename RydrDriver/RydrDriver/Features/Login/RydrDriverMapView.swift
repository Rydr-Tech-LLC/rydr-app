import SwiftUI
import MapKit
import CoreLocation

struct RydrDriverMapView: View {
    @Binding var position: MapCameraPosition

    let driverCoordinate: CLLocationCoordinate2D?
    let isOnline: Bool
    let pendingRequests: [DriverRideRadarBlip]
    let onRecenter: () -> Void

    var body: some View {
        Map(position: $position, interactionModes: [.all]) {
            if let driverCoordinate {
                Annotation("", coordinate: driverCoordinate, anchor: .center) {
                    DriverLocationDot(isOnline: isOnline)
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
