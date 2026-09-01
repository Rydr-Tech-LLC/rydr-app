//
//  ScheduledRidesDashboardVM.swift
//  Rydr Driver
//
//  "See What's Ahead" — the Scheduled Rides dashboard driver reach from the
//  main dashboard's floating action stack. Map opens around the driver's
//  location; eligible opportunities plot as price markers. Confirmed
//  reservations live behind a top-right button as a sheet list.
//

import SwiftUI
import Combine
import MapKit
import CoreLocation
#if canImport(_MapKit_SwiftUI)
import _MapKit_SwiftUI
#endif

// MARK: - ViewModel

final class ScheduledRidesDashboardVM: ObservableObject {
    @Published var mapPosition: MapCameraPosition = .region(DriverMapDefaults.pilotRegion)
    @Published var opportunities: [ScheduledRideOpportunity] = []
    @Published var reservations: [ScheduledRideReservation] = []
    @Published var selectedOpportunityID: String?
    @Published var isAccepting = false
    @Published var acceptError: String?
    @Published var isCancelling = false
    @Published var cancelError: String?
    @Published var isCheckingIn = false
    @Published var checkInError: String?

    private let service = ScheduledRideService()

    func eligibility(for opportunity: ScheduledRideOpportunity) -> ScheduledRideOpportunityEligibility {
        opportunity.eligibility(against: reservations)
    }

    func accept(_ opportunity: ScheduledRideOpportunity, driverId: String) async {
        guard case .eligible = eligibility(for: opportunity) else { return }

        isAccepting = true
        defer { isAccepting = false }

        do {
            let reservation = try await service.acceptOpportunity(opportunity, driverId: driverId)
            reservations.append(reservation)
            opportunities.removeAll { $0.id == opportunity.id }
            selectedOpportunityID = nil
        } catch {
            acceptError = "Couldn't accept this ride. Please try again."
        }
    }

    func cancel(_ reservation: ScheduledRideReservation, driverId: String, reason: String) async {
        isCancelling = true
        defer { isCancelling = false }

        do {
            try await service.cancelReservation(reservation.id, driverId: driverId, reason: reason)
            reservations.removeAll { $0.id == reservation.id }
        } catch {
            cancelError = "Couldn't cancel this ride. Please try again."
        }
    }

    func checkInEligibility(for reservation: ScheduledRideReservation) -> ScheduledRideCheckInEligibility {
        reservation.checkInEligibility(against: reservations)
    }

    /// The Driver app half of "At check-in, the Driver app calculates the
    /// pickup ETA using MapKit and sends it to Firebase" — reuses the same
    /// RideRequestRouteEstimator already used for the opportunity/reservation
    /// route details, so this is the same MapKit call, not a new one.
    func checkIn(_ reservation: ScheduledRideReservation, driverId: String, driverCoordinate: CLLocationCoordinate2D?) async {
        guard case .eligible = checkInEligibility(for: reservation) else { return }

        isCheckingIn = true
        defer { isCheckingIn = false }

        guard let estimate = await RideRequestRouteEstimator.estimateUsingMapKit(
            from: driverCoordinate,
            to: reservation.pickupCoordinate
        ) else {
            checkInError = "Couldn't calculate a pickup ETA. Check your location and try again."
            return
        }

        do {
            try await service.checkIn(
                reservationID: reservation.id,
                driverId: driverId,
                pickupETAMinutes: estimate.durationMinutes
            )
            if let index = reservations.firstIndex(where: { $0.id == reservation.id }) {
                reservations[index] = reservation.checkedIn(pickupETAMinutes: estimate.durationMinutes)
            }
        } catch {
            checkInError = "Couldn't check in. Please try again."
        }
    }

    func start(near coordinate: CLLocationCoordinate2D, driverId: String) async {
        mapPosition = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
            )
        )
        async let opportunitiesLoad: Void = loadOpportunities(near: coordinate)
        async let reservationsLoad: Void = loadReservations(driverId: driverId)
        _ = await (opportunitiesLoad, reservationsLoad)
    }

    func loadOpportunities(near coordinate: CLLocationCoordinate2D) async {
        do {
            opportunities = try await service.fetchEligibleOpportunities(near: coordinate, radiusMiles: 10)
        } catch {
            opportunities = []
        }
    }

    func loadReservations(driverId: String) async {
        do {
            reservations = try await service.fetchConfirmedReservations(driverId: driverId)
        } catch {
            reservations = []
        }
    }
}

// MARK: - View

struct ScheduledRidesDashboardView: View {
    let driverCoordinate: CLLocationCoordinate2D?
    let driverId: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = ScheduledRidesDashboardVM()
    @State private var showReservations = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $vm.mapPosition) {
                ForEach(vm.opportunities) { opportunity in
                    Annotation("", coordinate: opportunity.pickupCoordinate) {
                        ScheduledRideOpportunityMarker(
                            opportunity: opportunity,
                            isSelected: vm.selectedOpportunityID == opportunity.id
                        )
                        .onTapGesture {
                            vm.selectedOpportunityID = opportunity.id
                        }
                    }
                }
            }
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Circle().fill(.regularMaterial)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.primary)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Button {
                showReservations = true
            } label: {
                Circle().fill(.regularMaterial)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "list.bullet")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.primary)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .trailing)

            if let selectedOpportunity {
                ScheduledRideOpportunityCard(
                    opportunity: selectedOpportunity,
                    eligibility: vm.eligibility(for: selectedOpportunity),
                    isAccepting: vm.isAccepting,
                    onAccept: {
                        Task { await vm.accept(selectedOpportunity, driverId: driverId) }
                    },
                    onDismiss: { vm.selectedOpportunityID = nil }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .alert(
            "Couldn't Accept",
            isPresented: Binding(
                get: { vm.acceptError != nil },
                set: { isPresented in if !isPresented { vm.acceptError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.acceptError ?? "")
        }
        .task {
            await vm.start(
                near: driverCoordinate ?? DriverMapDefaults.pilotCoordinate,
                driverId: driverId
            )
        }
        .sheet(isPresented: $showReservations) {
            ScheduledRideReservationsSheet(vm: vm, driverId: driverId, driverCoordinate: driverCoordinate)
        }
    }

    private var selectedOpportunity: ScheduledRideOpportunity? {
        vm.opportunities.first { $0.id == vm.selectedOpportunityID }
    }
}

private struct ScheduledRideOpportunityMarker: View {
    let opportunity: ScheduledRideOpportunity
    let isSelected: Bool

    var body: some View {
        Text(opportunity.approvedMaximumDisplay)
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Styles.rydrGradient))
            .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
            .shadow(color: Color.red.opacity(0.28), radius: 8, y: 3)
            .scaleEffect(isSelected ? 1.12 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Reservations Sheet

private struct ScheduledRideReservationsSheet: View {
    @ObservedObject var vm: ScheduledRidesDashboardVM
    let driverId: String
    let driverCoordinate: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack {
            Group {
                if vm.reservations.isEmpty {
                    ContentUnavailableView(
                        "No Confirmed Rides",
                        systemImage: "calendar.badge.clock",
                        description: Text("Accepted scheduled rides will appear here.")
                    )
                } else {
                    List(vm.reservations) { reservation in
                        NavigationLink {
                            ScheduledRideReservationDetailView(
                                reservationID: reservation.id,
                                vm: vm,
                                driverId: driverId,
                                driverCoordinate: driverCoordinate
                            )
                        } label: {
                            ScheduledRideReservationRow(reservation: reservation)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Scheduled Reservations")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ScheduledRideReservationRow: View {
    let reservation: ScheduledRideReservation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(reservation.rideType)
                    .font(.subheadline.weight(.black))
                Spacer()
                Text(reservation.lockedBaseFareDisplay)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(Color.red)
            }

            Text("\(reservation.pickupArea) → \(reservation.destinationArea)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(reservation.pickupTime.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ScheduledRideReservationDetailView: View {
    let reservationID: String
    @ObservedObject var vm: ScheduledRidesDashboardVM
    let driverId: String
    let driverCoordinate: CLLocationCoordinate2D?

    @Environment(\.dismiss) private var dismiss
    @State private var showCancelConfirmation = false

    /// Looked up fresh on every render instead of held as a fixed snapshot —
    /// vm.checkIn/vm.cancel update vm.reservations, and this view needs to
    /// reflect that, not keep showing whatever this screen started with.
    private var reservation: ScheduledRideReservation? {
        vm.reservations.first { $0.id == reservationID }
    }

    var body: some View {
        Group {
            if let reservation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(reservation.pickupTime.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        UpfrontFareHero(fare: Double(reservation.lockedBaseFareCents) / 100)

                        RideRequestRouteDetails(
                            pickupAddress: reservation.pickupArea,
                            dropoffAddress: reservation.destinationArea,
                            pickupEstimate: nil,
                            dropoffEstimate: tripEstimate(for: reservation)
                        )

                        checkInSection(for: reservation)

                        Button(role: .destructive) {
                            showCancelConfirmation = true
                        } label: {
                            HStack {
                                if vm.isCancelling {
                                    ProgressView()
                                } else {
                                    Text("Cancel Ride")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .font(.headline.weight(.bold))
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.red, lineWidth: 1.5)
                        )
                        .foregroundStyle(Color.red)
                        .buttonStyle(.plain)
                        .disabled(vm.isCancelling)
                        .accessibilityLabel(vm.isCancelling ? "Cancelling ride" : "Cancel scheduled ride")
                    }
                    .padding(18)
                }
                .navigationTitle(reservation.rideType)
                .confirmationDialog(
                    "Why are you cancelling?",
                    isPresented: $showCancelConfirmation,
                    titleVisibility: .visible
                ) {
                    ForEach(Self.cancellationReasons, id: \.self) { reason in
                        Button(reason, role: .destructive) {
                            Task {
                                await vm.cancel(reservation, driverId: driverId, reason: reason)
                                dismiss()
                            }
                        }
                    }
                    Button("Keep Ride", role: .cancel) {}
                } message: {
                    Text("The rider will be notified and this reason will be saved with the ride.")
                }
            } else {
                // Reservation is gone from vm.reservations (e.g. cancelled
                // from elsewhere) — nothing to show, and the NavigationLink
                // will pop this screen on its own.
                EmptyView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Couldn't Cancel",
            isPresented: Binding(
                get: { vm.cancelError != nil },
                set: { isPresented in if !isPresented { vm.cancelError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.cancelError ?? "")
        }
        .alert(
            "Couldn't Check In",
            isPresented: Binding(
                get: { vm.checkInError != nil },
                set: { isPresented in if !isPresented { vm.checkInError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.checkInError ?? "")
        }
    }

    // TODO: Check In has no time gating yet — available immediately on
    // confirmation, even hours before pickup. The contract lists check-in
    // windows as a platformConfig/scheduledRides value (server-configured,
    // not a client constant), so this should read that config once it
    // exists rather than hardcoding a guess here.
    @ViewBuilder
    private func checkInSection(for reservation: ScheduledRideReservation) -> some View {
        if let checkedInAt = reservation.checkedInAt, let eta = reservation.pickupETAMinutes {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Checked in — \(Int(eta)) min to pickup")
                        .font(.subheadline.weight(.bold))
                    Text("Checked in at \(checkedInAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.green.opacity(0.10)))
        } else {
            let eligibility = vm.checkInEligibility(for: reservation)
            let isBlocked = eligibility != .eligible

            VStack(alignment: .leading, spacing: 8) {
                if case .blockedByExistingCheckIn(let other) = eligibility {
                    Label(
                        "Already checked in to your \(other.pickupTime.formatted(date: .omitted, time: .shortened)) ride. Complete or cancel it first.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                }

                Button {
                    Task { await vm.checkIn(reservation, driverId: driverId, driverCoordinate: driverCoordinate) }
                } label: {
                    HStack {
                        if vm.isCheckingIn {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Check In")
                            Image(systemName: "location.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .font(.headline.weight(.bold))
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Styles.rydrGradient))
                .foregroundStyle(.white)
                .shadow(color: Color.red.opacity(0.26), radius: 14, y: 8)
                .buttonStyle(.plain)
                .opacity(isBlocked || vm.isCheckingIn ? 0.5 : 1)
                .disabled(isBlocked || vm.isCheckingIn)
                .accessibilityLabel(vm.isCheckingIn ? "Checking in" : "Check in and calculate pickup ETA")
            }
        }
    }

    private func tripEstimate(for reservation: ScheduledRideReservation) -> RideRequestLegEstimate? {
        guard let miles = reservation.estimatedTripMiles,
              let minutes = reservation.estimatedTripMinutes else { return nil }
        return RideRequestLegEstimate(distanceMiles: miles, durationMinutes: minutes)
    }

    /// Subset of DriverRideInProgressView.driverCancellationReasons — drops
    /// "Deciding to go offline" and "Rider no-show", which only make sense
    /// once a ride is already underway, not before a scheduled pickup.
    private static let cancellationReasons: [String] = [
        "Destination too far",
        "Ride undesirable",
        "Accepted by mistake",
        "Safety concern",
        "Other"
    ]
}
