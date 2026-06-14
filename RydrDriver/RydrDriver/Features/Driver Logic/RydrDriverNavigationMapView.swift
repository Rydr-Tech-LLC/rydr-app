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

    var body: some View {
        Map(position: $position, interactionModes: [.all]) {
            if !routeCoordinates.isEmpty {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(Color.black.opacity(0.16), lineWidth: 12)

                MapPolyline(coordinates: routeCoordinates)
                    .stroke(Color.black.opacity(0.32), lineWidth: 7)
            }

            if let driverCoordinate {
                Annotation("", coordinate: driverCoordinate, anchor: .center) {
                    RydrNavigationDriverMarker(heading: heading)
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
        .mapStyle(.standard(elevation: .realistic))
        .overlay(alignment: .trailing) {
            FloatingCircleButton(systemName: "location.fill", action: onRecenter)
                .padding(.trailing, 18)
                .padding(.bottom, 300)
                .frame(maxHeight: .infinity, alignment: .bottom)
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
