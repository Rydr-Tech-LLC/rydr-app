import SwiftUI
import MapKit
import CoreLocation

struct RydrDriverMapView: View {
    @Binding var position: MapCameraPosition
    @Binding var filterPreferences: DriverRideFilterPreferences

    let driverCoordinate: CLLocationCoordinate2D?
    let isOnline: Bool
    let pendingRequests: [DriverRideRadarBlip]
    let recenterButtonBottomPadding: CGFloat
    let workZoneControlBottomPadding: CGFloat
    let onRecenter: () -> Void

    /// Coordinate the work zone camera was last fit to. Used to detect meaningful GPS
    /// movement so the work zone keeps following the driver instead of staying pinned
    /// to wherever it was first drawn.
    @State private var lastFittedCoordinate: CLLocationCoordinate2D?

    private var driverCoordinateKey: String? {
        driverCoordinate.map { "\($0.latitude),\($0.longitude)" }
    }

    var body: some View {
        RydrDriverMKMapView(
            position: $position,
            filterPreferences: filterPreferences,
            driverCoordinate: driverCoordinate,
            isOnline: isOnline,
            pendingRequests: pendingRequests
        )
        .ignoresSafeArea()
        .overlay(alignment: .trailing) {
            FloatingCircleButton(systemName: "location.magnifyingglass", action: onRecenter)
                .padding(.trailing, 18)
                .padding(.bottom, recenterButtonBottomPadding)
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
                .padding(.bottom, workZoneControlBottomPadding)
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
        .onChange(of: filterPreferences.workZoneEnabled) { _, isEnabled in
            guard isEnabled else { return }
            fitWorkZoneInViewport()
        }
        .onChange(of: filterPreferences.effectivePickupMiles) { _, _ in
            fitWorkZoneInViewport()
        }
        .onChange(of: driverCoordinateKey) { _, _ in
            recenterWorkZoneIfDriverMoved()
        }
        .onAppear {
            if filterPreferences.workZoneEnabled {
                fitWorkZoneInViewport()
            }
        }
    }

    /// Re-fits the work zone camera only once the driver has actually moved a
    /// meaningful distance, so the work zone continuously tracks live GPS without
    /// re-animating the camera on every tiny location jitter.
    private func recenterWorkZoneIfDriverMoved() {
        guard filterPreferences.workZoneEnabled, let driverCoordinate else { return }

        guard let lastFittedCoordinate else {
            fitWorkZoneInViewport()
            return
        }

        let moved = CLLocation(latitude: driverCoordinate.latitude, longitude: driverCoordinate.longitude)
            .distance(from: CLLocation(latitude: lastFittedCoordinate.latitude, longitude: lastFittedCoordinate.longitude))

        if moved >= 30 {
            fitWorkZoneInViewport()
        }
    }

    private func workZoneHandleCoordinate(from center: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let miles = filterPreferences.effectivePickupMiles
        let longitudeOffset = miles / max(1, 69.0 * cos(center.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude + longitudeOffset)
    }

    private func workZoneRadiusLabelCoordinate(from center: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let miles = filterPreferences.effectivePickupMiles
        let latitudeOffset = miles / 69.0
        return CLLocationCoordinate2D(latitude: center.latitude + latitudeOffset, longitude: center.longitude)
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

    /// Re-centers on the driver's live GPS location and zooms so the work zone radius
    /// occupies roughly 70-80% of the visible map — the dynamic "active operating
    /// territory" feel rather than a static, zoomed-out overlay. The actual 500-700ms
    /// animated transition happens at the MKMapView layer (see `setRegionIfNeeded`),
    /// which has precise control over animation duration.
    private func fitWorkZoneInViewport() {
        guard filterPreferences.workZoneEnabled, let driverCoordinate else { return }
        lastFittedCoordinate = driverCoordinate

        let miles = max(filterPreferences.effectivePickupMiles, DriverRideFilterPreferences.minimumWorkZoneMiles)

        // Diameter-to-viewport ratio tuned so the work zone circle's diameter fills
        // ~75% of the shorter screen dimension (within the requested 70-80% range).
        let latitudeDelta = max(0.10, (miles / 69.0) * 2.6)
        let longitudeScale = max(0.35, cos(driverCoordinate.latitude * .pi / 180))
        let longitudeDelta = max(0.10, latitudeDelta / longitudeScale)

        // Bias the camera center north of the driver so the vehicle marker settles in
        // the lower-middle of the screen — more look-ahead room, less dead-center.
        let verticalBias = latitudeDelta * 0.16
        let biasedCenter = CLLocationCoordinate2D(
            latitude: driverCoordinate.latitude + verticalBias,
            longitude: driverCoordinate.longitude
        )

        let region = MKCoordinateRegion(
            center: biasedCenter,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )

        position = .region(region)
    }
}

private struct RydrDriverMKMapView: UIViewRepresentable {
    @Binding var position: MapCameraPosition

    let filterPreferences: DriverRideFilterPreferences
    let driverCoordinate: CLLocationCoordinate2D?
    let isOnline: Bool
    let pendingRequests: [DriverRideRadarBlip]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        mapView.showsUserLocation = false
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .includingAll
        mapView.tintColor = .systemRed
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.configure(
            mapView,
            position: position,
            filterPreferences: filterPreferences,
            driverCoordinate: driverCoordinate,
            isOnline: isOnline,
            pendingRequests: pendingRequests
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var hasSetInitialRegion = false
        private var lastAppliedRegion: MKCoordinateRegion?
        private var workZoneOverlayIDs = Set<ObjectIdentifier>()
        private var destinationGlowOverlayIDs = Set<ObjectIdentifier>()
        private var destinationRouteOverlayIDs = Set<ObjectIdentifier>()

        /// The live work zone renderer, kept so the pulse timer can nudge its animation
        /// phase and trigger a redraw without re-creating the overlay.
        private weak var workZoneRenderer: WorkZoneOverlayRenderer?
        private var pulseTimer: Timer?
        private let pulseStartDate = Date()
        /// Seconds per breathing cycle — "a gentle pulse every few seconds."
        private let pulsePeriod: TimeInterval = 3.0

        override init() {
            super.init()
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self, let renderer = self.workZoneRenderer else { return }
                let elapsed = Date().timeIntervalSince(self.pulseStartDate)
                let phase = elapsed.truncatingRemainder(dividingBy: self.pulsePeriod) / self.pulsePeriod
                renderer.pulseProgress = CGFloat(phase)
                renderer.setNeedsDisplay()
            }
        }

        deinit {
            pulseTimer?.invalidate()
        }

        func configure(
            _ mapView: MKMapView,
            position: MapCameraPosition,
            filterPreferences: DriverRideFilterPreferences,
            driverCoordinate: CLLocationCoordinate2D?,
            isOnline: Bool,
            pendingRequests: [DriverRideRadarBlip]
        ) {
            workZoneOverlayIDs.removeAll()
            destinationGlowOverlayIDs.removeAll()
            destinationRouteOverlayIDs.removeAll()
            mapView.removeOverlays(mapView.overlays)
            mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

            if let driverCoordinate, filterPreferences.workZoneEnabled {
                // A single circle overlay, paired with a custom renderer that draws the
                // gradient fill, crisp border, soft glow, and pulse in one pass — this
                // keeps the work zone from ever looking like two mismatched layers.
                let radiusMeters = filterPreferences.effectivePickupMiles * 1609.344
                let circle = MKCircle(center: driverCoordinate, radius: radiusMeters)
                workZoneOverlayIDs.insert(ObjectIdentifier(circle))
                mapView.addOverlay(circle)
            }

            if let driverCoordinate,
               filterPreferences.hasDestinationFilter,
               let destination = filterPreferences.destinationCoordinate {
                let coordinates = [driverCoordinate, destination]
                let glowRoute = MKPolyline(coordinates: coordinates, count: coordinates.count)
                let route = MKPolyline(coordinates: coordinates, count: coordinates.count)
                destinationGlowOverlayIDs.insert(ObjectIdentifier(glowRoute))
                destinationRouteOverlayIDs.insert(ObjectIdentifier(route))
                mapView.addOverlay(glowRoute)
                mapView.addOverlay(route)
                mapView.addAnnotation(
                    RydrDriverMapAnnotation(
                        coordinate: destination,
                        kind: .destination(corridorMiles: filterPreferences.destinationCorridor.miles)
                    )
                )
            }

            if let driverCoordinate {
                mapView.addAnnotation(
                    RydrDriverMapAnnotation(
                        coordinate: driverCoordinate,
                        kind: filterPreferences.workZoneEnabled ? .workZoneCenter(isOnline: isOnline) : .driverLocation(isOnline: isOnline)
                    )
                )

                if filterPreferences.workZoneEnabled {
                    mapView.addAnnotation(
                        RydrDriverMapAnnotation(
                            coordinate: workZoneRadiusLabelCoordinate(from: driverCoordinate, miles: filterPreferences.effectivePickupMiles),
                            kind: .workZoneFloatingLabel(miles: filterPreferences.effectivePickupMiles)
                        )
                    )
                    mapView.addAnnotation(
                        RydrDriverMapAnnotation(
                            coordinate: workZoneHandleCoordinate(from: driverCoordinate, miles: filterPreferences.effectivePickupMiles),
                            kind: .workZoneHandle(miles: filterPreferences.effectivePickupMiles)
                        )
                    )
                }
            }

            for blip in pendingRequests.filter({ !$0.isExpired }) {
                mapView.addAnnotation(RydrDriverMapAnnotation(coordinate: blip.coordinate, kind: .rideRequest))
            }

            if let region = position.region {
                setRegionIfNeeded(region, on: mapView, animated: true)
            } else if !hasSetInitialRegion, let driverCoordinate {
                let region = MKCoordinateRegion(
                    center: driverCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.16, longitudeDelta: 0.16)
                )
                setRegionIfNeeded(region, on: mapView, animated: false)
                hasSetInitialRegion = true
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                if workZoneOverlayIDs.contains(ObjectIdentifier(circle)) {
                    let renderer = WorkZoneOverlayRenderer(circle: circle)
                    let elapsed = Date().timeIntervalSince(pulseStartDate)
                    renderer.pulseProgress = CGFloat(elapsed.truncatingRemainder(dividingBy: pulsePeriod) / pulsePeriod)
                    workZoneRenderer = renderer
                    return renderer
                }
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor.clear
                renderer.strokeColor = UIColor.systemRed.withAlphaComponent(0.85)
                renderer.lineWidth = 2.5
                return renderer
            }

            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.lineCap = .round
                renderer.lineJoin = .round
                if destinationGlowOverlayIDs.contains(ObjectIdentifier(polyline)) {
                    renderer.strokeColor = UIColor.systemRed.withAlphaComponent(0.15)
                    renderer.lineWidth = 34
                    renderer.lineDashPattern = [8, 8]
                } else if destinationRouteOverlayIDs.contains(ObjectIdentifier(polyline)) {
                    renderer.strokeColor = UIColor.systemRed
                    renderer.lineWidth = 6
                } else {
                    renderer.strokeColor = UIColor.systemRed
                    renderer.lineWidth = 6
                }
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? RydrDriverMapAnnotation else { return nil }
            let identifier = annotation.kind.reuseIdentifier
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.canShowCallout = false
            view.backgroundColor = .clear
            view.subviews.forEach { $0.removeFromSuperview() }

            let content = annotationView(for: annotation.kind)
            content.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(content)
            let contentSize = content.bounds.size == .zero
                ? content.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
                : content.bounds.size
            view.bounds = CGRect(origin: .zero, size: contentSize)
            NSLayoutConstraint.activate([
                content.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                content.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            return view
        }

        private func annotationView(for kind: RydrDriverMapAnnotation.Kind) -> UIView {
            switch kind {
            case .driverLocation(let isOnline):
                return host(WorkZoneCenterMarker(isOnline: isOnline))
            case .workZoneCenter(let isOnline):
                return host(WorkZoneCenterMarker(isOnline: isOnline))
            case .workZoneFloatingLabel(let miles):
                return host(WorkZoneFloatingLabel(miles: miles))
            case .workZoneHandle(let miles):
                return host(WorkZoneRadiusHandle(miles: miles))
            case .destination(let corridorMiles):
                return host(DestinationModePin(corridorMiles: corridorMiles))
            case .rideRequest:
                return host(RiderRequestBlip())
            }
        }

        private func host<Content: View>(_ view: Content) -> UIView {
            let controller = UIHostingController(rootView: view)
            controller.view.backgroundColor = .clear
            let fittingSize = controller.sizeThatFits(in: CGSize(width: 220, height: 220))
            controller.view.frame = CGRect(origin: .zero, size: fittingSize)
            return controller.view
        }

        private func setRegionIfNeeded(_ region: MKCoordinateRegion, on mapView: MKMapView, animated: Bool) {
            if let lastAppliedRegion, regionsAreClose(lastAppliedRegion, region) {
                return
            }
            lastAppliedRegion = region

            guard animated else {
                mapView.setRegion(region, animated: false)
                return
            }

            // Wrapping the (non-animated) region assignment in an explicit UIView
            // animation block gives precise control over duration — 0.6s sits in the
            // requested 500-700ms window for a smooth, deliberate camera move rather
            // than MapKit's default un-tunable `animated: true` timing.
            UIView.animate(
                withDuration: 0.6,
                delay: 0,
                options: [.curveEaseInOut],
                animations: {
                    mapView.setRegion(region, animated: false)
                }
            )
        }

        private func regionsAreClose(_ lhs: MKCoordinateRegion, _ rhs: MKCoordinateRegion) -> Bool {
            abs(lhs.center.latitude - rhs.center.latitude) < 0.0001
                && abs(lhs.center.longitude - rhs.center.longitude) < 0.0001
                && abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta) < 0.0001
                && abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta) < 0.0001
        }

        private func workZoneHandleCoordinate(from center: CLLocationCoordinate2D, miles: Double) -> CLLocationCoordinate2D {
            let longitudeOffset = miles / max(1, 69.0 * cos(center.latitude * .pi / 180))
            return CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude + longitudeOffset)
        }

        private func workZoneRadiusLabelCoordinate(from center: CLLocationCoordinate2D, miles: Double) -> CLLocationCoordinate2D {
            // A touch past the circle's true edge so the floating label clears the
            // outer glow instead of overlapping it.
            let latitudeOffset = (miles / 69.0) * 1.08
            return CLLocationCoordinate2D(latitude: center.latitude + latitudeOffset, longitude: center.longitude)
        }
    }
}

private final class RydrDriverMapAnnotation: NSObject, MKAnnotation {
    enum Kind {
        case driverLocation(isOnline: Bool)
        case workZoneCenter(isOnline: Bool)
        case workZoneFloatingLabel(miles: Double)
        case workZoneHandle(miles: Double)
        case destination(corridorMiles: Double)
        case rideRequest

        var reuseIdentifier: String {
            switch self {
            case .driverLocation:
                return "driverLocation"
            case .workZoneCenter:
                return "workZoneCenter"
            case .workZoneFloatingLabel:
                return "workZoneFloatingLabel"
            case .workZoneHandle:
                return "workZoneHandle"
            case .destination:
                return "destination"
            case .rideRequest:
                return "rideRequest"
            }
        }
    }

    dynamic var coordinate: CLLocationCoordinate2D
    let kind: Kind

    init(coordinate: CLLocationCoordinate2D, kind: Kind) {
        self.coordinate = coordinate
        self.kind = kind
        super.init()
    }
}

/// Draws the work zone circle as a single layered pass — soft outer glow, a subtle
/// Rydr-red radial gradient fill, a crisp solid border, and a gentle breathing pulse
/// ring — so it reads as one premium, "painted on the map" territory rather than a
/// flat static overlay.
private final class WorkZoneOverlayRenderer: MKOverlayRenderer {
    private let circle: MKCircle

    /// 0...1 progress through the current pulse cycle, driven by the Coordinator's
    /// timer. Setting this and calling `setNeedsDisplay()` animates the breathing ring.
    var pulseProgress: CGFloat = 0

    init(circle: MKCircle) {
        self.circle = circle
        super.init(overlay: circle)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let centerPoint = point(for: MKMapPoint(circle.coordinate))
        let metersToMapPoints = MKMapPointsPerMeterAtLatitude(circle.coordinate.latitude)
        let radiusPoints = CGFloat(circle.radius * metersToMapPoints * Double(zoomScale))
        guard radiusPoints > 0 else { return }

        let brandRed = UIColor.systemRed
        let boundingRect = CGRect(
            x: centerPoint.x - radiusPoints,
            y: centerPoint.y - radiusPoints,
            width: radiusPoints * 2,
            height: radiusPoints * 2
        )

        // Soft outer glow — concentric translucent strokes that fall off with distance.
        context.saveGState()
        for step in 0..<5 {
            let glowRadius = radiusPoints + CGFloat(step) * (radiusPoints * 0.045)
            let glowAlpha = 0.10 * (1.0 - CGFloat(step) / 5.0)
            context.setStrokeColor(brandRed.withAlphaComponent(glowAlpha).cgColor)
            context.setLineWidth(radiusPoints * 0.05)
            context.addEllipse(in: CGRect(
                x: centerPoint.x - glowRadius,
                y: centerPoint.y - glowRadius,
                width: glowRadius * 2,
                height: glowRadius * 2
            ))
            context.strokePath()
        }
        context.restoreGState()

        // Subtle Rydr-red gradient fill, 15-20% opacity from center to edge — frames
        // the driver without visually overwhelming the marker.
        context.saveGState()
        context.addEllipse(in: boundingRect)
        context.clip()
        let fillColors = [
            brandRed.withAlphaComponent(0.15).cgColor,
            brandRed.withAlphaComponent(0.20).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: fillColors, locations: [0, 1]) {
            context.drawRadialGradient(
                gradient,
                startCenter: centerPoint,
                startRadius: 0,
                endCenter: centerPoint,
                endRadius: radiusPoints,
                options: []
            )
        }
        context.restoreGState()

        // Crisp solid border at the true radius.
        context.saveGState()
        context.setStrokeColor(brandRed.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(2.5)
        context.addEllipse(in: boundingRect)
        context.strokePath()
        context.restoreGState()

        // Gentle pulse ring — expands just past the border and fades out as it grows,
        // repeating every few seconds.
        context.saveGState()
        let pulseRadius = radiusPoints * (1.0 + 0.07 * pulseProgress)
        let pulseAlpha = 0.45 * (1.0 - pulseProgress)
        context.setStrokeColor(brandRed.withAlphaComponent(pulseAlpha).cgColor)
        context.setLineWidth(2.5)
        context.addEllipse(in: CGRect(
            x: centerPoint.x - pulseRadius,
            y: centerPoint.y - pulseRadius,
            width: pulseRadius * 2,
            height: pulseRadius * 2
        ))
        context.strokePath()
        context.restoreGState()
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
                    .background(Circle().fill(Color(.secondarySystemBackground)))
                    .foregroundStyle(Color.red)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Work Zone")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.secondary)
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
                    .background(Circle().fill(Color(.secondarySystemBackground)))
                    .foregroundStyle(Color.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color(.systemBackground).opacity(0.96))
                .overlay(Capsule().stroke(Color.red.opacity(0.14), lineWidth: 1))
        )
        .foregroundStyle(.primary)
        .shadow(color: Color.red.opacity(0.16), radius: 16, y: 8)
    }
}

private struct WorkZoneFloatingLabel: View {
    let miles: Double

    var body: some View {
        VStack(spacing: 2) {
            Text("Your Work Zone")
                .font(.caption2.weight(.black))
                .foregroundStyle(.secondary)
            Text("\(Int(miles.rounded())) mi")
                .font(.subheadline.weight(.black))
                .foregroundStyle(Color.red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.96)))
        .overlay(Capsule().stroke(Color.red.opacity(0.20), lineWidth: 1))
        .shadow(color: Color.red.opacity(0.20), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your work zone, \(Int(miles.rounded())) mile radius")
    }
}

private struct WorkZoneCenterMarker: View {
    let isOnline: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 42, height: 42)
                .shadow(color: Color.red.opacity(0.22), radius: 14, y: 5)

            Circle()
                .stroke(Color.red.opacity(0.18), lineWidth: 8)
                .frame(width: 54, height: 54)

            Circle()
                .fill(Styles.rydrGradient)
                .frame(width: 28, height: 28)

            Image(systemName: "car.fill")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)

            Circle()
                .stroke(Color.white, lineWidth: 3)
                .frame(width: 28, height: 28)

            if isOnline {
                Circle()
                    .stroke(Color.red.opacity(0.34), lineWidth: 2)
                    .frame(width: 64, height: 64)
            }
        }
        .accessibilityLabel("Work Zone center")
    }
}

private struct WorkZoneRadiusHandle: View {
    let miles: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.96))
                .frame(width: 42, height: 42)
                .overlay(Circle().stroke(Color.red.opacity(0.22), lineWidth: 1))
                .shadow(color: Color.red.opacity(0.18), radius: 12, y: 5)

            Image(systemName: "arrow.left.and.right")
                .font(.caption.weight(.black))
                .foregroundStyle(Color.red)
        }
        .frame(width: 48, height: 48)
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
    var body: some View {
        RideSignalBlipView()
            .accessibilityLabel("Ride activity nearby")
    }
}

struct RideSignalBlipView: View {
    var count: Int? = nil
    var isActive: Bool = true

    @State private var wavePhase = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if isActive {
                    ForEach(0..<3, id: \.self) { index in
                        SignalWavePair(
                            scale: wavePhase ? 1.18 + Double(index) * 0.13 : 0.78 + Double(index) * 0.08,
                            opacity: wavePhase ? 0.02 : 0.28 - Double(index) * 0.055
                        )
                        .animation(
                            .easeOut(duration: 1.55)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.18),
                            value: wavePhase
                        )
                    }
                } else {
                    SignalWavePair(scale: 0.86, opacity: 0.16)
                }

                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 24, height: 24)
                    .shadow(color: Color.red.opacity(0.16), radius: 7, y: 3)

                Circle()
                    .fill(Styles.rydrGradient)
                    .frame(width: 14, height: 14)

                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 58, height: 46)

            if let count, count > 1 {
                Text("\(min(count, 9))")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.red))
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
                    .offset(x: 1, y: -1)
            }
        }
        .frame(width: 62, height: 50)
        .onAppear {
            guard isActive else { return }
            wavePhase = true
        }
    }
}

private struct SignalWavePair: View {
    let scale: Double
    let opacity: Double

    var body: some View {
        HStack(spacing: 22) {
            SignalArc(side: .left)
            SignalArc(side: .right)
        }
        .foregroundStyle(Color.red.opacity(opacity))
        .scaleEffect(scale)
    }
}

private struct SignalArc: Shape {
    enum Side {
        case left
        case right
    }

    let side: Side

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) * 0.42
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = side == .left ? Angle.degrees(118) : Angle.degrees(-62)
        let end = side == .left ? Angle.degrees(242) : Angle.degrees(62)
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path.strokedPath(.init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
    }
}

struct OnlineSearchIndicator: View {
    let demand: DriverDemandSnapshot

    @State private var sweepDegrees: Double = -35
    @State private var ping = false

    var body: some View {
        HStack(spacing: 16) {
            SonarBlipView(sweepDegrees: sweepDegrees, ping: ping, diameter: 86)
                .shadow(color: Color.red.opacity(0.55), radius: 22)

            VStack(alignment: .leading, spacing: 6) {
                Text("Standby")
                    .font(.system(size: 32, weight: .heavy, design: .rounded).italic())
                    .foregroundStyle(Styles.rydrGradient)
                    .shadow(color: Color.red.opacity(0.24), radius: 8, x: 0, y: 3)
                Text("Scanning for nearby rides")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.76))

                HStack(spacing: 6) {
                    Image(systemName: demandIcon)
                        .font(.caption.weight(.black))
                    Text(demand.title)
                    Text("•")
                        .foregroundStyle(demandColor.opacity(0.5))
                    Text(demand.paceText)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(demandColor)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(demandColor.opacity(0.11))
                )
            }

            Spacer()
        }
        .padding(.leading, 14)
        .padding(.trailing, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 520, minHeight: 118)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.97),
                            Color.white.opacity(0.90),
                            Color.red.opacity(0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.86), lineWidth: 1))
                .overlay(Capsule().stroke(Color.red.opacity(0.20), lineWidth: 1))
        )
        .shadow(color: Color.red.opacity(0.24), radius: 24, y: 12)
        .shadow(color: Color.black.opacity(0.12), radius: 18, y: 8)
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                sweepDegrees = 325
            }
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                ping = true
            }
        }
    }

    private var demandColor: Color {
        switch demand.level {
        case .low: return Color.green
        case .moderate: return Color.orange
        case .high: return Color.red
        }
    }

    private var demandIcon: String {
        switch demand.level {
        case .low: return "chart.bar"
        case .moderate: return "chart.bar.fill"
        case .high: return "chart.bar.xaxis"
        }
    }
}

struct SonarBlipView: View {
    let sweepDegrees: Double
    let ping: Bool
    var diameter: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.82))
                .frame(width: diameter * 0.92, height: diameter * 0.92)

            ForEach([0.38, 0.63, 0.88], id: \.self) { scale in
                Circle()
                    .stroke(Styles.rydrGradient.opacity(scale > 0.8 ? 0.38 : 0.24), lineWidth: 1.2)
                    .frame(width: diameter * scale, height: diameter * scale)
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color.red.opacity(0.10), Color.red.opacity(0.72)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: diameter * 0.42, height: 2.4)
                .offset(x: diameter * 0.21)
                .rotationEffect(.degrees(sweepDegrees))

            Circle()
                .fill(Styles.rydrGradient)
                .frame(width: diameter * 0.14, height: diameter * 0.14)
                .shadow(color: Color.red.opacity(0.5), radius: 6)

            Circle()
                .fill(Color.red.opacity(ping ? 0.95 : 0.26))
                .frame(width: diameter * 0.10, height: diameter * 0.10)
                .offset(x: diameter * 0.20, y: -diameter * 0.17)

            Circle()
                .fill(Color.red.opacity(ping ? 0.32 : 0.86))
                .frame(width: diameter * 0.08, height: diameter * 0.08)
                .offset(x: -diameter * 0.25, y: diameter * 0.15)
        }
        .frame(width: diameter, height: diameter)
        .padding(5)
        .background(
            Circle()
                .fill(Color.red.opacity(0.08))
                .overlay(Circle().stroke(Color.red.opacity(0.20), lineWidth: 1))
        )
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.70), lineWidth: 1)
                .scaleEffect(ping ? 1.18 : 1)
                .opacity(ping ? 0.18 : 0.55)
        )
        .accessibilityHidden(true)
    }
}
