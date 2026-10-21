import SwiftUI
import MapKit
import CoreLocation

struct RydrDriverNavigationMapView: View {
    @Binding var position: MapCameraPosition

    let driverCoordinate: CLLocationCoordinate2D?
    let pickupCoordinate: CLLocationCoordinate2D?
    let dropoffCoordinate: CLLocationCoordinate2D?
    let routeCoordinates: [CLLocationCoordinate2D]
    let isPickupStage: Bool
    let heading: CLLocationDirection
    let onRecenter: () -> Void

    @State private var visibleCameraHeading: Double = 0
    @State private var displayedDriverCoordinate: CLLocationCoordinate2D?
    @State private var markerAnimationTask: Task<Void, Never>?

    private var renderedRouteCoordinates: [CLLocationCoordinate2D] { routeCoordinates }

    private var snappedDriverCoordinate: CLLocationCoordinate2D? {
        driverCoordinate.map { NavigationRouteGeometry.snapped($0, path: routeCoordinates) }
    }

    private var driverCoordinateSignature: String {
        guard let coordinate = snappedDriverCoordinate else { return "none" }
        return String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)
    }

    var body: some View {
        Map(position: $position, interactionModes: [.all]) {
            if renderedRouteCoordinates.count > 1 {
                // Soft contact shadow beneath the route so it reads as sitting on the
                // road surface rather than floating above it.
                MapPolyline(coordinates: renderedRouteCoordinates)
                    .stroke(
                        Color.black.opacity(0.24),
                        style: StrokeStyle(lineWidth: 17, lineCap: .round, lineJoin: .round)
                    )

                // Fully opaque casing — covers the road's own centerline/lane markings
                // so they never visually split the route down the middle.
                MapPolyline(coordinates: renderedRouteCoordinates)
                    .stroke(
                        Color.white.opacity(0.94),
                        style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round)
                    )

                // Brand-colored route fill — ~25% wider than the previous styling and
                // painted directly on top of the casing.
                MapPolyline(coordinates: renderedRouteCoordinates)
                    .stroke(
                        Styles.rydrGradient,
                        style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
                    )

                // Thin gloss highlight down the center for added depth, like Apple Maps'
                // painted-on route treatment.
                MapPolyline(coordinates: renderedRouteCoordinates)
                    .stroke(
                        Color.white.opacity(0.22),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
            }

            if let markerCoordinate = displayedDriverCoordinate ?? snappedDriverCoordinate ?? driverCoordinate {
                Annotation("", coordinate: markerCoordinate, anchor: .center) {
                    RydrNavigationDriverMarker(heading: heading - visibleCameraHeading)
                }
            }

            if let pickupCoordinate {
                Annotation("Pickup", coordinate: pickupCoordinate, anchor: .bottom) {
                    RydrNavigationPin(kind: .pickup, isActive: isPickupStage)
                }
            }

            if let dropoffCoordinate {
                Annotation("Drop-off", coordinate: dropoffCoordinate, anchor: .bottom) {
                    RydrNavigationPin(kind: .dropoff, isActive: !isPickupStage)
                }
            }
        }
        .onMapCameraChange(frequency: .continuous) { context in
            visibleCameraHeading = context.camera.heading
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .mapStyle(.standard(elevation: .realistic))
        .onAppear {
            displayedDriverCoordinate = snappedDriverCoordinate ?? driverCoordinate
        }
        .onChange(of: driverCoordinateSignature) { _, _ in
            animateDriverMarker(to: snappedDriverCoordinate ?? driverCoordinate)
        }
        .onChange(of: routeCoordinates.count) { _, _ in
            markerAnimationTask?.cancel()
            displayedDriverCoordinate = snappedDriverCoordinate ?? driverCoordinate
        }
        .onDisappear {
            markerAnimationTask?.cancel()
        }
        .overlay(alignment: .trailing) {
            FloatingCircleButton(systemName: "location.fill", action: onRecenter)
                .padding(.trailing, 18)
                .padding(.bottom, 300)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    // MARK: - Route geometry helpers

    private func animateDriverMarker(to target: CLLocationCoordinate2D?) {
        markerAnimationTask?.cancel()
        guard let target else {
            displayedDriverCoordinate = nil
            return
        }
        guard let start = displayedDriverCoordinate else {
            displayedDriverCoordinate = target
            return
        }

        let distanceMeters = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
        guard distanceMeters >= 1.5 else {
            displayedDriverCoordinate = target
            return
        }

        let path = routeCoordinates
        guard let from = NavigationRouteGeometry.match(start, path: path),
              let to = NavigationRouteGeometry.match(target, path: path),
              from.distance <= 40, to.distance <= 40,
              to.progress >= from.progress, to.progress - from.progress <= 200 else {
            displayedDriverCoordinate = target
            return
        }
        let duration = min(1.0, max(0.3, distanceMeters / 18.0))
        markerAnimationTask = Task { @MainActor in
            let steps = 24
            let sleep = UInt64((duration / Double(steps)) * 1_000_000_000)
            for step in 1...steps {
                if Task.isCancelled { return }
                let t = Double(step) / Double(steps)
                let eased = t * t * (3 - 2 * t)
                displayedDriverCoordinate = NavigationRouteGeometry.coordinate(at: from.progress + (to.progress - from.progress) * eased, path: path) ?? target
                try? await Task.sleep(nanoseconds: sleep)
            }
            displayedDriverCoordinate = target
        }
    }

}

private struct RydrNavigationDriverMarker: View {
    let heading: CLLocationDirection

    var body: some View {
        ZStack {
            Circle()
                .stroke(Styles.rydrGradient.opacity(0.34), lineWidth: 2)
                .frame(width: 64, height: 64)

            Circle()
                .fill(Color.white.opacity(0.94))
                .frame(width: 46, height: 46)
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 5)

            Circle()
                .fill(Styles.rydrGradient)
                .frame(width: 32, height: 32)

            Image(systemName: "car.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.white)

            Image(systemName: "location.north.fill")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
                .offset(y: -30)
                .rotationEffect(.degrees(heading))
        }
        .accessibilityLabel("Current driver location")
    }
}

private enum RydrNavigationPinKind {
    case pickup
    case dropoff

    var systemImage: String {
        switch self {
        case .pickup: "mappin.circle.fill"
        case .dropoff: "flag.checkered.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .pickup: "Pickup"
        case .dropoff: "Drop-off"
        }
    }
}

private struct RydrNavigationPin: View {
    let kind: RydrNavigationPinKind
    let isActive: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isActive ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color(.systemBackground)))
                    .frame(width: 38, height: 38)
                    .shadow(color: Color.red.opacity(isActive ? 0.28 : 0.12), radius: 10, y: 5)

                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 38, height: 38)

                Image(systemName: kind.systemImage)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(isActive ? Color.white : Color.red)
            }

            Text(kind.label)
                .font(.caption2.weight(.black))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.regularMaterial))
                .foregroundStyle(.primary)
        }
        .accessibilityLabel(kind.label)
    }
}
