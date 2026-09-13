//
//  ScheduledRideOpportunityCard.swift
//  Rydr Driver
//
//  Accept/dismiss card for a tapped opportunity marker.
//
//  Forked from IncomingRideRequestCard rather than reused: an opportunity has
//  no rider identity and no accept-window urgency, so the countdown ring,
//  alert sound, and rider profile don't apply. UpfrontFareHero and
//  RideRequestRouteDetails are reused unmodified.
//

import SwiftUI

struct ScheduledRideOpportunityCard: View {
    let opportunity: ScheduledRideOpportunity
    let eligibility: ScheduledRideOpportunityEligibility
    let quoteState: ScheduledRideQuoteState
    let onAccept: () -> Void
    let onRetryQuote: () -> Void
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

            // The rider's approved maximum is never rendered here — only
            // driverPayoutCents may be shown as earnings, so there is nothing
            // to display until the quote lands.
            payoutSection

            RideRequestRouteDetails(
                pickupAddress: opportunity.pickupArea,
                // The projection carries no destination today, so say so
                // rather than showing a blank or inventing an area.
                dropoffAddress: opportunity.destinationArea ?? "Drop-off area shared after you accept",
                pickupEstimate: nil,
                dropoffEstimate: tripEstimate
            )

            if let noticeText {
                Label(noticeText, systemImage: noticeIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(noticeColor)
            }

            actionButton
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

    // MARK: Payout

    @ViewBuilder
    private var payoutSection: some View {
        switch quoteState {
        case .ready(let quote), .repriced(let quote):
            UpfrontFareHero(fare: Double(quote.driverPayoutCents) / 100)
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Checking your pay…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .idle, .responding, .confirming, .offerSubmitted, .failed:
            EmptyView()
        }
    }

    // MARK: Action

    @ViewBuilder
    private var actionButton: some View {
        switch quoteState {
        case .failed:
            Button("Try Again", action: onRetryQuote)
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.systemGray5)))
                .foregroundStyle(Color.primary)
                .buttonStyle(.plain)

        case .offerSubmitted:
            // Terminal for Choose My Driver: the rider chooses from up to
            // three offers, so there is nothing further for the driver to do.
            Label("Offer submitted", systemImage: "checkmark.circle.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)

        default:
            Button(action: onAccept) {
                HStack {
                    if quoteState.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Text(acceptTitle)
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
            .accessibilityLabel(accessibilityTitle)
        }
    }

    /// Names the commitment, not the gesture. Under `chooseDriver` a tap
    /// submits one of three offers — calling that "Accept" would promise a
    /// ride the driver hasn't been given.
    ///
    /// A repriced quote names the amount too, so re-confirming is a deliberate
    /// agreement to the new number rather than a reflex.
    private var acceptTitle: String {
        let verb = opportunity.selectionMode == .chooseDriver ? "Submit Offer" : "Accept"
        if case .repriced(let quote) = quoteState {
            return "\(verb) · \(quote.driverPayoutDisplay)"
        }
        return verb
    }

    private var accessibilityTitle: String {
        switch quoteState {
        case .loading: return "Loading pay for this scheduled ride"
        case .responding: return "Accepting scheduled ride opportunity"
        case .confirming: return "Confirming your scheduled ride"
        default: return "Accept scheduled ride opportunity"
        }
    }

    /// Disabled until there's a real quote — without a fingerprint the server
    /// would reject it anyway.
    private var isDisabled: Bool {
        quoteState.isBusy || eligibility != .eligible || quoteState.quote == nil
    }

    // MARK: Notice line

    private var noticeText: String? {
        switch eligibility {
        case .expired:
            return "This opportunity has expired."
        case .conflicting(let reservation):
            let time = reservation.pickupTime.formatted(date: .omitted, time: .shortened)
            return "Conflicts with your \(time) ride."
        case .eligible:
            switch quoteState {
            case .repriced:
                return "The pay for this ride changed. Review it and accept again."
            case .confirming:
                // Only claim a reservation is coming when we actually know the
                // mode. An unknown projection gets neutral wording instead of
                // a promise we can't keep.
                return opportunity.selectionMode == .quick
                    ? "Confirming your reservation…"
                    : "Response submitted."
            case .offerSubmitted:
                return "The rider will choose from up to three drivers."
            case .failed(let message):
                return message
            case .ready where opportunity.selectionMode == .chooseDriver:
                // Said before the tap: responding is a bid, not a booking.
                return "This rider picks from up to three drivers."
            default:
                return nil
            }
        }
    }

    private var noticeIcon: String {
        if case .eligible = eligibility, case .offerSubmitted = quoteState {
            return "checkmark.circle.fill"
        }
        return "exclamationmark.triangle.fill"
    }

    private var noticeColor: Color {
        if case .eligible = eligibility, case .offerSubmitted = quoteState {
            return .green
        }
        return .orange
    }
}
