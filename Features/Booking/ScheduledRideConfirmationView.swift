//
//  ScheduledRideConfirmationView.swift
//  RydrPlayground
//
//  Sprint 1 (Critical, ene):
//  "Build the initial scheduled-ride confirmation and management screen."
//
//  Handles both scheduling modes:
//   - Quick Schedule: shows status while the backend auto-matches a driver
//     under the rider's approved maximum, then shows the locked price + driver
//     once matched.
//   - Choose My Driver: shows a waiting state, then hands off to
//     ScheduledOfferSelectionView as soon as the first offer arrives
//     (Acceptance Criteria: "Choose My Driver allows selection after the
//     first offer").
//
//  Also serves as the "manage" screen: lets the rider cancel a pending
//  scheduled ride. Cancellation is the ONLY status write this screen makes.
//

import SwiftUI

struct ScheduledRideConfirmationView: View {
    @ObservedObject var scheduledRideManager: ScheduledRideManager
    @ObservedObject var rideManager: RideManager
    let requestId: String
    let onClose: () -> Void
    /// Khris's feedback: editing trip details or retrying after "no drivers
    /// responded" shouldn't feel like starting over from scratch. Both route
    /// back through the same schedule-time entry point, but the parent
    /// (BookingView) is responsible for prefilling it with this request's
    /// existing pickup/dropoff/time so the rider isn't re-entering everything.
    var onEditTrip: (ScheduledRideRequest) -> Void = { _ in }

    @State private var isCancelling = false
    @State private var showCancelConfirm = false
    @State private var showPaymentMethodSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let request = scheduledRideManager.activeRequest {
                        statusBanner(for: request)
                        tripDetailsCard(for: request)

                        if request.status == .paymentFailed {
                            paymentFailedCard
                        }

                        if request.mode == .quickSchedule
                            && (request.status == .pendingOffers || request.status == .driverCancelledFindingReplacement) {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(request.status == .driverCancelledFindingReplacement
                                     ? "Rematching you with a new driver under your approved maximum."
                                     : "Matching you with a driver under your approved maximum.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        }

                        if request.mode == .chooseMyDriver,
                           request.status == .awaitingRiderChoice || request.status == .driverCancelledFindingReplacement || request.status == .pendingOffers {
                            ScheduledOfferSelectionView(
                                rideManager: rideManager,
                                rideType: request.rideType,
                                estimate: request.estimate,
                                offers: scheduledRideManager.offers,
                                isLoadingOffers: scheduledRideManager.isLoadingOffers,
                                onSelect: { offer in
                                    Task { await select(offer, requestId: request.id) }
                                }
                            )
                        }

                        if request.status.offersRetry {
                            Button {
                                onEditTrip(request)
                            } label: {
                                Text("Try Again")
                                    .font(.headline.weight(.bold))
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.vertical, 14)
                            .background(Styles.rydrGradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        if request.status.isActionable {
                            Button {
                                onEditTrip(request)
                            } label: {
                                Label("Edit Trip Details", systemImage: "pencil")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }

                        if canCancel(request) {
                            Button(role: .destructive) {
                                showCancelConfirm = true
                            } label: {
                                if isCancelling {
                                    ProgressView().frame(maxWidth: .infinity)
                                } else {
                                    Text("Cancel Scheduled Ride")
                                        .font(.headline.weight(.bold))
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.08))
                            .foregroundStyle(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .disabled(isCancelling)
                        }
                    } else {
                        ProgressView("Loading your scheduled ride…")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }

                    if let errorMessage = scheduledRideManager.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Scheduled Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close", action: onClose)
                }
            }
            .confirmationDialog(
                "Cancel this scheduled ride?",
                isPresented: $showCancelConfirm,
                titleVisibility: .visible
            ) {
                Button("Cancel Ride", role: .destructive) {
                    Task { await cancel() }
                }
                Button("Keep Ride", role: .cancel) {}
            } message: {
                Text("This can't be undone. A cancellation fee may apply depending on how close it is to your scheduled pickup time.")
            }
            .sheet(isPresented: $showPaymentMethodSheet) {
                NavigationStack {
                    PaymentMethodView(showsHeader: true)
                }
            }
        }
        .onAppear {
            scheduledRideManager.listen(toRequestId: requestId)
        }
        .onDisappear {
            scheduledRideManager.stopListening()
        }
    }

    private var paymentFailedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text("We couldn't charge your card").font(.subheadline.weight(.bold))
            }
            Text("Update your payment method so we can confirm this ride before pickup.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                showPaymentMethodSheet = true
            } label: {
                Text("Update Payment Method")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 10)
            .background(Styles.rydrGradient)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(14)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func canCancel(_ request: ScheduledRideRequest) -> Bool {
        request.status.isActionable || request.status == .priceLocked || request.status == .confirmed
    }

    @ViewBuilder
    private func statusBanner(for request: ScheduledRideRequest) -> some View {
        let (icon, text, tint): (String, String, Color) = {
            switch request.status {
            case .pendingOffers:
                return ("clock.fill", "Waiting for a driver", .orange)
            case .awaitingRiderChoice:
                return ("person.2.fill", "Offers ready — choose your driver", .orange)
            case .driverCancelledFindingReplacement:
                return ("arrow.triangle.2.circlepath", "Your driver had to cancel — finding you a new one", .orange)
            case .paymentFailed:
                return ("creditcard.trianglebadge.exclamationmark.fill", "Payment issue — action needed", .red)
            case .priceLocked, .confirmed:
                return ("checkmark.seal.fill", "Confirmed", .green)
            case .cancelledByRider:
                return ("xmark.circle.fill", "Cancelled", .secondary)
            case .cancelledNoDrivers:
                return ("exclamationmark.triangle.fill", "No drivers were available", .red)
            case .expired:
                return ("clock.badge.exclamationmark.fill", "This request expired", .secondary)
            case .completed:
                return ("flag.checkered", "Completed", .secondary)
            }
        }()

        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.subheadline.weight(.bold)).foregroundStyle(tint)
            Spacer()
        }
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func tripDetailsCard(for request: ScheduledRideRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(request.pickup, systemImage: "circle.fill").font(.subheadline)
            Label(request.dropoff, systemImage: "mappin.and.ellipse").font(.subheadline)
            Divider()
            HStack {
                Image(systemName: "clock.fill")
                Text(request.requestedPickupDate.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Text(request.mode.title)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.red.opacity(0.1)))
            }
            .font(.subheadline)
            Divider()
            HStack {
                if let locked = request.lockedPrice {
                    Label("Locked price", systemImage: "lock.fill")
                    Spacer()
                    Text("$\(locked, specifier: "%.2f")").font(.headline.weight(.black))
                } else {
                    Label("Approved maximum", systemImage: "shield.fill")
                    Spacer()
                    Text("up to $\(request.riderApprovedMax, specifier: "%.2f")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func select(_ offer: ScheduledDriverOffer, requestId: String) async {
        do {
            try await scheduledRideManager.selectOffer(offer, on: requestId)
        } catch {
            scheduledRideManager.errorMessage = error.localizedDescription
        }
    }

    private func cancel() async {
        isCancelling = true
        defer { isCancelling = false }
        do {
            try await scheduledRideManager.cancelRequest(requestId)
        } catch {
            scheduledRideManager.errorMessage = error.localizedDescription
        }
    }
}
