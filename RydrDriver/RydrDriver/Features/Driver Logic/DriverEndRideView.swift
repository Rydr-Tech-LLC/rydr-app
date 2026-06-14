//
//  DriverEndRideView.swift
//  RydrDriver
//
//  Optional rider rating after a driver completes a ride.
//

import SwiftUI

struct DriverEndRideView: View {
    let ride: DriverActiveRide
    let onClose: () -> Void
    let onSubmit: (_ rating: Int?, _ feedback: String) -> Void

    @State private var rating: Int?
    @State private var feedback = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    completionHero
                    tripSummary

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rate \(ride.riderName)")
                            .font(.title2.weight(.black))
                        Text("Rating is optional. Add feedback only if it helps the next trip.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        ForEach(1...5, id: \.self) { value in
                            Button {
                                rating = value
                            } label: {
                                Image(systemName: (rating ?? 0) >= value ? "star.fill" : "star")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle((rating ?? 0) >= value ? Color.yellow : Color(.systemGray3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    TextEditor(text: $feedback)
                        .frame(minHeight: 120)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06), lineWidth: 1))

                    Button {
                        onSubmit(rating, feedback)
                    } label: {
                        Text(rating == nil && feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Back to Dashboard" : "Submit Rating")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Styles.rydrGradient))
                            .foregroundStyle(.white)
                    }
                }
                .padding()
            }
            .navigationTitle("Ride Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                    }
                    .accessibilityLabel("Close rating")
                }
            }
        }
    }

    private var completionHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 38, weight: .black))
                    .foregroundStyle(.green)
                Spacer()
                Text(ride.rideType)
                    .font(.caption.weight(.black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.20)))
            }
            Text("Ride completed")
                .font(.largeTitle.weight(.black))
                .foregroundStyle(.white)
            Text("Earnings recorded for alpha testing.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))
            Text(ride.estimatedFare.map { $0.formatted(.currency(code: "USD")) } ?? "--")
                .font(.system(size: 42, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Styles.rydrGradient)
                .overlay(alignment: .trailing) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 118, weight: .bold))
                        .foregroundStyle(.white.opacity(0.10))
                        .offset(x: 26, y: 22)
                }
        )
        .shadow(color: Color.red.opacity(0.24), radius: 20, y: 10)
    }

    private var tripSummary: some View {
        VStack(spacing: 0) {
            summaryRow(title: "Pickup", value: ride.pickup, icon: "person.fill")
            if let stop = ride.stop, !stop.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider().padding(.leading, 54)
                summaryRow(title: "Stop", value: stop, icon: "pause.circle.fill")
            }
            Divider().padding(.leading, 54)
            summaryRow(title: "Drop-off", value: ride.dropoff, icon: "flag.checkered")
            if ride.estimatedDistanceMiles != nil || ride.estimatedDurationMinutes != nil {
                Divider().padding(.leading, 54)
                summaryRow(title: "Trip", value: tripMetricsText, icon: "road.lanes")
            }
            if waitTimeText != nil {
                Divider().padding(.leading, 54)
                summaryRow(title: "Wait time", value: waitTimeText ?? "", icon: "timer")
            }
        }
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func summaryRow(title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.red.opacity(0.10)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value.isEmpty ? "Unavailable" : value)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var tripMetricsText: String {
        let distance = ride.estimatedDistanceMiles.map { String(format: "%.1f mi", $0) }
        let duration = ride.estimatedDurationMinutes.map { "\(Int($0.rounded())) min" }
        return [distance, duration].compactMap { $0 }.joined(separator: " • ")
    }

    private var waitTimeText: String? {
        let pickupPaidSeconds = paidPickupWaitSeconds
        let stopSeconds = stopWaitSeconds
        guard pickupPaidSeconds > 0 || stopSeconds > 0 else { return nil }
        var parts: [String] = []
        if pickupPaidSeconds > 0 {
            parts.append("Pickup paid wait \(formatMinutes(pickupPaidSeconds))")
        }
        if stopSeconds > 0 {
            parts.append("Stop wait \(formatMinutes(stopSeconds))")
        }
        return parts.joined(separator: " • ")
    }

    private var paidPickupWaitSeconds: TimeInterval {
        guard let start = ride.pickupPaidWaitStartedAt else { return 0 }
        return max(0, Date().timeIntervalSince(start))
    }

    private var stopWaitSeconds: TimeInterval {
        guard let start = ride.stopWaitStartedAt else { return 0 }
        return max(0, Date().timeIntervalSince(start))
    }

    private func formatMinutes(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return "\(minutes) min"
    }
}
