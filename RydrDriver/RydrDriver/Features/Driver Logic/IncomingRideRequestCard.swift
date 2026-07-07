//
//  IncomingRideRequestCard.swift
//  RydrDriver
//
//  Accept/decline card for incoming ride dispatch requests.
//

import SwiftUI
import MapKit
import CoreLocation
import AVFoundation

struct IncomingRideRequestCard: View {
    let request: DriverRideRequest
    let driverCoordinate: CLLocationCoordinate2D?
    let rate: DriverRateSetting
    let isResponding: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onTimeout: () -> Void

    @State private var alertSound = IncomingRideAlertSoundPlayer()
    @State private var pickupLeg: RideRequestLegEstimate?
    @State private var tripLeg: RideRequestLegEstimate?
    @State private var secondsRemaining = 15
    @State private var didRespond = false

    private let driverPayoutShare = 0.70

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Incoming \(request.rideType)")
                        .font(.title3.weight(.heavy))
                    Text("New ride request")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                CountdownRing(secondsRemaining: secondsRemaining, totalSeconds: 15)

                RiderMiniProfile(
                    name: request.riderName,
                    photoURL: request.riderPhotoURL,
                    rating: request.riderRating,
                    isVerifiedRider: request.riderVerified
                )
            }

            RideRequestMapPreview(
                driver: driverCoordinate,
                pickup: request.pickupCoordinate,
                dropoff: request.dropoffCoordinate
            )

            UpfrontFareHero(fare: upfrontFare)

            RideRequestRouteDetails(
                pickupAddress: request.pickup,
                dropoffAddress: request.dropoff,
                pickupEstimate: pickupLeg,
                dropoffEstimate: tripLeg ?? fallbackTripLeg
            )

            HStack(spacing: 10) {
                Button {
                    guard !isResponding else { return }
                    didRespond = true
                    alertSound.stop()
                    onDecline()
                } label: {
                    Label("Decline", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .font(.headline.weight(.bold))
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.systemGray5)))
                .foregroundStyle(Color.black)
                .disabled(isResponding)
                .accessibilityLabel("Decline ride request")
                .accessibilityHint("Dismisses this ride request and returns to standby.")

                Button {
                    guard !isResponding else { return }
                    didRespond = true
                    alertSound.stop()
                    onAccept()
                } label: {
                    HStack {
                        if isResponding {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isResponding ? "Accepting" : "Accept")
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .font(.headline.weight(.bold))
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Styles.rydrGradient))
                .foregroundStyle(.white)
                .shadow(color: Color.red.opacity(0.26), radius: 14, y: 8)
                .disabled(isResponding)
                .accessibilityLabel(isResponding ? "Accepting ride request" : "Accept ride request")
                .accessibilityHint("Accepts this ride and opens the active ride flow.")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.60), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.18), radius: 22, y: 12)
        .accessibilityElement(children: .contain)
        .onAppear {
            if !isResponding {
                alertSound.startLoop()
            }
        }
        .onDisappear {
            alertSound.stop()
        }
        .onChange(of: request.id) { _, _ in
            alertSound.restartLoop()
        }
        .onChange(of: isResponding) { _, responding in
            if responding {
                alertSound.stop()
            } else if !didRespond {
                alertSound.startLoop()
            }
        }
        .task(id: request.id) {
            await loadRouteEstimates()
        }
        .task(id: request.id) {
            await runCountdown()
        }
    }

    private var fallbackTripLeg: RideRequestLegEstimate? {
        guard let miles = request.estimatedDistanceMiles,
              let minutes = request.estimatedDurationMinutes else { return nil }
        return RideRequestLegEstimate(distanceMiles: miles, durationMinutes: minutes)
    }

    private var fareBaseLeg: RideRequestLegEstimate? {
        tripLeg ?? fallbackTripLeg
    }

    private var upfrontFare: Double {
        if let payout = request.estimatedDriverPayout {
            return roundedCurrency(payout)
        }
        if let leg = fareBaseLeg {
            let gross = (leg.distanceMiles * rate.perMile) + (leg.durationMinutes * rate.perMinute)
            return roundedCurrency(gross * driverPayoutShare)
        }
        if let fare = request.estimatedFare {
            return roundedCurrency(fare)
        }
        return 0
    }

    private func roundedCurrency(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func loadRouteEstimates() async {
        async let pickupEstimate = routeEstimate(from: driverCoordinate, to: request.pickupCoordinate)
        async let tripEstimate = routeEstimate(from: request.pickupCoordinate, to: request.dropoffCoordinate)
        let estimates = await (pickupEstimate, tripEstimate)
        await MainActor.run {
            pickupLeg = estimates.0
            tripLeg = estimates.1
        }
    }

    private func routeEstimate(from start: CLLocationCoordinate2D?, to end: CLLocationCoordinate2D?) async -> RideRequestLegEstimate? {
        guard let start, let end else { return nil }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return nil }
            return RideRequestLegEstimate(
                distanceMiles: ((route.distance / 1609.344) * 10).rounded() / 10,
                durationMinutes: max(1, (route.expectedTravelTime / 60).rounded())
            )
        } catch {
            return straightLineEstimate(from: start, to: end)
        }
    }

    private func straightLineEstimate(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> RideRequestLegEstimate {
        let miles = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude)) / 1609.344
        let adjustedMiles = (miles * 1.25 * 10).rounded() / 10
        return RideRequestLegEstimate(
            distanceMiles: adjustedMiles,
            durationMinutes: max(1, (adjustedMiles / 24.0 * 60).rounded())
        )
    }

    private func runCountdown() async {
        await MainActor.run {
            secondsRemaining = 15
            didRespond = false
        }
        for second in stride(from: 14, through: 0, by: -1) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled || didRespond { return }
            await MainActor.run {
                secondsRemaining = second
            }
        }
        guard !didRespond else { return }
        await MainActor.run {
            didRespond = true
            alertSound.stop()
            onTimeout()
        }
    }
}

@MainActor
private final class IncomingRideAlertSoundPlayer {
    private var player: AVAudioPlayer?

    func startLoop() {
        guard player?.isPlaying != true else { return }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true)

            if player == nil {
                guard let url = Bundle.main.url(forResource: "incoming-ride-alert", withExtension: "mp3") else {
                    return
                }
                let audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer.numberOfLoops = -1
                audioPlayer.prepareToPlay()
                player = audioPlayer
            }

            player?.currentTime = 0
            player?.play()
        } catch {
            player = nil
        }
    }

    func restartLoop() {
        stop()
        startLoop()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

private struct CountdownRing: View {
    let secondsRemaining: Int
    let totalSeconds: Int

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return max(0, min(1, Double(secondsRemaining) / Double(totalSeconds)))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.red.opacity(0.13), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Styles.rydrGradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(secondsRemaining)s")
                .font(.headline.monospacedDigit().weight(.black))
                .foregroundStyle(Color.red)
        }
        .frame(width: 58, height: 58)
        .padding(4)
        .background(Circle().fill(Color(.systemBackground)).shadow(color: Color.red.opacity(0.18), radius: 12, y: 6))
        .animation(.linear(duration: 0.25), value: secondsRemaining)
    }
}

private struct RideRequestLegEstimate: Equatable {
    let distanceMiles: Double
    let durationMinutes: Double

    var label: String {
        "\(Int(durationMinutes)) min • \(String(format: "%.1f", distanceMiles)) mi"
    }
}

private struct RideRequestMapPreview: View {
    let driver: CLLocationCoordinate2D?
    let pickup: CLLocationCoordinate2D?
    let dropoff: CLLocationCoordinate2D?

    var body: some View {
        RydrRideRequestPreviewMap(
            driver: driver,
            pickup: pickup,
            dropoff: dropoff,
            region: region
        )
        .frame(height: 238)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 12, y: 8)
    }

    private var coordinates: [CLLocationCoordinate2D] {
        [driver, pickup, dropoff].compactMap { $0 }
    }

    private var region: MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }

        let minLat = coordinates.map(\.latitude).min() ?? 33.7490
        let maxLat = coordinates.map(\.latitude).max() ?? 33.7490
        let minLng = coordinates.map(\.longitude).min() ?? -84.3880
        let maxLng = coordinates.map(\.longitude).max() ?? -84.3880
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(0.025, (maxLat - minLat) * 1.8),
                longitudeDelta: max(0.025, (maxLng - minLng) * 1.8)
            )
        )
    }

}

private struct RydrRideRequestPreviewMap: UIViewRepresentable {
    let driver: CLLocationCoordinate2D?
    let pickup: CLLocationCoordinate2D?
    let dropoff: CLLocationCoordinate2D?
    let region: MKCoordinateRegion

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsUserLocation = false
        mapView.pointOfInterestFilter = .includingAll
        mapView.tintColor = .systemRed
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.glowOverlayIDs.removeAll()
        context.coordinator.routeOverlayIDs.removeAll()
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        mapView.setRegion(region, animated: false)

        if let driver, let pickup {
            addRouteSegment([driver, pickup], to: mapView, coordinator: context.coordinator)
        }
        if let pickup, let dropoff {
            addRouteSegment([pickup, dropoff], to: mapView, coordinator: context.coordinator)
        }
        if let driver {
            mapView.addAnnotation(RydrRideRequestPreviewAnnotation(coordinate: driver, kind: .driver))
        }
        if let pickup {
            mapView.addAnnotation(RydrRideRequestPreviewAnnotation(coordinate: pickup, kind: .pickup))
        }
        if let dropoff {
            mapView.addAnnotation(RydrRideRequestPreviewAnnotation(coordinate: dropoff, kind: .dropoff))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func addRouteSegment(
        _ coordinates: [CLLocationCoordinate2D],
        to mapView: MKMapView,
        coordinator: Coordinator
    ) {
        var coordinates = coordinates
        let glowRoute = MKPolyline(coordinates: &coordinates, count: coordinates.count)
        let route = MKPolyline(coordinates: &coordinates, count: coordinates.count)
        coordinator.glowOverlayIDs.insert(ObjectIdentifier(glowRoute))
        coordinator.routeOverlayIDs.insert(ObjectIdentifier(route))
        mapView.addOverlay(glowRoute)
        mapView.addOverlay(route)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var glowOverlayIDs = Set<ObjectIdentifier>()
        var routeOverlayIDs = Set<ObjectIdentifier>()

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.lineCap = .round
            renderer.lineJoin = .round
            if glowOverlayIDs.contains(ObjectIdentifier(polyline)) {
                renderer.strokeColor = UIColor.systemRed.withAlphaComponent(0.22)
                renderer.lineWidth = 18
            } else {
                renderer.strokeColor = UIColor.systemRed
                renderer.lineWidth = 6
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? RydrRideRequestPreviewAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: annotation.kind.reuseIdentifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: annotation.kind.reuseIdentifier)
            view.annotation = annotation
            view.canShowCallout = false
            view.backgroundColor = .clear
            view.subviews.forEach { $0.removeFromSuperview() }
            let content = host(annotationView(for: annotation.kind))
            content.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(content)
            let size = content.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            view.bounds = CGRect(origin: .zero, size: size)
            NSLayoutConstraint.activate([
                content.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                content.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            return view
        }

        private func annotationView(for kind: RydrRideRequestPreviewAnnotation.Kind) -> some View {
            switch kind {
            case .driver:
                return AnyView(DriverLocationDot(isOnline: true))
            case .pickup:
                return AnyView(RydrPreviewPin(systemImage: "person.fill", title: "Pickup"))
            case .dropoff:
                return AnyView(RydrPreviewPin(systemImage: "flag.checkered", title: "Drop-off"))
            }
        }

        private func host<Content: View>(_ view: Content) -> UIView {
            let controller = UIHostingController(rootView: view)
            controller.view.backgroundColor = .clear
            let fittingSize = controller.sizeThatFits(in: CGSize(width: 180, height: 120))
            controller.view.frame = CGRect(origin: .zero, size: fittingSize)
            return controller.view
        }
    }
}

private final class RydrRideRequestPreviewAnnotation: NSObject, MKAnnotation {
    enum Kind {
        case driver
        case pickup
        case dropoff

        var reuseIdentifier: String {
            switch self {
            case .driver: return "driver"
            case .pickup: return "pickup"
            case .dropoff: return "dropoff"
            }
        }
    }

    let coordinate: CLLocationCoordinate2D
    let kind: Kind

    init(coordinate: CLLocationCoordinate2D, kind: Kind) {
        self.coordinate = coordinate
        self.kind = kind
        super.init()
    }
}

private struct RydrPreviewPin: View {
    let systemImage: String
    let title: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Styles.rydrGradient)
                    .frame(width: 42, height: 42)
                    .shadow(color: Color.red.opacity(0.32), radius: 12, y: 5)
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(.systemBackground).opacity(0.94)))
                .foregroundStyle(Color.red)
                .shadow(color: Color.black.opacity(0.10), radius: 8, y: 4)
        }
    }
}

private struct UpfrontFareHero: View {
    let fare: Double

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Upfront fare")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            Spacer()
            Text(fare, format: .currency(code: "USD"))
                .font(.system(size: 38, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Styles.rydrGradient)
                .overlay(alignment: .trailing) {
                    Image(systemName: "dollarsign.shield.fill")
                        .font(.system(size: 74, weight: .bold))
                        .foregroundStyle(.white.opacity(0.12))
                        .offset(x: 16, y: 2)
                }
        )
        .shadow(color: Color.red.opacity(0.32), radius: 22, y: 10)
    }
}

private struct RideRequestRouteDetails: View {
    let pickupAddress: String
    let dropoffAddress: String
    let pickupEstimate: RideRequestLegEstimate?
    let dropoffEstimate: RideRequestLegEstimate?

    var body: some View {
        VStack(spacing: 0) {
            RideRequestLocationRow(
                title: "Pickup",
                address: pickupAddress,
                systemImage: "person.fill",
                estimate: pickupEstimate,
                showsConnector: true
            )
            Divider()
                .padding(.leading, 60)
            RideRequestLocationRow(
                title: "Drop-off",
                address: dropoffAddress,
                systemImage: "flag.checkered",
                estimate: dropoffEstimate,
                showsConnector: false
            )
        }
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.systemBackground).opacity(0.92)))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct RideRequestLocationRow: View {
    let title: String
    let address: String
    let systemImage: String
    let estimate: RideRequestLegEstimate?
    let showsConnector: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Styles.rydrGradient)
                        .frame(width: 32, height: 32)
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.white)
                }
                if showsConnector {
                    Rectangle()
                        .fill(Styles.rydrGradient.opacity(0.45))
                        .frame(width: 3, height: 34)
                        .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Color.red)
                    Spacer()
                    Text(estimate?.label ?? "-- min • -- mi")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Text(address)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct RiderMiniProfile: View {
    let name: String
    let photoURL: String?
    let rating: Double?
    let isVerifiedRider: Bool

    var body: some View {
        HStack(spacing: 8) {
            avatar
                .frame(width: 38, height: 38)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.75), lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.yellow)
                    Text(rating.map { String(format: "%.2f", $0) } ?? "New")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if isVerifiedRider {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                            .accessibilityLabel("Verified Rider")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let photoURL, let url = URL(string: photoURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(Styles.rydrGradient)
                }
            }
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(Styles.rydrGradient)
        }
    }
}
