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

    /// Route geometry passed in from `MKRoute.polyline`, upsampled with a Catmull-Rom
    /// spline so curves render as smooth arcs rather than the sparse line segments
    /// MapKit's raw directions response returns.
    private var renderedRouteCoordinates: [CLLocationCoordinate2D] {
        Self.smoothedRouteCoordinates(routeCoordinates)
    }

    /// The driver's raw GPS fix, projected onto the nearest point of the route line.
    /// This keeps the vehicle marker glued to the road even when GPS jitter would
    /// otherwise place it slightly off the polyline.
    private var snappedDriverCoordinate: CLLocationCoordinate2D? {
        guard let driverCoordinate else { return nil }
        return Self.closestPoint(to: driverCoordinate, on: routeCoordinates) ?? driverCoordinate
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

            if let markerCoordinate = snappedDriverCoordinate ?? driverCoordinate {
                Annotation("", coordinate: markerCoordinate, anchor: .center) {
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

    // MARK: - Route geometry helpers

    /// Inserts Catmull-Rom interpolated points between each pair of route coordinates so
    /// curves render as smooth arcs instead of the sparse polyline MapKit's directions
    /// response returns. The underlying points still come straight from `MKRoute.polyline`,
    /// which is already snapped to the road network — this only adds visual smoothing.
    private static func smoothedRouteCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        segmentsPerPoint: Int = 8
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 2 else { return coordinates }

        var points = coordinates
        points.insert(points[0], at: 0)
        points.append(points[points.count - 1])

        var smoothed: [CLLocationCoordinate2D] = []
        for i in 1..<(points.count - 2) {
            let p0 = points[i - 1]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[i + 2]

            for step in 0..<segmentsPerPoint {
                let t = Double(step) / Double(segmentsPerPoint)
                smoothed.append(catmullRom(p0, p1, p2, p3, t))
            }
        }

        if let last = coordinates.last {
            smoothed.append(last)
        }
        return smoothed
    }

    private static func catmullRom(
        _ p0: CLLocationCoordinate2D,
        _ p1: CLLocationCoordinate2D,
        _ p2: CLLocationCoordinate2D,
        _ p3: CLLocationCoordinate2D,
        _ t: Double
    ) -> CLLocationCoordinate2D {
        let t2 = t * t
        let t3 = t2 * t

        func interpolate(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            0.5 * (
                (2 * b)
                + (-a + c) * t
                + (2 * a - 5 * b + 4 * c - d) * t2
                + (-a + 3 * b - 3 * c + d) * t3
            )
        }

        return CLLocationCoordinate2D(
            latitude: interpolate(p0.latitude, p1.latitude, p2.latitude, p3.latitude),
            longitude: interpolate(p0.longitude, p1.longitude, p2.longitude, p3.longitude)
        )
    }

    /// Projects `coordinate` onto the nearest point of `path`, used to glue the vehicle
    /// marker to the route line and absorb GPS jitter.
    private static func closestPoint(
        to coordinate: CLLocationCoordinate2D,
        on path: [CLLocationCoordinate2D]
    ) -> CLLocationCoordinate2D? {
        guard path.count > 1 else { return path.first }

        var bestPoint: CLLocationCoordinate2D?
        var bestDistance = Double.greatestFiniteMagnitude

        for index in 0..<(path.count - 1) {
            let projected = projectOntoSegment(coordinate, start: path[index], end: path[index + 1])
            let distance = CLLocation(latitude: projected.latitude, longitude: projected.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if distance < bestDistance {
                bestDistance = distance
                bestPoint = projected
            }
        }
        return bestPoint
    }

    /// Planar projection of `point` onto the segment `start`-`end`. Adequate accuracy at
    /// navigation zoom scales, where segment lengths are short relative to Earth's curvature.
    private static func projectOntoSegment(
        _ point: CLLocationCoordinate2D,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        let dx = end.longitude - start.longitude
        let dy = end.latitude - start.latitude
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return start }

        var t = ((point.longitude - start.longitude) * dx + (point.latitude - start.latitude) * dy) / lengthSquared
        t = max(0, min(1, t))

        return CLLocationCoordinate2D(latitude: start.latitude + t * dy, longitude: start.longitude + t * dx)
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
