import SwiftUI
import FirebaseAuth
import FirebaseFirestore

enum RiderNotificationSource: String {
    case rider
    case platform
}

struct RiderNotificationItem: Identifiable, Equatable {
    let id: String
    let documentId: String
    let source: RiderNotificationSource
    let title: String
    let body: String
    let type: String
    let target: String
    let createdAt: Date
    let isRead: Bool
    let rideId: String?
    let requestId: String?
    let chatId: String?

    var icon: String {
        switch type {
        case "rydrBankCode", "rydrBankCompleted": return "banknote.fill"
        case "betaAnnouncement": return "megaphone.fill"
        case "promo": return "tag.fill"
        case "rideAccepted", "driverArrived", "rideStarted", "rideCompleted", "rideCancelled": return "car.fill"
        case "paymentFailed", "paymentPending": return "creditcard.fill"
        case "supportReply": return "questionmark.bubble.fill"
        default: return "bell.fill"
        }
    }

    var tint: Color {
        switch type {
        case "rydrBankCode", "rydrBankCompleted": return .green
        case "betaAnnouncement": return .purple
        case "promo": return .orange
        case "paymentFailed": return .orange
        default: return .red
        }
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

@MainActor
final class RiderNotificationInboxViewModel: ObservableObject {
    @Published private(set) var items: [RiderNotificationItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private let defaults = UserDefaults.standard
    private var riderListener: ListenerRegistration?
    private var announcementListener: ListenerRegistration?
    private var riderItems: [RiderNotificationItem] = []
    private var platformItems: [RiderNotificationItem] = []
    private let platformReadKey = "rydr.rider.notifications.platformReadIds"
    private let platformDismissedKey = "rydr.rider.notifications.platformDismissedIds"

    var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }

    func start() {
        guard riderListener == nil, announcementListener == nil else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Sign in to view notifications."
            return
        }

        isLoading = true
        listenForRiderNotifications(uid: uid)
        listenForPlatformAnnouncements()
    }

    func stop() {
        riderListener?.remove()
        announcementListener?.remove()
        riderListener = nil
        announcementListener = nil
    }

    func markRead(_ item: RiderNotificationItem) {
        guard !item.isRead else { return }

        switch item.source {
        case .rider:
            guard let uid = Auth.auth().currentUser?.uid else { return }
            db.collection("riders")
                .document(uid)
                .collection("notifications")
                .document(item.documentId)
                .updateData([
                    "isRead": true,
                    "readAt": FieldValue.serverTimestamp()
                ]) { [weak self] error in
                    if let error {
                        Task { @MainActor in self?.errorMessage = error.localizedDescription }
                    }
                }
        case .platform:
            var ids = platformReadIds()
            ids.insert(item.documentId)
            defaults.set(Array(ids), forKey: platformReadKey)
            platformItems = platformItems.map { existing in
                existing.documentId == item.documentId ? existing.copy(isRead: true) : existing
            }
            publishCombinedItems()
        }
    }

    func markAllRead() {
        items.filter { !$0.isRead }.forEach(markRead)
    }

    func dismiss(_ item: RiderNotificationItem) {
        switch item.source {
        case .rider:
            guard let uid = Auth.auth().currentUser?.uid else { return }
            db.collection("riders")
                .document(uid)
                .collection("notifications")
                .document(item.documentId)
                .updateData([
                    "isDismissed": true,
                    "dismissedAt": FieldValue.serverTimestamp()
                ]) { [weak self] error in
                    if let error {
                        Task { @MainActor in self?.errorMessage = error.localizedDescription }
                    }
                }
        case .platform:
            var ids = platformDismissedIds()
            ids.insert(item.documentId)
            defaults.set(Array(ids), forKey: platformDismissedKey)
            platformItems.removeAll { $0.documentId == item.documentId }
            publishCombinedItems()
        }
    }

    private func listenForRiderNotifications(uid: String) {
        riderListener = db.collection("riders")
            .document(uid)
            .collection("notifications")
            .order(by: "createdAt", descending: true)
            .limit(to: 60)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.riderItems = (snapshot?.documents ?? []).compactMap {
                        Self.item(from: $0, source: .rider, platformReadIds: [])
                    }
                    self.publishCombinedItems()
                }
            }
    }

    private func listenForPlatformAnnouncements() {
        announcementListener = db.collection("platformAnnouncements")
            .order(by: "createdAt", descending: true)
            .limit(to: 30)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    let readIds = self.platformReadIds()
                    let dismissedIds = self.platformDismissedIds()
                    self.platformItems = (snapshot?.documents ?? [])
                        .filter { !dismissedIds.contains($0.documentID) }
                        .compactMap { Self.item(from: $0, source: .platform, platformReadIds: readIds) }
                    self.publishCombinedItems()
                }
            }
    }

    private func publishCombinedItems() {
        items = (riderItems + platformItems)
            .sorted { $0.createdAt > $1.createdAt }
        errorMessage = nil
    }

    private func platformReadIds() -> Set<String> {
        Set(defaults.stringArray(forKey: platformReadKey) ?? [])
    }

    private func platformDismissedIds() -> Set<String> {
        Set(defaults.stringArray(forKey: platformDismissedKey) ?? [])
    }

    private static func item(
        from document: QueryDocumentSnapshot,
        source: RiderNotificationSource,
        platformReadIds: Set<String>
    ) -> RiderNotificationItem? {
        let data = document.data()
        if source == .platform {
            let published = data["published"] as? Bool ?? true
            let audience = data["audience"] as? String ?? "all"
            let expiresAt = (data["expiresAt"] as? Timestamp)?.dateValue()
            guard published, audience == "all" || audience == "rider" else { return nil }
            if let expiresAt, expiresAt < Date() { return nil }
        } else {
            let isDismissed = data["isDismissed"] as? Bool ?? false
            if isDismissed || data["dismissedAt"] != nil { return nil }
        }

        let title = data["title"] as? String ?? ""
        let body = data["body"] as? String ?? ""
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let type = data["type"] as? String ?? (source == .platform ? "betaAnnouncement" : "general")
        let target = data["target"] as? String ?? "notifications"
        let isRead = source == .platform
            ? platformReadIds.contains(document.documentID)
            : (data["isRead"] as? Bool ?? false)

        return RiderNotificationItem(
            id: "\(source.rawValue)-\(document.documentID)",
            documentId: document.documentID,
            source: source,
            title: title,
            body: body,
            type: type,
            target: target,
            createdAt: createdAt,
            isRead: isRead,
            rideId: data["rideId"] as? String,
            requestId: data["requestId"] as? String,
            chatId: data["chatId"] as? String
        )
    }

}

private extension RiderNotificationItem {
    func copy(isRead: Bool) -> RiderNotificationItem {
        RiderNotificationItem(
            id: id,
            documentId: documentId,
            source: source,
            title: title,
            body: body,
            type: type,
            target: target,
            createdAt: createdAt,
            isRead: isRead,
            rideId: rideId,
            requestId: requestId,
            chatId: chatId
        )
    }
}

struct NotificationView: View {
    @StateObject private var vm = RiderNotificationInboxViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header

                if vm.isLoading && vm.items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if vm.items.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.items) { item in
                            notificationRow(item)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark Read") {
                    vm.markAllRead()
                }
                .font(.caption.weight(.bold))
                .disabled(vm.unreadCount == 0)
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live Updates")
                    .font(.title2.weight(.heavy))
                Spacer()
                if vm.unreadCount > 0 {
                    Text("\(vm.unreadCount) unread")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.10), in: Capsule())
                }
            }

            Text("RydrBank rewards, ride updates, beta announcements, support replies, and account alerts will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = vm.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.badge")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 78, height: 78)
                .background(Color.red.opacity(0.10), in: Circle())
            Text("No notifications yet")
                .font(.headline.weight(.heavy))
            Text("When Rydr has live updates for you, they will land here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func notificationRow(_ item: RiderNotificationItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(item.tint)
                .frame(width: 42, height: 42)
                .background(item.tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(item.relativeTime)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(item.body)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if item.source == .platform {
                    Text("Rydr")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.purple)
                }
            }

            VStack(spacing: 12) {
                Button {
                    vm.dismiss(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss notification")

                if !item.isRead {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 9, height: 9)
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(item.isRead ? Color.clear : Color.red.opacity(0.18), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            vm.markRead(item)
        }
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(red: 0.09, green: 0.09, blue: 0.10) : .white
    }
}
