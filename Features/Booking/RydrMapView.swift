import SwiftUI
import MapKit
import CoreLocation

enum RydrMapDefaults {
    static let atlantaCoordinate = CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880)
    static let atlantaRegion = MKCoordinateRegion(
        center: atlantaCoordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
    )
}

struct RydrMapView: View {
    @Binding var position: MapCameraPosition

    let pickupCoordinate: CLLocationCoordinate2D?
    let dropoffCoordinate: CLLocationCoordinate2D?
    let routePolyline: MKPolyline?
    let showsUserLocation: Bool
    let onRecenter: () -> Void

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom, .pitch, .rotate]) {
            if showsUserLocation {
                UserAnnotation()
            }

            if let routePolyline {
                MapPolyline(routePolyline)
                    .stroke(Color.black.opacity(0.14), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))

                MapPolyline(routePolyline)
                    .stroke(Styles.rydrGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }

            if let pickupCoordinate {
                Annotation("Pickup", coordinate: pickupCoordinate, anchor: .bottom) {
                    RydrMapPin(kind: .pickup)
                }
            }

            if let dropoffCoordinate {
                Annotation("Drop-off", coordinate: dropoffCoordinate, anchor: .bottom) {
                    RydrMapPin(kind: .dropoff)
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            Label("Rydr Map", systemImage: "location.north.line.fill")
                .font(.caption2.weight(.black))
                .foregroundStyle(Styles.rydrGradient)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.leading, 18)
                .padding(.top, 72)
        }
        .overlay(alignment: .trailing) {
            recenterButton
                .padding(.trailing, 18)
                .padding(.bottom, 170)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var recenterButton: some View {
        Button(action: onRecenter) {
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.red)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recenter map")
    }
}

private enum RydrMapPinKind {
    case pickup
    case dropoff
}

private struct RydrMapPin: View {
    let kind: RydrMapPinKind

    private var symbol: String {
        switch kind {
        case .pickup: return "figure.wave"
        case .dropoff: return "flag.checkered"
        }
    }

    private var title: String {
        switch kind {
        case .pickup: return "Pickup"
        case .dropoff: return "Drop-off"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(fillStyle)
                    .frame(width: 42, height: 42)
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)

                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(kind == .pickup ? Color.red : Color.white)
            }

            Triangle()
                .fill(fillStyle)
                .frame(width: 14, height: 10)
                .offset(y: -2)
        }
        .accessibilityLabel(title)
    }

    private var fillStyle: AnyShapeStyle {
        switch kind {
        case .pickup:
            return AnyShapeStyle(Color.white)
        case .dropoff:
            return AnyShapeStyle(Styles.rydrGradient)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
