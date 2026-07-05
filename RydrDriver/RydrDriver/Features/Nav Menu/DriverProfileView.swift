import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

struct DriverProfileView: View {
    @StateObject private var vm = DriverProfileViewModel()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                profileHero
                statsGrid
                feedbackSection
                profileSections
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            vm.start()
        }
    }

    private var profileHero: some View {
        VStack(spacing: 14) {
            avatar
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 4))
                .shadow(color: Color.red.opacity(0.22), radius: 20, y: 9)

            VStack(spacing: 4) {
                Text(vm.profile.displayName)
                    .font(.title.weight(.heavy))
                    .multilineTextAlignment(.center)
                Text(vm.profile.email.isEmpty ? "Rydr Driver" : vm.profile.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                Text(vm.profile.photoReviewStatus == "pending" ? "Photo pending review" : "Verified driver profile")
            }
            .font(.caption.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.red.opacity(0.10)))
            .foregroundStyle(Color.red)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Styles.rydrGradient.opacity(0.18))
                        .frame(width: 170, height: 170)
                        .offset(x: 70, y: -85)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
        )
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = vm.profile.photoURL.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    profilePlaceholder
                }
            }
        } else {
            profilePlaceholder
        }
    }

    private var profilePlaceholder: some View {
        ZStack {
            Circle().fill(Styles.rydrGradient)
            Image(systemName: "person.fill")
                .font(.system(size: 42, weight: .black))
                .foregroundStyle(.white)
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 12) {
            DriverProfileMetricCard(
                title: "Lifetime rides",
                value: "\(vm.profile.lifetimeRideCount)",
                systemImage: "steeringwheel"
            )
            DriverProfileMetricCard(
                title: "Rating",
                value: String(format: "%.2f", vm.profile.starRating),
                systemImage: "star.fill"
            )
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rider Feedback")
                    .font(.headline.weight(.heavy))
                Spacer()
                Image(systemName: "quote.bubble.fill")
                    .foregroundStyle(Styles.rydrGradient)
            }

            if vm.profile.feedbackHighlights.isEmpty {
                Text("Rider feedback will appear here after completed rides.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            } else {
                ForEach(vm.profile.feedbackHighlights, id: \.self) { feedback in
                    Text("\"\(feedback)\"")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                }
            }
        }
        .padding(18)
        .background(profileCardBackground)
    }

    private var profileSections: some View {
        VStack(spacing: 10) {
            DriverProfileLinkRow(title: "Public profile details", subtitle: "Photo, name, and rider-facing profile", systemImage: "person.text.rectangle.fill")
            DriverProfileLinkRow(title: "Ride preferences", subtitle: "Ride types and work style", systemImage: "slider.horizontal.3")
            DriverProfileLinkRow(title: "Trust and safety", subtitle: "Reports, safety settings, and support", systemImage: "shield.fill")
        }
        .padding(14)
        .background(profileCardBackground)
    }

    private var profileCardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 14, y: 7)
    }
}

private struct DriverProfileMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline.weight(.black))
                .foregroundStyle(Styles.rydrGradient)
            Text(value)
                .font(.title2.monospacedDigit().weight(.heavy))
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 12, y: 6)
        )
    }
}

private struct DriverProfileLinkRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.red.opacity(0.08)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

private struct DriverProfileSummary {
    var displayName = "Rydr Driver"
    var email = ""
    var photoURL: String?
    var photoReviewStatus = "approved"
    var lifetimeRideCount = 0
    var starRating = 5.0
    var feedbackHighlights: [String] = []
}

@MainActor
private final class DriverProfileViewModel: ObservableObject {
    @Published var profile = DriverProfileSummary()

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    deinit {
        listener?.remove()
    }

    func start() {
        listener?.remove()
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener = db.collection("drivers").document(uid).addSnapshotListener { [weak self] snapshot, _ in
            guard let self else { return }
            let data = snapshot?.data() ?? [:]
            let user = Auth.auth().currentUser
            Task { @MainActor in
                self.profile = DriverProfileSummary(
                    displayName: Self.publicDisplayName(from: data, authUser: user),
                    email: data["email"] as? String ?? user?.email ?? "",
                    photoURL: data["pendingProfilePhotoURL"] as? String ?? data["profilePhotoURL"] as? String,
                    photoReviewStatus: data["profilePhotoReviewStatus"] as? String ?? ((data["pendingProfilePhotoURL"] as? String) == nil ? "approved" : "pending"),
                    lifetimeRideCount: Self.intValue(data["lifetimeRideCount"] ?? data["completedRideCount"] ?? data["totalCompletedRides"]),
                    starRating: Self.doubleValue(data["driverRating"] ?? data["rating"] ?? data["averageRating"]) ?? 5.0,
                    feedbackHighlights: Self.feedbackHighlights(from: data)
                )
            }
        }
    }

    private static func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func publicDisplayName(from data: [String: Any], authUser: User?) -> String {
        let first = (data["firstName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (data["lastName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let legalName = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        if !legalName.isEmpty { return legalName }

        if let displayName = data["displayName"] as? String {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != "Rydr Driver" { return trimmed }
        }

        if let name = data["name"] as? String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != "Rydr Driver" { return trimmed }
        }

        if let authName = authUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !authName.isEmpty,
           authName != "Rydr Driver" {
            return authName
        }

        return "Rydr Driver"
    }

    private static func feedbackHighlights(from data: [String: Any]) -> [String] {
        for key in ["driverFeedbackHighlights", "recentRiderFeedback", "feedback"] {
            if let feedback = data[key] as? [String] {
                return feedback.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
        }
        return []
    }
}
