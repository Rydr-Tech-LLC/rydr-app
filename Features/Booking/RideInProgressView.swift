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

struct RideInProgressView: View {
    @ObservedObject var rideManager: RideManager
    @Environment(\.dismiss) private var dismiss

    // Camera we can recenter as positions change
    @State private var camera: MapCameraPosition = .automatic

    // Sheets & UI bits
    @State private var showReportAlert = false
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
            }
            // Chat / payment / notes / end sheets
            .sheet(isPresented: $showChat) { ChatSheet() }
            .sheet(isPresented: $showPaymentSheet) {
                PaymentPicker(cards: rideManager.savedCards, selected: $rideManager.selectedCardIndex)
            }
            .sheet(isPresented: $showNotesSheet) {
                PickupNotesSheet(pickupNotes: $pickupNotes, gateCode: $gateCode)
            }
            .sheet(isPresented: $showTripOptionsSheet) {
                TripOptionsSheet(
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
                            showReportAlert = true
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
                EndRideView(ride: rideManager.lastReceipt, onDone: { dismiss() })
            }
            .alert("Report an incident", isPresented: $showReportAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Thanks for the report. Our team will review this trip.")
            }
    }

    // MARK: content (awaiting→pickup vs on the way to drop-off)
    @ViewBuilder
    private var content: some View {
        if rideManager.currentRide?.status == .enRouteToPickup {
            awaitingPickupUI
        } else {
            onTheWayToDropoffUI
        }
    }

    // MARK: Awaiting pickup — features up top, map as a section
    private var awaitingPickupUI: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                statusCard

                primaryActionsRow

                mapSection

                quietControls

                paymentRow

                shareSection
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    // MARK: En-route to drop-off — more focus on navigation
    private var onTheWayToDropoffUI: some View {
        ZStack(alignment: .bottom) {
            map
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                statusCard
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
                primaryActionsRow
                compactRideControls
                .padding(.bottom, 12)
            }
            .padding()
        }
    }

    // MARK: – UI blocks

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        Text(String(rideManager.currentRide?.driver.name.prefix(1) ?? "D"))
                            .font(.headline.weight(.semibold))
                    )
                    .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 3) {
                    Text(rideManager.currentRide?.driver.name ?? "Driver")
                        .font(.headline)
                    Text(rideManager.currentRide?.driver.carMakeModel ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("$\(rideManager.currentRide?.fare ?? 0, specifier: "%.2f")")
                    .font(.headline.weight(.semibold))
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: rideManager.currentRide?.status == .enRouteToPickup ? "clock.badge.checkmark" : "location.fill")
                    .foregroundStyle(Styles.rydrGradient)
                Text(statusHeadline)
                    .font(.title2.weight(.bold))
                Spacer()
            }

            if let ride = rideManager.currentRide {
                VStack(alignment: .leading, spacing: 8) {
                    routeLine(icon: "mappin.circle.fill", label: "Pickup", value: ride.pickup)
                    routeLine(icon: "flag.checkered.circle.fill", label: "Drop-off", value: ride.dropoff)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var primaryActionsRow: some View {
        HStack(spacing: 10) {
            iconActionButton(icon: "message.fill", accessibilityLabel: "Message driver", tint: .red) {
                showChat = true
            }
            iconActionButton(icon: "phone.fill", accessibilityLabel: "Call driver", tint: .red) {
                callDriver()
            }
            iconActionButton(icon: "ellipsis", accessibilityLabel: "Trip options", tint: .secondary) {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live map")
                    .font(.headline)
                Spacer()
                Text(etaText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            map.frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        }
    }

    private var shareSection: some View {
        Button { shareRide() } label: {
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(Styles.rydrGradient)      // ← gradient icon
                Text("Share status & ETA (\(etaText))")
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: Map + overlays

    private var map: some View {
        Map(position: $camera) {
            if let coords = legPolyline {
                MapPolyline(coordinates: coords)
                    .stroke(polylineStyle, lineWidth: 6)
            }

            // Driver pin (custom)
            Annotation("", coordinate: rideManager.liveDriverCoordinate) {
                ZStack {
                    Circle().fill(.background).frame(width: 28, height: 28)
                    Image(systemName: "car.fill")
                        .foregroundStyle(Styles.rydrGradient)  // ← gradient car icon
                }
            }

            // Pickup / dropoff markers
            if let pickup = rideManager.pickupCoordinate {
                Marker("Pickup", coordinate: pickup)
                    .tint(.red)
            }
            if let drop = rideManager.dropoffCoordinate {
                Marker("Drop-off", coordinate: drop)
                    .tint(.blue)
            }
        }
    }

    private var polylineStyle: some ShapeStyle {
        if #available(iOS 18.0, *) {
            return Styles.rydrGradient
        } else {
            return Color.red.opacity(0.85) // iOS 17 MapPolyline can't take a gradient directly
        }
    }

    /// Coordinates for the active leg (driver→pickup, then pickup→dropoff)
    private var legPolyline: [CLLocationCoordinate2D]? {
        switch rideManager.currentRide?.status {
        case .enRouteToPickup?:
            guard let pickup = rideManager.pickupCoordinate else { return nil }
            return [rideManager.liveDriverCoordinate, pickup]
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
        if rideManager.currentRide?.status == .enRouteToPickup {
            return "Arrives in \(etaText)"
        }
        return "Heading to drop-off — arrives in \(etaText) (\(etaArrivalText))"
    }

    private var etaText: String {
        let min = max(1, Int(rideManager.remainingMinutesRounded))
        return "\(min) min"
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
        let text = "I'm on a Rydr: \(rideManager.currentRide?.pickup ?? "") → \(rideManager.currentRide?.dropoff ?? "")"
        let avc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.rootViewController?
            .present(avc, animated: true)
    }

    private func callDriver() {
        if let url = URL(string: "tel://5550100"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private struct TripOptionsSheet: View {
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
                            Label("Cancel and find another driver", systemImage: "xmark.circle.fill")
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

    // Minimal in-app chat mock
    private struct ChatSheet: View {
        @State private var text = ""
        @State private var messages: [String] = ["Driver: On my way!", "You: Great, thanks."]
        var body: some View {
            VStack {
                List(messages, id: \.self) { Text($0) }
                HStack {
                    TextField("Message", text: $text)
                        .textFieldStyle(.roundedBorder)
                    Button("Send") {
                        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        messages.append(text); text = ""
                    }
                }
                .padding()
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
