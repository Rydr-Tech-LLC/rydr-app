import SwiftUI
import CoreLocation

struct ScheduleTimeSelectionView: View {
    @ObservedObject var manager: ScheduledRideManager
    let onCancel: () -> Void
    let onContinue: () -> Void
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Choose a future pickup time. If no driver confirms before pickup, Rydr will automatically move the request into regular dispatch.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    DatePicker(
                        "Pickup time",
                        selection: $manager.requestedPickupDate,
                        in: Date().addingTimeInterval(ScheduledRideManager.minimumLeadTime)...Date().addingTimeInterval(ScheduledRideManager.maximumLeadTime),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    Text("How should we match you?").font(.headline)
                    ForEach(ScheduledRideMode.allCases) { mode in
                        Button {
                            manager.selectedMode = mode
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: mode.systemImage).font(.title3).foregroundStyle(Styles.rydrGradient)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mode.title).font(.headline).foregroundStyle(.primary)
                                    Text(mode.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: manager.selectedMode == mode ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(manager.selectedMode == mode ? Color.red : Color.secondary)
                            }
                            .padding(15)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                    if let validationMessage { Text(validationMessage).font(.footnote).foregroundStyle(.orange) }
                    Button("Continue") {
                        if let message = manager.validate(date: manager.requestedPickupDate) { validationMessage = message }
                        else { validationMessage = nil; onContinue() }
                    }
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Styles.rydrGradient).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                }.padding(20)
            }
            .navigationTitle("Schedule a Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel", action: onCancel) } }
        }
    }
}

struct ScheduledRideReviewView: View {
    @ObservedObject var manager: ScheduledRideManager
    let pickup: String
    let dropoff: String
    let pickupCoordinate: CLLocationCoordinate2D?
    let dropoffCoordinate: CLLocationCoordinate2D?
    let rideType: String
    let onClose: () -> Void
    let onCreated: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(pickup, systemImage: "circle.fill")
                        Label(dropoff, systemImage: "mappin.and.ellipse")
                        Divider()
                        Label(manager.requestedPickupDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar.badge.clock")
                    }.padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                    if manager.isWorking { ProgressView("Calculating your fare…").frame(maxWidth: .infinity) }
                    if let preview = manager.preview {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Estimated fare range").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            Text("\(money(preview.suggestedLowCents)) – \(money(preview.suggestedHighCents))").font(.title2.bold())
                            Text("\(preview.distanceMiles, specifier: "%.1f") mi • \(Int(preview.durationMinutes.rounded())) min • \(preview.eligibleDriverCount) eligible drivers")
                                .font(.caption).foregroundStyle(.secondary)
                            if manager.selectedMode == .quickSchedule {
                                Text("You approve a maximum of \(money(preview.suggestedHighCents)). The accepted driver's exact price is locked when they accept.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    }
                    Text(manager.selectedMode.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    if let error = manager.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
                    Button {
                        Task {
                            do {
                                let id = try await manager.createRequest(
                                    pickup: pickup, dropoff: dropoff,
                                    pickupCoordinate: pickupCoordinate, dropoffCoordinate: dropoffCoordinate,
                                    rideType: rideType
                                )
                                onCreated(id)
                            } catch { manager.errorMessage = error.localizedDescription }
                        }
                    } label: {
                        Text("Approve & Schedule").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .background(Styles.rydrGradient).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                    .disabled(manager.preview == nil || manager.isWorking)
                    .opacity(manager.preview == nil || manager.isWorking ? 0.5 : 1)
                }.padding(20)
            }
            .navigationTitle("Review Scheduled Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel", action: onClose) } }
            .task {
                await manager.loadPreview(
                    pickup: pickup, dropoff: dropoff,
                    pickupCoordinate: pickupCoordinate, dropoffCoordinate: dropoffCoordinate,
                    rideType: rideType
                )
            }
        }
    }

    private func money(_ cents: Int) -> String { String(format: "$%.2f", Double(cents) / 100) }
}

struct ScheduledRideStatusView: View {
    @ObservedObject var manager: ScheduledRideManager
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let request = manager.activeRequest {
                        Image(systemName: request.status == .confirmed || request.status == .active ? "checkmark.circle.fill" : "calendar.badge.clock")
                            .font(.system(size: 58)).foregroundStyle(request.status == .expired ? .orange : .green)
                        Text(request.status.title).font(.title2.bold())
                        Text(request.scheduledPickupAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 10) {
                            Label(request.pickup, systemImage: "circle.fill")
                            Label(request.dropoff, systemImage: "mappin.and.ellipse")
                            if let locked = request.lockedPriceCents {
                                Divider(); Text("Locked price: \(money(locked))").font(.headline)
                            }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                        if request.status == .awaitingRiderSelection || request.status == .replacementApprovalRequired {
                            ForEach(manager.offers) { offer in
                                Button {
                                    Task {
                                        do {
                                            try await manager.select(offer)
                                        } catch {
                                            manager.errorMessage = error.localizedDescription
                                        }
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(offer.driverName).font(.headline)
                                            Text(offer.vehicleSummary ?? "Verified Rydr vehicle").font(.caption).foregroundStyle(.secondary)
                                            Text("★ \(offer.rating, specifier: "%.1f") (\(offer.ratingCount))").font(.caption)
                                        }
                                        Spacer(); Text(money(offer.totalCents)).font(.headline)
                                    }.padding(14).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                                }.buttonStyle(.plain)
                            }
                        }
                        if ![ScheduledRideStatus.active, .completed, .cancelled].contains(request.status) {
                            Button("Cancel scheduled ride", role: .destructive) {
                                Task {
                                    do {
                                        try await manager.cancel()
                                        onClose()
                                    } catch {
                                        manager.errorMessage = error.localizedDescription
                                    }
                                }
                            }
                        }
                    } else {
                        ProgressView("Loading scheduled ride…")
                    }
                    if let error = manager.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
                }.padding(20)
            }
            .navigationTitle("Scheduled Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onClose) } }
        }
    }

    private func money(_ cents: Int) -> String { String(format: "$%.2f", Double(cents) / 100) }
}

struct ScheduledRideListView: View {
    @ObservedObject var manager: ScheduledRideManager
    let onSelect: (ScheduledRideRequest) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if manager.scheduledRequests.isEmpty {
                    ContentUnavailableView("No scheduled rides", systemImage: "calendar.badge.clock")
                }
                ForEach(manager.scheduledRequests) { request in
                    Button {
                        manager.listen(requestId: request.id)
                        onSelect(request)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(request.status.title).font(.caption.bold()).foregroundStyle(.red)
                                Spacer()
                                if let price = request.lockedPriceCents { Text(money(price)).font(.headline) }
                            }
                            Text(request.scheduledPickupAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                            Text("\(request.pickup) → \(request.dropoff)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }.padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(removalTitle(for: request), role: .destructive) {
                            Task {
                                do {
                                    try await manager.cancel(
                                        requestId: request.id,
                                        reason: removalReason(for: request)
                                    )
                                } catch {
                                    manager.errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .disabled(manager.cancellingRequestIDs.contains(request.id))
                    }
                }
            }
            .navigationTitle("My Scheduled Rides")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onClose) } }
            .alert(
                "Unable to update scheduled ride",
                isPresented: Binding(
                    get: { manager.errorMessage != nil },
                    set: { if !$0 { manager.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { manager.errorMessage = nil }
            } message: {
                Text(manager.errorMessage ?? "Please try again.")
            }
        }
    }

    private func isPastDueUndispatched(_ request: ScheduledRideRequest) -> Bool {
        request.activeRideId == nil
            && (request.status == .expired || request.scheduledPickupAt < Date())
    }

    private func removalTitle(for request: ScheduledRideRequest) -> String {
        isPastDueUndispatched(request) ? "Remove" : "Cancel"
    }

    private func removalReason(for request: ScheduledRideRequest) -> String {
        isPastDueUndispatched(request)
            ? "Rider removed an undispatched past-due scheduled ride"
            : "Rider cancelled scheduled ride"
    }

    private func money(_ cents: Int) -> String { String(format: "$%.2f", Double(cents) / 100) }
}
