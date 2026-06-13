//
//  DriverRideInProgressView.swift
//  RydrDriver
//
//  Driver turn-by-turn ride workflow.
//

import SwiftUI
import MapKit
import CoreLocation

struct DriverRideInProgressView: View {
    let ride: DriverActiveRide
    let driverCoordinate: CLLocationCoordinate2D?
    let onPickup: () -> Void
    let onDropoff: () -> Void
    let onCancel: () -> Void
    let onReportIncident: () -> Void
    let onSendMessage: (_ text: String) async throws -> Void
    #if DEBUG
    let onDebugMoveToDestination: () -> Void
    let onDebugMoveDriver: (_ coordinate: CLLocationCoordinate2D) -> Void
    #endif

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )
    @State private var showCancelConfirm = false
    @State private var showIncidentConfirm = false
    @State private var showIncidentSheet = false
    @State private var showMessageSheet = false
    @State private var calculatedRouteCoordinates: [CLLocationCoordinate2D] = []
    @State private var routeSteps: [String] = []
    @State private var routeDistanceMeters: CLLocationDistance?
    @State private var routeTravelTime: TimeInterval?
    #if DEBUG
    @State private var isMockDrivingRoute = false
    #endif

    private let arrivalThresholdMeters: CLLocationDistance = 250

    var body: some View {
        ZStack(alignment: .bottom) {
            map
                .ignoresSafeArea()

            VStack(spacing: 12) {
                header
                actionPanel
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .onAppear {
            camera = .region(region)
        }
        .onChange(of: ride.id) { _, _ in
            camera = .region(region)
        }
        .onChange(of: routeCameraKey) { _, _ in
            camera = .region(region)
        }
        .task(id: routeCalculationKey) {
            await calculateRoute()
        }
        .confirmationDialog("Cancel this ride?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("Confirm Cancellation", role: .destructive, action: onCancel)
            Button("Keep Ride", role: .cancel) { }
        } message: {
            Text("The rider will be notified that you cancelled.")
        }
        .confirmationDialog("Report an incident", isPresented: $showIncidentConfirm, titleVisibility: .visible) {
            Button("Open Incident Report") {
                showIncidentSheet = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Use this for safety concerns, rider issues, or trip problems.")
        }
        .sheet(isPresented: $showIncidentSheet) {
            DriverIncidentReportSheet(
                ride: ride,
                onSubmit: {
                    showIncidentSheet = false
                    onReportIncident()
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showMessageSheet) {
            DriverRideMessageSheet(
                riderName: ride.riderName,
                onSend: onSendMessage
            )
            .presentationDetents([.medium])
        }
    }

    private var map: some View {
        RydrDriverNavigationMapView(
            position: $camera,
            driverCoordinate: driverCoordinate,
            pickupCoordinate: ride.pickupCoordinate,
            dropoffCoordinate: ride.dropoffCoordinate,
            routeCoordinates: displayedRouteCoordinates,
            isPickupStage: isPickupStage,
            onRecenter: { camera = .region(region) }
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stageTitle)
                    .font(.headline.weight(.black))
                Text(ride.riderName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showMessageSheet = true
            } label: {
                Image(systemName: "message.fill")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color(.systemGray5)))
                    .foregroundStyle(Styles.rydrGradient)
            }
            Button {
                showIncidentConfirm = true
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.orange.opacity(0.16)))
                    .foregroundStyle(.orange)
            }
            Button {
                showCancelConfirm = true
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color(.systemGray5)))
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.22), lineWidth: 1))
        )
    }

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            RouteSummaryRow(
                title: primaryDestinationTitle,
                address: primaryDestinationAddress,
                systemImage: primaryDestinationIcon,
                isNearby: canTapPrimaryAction
            )

            navigationStatus

            Button {
                if isPickupStage {
                    onPickup()
                } else {
                    onDropoff()
                }
            } label: {
                Text(primaryActionTitle)
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(canTapPrimaryAction ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color(.systemGray4)))
                    )
                    .foregroundStyle(.white)
            }
            .disabled(!canTapPrimaryAction)

            #if DEBUG
            Button {
                Task { await mockDriveRoute() }
            } label: {
                Label(isMockDrivingRoute ? "Mock Driving..." : "Mock Drive Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Styles.rydrGradient.opacity(displayedRouteCoordinates.count > 1 && !isMockDrivingRoute ? 1 : 0.35))
                    )
                    .foregroundStyle(.white)
            }
            .disabled(displayedRouteCoordinates.count < 2 || isMockDrivingRoute)

            Button {
                onDebugMoveToDestination()
            } label: {
                Label(debugArrivalTitle, systemImage: "scope")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.systemGray6))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.35), lineWidth: 1))
                    )
                    .foregroundStyle(.red)
            }
            #endif

            if !canTapPrimaryAction {
                Text("This action unlocks when you are near the \(isPickupStage ? "pickup" : "drop-off") location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.22), lineWidth: 1))
        )
    }

    private var navigationStatus: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.north.line.fill")
                .font(.subheadline.weight(.black))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Styles.rydrGradient))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Rydr Nav")
                    .font(.caption.weight(.black))
                VStack(alignment: .leading, spacing: 2) {
                    Text(navigationInstruction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let routeSummary {
                        Text(routeSummary)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemGray6).opacity(0.92))
        )
    }

    private var stageTitle: String {
        isPickupStage ? "Navigate to pickup" : "Ride in progress"
    }

    private var isPickupStage: Bool {
        ride.status != "inProgress"
    }

    private var primaryDestinationTitle: String {
        isPickupStage ? "Pickup" : "Drop-off"
    }

    private var primaryDestinationAddress: String {
        isPickupStage ? ride.pickup : ride.dropoff
    }

    private var primaryDestinationIcon: String {
        isPickupStage ? "mappin.circle.fill" : "flag.checkered.circle.fill"
    }

    private var primaryActionTitle: String {
        isPickupStage ? "Tap to Pick Up" : "Tap to Drop Off"
    }

    private var navigationInstruction: String {
        if canTapPrimaryAction {
            return isPickupStage
                ? "You are at pickup. Confirm when the rider is in the vehicle."
                : "You are at drop-off. Confirm once the rider exits safely."
        }

        if let nextStep = routeSteps.first, !nextStep.isEmpty {
            return nextStep
        }

        return isPickupStage
            ? "Calculating Rydr route to the pickup location."
            : "Calculating Rydr route to the drop-off location."
    }

    private var routeSummary: String? {
        guard let routeDistanceMeters, let routeTravelTime else { return nil }
        let miles = routeDistanceMeters / 1609.344
        let minutes = max(1, Int((routeTravelTime / 60).rounded()))
        return String(format: "%.1f mi • %d min", miles, minutes)
    }

    #if DEBUG
    private var debugArrivalTitle: String {
        isPickupStage ? "Mock Arrival at Pickup" : "Mock Arrival at Drop-off"
    }
    #endif

    private var primaryDestinationCoordinate: CLLocationCoordinate2D? {
        isPickupStage ? ride.pickupCoordinate : ride.dropoffCoordinate
    }

    private var canTapPrimaryAction: Bool {
        guard let driverCoordinate, let destination = primaryDestinationCoordinate else { return false }
        return CLLocation(latitude: driverCoordinate.latitude, longitude: driverCoordinate.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude)) <= arrivalThresholdMeters
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        if isPickupStage {
            return [driverCoordinate, ride.pickupCoordinate].compactMap { $0 }
        }
        return [driverCoordinate, ride.dropoffCoordinate].compactMap { $0 }
    }

    private var displayedRouteCoordinates: [CLLocationCoordinate2D] {
        calculatedRouteCoordinates.isEmpty ? routeCoordinates : calculatedRouteCoordinates
    }

    private var routeCameraKey: String {
        let coordinateKey = driverCoordinate.map { "\($0.latitude),\($0.longitude)" } ?? "none"
        return "\(ride.status)-\(coordinateKey)"
    }

    private var routeCalculationKey: String {
        let destinationKey = primaryDestinationCoordinate.map { "\($0.latitude),\($0.longitude)" } ?? "none"
        let driverKey = driverCoordinate.map { "\($0.latitude),\($0.longitude)" } ?? "none"
        return "\(ride.id)-\(ride.status)-\(driverKey)-\(destinationKey)"
    }

    private var region: MKCoordinateRegion {
        let coordinates = [driverCoordinate, ride.pickupCoordinate, ride.dropoffCoordinate].compactMap { $0 }
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
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.025, (maxLat - minLat) * 1.8),
                longitudeDelta: max(0.025, (maxLng - minLng) * 1.8)
            )
        )
    }

    @MainActor
    private func calculateRoute() async {
        guard let driverCoordinate, let destination = primaryDestinationCoordinate else {
            calculatedRouteCoordinates = []
            routeSteps = []
            routeDistanceMeters = nil
            routeTravelTime = nil
            return
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: driverCoordinate.latitude, longitude: driverCoordinate.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        request.transportType = .automobile

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return }
            calculatedRouteCoordinates = route.polyline.coordinates
            routeSteps = route.steps
                .map(\.instructions)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            routeDistanceMeters = route.distance
            routeTravelTime = route.expectedTravelTime
            camera = .region(region(for: calculatedRouteCoordinates))
        } catch {
            calculatedRouteCoordinates = []
            routeSteps = []
            routeDistanceMeters = nil
            routeTravelTime = nil
        }
    }

    #if DEBUG
    @MainActor
    private func mockDriveRoute() async {
        let coordinates = sampledRouteCoordinates(from: displayedRouteCoordinates)
        guard !coordinates.isEmpty else { return }
        isMockDrivingRoute = true
        defer { isMockDrivingRoute = false }

        for coordinate in coordinates {
            if Task.isCancelled { return }
            onDebugMoveDriver(coordinate)
            try? await Task.sleep(nanoseconds: 260_000_000)
        }
    }

    private func sampledRouteCoordinates(from coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 24 else { return coordinates }
        let step = max(1, coordinates.count / 24)
        var sampled = stride(from: 0, to: coordinates.count, by: step).map { coordinates[$0] }
        if sampled.last?.latitude != coordinates.last?.latitude || sampled.last?.longitude != coordinates.last?.longitude {
            sampled.append(coordinates.last!)
        }
        return sampled
    }
    #endif

    private func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else { return region }
        let minLat = coordinates.map(\.latitude).min() ?? DriverMapDefaults.pilotCoordinate.latitude
        let maxLat = coordinates.map(\.latitude).max() ?? DriverMapDefaults.pilotCoordinate.latitude
        let minLng = coordinates.map(\.longitude).min() ?? DriverMapDefaults.pilotCoordinate.longitude
        let maxLng = coordinates.map(\.longitude).max() ?? DriverMapDefaults.pilotCoordinate.longitude
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.018, (maxLat - minLat) * 1.6),
                longitudeDelta: max(0.018, (maxLng - minLng) * 1.6)
            )
        )
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coordinates = Array(repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}

private struct RouteSummaryRow: View {
    let title: String
    let address: String
    let systemImage: String
    let isNearby: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label(isNearby ? "Nearby" : "En route", systemImage: isNearby ? "checkmark.circle.fill" : "location.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isNearby ? .green : .secondary)
                }
                Text(address)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct DriverIncidentReportSheet: View {
    let ride: DriverActiveRide
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var details = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ride \(ride.id)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                TextEditor(text: $details)
                    .frame(minHeight: 130)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06), lineWidth: 1))

                Button {
                    onSubmit()
                } label: {
                    Text("Submit Incident Report")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Styles.rydrGradient))
                        .foregroundStyle(.white)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Report Incident")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct DriverRideMessageSheet: View {
    let riderName: String
    let onSend: (_ text: String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Message \(riderName)")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    quickMessage("I am on my way.")
                    quickMessage("I have arrived.")
                    quickMessage("I am looking for you.")
                }

                TextEditor(text: $message)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06), lineWidth: 1))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    send()
                } label: {
                    Label("Send Message", systemImage: "paperplane.fill")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(canSend ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color(.systemGray4))))
                        .foregroundStyle(.white)
                }
                .disabled(!canSend)

                Spacer()
            }
            .padding()
            .navigationTitle("Ride Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func quickMessage(_ text: String) -> some View {
        Button {
            message = text
        } label: {
            Text(text)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }

    private func send() {
        isSending = true
        errorMessage = nil
        let outgoing = message
        Task {
            do {
                try await onSend(outgoing)
                await MainActor.run {
                    isSending = false
                    message = ""
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
