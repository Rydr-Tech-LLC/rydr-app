//
//  IncomingRideRequestCard.swift
//  RydrDriver
//
//  Accept/decline card for incoming ride dispatch requests.
//

import SwiftUI
import MapKit
import CoreLocation

struct IncomingRideRequestCard: View {
    let request: DriverRideRequest
    let driverCoordinate: CLLocationCoordinate2D?
    let rate: DriverRateSetting
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onTimeout: () -> Void

    @State private var pickupLeg: RideRequestLegEstimate?
    @State private var tripLeg: RideRequestLegEstimate?
    @State private var secondsRemaining = 15
    @State private var didRespond = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Incoming \(request.rideType)")
                        .font(.headline)
                    Text("Accept or decline this request")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(secondsRemaining)s")
                    .font(.caption.monospacedDigit().weight(.black))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.red.opacity(0.14)))
                    .foregroundStyle(.red)
                RiderMiniProfile(
                    name: request.riderName,
                    photoURL: request.riderPhotoURL,
                    rating: request.riderRating
                )
            }

            RideRequestMapPreview(
                driver: driverCoordinate,
                pickup: request.pickupCoordinate,
                dropoff: request.dropoffCoordinate
            )

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Upfront fare")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Driver payout after 60/40 split")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(upfrontFare, format: .currency(code: "USD"))
                    .font(.title3.monospacedDigit().weight(.black))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))

            RideRequestLocationBreakdown(
                title: "Pickup",
                address: request.pickup,
                systemImage: "mappin.circle.fill",
                estimate: pickupLeg
            )

            RideRequestLocationBreakdown(
                title: "Drop-off",
                address: request.dropoff,
                systemImage: "flag.checkered.circle.fill",
                estimate: tripLeg ?? fallbackTripLeg
            )

            HStack(spacing: 10) {
                Button {
                    didRespond = true
                    onDecline()
                } label: {
                    Text("Decline")
                        .frame(maxWidth: .infinity)
                }
                    .font(.headline)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray5)))
                    .foregroundStyle(Color.black)

                Button {
                    didRespond = true
                    onAccept()
                } label: {
                    Text("Accept")
                        .frame(maxWidth: .infinity)
                }
                    .font(.headline)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Styles.rydrGradient))
                    .foregroundStyle(.white)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(.regularMaterial))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
        .accessibilityElement(children: .contain)
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
        if let leg = fareBaseLeg {
            let gross = (leg.distanceMiles * rate.perMile) + (leg.durationMinutes * rate.perMinute)
            return ((gross * 0.60) * 100).rounded() / 100
        }
        if let fare = request.estimatedFare {
            return ((fare * 0.60) * 100).rounded() / 100
        }
        return 0
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
        request.source = MKMapItem(
            location: CLLocation(latitude: start.latitude, longitude: start.longitude),
            address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(latitude: end.latitude, longitude: end.longitude),
            address: nil
        )
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
            onTimeout()
        }
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
        Map(position: .constant(.region(region)), interactionModes: []) {
            if let driver, let pickup {
                MapPolyline(coordinates: [driver, pickup])
                    .stroke(polylineStyle, lineWidth: 5)
            }
            if let pickup, let dropoff {
                MapPolyline(coordinates: [pickup, dropoff])
                    .stroke(polylineStyle, lineWidth: 5)
            }
            if let driver {
                Annotation("", coordinate: driver, anchor: .center) {
                    DriverLocationDot(isOnline: true)
                }
            }
            if let pickup {
                Marker("Pickup", systemImage: "mappin.circle.fill", coordinate: pickup)
                    .tint(.red)
            }
            if let dropoff {
                Marker("Drop-off", systemImage: "flag.checkered.circle.fill", coordinate: dropoff)
                    .tint(.blue)
            }
        }
        .frame(height: 176)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.26), lineWidth: 1)
        )
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

    private var polylineStyle: some ShapeStyle {
        if #available(iOS 18.0, *) {
            return Styles.rydrGradient
        } else {
            return Color.red.opacity(0.85)
        }
    }
}

private struct RideRequestLocationBreakdown: View {
    let title: String
    let address: String
    let systemImage: String
    let estimate: RideRequestLegEstimate?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(estimate?.label ?? "-- min • -- mi")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(address)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

private struct RiderMiniProfile: View {
    let name: String
    let photoURL: String?
    let rating: Double?

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
