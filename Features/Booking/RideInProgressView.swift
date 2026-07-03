//
//  RideInProgressView.swift
//  RydrPlayground
//
//  Drop-in replacement.
//  Shows driver tile, live route polyline, actions, payment picker,
//  and presents an EndRideView when the ride completes.
//
import SwiftUI
import MapKit
import _MapKit_SwiftUI
import CoreLocation
import FirebaseAuth
import FirebaseFirestore

struct RideInProgressView: View {
    @ObservedObject var rideManager: RideManager
    @Environment(\.dismiss) private var dismiss

    // Camera we can recenter as positions change
    @State private var camera: MapCameraPosition = .automatic

    // Sheets & UI bits
    @State private var showIncidentReportSheet = false
    @State private var showReportResultAlert = false
    @State private var reportResultTitle = ""
    @State private var reportResultMessage = ""
    @State private var showChat = false
    @State private var showPaymentSheet = false
    @State private var showNotesSheet = false
    @State private var showTripOptionsSheet = false
    @State private var pickupNotes = ""
    @State private var gateCode = ""
    @State private var showEnd = false

    var body: some View {
        content
            .navigationTitle("Ride in progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { recenterCamera() }
            .onChange(of: rideManager.liveDriverCoordinate.latitude, initial: false) { _, _ in
                recenterCamera()
            }
            .onChange(of: rideManager.liveDriverCoordinate.longitude, initial: false) { _, _ in
                recenterCamera()
            }
            .onChange(of: rideManager.state, initial: false) { _, newState in
                if newState == .completed { showEnd = true }
                if newState == .selecting { dismiss() }
            }
            // Chat / payment / notes / end sheets
            .sheet(isPresented: $showChat) {
                if let context = rideManager.activeRideChatContext {
                    RideChatView(
                        rideId: context.rideId,
                        riderId: context.riderId,
                        driverId: context.driverId,
                        driverName: context.driverName
                    )
                } else {
                    RideChatUnavailableView()
                }
            }
            .sheet(isPresented: $showPaymentSheet) {
                PaymentPicker(cards: rideManager.savedCards, selected: $rideManager.selectedCardIndex)
            }
            .sheet(isPresented: $showNotesSheet) {
                PickupNotesSheet(pickupNotes: $pickupNotes, gateCode: $gateCode)
            }
            .sheet(isPresented: $showTripOptionsSheet) {
                TripOptionsSheet(
                    cancelTitle: cancelTitle,
                    onPayment: {
                        showTripOptionsSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showPaymentSheet = true
                        }
                    },
                    onOpenMaps: {
                        showTripOptionsSheet = false
                        openPreferredMap()
                    },
                    onChangePickup: { showTripOptionsSheet = false },
                    onChangeDropoff: { showTripOptionsSheet = false },
                    onAddStop: { showTripOptionsSheet = false },
                    onPickupNotes: {
                        showTripOptionsSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showNotesSheet = true
                        }
                    },
                    onReport: {
                        showTripOptionsSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showIncidentReportSheet = true
                        }
                    },
                    onCancel: {
                        showTripOptionsSheet = false
                        rideManager.riderCancelAndAutoReassign()
                    }
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showEnd) {
                EndRideView(
                    ride: rideManager.lastReceipt,
                    onDone: { dismiss() },
                    onTipSelected: { try await rideManager.applyTipToLastReceipt(cents: $0) },
                    onFeedbackSubmitted: { try await rideManager.submitDriverFeedback($0) },
                    rideManager: rideManager
                )
            }
            .sheet(isPresented: $showIncidentReportSheet) {
                IncidentReportSheet(rideManager: rideManager) {
                    reportResultTitle = "Incident report submitted"
                    reportResultMessage = "Rydr safety support will review this trip in Mission Control."
                    showReportResultAlert = true
                }
            }
            .alert(reportResultTitle, isPresented: $showReportResultAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(reportResultMessage)
            }
    }

    // MARK: content (awaiting→pickup vs on the way to drop-off)
    @ViewBuilder
    private var content: some View {
        if rideManager.currentRide?.status == .enRouteToDropoff {
            onTheWayToDropoffUI
        } else if rideManager.currentRide != nil {
            awaitingPickupUI
        } else {
            ProgressView("Updating ride...")
        }
    }

    // MARK: Awaiting pickup — features up top, map as a section
    private var awaitingPickupUI: some View {
        stackedRideUI
    }

    // MARK: En-route to drop-off — keep the same rider-facing layout
    private var onTheWayToDropoffUI: some View {
        stackedRideUI
    }

    private var stackedRideUI: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                topStatusHeader
                driverSummaryCard
                phaseInfoCard
                mapSection
                tripMetricsCard
                primaryActionsRow
                safetyCard
                tripTimelineCard
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: – UI blocks

    private var topStatusHeader: some View {
        HStack(spacing: 14) {
            phaseIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(phaseTitle)
                    .font(.title2.weight(.black))
                    .foregroundStyle(.primary)
                Text(phaseSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showIncidentReportSheet = true
            } label: {
                Label("Help", systemImage: "headphones")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(.white, in: Capsule())
                    .shadow(color: Color.black.opacity(0.08), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private var phaseIcon: some View {
        ZStack {
            Circle()
                .fill(phaseTint.opacity(0.12))
                .frame(width: 46, height: 46)
            Image(systemName: statusIcon)
                .font(.system(size: 19, weight: .black))
                .foregroundStyle(phaseIconStyle)
        }
    }

    private var driverSummaryCard: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .stroke(driverRingStyle, lineWidth: 3)
                    .frame(width: 68, height: 68)
                VehicleOrDriverImage(source: rideManager.currentRide?.driver.profileImage, contentMode: .fill) {
                    Circle()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .overlay(
                            Text(String(rideManager.currentRide?.driver.name.prefix(1) ?? "D"))
                                .font(.title3.weight(.black))
                                .foregroundStyle(.primary)
                        )
                }
                .frame(width: 58, height: 58)
                .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(rideManager.currentRide?.driver.name ?? "Driver")
                        .font(.headline.weight(.black))
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(Color.blue)
                }
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.orange)
                    Text(driverRatingText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    VehicleOrDriverImage(source: rideManager.currentRide?.driver.carImage, contentMode: .fit) {
                        Image(systemName: "car.fill").foregroundStyle(.secondary)
                    }
                    .frame(width: 20, height: 20)
                    Text(rideManager.currentRide?.driver.carMakeModel ?? "Vehicle details pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text((rideManager.currentRide?.fare ?? 0), format: .currency(code: "USD"))
                    .font(.headline.weight(.black))
                Text(rideManager.currentRide?.rideType ?? "Rydr")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Styles.rydrGradient)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.red.opacity(0.08)))
                Text("Plate pending")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color(.secondarySystemGroupedBackground)))
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
    }

    private var phaseInfoCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(phaseTint.opacity(0.35), lineWidth: 2)
                    .frame(width: 44, height: 44)
                Image(systemName: phaseInfoIcon)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(phaseIconStyle)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(phaseInfoTitle)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(phaseTint)
                Text(phaseInfoSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if isRidingToDropoff {
                Button {
                    shareRide()
                } label: {
                    Label("Share ETA", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.green, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share ride ETA")
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [phaseTint.opacity(0.10), Color(.systemBackground)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private var primaryActionsRow: some View {
        HStack(spacing: 12) {
            if isRidingToDropoff {
                labeledActionButton(title: "Share ETA", icon: "square.and.arrow.up", tint: .primary) {
                    shareRide()
                }
            } else {
                labeledActionButton(title: "Message", icon: "message.fill", tint: .primary) {
                    showChat = true
                }
            }
            labeledActionButton(title: "More", icon: "ellipsis", tint: .primary) {
                showTripOptionsSheet = true
            }
        }
    }

    private var quietControls: some View {
        Button {
            showTripOptionsSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Styles.rydrGradient)
                Text("Trip options")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var compactRideControls: some View {
        HStack(spacing: 10) {
            Button {
                shareRide()
            } label: {
                Label("Share ETA", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Button {
                showTripOptionsSheet = true
            } label: {
                Label("Options", systemImage: "ellipsis")
            }
            .buttonStyle(.bordered)
        }
    }

    private var paymentRow: some View {
        Button {
            showPaymentSheet = true
        } label: {
            HStack {
                let card = rideManager.savedCards[min(rideManager.selectedCardIndex, max(0, rideManager.savedCards.count-1))]
                Image(systemName: "creditcard.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paying with")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(card.brand) ••\(card.last4)")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text("Change")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var mapSection: some View {
        ZStack(alignment: .topTrailing) {
            map.frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
            Button {
                recenterCamera()
            } label: {
                Image(systemName: "scope")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .padding(12)
        }
    }

    private var tripMetricsCard: some View {
        HStack(spacing: 0) {
            metricColumn(value: mapEtaText, label: rideManager.currentRide?.status == .enRouteToDropoff ? "to drop-off" : "away")
            Divider().frame(height: 32)
            metricColumn(value: distanceText, label: rideManager.currentRide?.status == .enRouteToDropoff ? "remaining" : "from you")
            Divider().frame(height: 32)
            metricColumn(value: etaArrivalText, label: "arrival")
        }
        .padding(.vertical, 13)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func metricColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.black))
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var safetyCard: some View {
        Button {
            showIncidentReportSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "shield.checkered")
                    .font(.title2.weight(.black))
                    .foregroundStyle(Styles.rydrGradient)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your safety matters")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.primary)
                    Text("Your ride is insured and monitored for a safer experience.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.red.opacity(0.10), Color(.systemBackground)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var tripTimelineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.black.opacity(0.20))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)

            if let ride = rideManager.currentRide {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(pickupTimelineColor)
                            .frame(width: 12, height: 12)
                        Rectangle()
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 2, height: 30)
                        Image(systemName: "flag.fill")
                            .font(.caption)
                            .foregroundStyle(Color.red)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        routeLine(icon: "mappin.circle.fill", label: "Pickup", value: ride.pickup)
                        routeLine(icon: "flag.checkered.circle.fill", label: "Drop-off", value: ride.dropoff)
                    }

                    Spacer()

                    Button {
                        shareRide()
                    } label: {
                        Label("Share ETA", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: Map + overlays

    private var map: some View {
        RydrRideProgressMapView(
            position: $camera,
            driverCoordinate: rideManager.liveDriverCoordinate,
            pickupCoordinate: rideManager.pickupCoordinate,
            dropoffCoordinate: rideManager.dropoffCoordinate,
            routeCoordinates: legPolyline ?? []
        )
    }

    /// Coordinates for the active leg (driver→pickup, then pickup→dropoff)
    private var legPolyline: [CLLocationCoordinate2D]? {
        switch rideManager.currentRide?.status {
        case .enRouteToPickup?:
            guard let pickup = rideManager.pickupCoordinate else { return nil }
            return [rideManager.liveDriverCoordinate, pickup]
        case .waitingForRider?:
            return nil
        case .enRouteToDropoff?:
            guard let pickup = rideManager.pickupCoordinate,
                  let drop = rideManager.dropoffCoordinate else { return nil }
            return [pickup, drop]
        default:
            return nil
        }
    }

    private func recenterCamera() {
        // Fit both ends of the current leg
        guard let leg = legPolyline, leg.count == 2 else {
            camera = .region(.init(center: rideManager.liveDriverCoordinate,
                                   span: .init(latitudeDelta: 0.05, longitudeDelta: 0.05)))
            return
        }
        let a = leg[0], b = leg[1]
        let center = CLLocationCoordinate2D(latitude: (a.latitude + b.latitude)/2,
                                            longitude: (a.longitude + b.longitude)/2)
        let span = MKCoordinateSpan(latitudeDelta: abs(a.latitude - b.latitude) + 0.05,
                                    longitudeDelta: abs(a.longitude - b.longitude) + 0.05)
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: small UI bits

    private var phaseTitle: String {
        switch rideManager.currentRide?.status {
        case .enRouteToPickup?:
            return "On the way"
        case .waitingForRider?:
            return rideManager.pickupWaitSecondsRemaining > 0 ? "Driver arrived" : "Paid wait active"
        case .enRouteToDropoff?:
            return "On the way"
        default:
            return "Updating ride"
        }
    }

    private var driverRatingText: String {
        guard let rating = rideManager.currentRide?.driver.rating, rating > 0 else {
            return "Rydr verified"
        }
        return String(format: "%.1f • Rydr verified", rating)
    }

    private var phaseSubtitle: String {
        let driver = rideManager.currentRide?.driver.name ?? "Your driver"
        switch rideManager.currentRide?.status {
        case .enRouteToPickup?:
            return "\(driver) is on the way to pick you up"
        case .waitingForRider?:
            return rideManager.pickupWaitSecondsRemaining > 0
                ? "\(driver) is waiting at pickup"
                : "Paid wait time is now active"
        case .enRouteToDropoff?:
            return "You're on your way to drop-off"
        default:
            return "Getting the latest ride status"
        }
    }

    private var phaseTint: Color {
        switch rideManager.currentRide?.status {
        case .enRouteToDropoff?:
            return .green
        case .waitingForRider?:
            return rideManager.pickupWaitSecondsRemaining > 0 ? .orange : .red
        default:
            return .red
        }
    }

    private var phaseIconStyle: AnyShapeStyle {
        switch rideManager.currentRide?.status {
        case .enRouteToDropoff?:
            return AnyShapeStyle(Color.green)
        case .waitingForRider?:
            return rideManager.pickupWaitSecondsRemaining > 0
                ? AnyShapeStyle(Color.orange)
                : AnyShapeStyle(Styles.rydrGradient)
        default:
            return AnyShapeStyle(Styles.rydrGradient)
        }
    }

    private var driverRingStyle: AnyShapeStyle {
        switch rideManager.currentRide?.status {
        case .enRouteToDropoff?:
            return AnyShapeStyle(Color.green)
        default:
            return AnyShapeStyle(Styles.rydrGradient)
        }
    }

    private var phaseInfoIcon: String {
        switch rideManager.currentRide?.status {
        case .enRouteToDropoff?:
            return "person.fill.checkmark"
        case .waitingForRider?:
            return rideManager.pickupWaitSecondsRemaining > 0 ? "timer" : "dollarsign.circle.fill"
        default:
            return "car.fill"
        }
    }

    private var phaseInfoTitle: String {
        switch rideManager.currentRide?.status {
        case .enRouteToDropoff?:
            return "You're in the car"
        case .waitingForRider?:
            return rideManager.pickupWaitSecondsRemaining > 0
                ? "Complimentary wait \(pickupWaitText)"
                : "Paid wait time \(paidWaitText)"
        default:
            return "Arriving in \(etaText)"
        }
    }

    private var phaseInfoSubtitle: String {
        switch rideManager.currentRide?.status {
        case .enRouteToDropoff?:
            return "Share your ETA with someone you trust, or follow the trip below."
        case .waitingForRider?:
            if rideManager.pickupWaitSecondsRemaining > 0 {
                return "Your driver has arrived. Please head to the pickup spot."
            }
            let charge = String(format: "$%.2f", rideManager.pickupWaitCharge)
            return "Wait charges are accruing. Current wait charge: \(charge)."
        default:
            return "Your driver is heading to the pickup location."
        }
    }

    private var isRidingToDropoff: Bool {
        rideManager.currentRide?.status == .enRouteToDropoff
    }

    private var pickupTimelineColor: Color {
        switch rideManager.currentRide?.status {
        case .enRouteToDropoff?:
            return .green
        case .waitingForRider?:
            return .orange
        default:
            return .red
        }
    }

    private var distanceText: String {
        guard let destination = activeDestinationCoordinate else { return "—" }
        let from = CLLocation(latitude: rideManager.liveDriverCoordinate.latitude, longitude: rideManager.liveDriverCoordinate.longitude)
        let to = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let miles = from.distance(from: to) / 1609.344
        return String(format: "%.1f mi", max(0, miles))
    }

    private var activeDestinationCoordinate: CLLocationCoordinate2D? {
        switch rideManager.currentRide?.status {
        case .enRouteToDropoff?:
            return rideManager.dropoffCoordinate
        default:
            return rideManager.pickupCoordinate
        }
    }

    private func labeledActionButton(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func iconActionButton(icon: String, accessibilityLabel: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            .foregroundStyle(tint)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func routeLine(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }

    private var statusHeadline: String {
        switch rideManager.currentRide?.status {
        case .enRouteToPickup?:
            return "Driver arrives in \(etaText)"
        case .waitingForRider?:
            if rideManager.pickupWaitSecondsRemaining > 0 {
                return "Driver is here · \(pickupWaitText) complimentary wait"
            }
            let charge = String(format: "+$%.2f", rideManager.pickupWaitCharge)
            return "Paid wait time · \(paidWaitText) · \(charge)"
        case .enRouteToDropoff?:
            return "Heading to drop-off — arrives in \(etaText) (\(etaArrivalText))"
        default:
            return "Updating ride..."
        }
    }

    private var statusIcon: String {
        switch rideManager.currentRide?.status {
        case .enRouteToPickup?:
            return "clock.badge.checkmark"
        case .waitingForRider?:
            return "figure.wave"
        case .enRouteToDropoff?:
            return "location.fill"
        default:
            return "clock"
        }
    }

    private var etaText: String {
        let min = max(1, Int(rideManager.remainingMinutesRounded))
        return "\(min) min"
    }

    private var mapEtaText: String {
        rideManager.currentRide?.status == .waitingForRider ? "Here now" : etaText
    }

    private var pickupWaitText: String {
        let seconds = max(0, rideManager.pickupWaitSecondsRemaining)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var paidWaitText: String {
        let seconds = max(0, rideManager.paidPickupWaitSeconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var cancelTitle: String {
        rideManager.currentRide?.status == .enRouteToDropoff
            ? "End ride now"
            : "Cancel and find another driver"
    }
    
    private var etaArrivalText: String {
        let minutes = max(1, Int(rideManager.remainingMinutesRounded))
        let date = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func shareRide() {
        guard let ride = rideManager.currentRide else { return }

        let text: String
        if isRidingToDropoff {
            text = """
            I'm in my Rydr and on the way to \(ride.dropoff).
            ETA: \(etaArrivalText) (\(etaText)).
            Trip: \(ride.pickup) → \(ride.dropoff)
            """
        } else {
            text = """
            My Rydr driver is on the way.
            ETA: \(etaArrivalText) (\(etaText)).
            Trip: \(ride.pickup) → \(ride.dropoff)
            """
        }
        let avc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.rootViewController?
            .present(avc, animated: true)
    }

    private func openPreferredMap() {
        recenterCamera()
    }

    private func callDriver() {
        if let url = URL(string: "tel://5550100"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private struct TripOptionsSheet: View {
        let cancelTitle: String
        var onPayment: () -> Void
        var onOpenMaps: () -> Void
        var onChangePickup: () -> Void
        var onChangeDropoff: () -> Void
        var onAddStop: () -> Void
        var onPickupNotes: () -> Void
        var onReport: () -> Void
        var onCancel: () -> Void

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        optionRow("creditcard.fill", "Payment method", action: onPayment)
                        optionRow("map.fill", "Rydr Map", action: onOpenMaps)
                    }

                    Section {
                        optionRow("mappin.and.ellipse", "Change pickup", action: onChangePickup)
                        optionRow("flag.checkered", "Change drop-off", action: onChangeDropoff)
                        optionRow("plus", "Add stop", action: onAddStop)
                    }

                    Section {
                        optionRow("note.text", "Pickup notes / gate code", action: onPickupNotes)
                        optionRow("exclamationmark.triangle.fill", "Report an incident", action: onReport)
                    }

                    Section {
                        Button(role: .destructive, action: onCancel) {
                            Label(cancelTitle, systemImage: "xmark.circle.fill")
                        }
                    }
                }
                .navigationTitle("Trip options")
                .navigationBarTitleDisplayMode(.inline)
            }
        }

        private func optionRow(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Label(title, systemImage: icon)
            }
        }
    }

    private struct RideChatUnavailableView: View {
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                ContentUnavailableView(
                    "Ride chat unavailable",
                    systemImage: "message",
                    description: Text("Chat opens after a driver accepts your ride.")
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private struct PaymentPicker: View {
        let cards: [PaymentCard]
        @Binding var selected: Int
        var body: some View {
            Form {
                Section("Choose a card") {
                    ForEach(cards.indices, id: \.self) { i in
                        HStack {
                            Text("\(cards[i].brand) ••\(cards[i].last4)")
                            Spacer()
                            if i == selected { Image(systemName: "checkmark") }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selected = i }
                    }
                }
            }
            .navigationTitle("Payment")
        }
    }

    private struct PickupNotesSheet: View {
        @Binding var pickupNotes: String
        @Binding var gateCode: String
        var body: some View {
            Form {
                Section("Pickup notes") {
                    TextField("e.g. meet by the lobby", text: $pickupNotes)
                }
                Section("Gate code") {
                    TextField("####", text: $gateCode)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Notes")
        }
    }
}

private struct IncidentReportDraft {
    var reportType: String = IncidentReportSheet.reportTypes[0]
    var description: String = ""
}

private enum IncidentReportError: LocalizedError {
    case notSignedIn
    case missingRide
    case emptyDescription

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Please sign in again before filing a safety report."
        case .missingRide:
            return "We could not identify the active ride. Please contact support."
        case .emptyDescription:
            return "Tell us what happened so the safety team can review it."
        }
    }
}

private final class IncidentReportService {
    private let db = Firestore.firestore()

    @MainActor
    func submit(draft: IncidentReportDraft, rideManager: RideManager) async throws {
        guard let user = Auth.auth().currentUser else {
            throw IncidentReportError.notSignedIn
        }
        guard let ride = rideManager.currentRide,
              let context = rideManager.activeRideChatContext else {
            throw IncidentReportError.missingRide
        }

        let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            throw IncidentReportError.emptyDescription
        }

        let reportRef = db.collection("safetyReports").document()
        let reportId = reportRef.documentID
        let payload: [String: Any] = [
            "id": reportId,
            "reportType": draft.reportType,
            "description": description,
            "status": "open",
            "source": "ios_rider_app",
            "submittedByRole": "rider",
            "rideId": context.rideId,
            "riderId": user.uid,
            "riderName": normalized(user.displayName) ?? "Rydr rider",
            "riderEmail": user.email ?? "",
            "driverId": ride.driver.id,
            "driverName": ride.driver.name,
            "rideStatus": ride.status.rawValue,
            "rideType": ride.rideType,
            "pickup": ride.pickup,
            "dropoff": ride.dropoff,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await reportRef.setData(payload)
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct IncidentReportSheet: View {
    static let reportTypes = [
        "Unsafe driving",
        "Harassment or threat",
        "Wrong driver or vehicle",
        "Crash or emergency",
        "Other safety concern"
    ]

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var rideManager: RideManager
    var onSubmitted: () -> Void

    @State private var draft = IncidentReportDraft()
    @State private var isSubmitting = false
    @State private var inlineError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Issue", selection: $draft.reportType) {
                        ForEach(Self.reportTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }

                    TextField("Describe what happened", text: $draft.description, axis: .vertical)
                        .lineLimit(4...8)
                } header: {
                    Text("Incident details")
                } footer: {
                    Text("Reports are sent to Rydr safety support with this ride, rider, and driver attached.")
                }

                if let inlineError {
                    Section {
                        Text(inlineError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                            }
                            Text(isSubmitting ? "Submitting..." : "Submit Incident Report")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isSubmitting || draft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Report Incident")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        inlineError = nil
        defer { isSubmitting = false }

        do {
            try await IncidentReportService().submit(draft: draft, rideManager: rideManager)
            dismiss()
            onSubmitted()
        } catch {
            inlineError = error.localizedDescription
        }
    }
}
