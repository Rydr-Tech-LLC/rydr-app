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
    let onRecenter: () -> Void

    var body: some View {
        Map(position: $position, interactionModes: [.all]) {
            if !routeCoordinates.isEmpty {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(Styles.rydrGradient, lineWidth: 7)
            }

            if let driverCoordinate {
                Annotation("", coordinate: driverCoordinate, anchor: .center) {
                    DriverLocationDot(isOnline: true)
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
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .trailing) {
            FloatingCircleButton(systemName: "location.fill", action: onRecenter)
                .padding(.trailing, 18)
                .padding(.bottom, 300)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
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
