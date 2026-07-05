import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

struct DriverSafetyCenterView: View {
    @ObservedObject var vm: DriverDashboardVM
    @StateObject private var model = DriverSafetyCenterModel()
    @State private var showIncidentReport = false
    @State private var appealTarget: DriverSafetyPenalty?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                safetyStatusCard
                incidentReportCard
                penaltyMarkersCard
                safetyVideosCard
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Safety")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.start(activeRide: vm.activeRide)
        }
        .onDisappear {
            model.stop()
        }
        .sheet(isPresented: $showIncidentReport) {
            DriverIncidentReportSheet(activeRide: vm.activeRide) { type, rideId, description in
                await model.submitIncidentReport(type: type, rideId: rideId, description: description)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $appealTarget) { penalty in
            DriverPenaltyAppealSheet(penalty: penalty) { reason in
                await model.submitAppeal(for: penalty, reason: reason)
            }
            .presentationDetents([.medium])
        }
    }

    private var safetyStatusCard: some View {
        SafetyCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: model.hasInvestigationHold ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(model.hasInvestigationHold ? .orange : .green)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill((model.hasInvestigationHold ? Color.orange : Color.green).opacity(0.13)))

                VStack(alignment: .leading, spacing: 6) {
                    Text(model.hasInvestigationHold ? "Safety review in progress" : "No active safety hold")
                        .font(.headline.weight(.bold))
                    Text(model.hasInvestigationHold
                         ? "One or more conduct markers may limit access until Mission Control completes a manual review."
                         : "Safety markers and rider concerns will appear here when Mission Control places them on your account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var incidentReportCard: some View {
        SafetyCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Report an incident")
                            .font(.headline.weight(.bold))
                        Text(vm.activeRide == nil ? "Submit a driver safety report for Mission Control review." : "Active ride attached: \(vm.activeRide?.id ?? "")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        showIncidentReport = true
                    } label: {
                        Label("Report", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Styles.rydrGradient))
                            .foregroundStyle(.white)
                    }
                }

                if let message = model.message {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(message.localizedCaseInsensitiveContains("could not") ? .red : .secondary)
                }
            }
        }
    }

    private var penaltyMarkersCard: some View {
        SafetyCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Safety penalty markers")
                            .font(.headline.weight(.bold))
                        Text("Rider-reported concerns are reviewed against trip records and Mission Control analytics.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(model.penalties.count)")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.primary)
                }

                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else if model.penalties.isEmpty {
                    EmptySafetyState()
                } else {
                    VStack(spacing: 10) {
                        ForEach(model.penalties) { penalty in
                            DriverSafetyPenaltyRow(
                                penalty: penalty,
                                appeal: model.appeal(for: penalty),
                                onAppeal: { appealTarget = penalty }
                            )
                        }
                    }
                }
            }
        }
    }

    private var safetyVideosCard: some View {
        SafetyCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Styles.rydrGradient)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.red.opacity(0.10)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Safety videos")
                            .font(.headline.weight(.bold))
                        Text("Future coaching and review videos will appear here when assigned to a marker.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Text("No videos assigned.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
            }
        }
    }
}

@MainActor
final class DriverSafetyCenterModel: ObservableObject {
    @Published var penalties: [DriverSafetyPenalty] = []
    @Published var appeals: [DriverPenaltyAppeal] = []
    @Published var isLoading = true
    @Published var message: String?

    private let db = Firestore.firestore()
    private var penaltyListener: ListenerRegistration?
    private var appealListener: ListenerRegistration?
    private var activeRide: DriverActiveRide?

    var hasInvestigationHold: Bool {
        penalties.contains { $0.requiresInvestigationHold && !$0.isClosed }
    }

    func start(activeRide: DriverActiveRide?) {
        self.activeRide = activeRide
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoading = false
            message = "Sign in to view safety records."
            return
        }

        penaltyListener?.remove()
        appealListener?.remove()
        isLoading = true

        penaltyListener = db.collection("driverSafetyPenalties")
            .whereField("driverId", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor in
                    if let error {
                        self.message = "Safety markers could not be loaded: \(error.localizedDescription)"
                        self.isLoading = false
                        return
                    }
                    self.penalties = (snapshot?.documents ?? [])
                        .compactMap(DriverSafetyPenalty.init(document:))
                        .sorted(by: DriverSafetyPenalty.sort)
                    self.isLoading = false
                }
            }

        appealListener = db.collection("driverSafetyPenaltyAppeals")
            .whereField("driverId", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                Task { @MainActor in
                    if error == nil {
                        self.appeals = (snapshot?.documents ?? []).compactMap(DriverPenaltyAppeal.init(document:))
                    }
                }
            }
    }

    func stop() {
        penaltyListener?.remove()
        appealListener?.remove()
        penaltyListener = nil
        appealListener = nil
    }

    func appeal(for penalty: DriverSafetyPenalty) -> DriverPenaltyAppeal? {
        appeals
            .filter { $0.penaltyId == penalty.id }
            .sorted(by: DriverPenaltyAppeal.sort)
            .first
    }

    func submitIncidentReport(type: DriverIncidentType, rideId: String?, description: String) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            message = "Sign in before submitting a report."
            return
        }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else {
            message = "Add more detail before submitting the report."
            return
        }

        var payload: [String: Any] = [
            "reportType": type.rawValue,
            "reportTypeLabel": type.title,
            "reporterRole": "driver",
            "driverId": uid,
            "description": trimmed,
            "status": "open",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let rideId, !rideId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["rideId"] = rideId.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let activeRide {
            payload["rideId"] = activeRide.id
            payload["riderId"] = activeRide.riderId
            payload["riderName"] = activeRide.riderName
        }

        do {
            _ = try await db.collection("safetyReports").addDocument(data: payload)
            message = "Incident report submitted."
        } catch {
            RydrCrashReporter.record(error, context: "driver_submit_safety_report")
            message = "Report could not be submitted: \(error.localizedDescription)"
        }
    }

    func submitAppeal(for penalty: DriverSafetyPenalty, reason: String) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            message = "Sign in before submitting an appeal."
            return
        }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else {
            message = "Add more detail before submitting the appeal."
            return
        }

        var payload: [String: Any] = [
            "penaltyId": penalty.id,
            "driverId": uid,
            "category": penalty.category,
            "reason": trimmed,
            "status": "submitted",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let rideId = penalty.rideId { payload["rideId"] = rideId }
        if let riderReportId = penalty.riderReportId { payload["riderReportId"] = riderReportId }

        do {
            _ = try await db.collection("driverSafetyPenaltyAppeals").addDocument(data: payload)
            message = "Appeal submitted for Mission Control review."
        } catch {
            RydrCrashReporter.record(error, context: "driver_submit_safety_penalty_appeal")
            message = "Appeal could not be submitted: \(error.localizedDescription)"
        }
    }
}

struct DriverSafetyPenalty: Identifiable, Equatable {
    let id: String
    let category: String
    let categoryLabel: String
    let description: String
    let severity: String
    let status: String
    let reviewStatus: String
    let appealStatus: String
    let penaltyType: String
    let rideId: String?
    let riderReportId: String?
    let createdAt: Date?

    nonisolated init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        id = document.documentID
        category = (data["category"] as? String) ?? (data["penaltyCategory"] as? String) ?? "other"
        categoryLabel = (data["categoryLabel"] as? String) ?? Self.title(for: category)
        description = (data["description"] as? String) ?? (data["summary"] as? String) ?? "Rider safety concern under review."
        severity = (data["severity"] as? String) ?? "standard"
        status = (data["status"] as? String) ?? "active"
        reviewStatus = (data["reviewStatus"] as? String) ?? "pending"
        appealStatus = (data["appealStatus"] as? String) ?? "not_appealed"
        penaltyType = (data["penaltyType"] as? String) ?? (data["type"] as? String) ?? "safety"
        rideId = data["rideId"] as? String
        riderReportId = data["riderReportId"] as? String
        createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
    }

    nonisolated var requiresInvestigationHold: Bool {
        let lower = "\(penaltyType) \(category) \(categoryLabel)".lowercased()
        return lower.contains("unprofessional") ||
            lower.contains("flirting") ||
            lower.contains("unwelcome") ||
            lower.contains("inappropriate_language") ||
            lower.contains("inappropriate language")
    }

    nonisolated var isClosed: Bool {
        ["dismissed", "removed", "resolved", "cleared"].contains(status.lowercased()) ||
            ["cleared", "dismissed"].contains(reviewStatus.lowercased())
    }

    nonisolated static func sort(lhs: DriverSafetyPenalty, rhs: DriverSafetyPenalty) -> Bool {
        (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
    }

    nonisolated static func title(for category: String) -> String {
        category
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

struct DriverPenaltyAppeal: Identifiable {
    let id: String
    let penaltyId: String
    let status: String
    let createdAt: Date?

    nonisolated init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let penaltyId = data["penaltyId"] as? String else { return nil }
        id = document.documentID
        self.penaltyId = penaltyId
        status = (data["status"] as? String) ?? "submitted"
        createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
    }

    nonisolated static func sort(lhs: DriverPenaltyAppeal, rhs: DriverPenaltyAppeal) -> Bool {
        (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
    }
}

enum DriverIncidentType: String, CaseIterable, Identifiable {
    case riderBehavior = "rider_behavior"
    case safetyHazard = "safety_hazard"
    case vehicleOrRoadIssue = "vehicle_or_road_issue"
    case tripProblem = "trip_problem"
    case other = "other"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .riderBehavior: return "Rider behavior"
        case .safetyHazard: return "Safety hazard"
        case .vehicleOrRoadIssue: return "Vehicle or road issue"
        case .tripProblem: return "Trip problem"
        case .other: return "Other"
        }
    }
}

private struct DriverSafetyPenaltyRow: View {
    let penalty: DriverSafetyPenalty
    let appeal: DriverPenaltyAppeal?
    let onAppeal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(color.opacity(0.12)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(penalty.categoryLabel)
                        .font(.subheadline.weight(.bold))
                    Text(penalty.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                MarkerPill(text: penalty.severity.capitalized, color: color)
                MarkerPill(text: penalty.reviewStatus.replacingOccurrences(of: "_", with: " ").capitalized, color: .secondary)
                if penalty.requiresInvestigationHold && !penalty.isClosed {
                    MarkerPill(text: "Investigation hold", color: .orange)
                }
            }

            HStack {
                if let rideId = penalty.rideId {
                    Text("Ride \(rideId)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let appeal {
                    Text("Appeal \(appeal.status.replacingOccurrences(of: "_", with: " "))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if !penalty.isClosed {
                    Button("Appeal") { onAppeal() }
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private var icon: String {
        penalty.requiresInvestigationHold ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle.fill"
    }

    private var color: Color {
        penalty.requiresInvestigationHold ? .orange : (penalty.severity.lowercased() == "high" ? .red : .yellow)
    }
}

private struct DriverIncidentReportSheet: View {
    let activeRide: DriverActiveRide?
    let onSubmit: (DriverIncidentType, String?, String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var type: DriverIncidentType = .riderBehavior
    @State private var rideId: String = ""
    @State private var description: String = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Incident") {
                    Picker("Type", selection: $type) {
                        ForEach(DriverIncidentType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    TextField("Ride ID", text: $rideId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextEditor(text: $description)
                        .frame(minHeight: 140)
                }
            }
            .navigationTitle("Report Incident")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Submitting" : "Submit") {
                        Task {
                            isSubmitting = true
                            await onSubmit(type, rideId.isEmpty ? activeRide?.id : rideId, description)
                            isSubmitting = false
                            dismiss()
                        }
                    }
                    .disabled(isSubmitting || description.trimmingCharacters(in: .whitespacesAndNewlines).count < 12)
                }
            }
            .onAppear {
                if rideId.isEmpty, let activeRide {
                    rideId = activeRide.id
                }
            }
        }
    }
}

private struct DriverPenaltyAppealSheet: View {
    let penalty: DriverSafetyPenalty
    let onSubmit: (String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(penalty.categoryLabel)
                    .font(.headline.weight(.bold))
                Text("Explain what Mission Control should review, including ride context or anything the rider report missed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: $reason)
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                Spacer()
            }
            .padding()
            .navigationTitle("Appeal Marker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Submitting" : "Submit") {
                        Task {
                            isSubmitting = true
                            await onSubmit(reason)
                            isSubmitting = false
                            dismiss()
                        }
                    }
                    .disabled(isSubmitting || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
                }
            }
        }
    }
}

private struct SafetyCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.04), radius: 10, y: 5)
    }
}

private struct MarkerPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.12)))
            .foregroundStyle(color)
    }
}

private struct EmptySafetyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.checkered")
                .font(.title2.weight(.bold))
                .foregroundStyle(.secondary)
            Text("No safety markers")
                .font(.subheadline.weight(.bold))
            Text("Markers placed after rider reports or Mission Control review will show here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
