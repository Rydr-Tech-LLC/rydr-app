import SwiftUI
import MapKit
import CoreLocation

struct RydrRideProgressMapView: View {
    @Binding var position: MapCameraPosition

    let driverCoordinate: CLLocationCoordinate2D
    let pickupCoordinate: CLLocationCoordinate2D?
    let dropoffCoordinate: CLLocationCoordinate2D?
    let routeCoordinates: [CLLocationCoordinate2D]

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom, .pitch, .rotate]) {
            if !routeCoordinates.isEmpty {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(Styles.rydrGradient, lineWidth: 6)
            }

            Annotation("", coordinate: driverCoordinate, anchor: .center) {
                RydrRiderDriverDot()
            }

            if let pickupCoordinate {
                Annotation("Pickup", coordinate: pickupCoordinate, anchor: .bottom) {
                    RydrRideProgressPin(kind: .pickup)
                }
            }

            if let dropoffCoordinate {
                Annotation("Drop-off", coordinate: dropoffCoordinate, anchor: .bottom) {
                    RydrRideProgressPin(kind: .dropoff)
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }
}

private enum RydrRideProgressPinKind {
    case pickup
    case dropoff

    var symbol: String {
        switch self {
        case .pickup: "mappin.circle.fill"
        case .dropoff: "flag.checkered.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .pickup: "Pickup"
        case .dropoff: "Drop-off"
        }
    }
}

private struct RydrRideProgressPin: View {
    let kind: RydrRideProgressPinKind

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(kind == .pickup ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(Styles.rydrGradient))
                    .frame(width: 38, height: 38)
                    .shadow(color: Color.red.opacity(0.20), radius: 9, y: 4)

                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 38, height: 38)

                Image(systemName: kind.symbol)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(kind == .pickup ? Color.red : Color.white)
            }

            Text(kind.title)
                .font(.caption2.weight(.black))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.regularMaterial))
        }
        .accessibilityLabel(kind.title)
    }
}

private struct RydrRiderDriverDot: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.background)
                .frame(width: 32, height: 32)
                .shadow(color: Color.red.opacity(0.20), radius: 10, y: 4)

            Circle()
                .stroke(Styles.rydrGradient, lineWidth: 3)
                .frame(width: 32, height: 32)

            Image(systemName: "car.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Styles.rydrGradient)
        }
        .accessibilityLabel("Driver location")
    }
}
