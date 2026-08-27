//
//  ScheduledRideOpportunityCard.swift
//  Rydr Driver
//
//  Accept/dismiss card for a tapped scheduled-ride opportunity marker.
//  Forked from IncomingRideRequestCard.swift rather than reused directly —
//  ScheduledRideOpportunity carries no rider identity, no destination
//  coordinate, and no accept-window urgency, so the countdown ring, alert
//  sound, and rider mini-profile don't apply here. UpfrontFareHero and
//  RideRequestRouteDetails do apply and are reused unmodified.
//

import SwiftUI

struct ScheduledRideOpportunityCard: View {
    let opportunity: ScheduledRideOpportunity
    let eligibility: ScheduledRideOpportunityEligibility
    let isAccepting: Bool
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scheduled \(opportunity.rideType)")
                        .font(.title3.weight(.heavy))
                    Text(opportunity.pickupTime.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.secondary)
                        .padding(8)
                        .background(Circle().fill(Color(.systemGray6)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss opportunity")
            }

            UpfrontFareHero(fare: Double(opportunity.approvedMaximumCents) / 100)

            RideRequestRouteDetails(
                pickupAddress: opportunity.pickupArea,
                dropoffAddress: opportunity.destinationArea,
                pickupEstimate: nil,
                dropoffEstimate: tripEstimate
            )

            if let ineligibleReason {
                Label(ineligibleReason, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
            }

            Button(action: onAccept) {
                HStack {
                    if isAccepting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Accept")
                        Image(systemName: "arrow.right")
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
            .opacity(isDisabled ? 0.5 : 1)
            .disabled(isDisabled)
            .accessibilityLabel(isAccepting ? "Accepting scheduled ride opportunity" : "Accept scheduled ride opportunity")
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
    }

    private var tripEstimate: RideRequestLegEstimate? {
        guard let miles = opportunity.estimatedTripMiles,
              let minutes = opportunity.estimatedTripMinutes else { return nil }
        return RideRequestLegEstimate(distanceMiles: miles, durationMinutes: minutes)
    }

    private var isDisabled: Bool {
        isAccepting || eligibility != .eligible
    }

    private var ineligibleReason: String? {
        switch eligibility {
        case .eligible:
            return nil
        case .expired:
            return "This opportunity has expired."
        case .conflicting(let reservation):
            let time = reservation.pickupTime.formatted(date: .omitted, time: .shortened)
            return "Conflicts with your \(time) ride."
        }
    }
}
