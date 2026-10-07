import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import MapKit
import CoreLocation

private struct DriverScheduledOpportunity: Identifiable {
    let id: String
    let pickup: String
    let dropoff: String
    let rideType: String
    let scheduledPickupAt: Date
    let totalCents: Int
    let distanceMiles: Double
    let durationMinutes: Double
}

private struct DriverScheduledAssignment: Identifiable {
    let id: String
    let pickup: String
    let dropoff: String
    let rideType: String
    let scheduledPickupAt: Date
    let status: String
    let lockedPriceCents: Int
    let pickupCoordinate: CLLocationCoordinate2D?
    let activeRideId: String?
}

@MainActor
private final class DriverScheduledRidesVM: ObservableObject {
    @Published var opportunities: [DriverScheduledOpportunity] = []
    @Published var assignments: [DriverScheduledAssignment] = []
    @Published var workingIDs: Set<String> = []
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var opportunityListener: ListenerRegistration?
    private var assignmentListener: ListenerRegistration?

    deinit {
        opportunityListener?.remove()
        assignmentListener?.remove()
    }

    func start() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        opportunityListener?.remove()
        assignmentListener?.remove()
        opportunityListener = db.collectionGroup("opportunities")
            .whereField("driverId", isEqualTo: uid)
            .whereField("status", isEqualTo: "available")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error { self?.errorMessage = error.localizedDescription; return }
                    self?.opportunities = snapshot?.documents.compactMap(Self.parseOpportunity)
                        .sorted { $0.scheduledPickupAt < $1.scheduledPickupAt } ?? []
                }
            }
        assignmentListener = db.collection("scheduledRideRequests")
            .whereField("assignedDriverId", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    if let error { self?.errorMessage = error.localizedDescription; return }
                    self?.assignments = snapshot?.documents.compactMap(Self.parseAssignment)
                        .filter { !["completed", "cancelled", "expired"].contains($0.status) }
                        .sorted { $0.scheduledPickupAt < $1.scheduledPickupAt } ?? []
                }
            }
    }

    func respond(_ response: String, to requestId: String) async {
        workingIDs.insert(requestId)
        defer { workingIDs.remove(requestId) }
        do { try await RydrBackendService.respondToScheduledRide(requestId: requestId, response: response) }
        catch { errorMessage = error.localizedDescription }
    }

    func checkIn(_ assignment: DriverScheduledAssignment, currentLocation: CLLocation?) async {
        guard let destination = assignment.pickupCoordinate else {
            errorMessage = "The pickup coordinate is unavailable."
            return
        }
        workingIDs.insert(assignment.id)
        defer { workingIDs.remove(assignment.id) }
        do {
            let eta = try await pickupETA(from: currentLocation?.coordinate, to: destination)
            try await RydrBackendService.checkInScheduledRide(requestId: assignment.id, etaSeconds: eta)
        } catch { errorMessage = error.localizedDescription }
    }

    func release(_ assignment: DriverScheduledAssignment) async {
        workingIDs.insert(assignment.id)
        defer { workingIDs.remove(assignment.id) }
        do { try await RydrBackendService.releaseScheduledRide(requestId: assignment.id, reason: "Driver released scheduled ride") }
        catch { errorMessage = error.localizedDescription }
    }

    private func pickupETA(from origin: CLLocationCoordinate2D?, to destination: CLLocationCoordinate2D) async throws -> Int {
        guard let origin else {
            throw NSError(
                domain: "DriverScheduledRides",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Your current location is unavailable."]
            )
        }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw URLError(.cannotFindHost) }
        return max(0, Int(route.expectedTravelTime.rounded()))
    }

    private static func parseOpportunity(_ document: QueryDocumentSnapshot) -> DriverScheduledOpportunity? {
        let data = document.data()
        guard let requestId = document.reference.parent.parent?.documentID,
              let quote = data["quote"] as? [String: Any] else { return nil }
        return DriverScheduledOpportunity(
            id: requestId,
            pickup: data["pickup"] as? String ?? "Pickup",
            dropoff: data["dropoff"] as? String ?? "Destination",
            rideType: data["rideType"] as? String ?? "Rydr",
            scheduledPickupAt: (data["scheduledPickupAt"] as? Timestamp)?.dateValue() ?? Date(),
            totalCents: int(quote["totalCents"]),
            distanceMiles: double(data["distanceToPickupMiles"]),
            durationMinutes: 0
        )
    }

    private static func parseAssignment(_ document: QueryDocumentSnapshot) -> DriverScheduledAssignment? {
        let data = document.data()
        return DriverScheduledAssignment(
            id: document.documentID,
            pickup: data["pickup"] as? String ?? "Pickup",
            dropoff: data["dropoff"] as? String ?? "Destination",
            rideType: data["rideType"] as? String ?? "Rydr",
            scheduledPickupAt: (data["scheduledPickupAt"] as? Timestamp)?.dateValue() ?? Date(),
            status: data["status"] as? String ?? "confirmed",
            lockedPriceCents: int(data["lockedPriceCents"]),
            pickupCoordinate: coordinate(data["pickupCoordinate"]),
            activeRideId: data["activeRideId"] as? String
        )
    }

    private static func coordinate(_ value: Any?) -> CLLocationCoordinate2D? {
        guard let data = value as? [String: Any] else { return nil }
        let lat = double(data["lat"]), lng = double(data["lng"])
        guard lat != 0 || lng != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    private static func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? value as? Int ?? 0 }
    private static func double(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? value as? Double ?? 0 }
}

struct DriverScheduledRidesView: View {
    let currentLocation: CLLocation?
    @StateObject private var vm = DriverScheduledRidesVM()
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Scheduled rides", selection: $tab) {
                Text("Opportunities").tag(0)
                Text("My Schedule").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if let error = vm.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.orange).padding(.horizontal)
            }
            ScrollView {
                LazyVStack(spacing: 14) {
                    if tab == 0 {
                        if vm.opportunities.isEmpty { empty("No scheduled opportunities right now.") }
                        ForEach(vm.opportunities) { opportunity in opportunityCard(opportunity) }
                    } else {
                        if vm.assignments.isEmpty { empty("No confirmed scheduled rides.") }
                        ForEach(vm.assignments) { assignment in assignmentCard(assignment) }
                    }
                }.padding()
            }
        }
        .navigationTitle("Scheduled Rides")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.start() }
    }

    private func opportunityCard(_ item: DriverScheduledOpportunity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.rideType).font(.caption.bold()).foregroundStyle(.secondary)
            Text(item.scheduledPickupAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
            Label(item.pickup, systemImage: "circle.fill")
            Label(item.dropoff, systemImage: "mappin.and.ellipse")
            HStack {
                Text(money(item.totalCents)).font(.title3.bold())
                Spacer()
                Button("Decline") { Task { await vm.respond("decline", to: item.id) } }.buttonStyle(.bordered)
                Button("Accept") { Task { await vm.respond("accept", to: item.id) } }.buttonStyle(.borderedProminent).tint(.red)
            }
        }
        .padding(16).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .disabled(vm.workingIDs.contains(item.id))
    }

    private func assignmentCard(_ item: DriverScheduledAssignment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.status == "checkInRequired" ? "CHECK IN REQUIRED" : item.status.uppercased())
                    .font(.caption2.bold()).foregroundStyle(item.status == "checkInRequired" ? .orange : .green)
                Spacer(); Text(money(item.lockedPriceCents)).font(.headline)
            }
            Text(item.scheduledPickupAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
            Label(item.pickup, systemImage: "circle.fill")
            Label(item.dropoff, systemImage: "mappin.and.ellipse")
            if item.status == "checkInRequired" || item.status == "confirmed" {
                Button("Check in with live ETA") { Task { await vm.checkIn(item, currentLocation: currentLocation) } }
                    .buttonStyle(.borderedProminent).tint(.red).frame(maxWidth: .infinity)
            }
            if item.status != "active" {
                Button("Release scheduled ride", role: .destructive) { Task { await vm.release(item) } }
            }
        }
        .padding(16).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
        .disabled(vm.workingIDs.contains(item.id))
    }

    private func empty(_ message: String) -> some View {
        ContentUnavailableView("Scheduled Rides", systemImage: "calendar.badge.clock", description: Text(message))
            .padding(.top, 60)
    }
    private func money(_ cents: Int) -> String { String(format: "$%.2f", Double(cents) / 100) }
}
