//
//  QuickScheduleReviewView.swift
//  RydrPlayground
//
//  Sprint 1 (Critical, ene):
//  "Build the Quick Schedule review screen showing the estimated range,
//   maximum base price, and payment method."
//
//  Used as the approval step for BOTH scheduling modes — the rider approves
//  a maximum before a request is created, whether that max is the actual
//  charge (Quick Schedule) or just a display ceiling shown before offers
//  arrive (Choose My Driver).
//
//  Acceptance criterion: "The UI distinguishes estimates from locked prices."
//  This screen deliberately never shows a single confident-looking number —
//  everything here is labeled as an estimate/approved maximum, never "your price."
//

import SwiftUI
import CoreLocation

struct QuickScheduleReviewView: View {
    @ObservedObject var scheduledRideManager: ScheduledRideManager
    @ObservedObject var rideManager: RideManager

    let rideType: String
    let pickup: String
    let dropoff: String
    let pickupCoordinate: CLLocationCoordinate2D?
    let dropoffCoordinate: CLLocationCoordinate2D?
    let estimate: RideEstimate

    let onClose: () -> Void
    let onConfirmed: (String) -> Void   // scheduledRideRequest id

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var priceRange: (low: Double, high: Double) {
        scheduledRideManager.priceRange(estimate: estimate, rideType: rideType)
    }

    private var selectedCard: PaymentCard? {
        rideManager.savedCards.indices.contains(rideManager.selectedCardIndex)
            ? rideManager.savedCards[rideManager.selectedCardIndex]
            : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    tripSummaryCard
                    priceCard
                    paymentMethodCard
                    modeReminderCard
                    whatToExpectCard

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    Button {
                        Task { await confirm() }
                    } label: {
                        if isSubmitting {
                            ProgressView().tint(.white).frame(maxWidth: .infinity)
                        } else {
                            Text("Approve & Schedule")
                                .font(.headline.weight(.bold))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 14)
                    .background(Styles.rydrGradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(isSubmitting || selectedCard == nil)
                    .opacity(selectedCard == nil ? 0.5 : 1)

                    if selectedCard == nil {
                        Text("Add a payment method before scheduling a ride.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Review & Approve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onClose)
                }
            }
        }
    }

    private var tripSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(pickup, systemImage: "circle.fill").font(.subheadline)
            Label(dropoff, systemImage: "mappin.and.ellipse").font(.subheadline)
            Divider()
            HStack {
                Image(systemName: "clock.fill")
                Text(scheduledRideManager.requestedPickupDate.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Text(scheduledRideManager.selectedMode.title)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.red.opacity(0.1)))
            }
            .font(.subheadline)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Estimated price range")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text("$\(priceRange.low, specifier: "%.2f") – $\(priceRange.high, specifier: "%.2f")")
                .font(.title2.weight(.black))

            Divider()

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Maximum you're approving")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("Not a final charge — you'll never be charged more than this.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("$\(priceRange.high, specifier: "%.2f")")
                    .font(.title3.weight(.black))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var paymentMethodCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "creditcard.fill")
                .foregroundStyle(Styles.rydrGradient)
            if let card = selectedCard {
                Text("\(card.brand) •••• \(card.last4)")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("No payment method on file")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var modeReminderCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
            Text(scheduledRideManager.selectedMode == .quickSchedule
                 ? "We'll auto-match you with the first available driver under your approved maximum."
                 : "You'll be able to choose from up to three driver offers once they start coming in.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Sets expectations up front, addressing Khris N's 8/6 feedback on the
    /// research sprint: no drivers may respond, a matched driver may cancel,
    /// edits require a fresh quote, and payment issues may surface close to
    /// pickup. Better to say this plainly here than have it be a surprise later.
    private var whatToExpectCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What to expect")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            expectRow("If no drivers respond, you can try again with one tap — no need to re-enter your trip.")
            expectRow("If your driver has to cancel, we'll look for a replacement automatically and keep you posted here.")
            expectRow("Changing your pickup, drop-off, or time requires a fresh price approval.")
            expectRow("Your payment method is confirmed closer to pickup — keep it up to date to avoid delays.")
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func expectRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func confirm() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let id = try await scheduledRideManager.createRequest(
                pickup: pickup,
                dropoff: dropoff,
                pickupCoordinate: pickupCoordinate,
                dropoffCoordinate: dropoffCoordinate,
                rideType: rideType,
                estimate: estimate,
                approvedMax: priceRange.high
            )
            onConfirmed(id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
