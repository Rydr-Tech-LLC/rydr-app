//
//  DriverRideInProgressView.swift
//  RydrDriver
//
//  Driver turn-by-turn ride workflow.
//

import SwiftUI
import MapKit
import CoreLocation
import Combine

private enum DriverRideLifecyclePhase {
    case accepted
    case navigatingToPickup
    case waitingForRider
    case navigatingToStop
    case waitingAtStop
    case navigatingToDropoff
    case completed
}

struct DriverRideInProgressView: View {
    let ride: DriverActiveRide
    let currentDriverId: String
    let driverCoordinate: CLLocationCoordinate2D?
    let driverSpeedMetersPerSecond: CLLocationSpeed?
    let isUpdatingRide: Bool
    let onStartNavigation: () -> Void
    let onArrivedAtPickup: () -> Void
    let onStartRide: () -> Void
    let onArrivedAtStop: () -> Void
    let onHeadToDropoff: () -> Void
    let onCompleteRide: () -> Void
    let onPickupPaidWaitStarted: () -> Void
    let onCancel: (_ reason: String) -> Void
    let onReportIncident: () -> Void
    let onRidePreferencesDismissed: (_ preferences: DriverVisibleRidePreferences) -> Void
    let onSendMessage: (_ text: String) async throws -> Void
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
    @State private var isRouteTrayExpanded = false
    @State private var isNavigationStarted = false
    @State private var now = Date()
    @State private var didPublishPickupPaidWait = false
    @State private var pendingRidePreferences: DriverVisibleRidePreferences?
    @State private var presentedRidePreferencesRideId: String?

    private let arrivalThresholdMeters: CLLocationDistance = 250
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            map
                .ignoresSafeArea()

            topInstructionCard
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            routeControlTray
            .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear {
            camera = .region(region)
            presentRidePreferencesIfNeeded()
        }
        .onChange(of: ride.id) { _, _ in
            isNavigationStarted = false
            presentedRidePreferencesRideId = nil
            camera = .region(region)
            presentRidePreferencesIfNeeded()
        }
        .onChange(of: ride.ridePreferences) { _, _ in
            presentRidePreferencesIfNeeded()
        }
        .onChange(of: ride.normalizedStatus) { _, newStatus in
            if ["inProgress", "navigatingToStop"].contains(newStatus) {
                startNavigation()
            }
        }
        .onReceive(timer) { value in
            now = value
            if lifecyclePhase == .waitingForRider,
               ride.pickupPaidWaitStartedAt == nil,
               pickupPaidWaitActive,
               !didPublishPickupPaidWait {
                didPublishPickupPaidWait = true
                onPickupPaidWaitStarted()
            }
        }
        .onChange(of: routeCameraKey) { _, _ in
            guard isNavigationStarted else { return }
            camera = .camera(navigationCamera)
        }
        .task(id: routeCalculationKey) {
            await calculateRoute()
        }
        .confirmationDialog("Why are you cancelling?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            ForEach(driverCancellationReasons, id: \.self) { reason in
                Button(reason, role: .destructive) {
                    onCancel(reason)
                }
            }
            Button("Keep Ride", role: .cancel) { }
        } message: {
            Text("The rider will be notified and this reason will be saved with the ride.")
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
                rideId: ride.id,
                riderId: ride.riderId,
                driverId: currentDriverId,
                riderName: ride.riderName,
                driverSpeedMetersPerSecond: driverSpeedMetersPerSecond,
                onSend: onSendMessage
            )
            .presentationDetents([.medium])
        }
        .sheet(item: $pendingRidePreferences) { preferences in
            DriverRidePreferencesPopup(
                riderName: ride.riderName,
                preferences: preferences,
                onDismiss: {
                    onRidePreferencesDismissed(preferences)
                    pendingRidePreferences = nil
                }
            )
            .presentationDetents([.medium])
            .interactiveDismissDisabled()
        }
    }

    private func presentRidePreferencesIfNeeded() {
        guard presentedRidePreferencesRideId != ride.id,
              let preferences = ride.ridePreferences,
              !preferences.isEmpty else {
            return
        }
        presentedRidePreferencesRideId = ride.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            pendingRidePreferences = preferences
        }
    }

    private var map: some View {
        RydrDriverNavigationMapView(
            position: $camera,
            driverCoordinate: driverCoordinate,
            pickupCoordinate: ride.pickupCoordinate,
            dropoffCoordinate: primaryDestinationCoordinate,
            routeCoordinates: displayedRouteCoordinates,
            isPickupStage: isPickupStage,
            heading: routeHeading,
            onRecenter: { camera = .camera(navigationCamera) }
        )
    }

    private var topInstructionCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: instructionIcon)
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text(navigationInstruction)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.70)

                    Text(stageTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)

                    if !isNavigationStarted {
                        Button {
                            if lifecyclePhase == .accepted {
                                handlePrimaryAction()
                            } else {
                                startNavigation()
                            }
                        } label: {
                            Label("Start Navigation", systemImage: "location.north.line.fill")
                                .font(.caption.weight(.black))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Styles.rydrGradient))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 5)
                        .accessibilityLabel("Start Rydr Map navigation")
                        .accessibilityHint("Switches the map into ground-level in-app navigation.")
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.66))
            )

            HStack(spacing: 16) {
                Image(systemName: "arrow.turn.up.right")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.70))
                    .frame(width: 54)

                Text(upcomingInstruction)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.48))
            )
            .offset(y: -1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 24, y: 12)
    }

    private var routeControlTray: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.black.opacity(0.28))
                .frame(width: 54, height: 5)
                .padding(.top, 8)

            HStack(spacing: 8) {
                NavigationMetric(value: arrivalTimeText, label: "arrival")
                NavigationMetric(value: travelTimeText, label: "min")
                NavigationMetric(value: distanceText, label: "mi")
            }

            if isRouteTrayExpanded {
                expandedRouteActions
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, isRouteTrayExpanded ? 18 : 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(Color.white.opacity(0.76))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(Color.white.opacity(0.80), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.22), radius: 22, y: 10)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        if value.translation.height < -24 {
                            isRouteTrayExpanded = true
                        } else if value.translation.height > 24 {
                            isRouteTrayExpanded = false
                        } else {
                            isRouteTrayExpanded.toggle()
                        }
                    }
                }
        )
        .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isRouteTrayExpanded.toggle()
            }
        }
    }

    private var expandedRouteActions: some View {
        VStack(spacing: 12) {
            RouteSummaryRow(
                title: primaryDestinationTitle,
                address: primaryDestinationAddress,
                systemImage: primaryDestinationIcon,
                isNearby: canTapPrimaryAction
            )

            NavigationDetailRow(icon: "person.crop.circle.fill", title: ride.riderName, subtitle: ride.rideType)

            if let fareText {
                NavigationDetailRow(icon: "dollarsign.circle.fill", title: fareText, subtitle: "Upfront fare")
            }

            if shouldShowWaitingState {
                waitStateCard
            }

            VStack(spacing: 0) {
                navigationOption("Open in \(DriverNavigationHandoff.currentProvider.title)", icon: DriverNavigationHandoff.currentProvider.icon) {
                    openNavigation(provider: DriverNavigationHandoff.currentProvider)
                }
                Divider().padding(.leading, 58)
                if canMessageRider {
                    navigationOption("Message Rider", icon: "message.fill") {
                        showMessageSheet = true
                    }
                    Divider().padding(.leading, 58)
                }
                navigationOption("Report an Incident", icon: "exclamationmark.bubble.fill", color: .red) {
                    showIncidentConfirm = true
                }
                Divider().padding(.leading, 58)
                if shouldShowCancelRideButton {
                    navigationOption("Cancel Ride", icon: "xmark.circle.fill", color: .red) {
                        showCancelConfirm = true
                    }
                    Divider().padding(.leading, 58)
                }
                navigationOption("Recenter Navigation", icon: "location.fill") {
                    startNavigation()
                }
            }
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.05)))

            Button {
                handlePrimaryAction()
            } label: {
                HStack(spacing: 8) {
                    if isUpdatingRide {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(primaryActionTitle)
                }
                .font(.headline.weight(.black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(canTapPrimaryAction ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color(.systemGray4)))
                )
                .foregroundStyle(.white)
            }
            .disabled(!canTapPrimaryAction || isUpdatingRide)
            .accessibilityLabel(primaryActionTitle)
            .accessibilityHint(canTapPrimaryAction ? "Updates the ride to the next phase." : disabledActionMessage)

            if !canTapPrimaryAction {
                Text(disabledActionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
    }

    private var lifecyclePhase: DriverRideLifecyclePhase {
        switch ride.normalizedStatus {
        case "accepted":
            return .accepted
        case "enRouteToPickup", "navigatingToPickup":
            return .navigatingToPickup
        case "arrivedAtPickup", "waitingForRider":
            return .waitingForRider
        case "navigatingToStop":
            return .navigatingToStop
        case "arrivedAtStop", "waitingAtStop":
            return .waitingAtStop
        case "completed":
            return .completed
        default:
            return .navigatingToDropoff
        }
    }

    private var shouldShowWaitingState: Bool {
        lifecyclePhase == .waitingForRider || lifecyclePhase == .waitingAtStop
    }

    private var pickupWaitStartedAt: Date {
        ride.pickupWaitStartedAt ?? ride.arrivedAtPickupAt ?? now
    }

    private var pickupWaitElapsed: TimeInterval {
        max(0, now.timeIntervalSince(pickupWaitStartedAt))
    }

    private var pickupComplimentaryRemaining: TimeInterval {
        max(0, DriverActiveRide.pickupComplimentaryWaitSeconds - pickupWaitElapsed)
    }

    private var pickupPaidWaitActive: Bool {
        ride.pickupPaidWaitStartedAt != nil || pickupWaitElapsed >= DriverActiveRide.pickupComplimentaryWaitSeconds
    }

    private var stopWaitStartedAt: Date {
        ride.stopWaitStartedAt ?? ride.arrivedAtStopAt ?? now
    }

    private var stopWaitElapsed: TimeInterval {
        max(0, now.timeIntervalSince(stopWaitStartedAt))
    }

    private var waitStateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(waitStateTitle)
                .font(.headline.weight(.black))
                .foregroundStyle(.primary)

            Text(waitStateSubtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(waitStateMetricLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(waitStateMetricValue)
                    .font(.title2.weight(.black).monospacedDigit())
                    .foregroundStyle(pickupPaidWaitActive || lifecyclePhase == .waitingAtStop ? Color.green : Color.primary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.05)))
    }

    private var waitStateTitle: String {
        if lifecyclePhase == .waitingAtStop { return "Waiting at stop" }
        return pickupPaidWaitActive ? "Paid wait time active" : "Waiting for rider"
    }

    private var waitStateSubtitle: String {
        if lifecyclePhase == .waitingAtStop {
            return "Paid wait time is active. You're earning your per-minute rate while waiting."
        }
        if pickupPaidWaitActive {
            return "You're earning your per-minute rate while waiting."
        }
        return "\(ride.riderName) has been notified that you've arrived."
    }

    private var waitStateMetricLabel: String {
        if lifecyclePhase == .waitingAtStop { return "Paid stop wait" }
        return pickupPaidWaitActive ? "Paid wait active" : "Complimentary wait time"
    }

    private var waitStateMetricValue: String {
        if lifecyclePhase == .waitingAtStop {
            return formattedDuration(stopWaitElapsed)
        }
        return pickupPaidWaitActive ? formattedDuration(pickupWaitElapsed - DriverActiveRide.pickupComplimentaryWaitSeconds) : formattedDuration(pickupComplimentaryRemaining)
    }

    private var shouldShowCancelRideButton: Bool {
        lifecyclePhase != .completed
    }

    private var canMessageRider: Bool {
        [.accepted, .navigatingToPickup, .waitingForRider].contains(lifecyclePhase)
    }

    private var driverCancellationReasons: [String] {
        [
            "Destination too far",
            "Ride undesirable",
            "Accepted by mistake",
            "Deciding to go offline",
            "Rider no-show",
            "Safety concern",
            "Other"
        ]
    }

    private var disabledActionMessage: String {
        switch lifecyclePhase {
        case .navigatingToPickup:
            return "I've Arrived unlocks when you are near the pickup location."
        case .navigatingToStop:
            return "Arrived at Stop unlocks when you are near the added stop."
        case .navigatingToDropoff:
            return "Complete Ride unlocks when you are near the final drop-off."
        default:
            return "This action is unavailable right now."
        }
    }

    private var stageTitle: String {
        switch lifecyclePhase {
        case .accepted: return "Ride accepted"
        case .navigatingToPickup: return "Navigate to pickup"
        case .waitingForRider: return pickupPaidWaitActive ? "Paid wait time active" : "Waiting for rider"
        case .navigatingToStop: return "Navigate to stop"
        case .waitingAtStop: return "Waiting at stop"
        case .navigatingToDropoff: return "Navigate to drop-off"
        case .completed: return "Completed"
        }
    }

    private var isPickupStage: Bool {
        [.accepted, .navigatingToPickup, .waitingForRider].contains(lifecyclePhase)
    }

    private var primaryDestinationTitle: String {
        switch lifecyclePhase {
        case .accepted, .navigatingToPickup, .waitingForRider:
            return "Pickup"
        case .navigatingToStop, .waitingAtStop:
            return "Stop"
        case .navigatingToDropoff, .completed:
            return "Drop-off"
        }
    }

    private var primaryDestinationAddress: String {
        switch lifecyclePhase {
        case .accepted, .navigatingToPickup, .waitingForRider:
            return ride.pickup
        case .navigatingToStop, .waitingAtStop:
            return ride.stop ?? "Added stop"
        case .navigatingToDropoff, .completed:
            return ride.dropoff
        }
    }

    private var primaryDestinationIcon: String {
        switch lifecyclePhase {
        case .accepted, .navigatingToPickup, .waitingForRider:
            return "mappin.circle.fill"
        case .navigatingToStop, .waitingAtStop:
            return "pause.circle.fill"
        case .navigatingToDropoff, .completed:
            return "flag.checkered.circle.fill"
        }
    }

    private var primaryActionTitle: String {
        switch lifecyclePhase {
        case .accepted: return "Start Navigation"
        case .navigatingToPickup: return "I've Arrived"
        case .waitingForRider: return "Start Ride"
        case .navigatingToStop: return "Arrived at Stop"
        case .waitingAtStop: return "Head to Drop-off"
        case .navigatingToDropoff: return "Complete Ride"
        case .completed: return "Back to Dashboard"
        }
    }

    private var navigationInstruction: String {
        if lifecyclePhase == .accepted {
            return "Start Rydr Map navigation to pickup."
        }
        if lifecyclePhase == .waitingForRider {
            return pickupPaidWaitActive ? "Paid wait time active." : "Waiting for rider."
        }
        if lifecyclePhase == .waitingAtStop {
            return "Paid wait time is active."
        }
        if lifecyclePhase == .navigatingToDropoff && canTapPrimaryAction {
            return "You are near drop-off. Complete the ride when safe."
        }
        if lifecyclePhase == .navigatingToPickup && canTapPrimaryAction {
            return "You are at pickup. Mark arrival for the rider."
        }
        if lifecyclePhase == .navigatingToStop && canTapPrimaryAction {
            return "You are at the added stop."
        }

        if let nextStep = routeSteps.first, !nextStep.isEmpty {
            return nextStep
        }

        return "Calculating Rydr route to \(primaryDestinationTitle.lowercased())."
    }

    private var upcomingInstruction: String {
        routeSteps.dropFirst().first ?? primaryDestinationAddress
    }

    private var instructionIcon: String {
        let instruction = navigationInstruction.lowercased()
        if instruction.contains("left") { return "arrow.turn.up.left" }
        if instruction.contains("right") { return "arrow.turn.up.right" }
        if instruction.contains("arrived") || instruction.contains("pickup") || instruction.contains("drop-off") || instruction.contains("stop") {
            return isPickupStage ? "mappin.circle.fill" : "flag.checkered.circle.fill"
        }
        return "arrow.up"
    }

    private var arrivalTimeText: String {
        guard let routeTravelTime else { return "--" }
        return Date.now.addingTimeInterval(routeTravelTime).formatted(date: .omitted, time: .shortened)
    }

    private var travelTimeText: String {
        guard let routeTravelTime else { return "--" }
        let minutes = max(1, Int((routeTravelTime / 60).rounded()))
        return "\(minutes)"
    }

    private var distanceText: String {
        guard let routeDistanceMeters else { return "--" }
        return String(format: "%.1f", routeDistanceMeters / 1609.344)
    }

    private var fareText: String? {
        ride.estimatedFare?.formatted(.currency(code: "USD"))
    }

    private var primaryDestinationCoordinate: CLLocationCoordinate2D? {
        switch lifecyclePhase {
        case .accepted, .navigatingToPickup, .waitingForRider:
            return ride.pickupCoordinate
        case .navigatingToStop, .waitingAtStop:
            return ride.stopCoordinate
        case .navigatingToDropoff, .completed:
            return ride.dropoffCoordinate
        }
    }

    private var canTapPrimaryAction: Bool {
        if [.accepted, .waitingForRider, .waitingAtStop, .completed].contains(lifecyclePhase) {
            return true
        }
        guard let driverCoordinate, let destination = primaryDestinationCoordinate else { return false }
        return CLLocation(latitude: driverCoordinate.latitude, longitude: driverCoordinate.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude)) <= arrivalThresholdMeters
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        [driverCoordinate, primaryDestinationCoordinate].compactMap { $0 }
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

    private var navigationCamera: MapCamera {
        let driver = driverCoordinate ?? displayedRouteCoordinates.first ?? primaryDestinationCoordinate ?? DriverMapDefaults.pilotCoordinate
        let heading = routeHeading
        // Offset the look-at point ahead of the vehicle (rather than centering directly
        // on it) so the marker settles in the lower third of the screen with more road
        // visible ahead — the cinematic framing Apple Maps uses for turn-by-turn.
        let lookAheadCenter = driver.offset(bearingDegrees: heading, distanceMeters: 60)
        return MapCamera(
            centerCoordinate: lookAheadCenter,
            distance: 800,
            heading: heading,
            pitch: 65
        )
    }

    private func startNavigation() {
        isNavigationStarted = true
        withAnimation(.easeInOut(duration: 0.28)) {
            camera = .camera(navigationCamera)
        }
    }

    private func handlePrimaryAction() {
        switch lifecyclePhase {
        case .accepted:
            startNavigation()
            onStartNavigation()
        case .navigatingToPickup:
            onArrivedAtPickup()
        case .waitingForRider:
            onStartRide()
            startNavigation()
        case .navigatingToStop:
            onArrivedAtStop()
        case .waitingAtStop:
            onHeadToDropoff()
            startNavigation()
        case .navigatingToDropoff:
            onCompleteRide()
        case .completed:
            onCompleteRide()
        }
    }

    private func openNavigation(provider: DriverNavigationProvider) {
        switch provider {
        case .rydr:
            startNavigation()
        case .appleMaps, .googleMaps, .waze:
            guard let destination = primaryDestinationCoordinate else { return }
            DriverNavigationHandoff.open(
                provider: provider,
                coordinate: destination,
                name: primaryDestinationAddress
            )
        }
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var routeHeading: CLLocationDirection {
        let coordinates = displayedRouteCoordinates
        guard coordinates.count >= 2 else { return 0 }
        let origin = driverCoordinate ?? coordinates[0]
        let target = coordinates.dropFirst().first ?? coordinates[1]
        return bearing(from: origin, to: target)
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
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: driverCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
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
            camera = isNavigationStarted
                ? .camera(navigationCamera)
                : .region(region(for: calculatedRouteCoordinates))
        } catch {
            calculatedRouteCoordinates = []
            routeSteps = []
            routeDistanceMeters = nil
            routeTravelTime = nil
        }
    }

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

    private func navigationOption(
        _ title: String,
        icon: String,
        color: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(color == .primary ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(color))
                    .frame(width: 34, height: 34)

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(color)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    private func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coordinates = Array(repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}

private extension CLLocationCoordinate2D {
    /// Returns the coordinate `distanceMeters` away from `self` along `bearingDegrees`,
    /// using the standard spherical-Earth destination-point formula.
    func offset(bearingDegrees: CLLocationDirection, distanceMeters: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let angularDistance = distanceMeters / earthRadius

        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}

private struct NavigationMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 31, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct NavigationDetailRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Styles.rydrGradient))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.05)))
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

private struct DriverRidePreferencesPopup: View {
    let riderName: String
    let preferences: DriverVisibleRidePreferences
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Styles.rydrGradient.opacity(0.18))
                    .frame(width: 72, height: 72)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(Styles.rydrGradient)
            }

            VStack(spacing: 8) {
                Text("Rider Preferences")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.primary)
                Text("\(riderName) shared these ride preferences.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(preferences.summaryItems, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))

            Button(action: onDismiss) {
                Text("Dismiss")
                    .font(.headline.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Styles.rydrGradient))
                    .foregroundStyle(.white)
            }
        }
        .padding(24)
        .presentationBackground(.regularMaterial)
    }
}

private struct DriverRideMessageSheet: View {
    let rideId: String
    let riderId: String
    let driverId: String
    let riderName: String
    let driverSpeedMetersPerSecond: CLLocationSpeed?
    let onSend: (_ text: String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [DriverRideChatMessage] = []
    @State private var message = ""
    @State private var isSending = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var listener: DriverRideChatListener?
    @State private var privateListener: DriverRideChatListener?
    @State private var privateMessages: [DriverRideChatMessage] = []
    @State private var setupTask: Task<Void, Never>?

    private let service = DriverRideChatService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chatList

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    if isDriverMoving {
                        Label("Messaging is locked while motion is detected.", systemImage: "car.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        quickReplies

                        TextEditor(text: $message)
                            .frame(minHeight: 84, maxHeight: 110)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06), lineWidth: 1))
                    }

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
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Message \(riderName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: startChat)
            .onDisappear(perform: stopChat)
        }
    }

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if isLoading {
                        ProgressView("Loading chat...")
                            .padding(.top, 30)
                    } else if combinedMessages.isEmpty {
                        ContentUnavailableView(
                            "No messages yet",
                            systemImage: "message",
                            description: Text("Use quick updates when stopped.")
                        )
                        .padding(.top, 36)
                    } else {
                        ForEach(combinedMessages) { chatMessage in
                            chatBubble(chatMessage)
                                .id(chatMessage.id)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .onChange(of: combinedMessages.count, initial: false) { _, _ in
                guard let latest = combinedMessages.last else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(latest.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var quickReplies: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickMessage("I am on my way.")
                quickMessage("I have arrived.")
                quickMessage("I am looking for you.")
            }
        }
    }

    private var combinedMessages: [DriverRideChatMessage] {
        (messages + privateMessages).sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.id < rhs.id }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private var canSend: Bool {
        !isDriverMoving && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private var isDriverMoving: Bool {
        guard let speed = driverSpeedMetersPerSecond, speed >= 0 else { return false }
        return speed >= 2.7
    }

    private func chatBubble(_ chatMessage: DriverRideChatMessage) -> some View {
        if chatMessage.isPrivateDriverNote {
            return AnyView(
                HStack {
                    Label(chatMessage.text, systemImage: "lock.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemBackground)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                }
            )
        }
        let isDriverMessage = chatMessage.senderId == driverId || chatMessage.senderRole == "driver"

        return AnyView(HStack {
            if isDriverMessage { Spacer(minLength: 48) }

            Text(chatMessage.text)
                .font(.body)
                .foregroundStyle(isDriverMessage ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(isDriverMessage ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color(.systemBackground)))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isDriverMessage ? Color.clear : Color.black.opacity(0.06), lineWidth: 1)
                )

            if !isDriverMessage { Spacer(minLength: 48) }
        })
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

    private func startChat() {
        guard setupTask == nil, listener == nil else { return }
        isLoading = true

        setupTask = Task {
            do {
                try await service.createOrInitializeChat(rideId: rideId, riderId: riderId, driverId: driverId)
                let registration = try await service.listenToMessages(
                    rideId: rideId,
                    riderId: riderId,
                    driverId: driverId
                ) { result in
                    Task { @MainActor in
                        switch result {
                        case .success(let newMessages):
                            messages = newMessages
                            isLoading = false
                            errorMessage = nil
                        case .failure(let error):
                            isLoading = false
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                let privateRegistration = try await service.listenToDriverPrivateMessages(
                    rideId: rideId,
                    riderId: riderId,
                    driverId: driverId
                ) { result in
                    Task { @MainActor in
                        switch result {
                        case .success(let newMessages):
                            privateMessages = newMessages
                            errorMessage = nil
                        case .failure(let error):
                            errorMessage = error.localizedDescription
                        }
                    }
                }

                guard !Task.isCancelled else {
                    service.stopListening(registration)
                    service.stopListening(privateRegistration)
                    return
                }

                await MainActor.run {
                    listener = registration
                    privateListener = privateRegistration
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func stopChat() {
        setupTask?.cancel()
        setupTask = nil
        service.stopListening(listener)
        service.stopListening(privateListener)
        listener = nil
        privateListener = nil
    }

    private func send() {
        guard !isDriverMoving else {
            errorMessage = "Stop the vehicle before sending a message."
            return
        }
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
