//
//  ScheduleTimeSelectionView.swift
//  RydrPlayground
//
//  Sprint 1 (Critical, ene):
//  "Add the Now/Schedule option and future date/time picker to the booking flow."
//  "Add Quick Schedule and Choose My Driver selection."
//
//  Presented as a sheet from BookingView's "Schedule for later" affordance.
//

import SwiftUI

struct ScheduleTimeSelectionView: View {
    @ObservedObject var scheduledRideManager: ScheduledRideManager
    let rideType: String
    let pickup: String
    let dropoff: String
    let estimate: RideEstimate
    let onCancel: () -> Void
    let onContinue: () -> Void

    private enum BookWhen: String, CaseIterable, Identifiable {
        case now, schedule
        var id: String { rawValue }
        var title: String { self == .now ? "Now" : "Schedule" }
    }

    @State private var bookWhen: BookWhen = .schedule
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Now / Schedule toggle
                    Picker("When", selection: $bookWhen) {
                        ForEach(BookWhen.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if bookWhen == .now {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Book now instead")
                                .font(.headline)
                            Text("Close this sheet to request a driver right away using the normal booking flow.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        datePickerSection
                        modeSection
                    }

                    if let validationMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(validationMessage).font(.footnote)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
                    }

                    Button {
                        continueTapped()
                    } label: {
                        Text(bookWhen == .now ? "Close" : "Continue")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .background(Styles.rydrGradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(20)
            }
            .navigationTitle("Schedule a Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private var datePickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pickup time")
                .font(.headline)
            DatePicker(
                "Pickup time",
                selection: $scheduledRideManager.requestedPickupDate,
                in: Date().addingTimeInterval(ScheduledRideManager.minimumLeadTime)...Date().addingTimeInterval(ScheduledRideManager.maximumLeadTime),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            // Time zone display requirement (Testing checklist item).
            Text("Shown in \(TimeZone.current.identifier) (\(TimeZone.current.abbreviation() ?? "local time"))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How do you want to be matched?")
                .font(.headline)

            ForEach(ScheduledRideMode.allCases) { mode in
                Button {
                    scheduledRideManager.selectedMode = mode
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: mode.systemImage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Styles.rydrGradient)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(mode.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        Image(systemName: scheduledRideManager.selectedMode == mode ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(scheduledRideManager.selectedMode == mode ? Styles.rydrGradient : LinearGradient(colors: [.gray.opacity(0.4)], startPoint: .top, endPoint: .bottom))
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(scheduledRideManager.selectedMode == mode ? Color.red.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func continueTapped() {
        if bookWhen == .now {
            onCancel()
            return
        }
        if let error = scheduledRideManager.validate(date: scheduledRideManager.requestedPickupDate) {
            validationMessage = error
            return
        }
        validationMessage = nil
        scheduledRideManager.isSchedulingForLater = true
        onContinue()
    }
}
