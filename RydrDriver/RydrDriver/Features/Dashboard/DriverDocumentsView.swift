import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

struct DriverDocumentsView: View {
    @ObservedObject var vm: DriverDashboardVM

    @State private var snapshot = DriverDocumentsSnapshot.empty
    @State private var selectedDocument: DriverDocumentKind?
    @State private var isLoading = true
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    hero
                    verificationNotice
                    documentsSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(documentsBackground.ignoresSafeArea())
            .navigationTitle("Documents")
            .navigationBarTitleDisplayMode(.inline)
            .task { loadDocuments() }
            .sheet(item: $selectedDocument) { kind in
                DriverDocumentDetailView(kind: kind, snapshot: snapshot) {
                    loadDocuments()
                }
                .presentationDetents([.large])
            }
            .alert("Documents", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Documents")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep your documents up to date")
                    HStack(spacing: 4) {
                        Text("to stay active on")
                        Text("Rydr.")
                            .fontWeight(.black)
                            .foregroundStyle(Styles.rydrGradient)
                    }
                }
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
            }
            Spacer()
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 84, weight: .black))
                    .foregroundStyle(Styles.rydrGradient)
                    .shadow(color: Color.red.opacity(0.22), radius: 18, y: 10)
                Image("Rydr - Driver")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 62, height: 62)
                    .padding(10)
                    .background(.white, in: Circle())
                    .shadow(color: Color.black.opacity(0.10), radius: 14, y: 8)
                    .offset(x: 10, y: 16)
            }
            .accessibilityHidden(true)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var verificationNotice: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 54, height: 54)
                .background(Color.red.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Stay Verified. Stay Active.")
                    .font(.headline.weight(.black))
                Text("Expired or missing documents may affect your ability to receive rides.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.red.opacity(0.08), Color(.systemBackground)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.red.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 8)
    }

    private var documentsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Your Documents")
                    .font(.title3.weight(.black))
                Spacer()
                Label("\(snapshot.activeCount) of \(DriverDocumentKind.allCases.count) active", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(snapshot.activeCount == DriverDocumentKind.allCases.count ? .green : .orange)
            }

            if isLoading {
                ProgressView("Loading documents...")
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(cardBackground)
            } else {
                VStack(spacing: 0) {
                    ForEach(DriverDocumentKind.allCases) { kind in
                        Button {
                            selectedDocument = kind
                        } label: {
                            DriverDocumentRow(kind: kind, record: snapshot.record(for: kind))
                        }
                        .buttonStyle(.plain)

                        if kind != DriverDocumentKind.allCases.last {
                            Divider().padding(.leading, 80)
                        }
                    }
                }
                .background(cardBackground)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.systemBackground))
            .shadow(color: Color.black.opacity(0.05), radius: 16, y: 8)
    }

    private var documentsBackground: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color(red: 1.0, green: 0.965, blue: 0.97), Color(.systemGroupedBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func loadDocuments() {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoading = false
            message = "Sign in before managing documents."
            return
        }

        isLoading = true
        Firestore.firestore().collection("drivers").document(uid).getDocument { doc, error in
            Task { @MainActor in
                isLoading = false
                if let error {
                    message = error.localizedDescription
                    return
                }
                snapshot = DriverDocumentsSnapshot(data: doc?.data() ?? [:])
            }
        }
    }
}

private struct DriverDocumentRow: View {
    let kind: DriverDocumentKind
    let record: DriverDocumentRecord

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: kind.icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 54, height: 54)
                .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.primary)
                Text(record.subtitle(for: kind))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            DriverDocumentStatusPill(status: record.status, isBackgroundCheck: kind == .backgroundCheck)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .contentShape(Rectangle())
    }
}

private struct DriverDocumentDetailView: View {
    let kind: DriverDocumentKind
    let snapshot: DriverDocumentsSnapshot
    let onUploaded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var frontItem: PhotosPickerItem?
    @State private var backItem: PhotosPickerItem?
    @State private var singleItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var message: String?

    private var record: DriverDocumentRecord {
        snapshot.record(for: kind)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    currentDocumentCard

                    if kind == .backgroundCheck {
                        backgroundCheckCard
                    } else {
                        uploadCard
                    }
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: frontItem) { _, item in handlePicker(item, side: .front) }
            .onChange(of: backItem) { _, item in handlePicker(item, side: .back) }
            .onChange(of: singleItem) { _, item in handlePicker(item, side: .single) }
            .alert(kind.title, isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: kind.icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 62, height: 62)
                .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(kind.title)
                    .font(.title2.weight(.black))
                Text(kind.detailDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(18)
        .background(detailCardBackground)
    }

    private var currentDocumentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Current Document")
                    .font(.headline.weight(.black))
                Spacer()
                DriverDocumentStatusPill(status: record.status, isBackgroundCheck: kind == .backgroundCheck)
            }

            if let previewURL = record.previewURL {
                AsyncImage(url: previewURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        documentPlaceholder(title: "Preview unavailable")
                    case .empty:
                        ProgressView()
                    @unknown default:
                        documentPlaceholder(title: "Preview unavailable")
                    }
                }
                .frame(height: 190)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                documentPlaceholder(title: kind == .backgroundCheck ? "No background report linked" : "No uploaded document yet")
                    .frame(height: 170)
            }

            Label(record.lastChangedText, systemImage: "clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(detailCardBackground)
    }

    private var uploadCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Upload \(kind.uploadTitle)")
                .font(.headline.weight(.black))

            Text(kind.uploadGuidance)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if kind == .driverLicense {
                HStack(spacing: 12) {
                    PhotosPicker(selection: $frontItem, matching: .images) {
                        documentUploadButton(title: "Front", icon: "rectangle.and.text.magnifyingglass", isUploading: isUploading)
                    }
                    PhotosPicker(selection: $backItem, matching: .images) {
                        documentUploadButton(title: "Back", icon: "rectangle.stack.fill", isUploading: isUploading)
                    }
                }
            } else {
                PhotosPicker(selection: $singleItem, matching: .images) {
                    documentUploadButton(title: "Upload \(kind.uploadTitle)", icon: kind.icon, isUploading: isUploading)
                }
            }

            Text("New uploads are marked pending review until Rydr approves them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(detailCardBackground)
    }

    private var backgroundCheckCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(record.status.isApproved ? "Background check cleared" : "Complete or check background status")
                .font(.headline.weight(.black))
            Text("During beta and the first live-production period, background checks are handled outside the app. Use the external background check flow to complete the check or review your status.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openURL(snapshot.backgroundCheckURL)
            } label: {
                Label(record.status.isApproved ? "View Background Check Status" : "Complete Background Check", systemImage: "arrow.up.right.square.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Styles.rydrGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(detailCardBackground)
    }

    private var detailCardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(.systemBackground))
            .shadow(color: Color.black.opacity(0.05), radius: 15, y: 8)
    }

    private func documentPlaceholder(title: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.red.opacity(0.06))
            VStack(spacing: 10) {
                Image(systemName: kind.icon)
                    .font(.title.weight(.bold))
                    .foregroundStyle(Styles.rydrGradient)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func documentUploadButton(title: String, icon: String, isUploading: Bool) -> some View {
        VStack(spacing: 10) {
            if isUploading {
                ProgressView()
                    .tint(.red)
            } else {
                Image(systemName: icon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Styles.rydrGradient)
            }
            Text(title)
                .font(.subheadline.weight(.black))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 112)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.red.opacity(0.20), style: StrokeStyle(lineWidth: 1.2, dash: [7, 5]))
        )
    }

    private func handlePicker(_ item: PhotosPickerItem?, side: DriverDocumentSide) {
        guard let item else { return }
        Task {
            do {
                guard let uploadKind = kind.uploadKind else { return }
                await MainActor.run {
                    isUploading = true
                    message = nil
                }
                _ = try await DriverDocumentUploadService.upload(item: item, kind: uploadKind, side: side.uploadSide)
                await MainActor.run {
                    isUploading = false
                    message = "\(kind.title) uploaded. Rydr is reviewing it now."
                    onUploaded()
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    message = error.localizedDescription
                }
            }
        }
    }
}

private struct DriverDocumentStatusPill: View {
    let status: DriverDocumentStatus
    let isBackgroundCheck: Bool

    var body: some View {
        Label(status.label(isBackgroundCheck: isBackgroundCheck), systemImage: status.icon)
            .font(.caption.weight(.black))
            .foregroundStyle(status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(status.color.opacity(0.13)))
            .lineLimit(1)
    }
}

private enum DriverDocumentKind: String, CaseIterable, Identifiable {
    case driverLicense
    case insurance
    case registration
    case backgroundCheck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .driverLicense: return "Driver License"
        case .insurance: return "Insurance"
        case .registration: return "Registration"
        case .backgroundCheck: return "Background Check Status"
        }
    }

    var icon: String {
        switch self {
        case .driverLicense: return "person.text.rectangle.fill"
        case .insurance: return "shield.lefthalf.filled"
        case .registration: return "car.fill"
        case .backgroundCheck: return "person.crop.circle.fill"
        }
    }

    var uploadTitle: String {
        switch self {
        case .driverLicense: return "License Photos"
        case .insurance: return "Insurance Card"
        case .registration: return "Registration"
        case .backgroundCheck: return "Background Check"
        }
    }

    var detailDescription: String {
        switch self {
        case .driverLicense: return "Review the last uploaded license and submit updated front or back photos."
        case .insurance: return "Keep your current insurance card on file for review."
        case .registration: return "Upload your current vehicle registration for review."
        case .backgroundCheck: return "Review your background check status or continue the external check flow."
        }
    }

    var uploadGuidance: String {
        switch self {
        case .driverLicense: return "Upload a clear photo of the front or back of your driver license."
        case .insurance: return "Upload the current insurance card for the vehicle you drive on Rydr."
        case .registration: return "Upload the registration document for the vehicle you drive on Rydr."
        case .backgroundCheck: return ""
        }
    }
}

private enum DriverDocumentSide: String {
    case front
    case back
    case single
}

private extension DriverDocumentKind {
    var uploadKind: DriverDocumentUploadKind? {
        switch self {
        case .driverLicense: return .driverLicense
        case .insurance: return .insurance
        case .registration: return .registration
        case .backgroundCheck: return nil
        }
    }
}

private extension DriverDocumentSide {
    var uploadSide: DriverDocumentUploadSide {
        switch self {
        case .front: return .front
        case .back: return .back
        case .single: return .single
        }
    }
}

struct DriverDocumentUploadResult {
    let storagePath: String
    let downloadURL: URL
}

enum DriverDocumentUploadKind: String {
    case driverLicense
    case insurance
    case registration
    case vehicleInspection
}

enum DriverDocumentUploadSide: String {
    case front
    case back
    case single
}

enum DriverDocumentUploadError: LocalizedError {
    case notSignedIn
    case missingSelection
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in before uploading documents."
        case .missingSelection: return "Choose a clear document photo before continuing."
        case .unreadableImage: return "Could not read that document photo. Please choose a different image."
        }
    }
}

enum DriverDocumentUploadService {
    static func upload(item: PhotosPickerItem?, kind: DriverDocumentUploadKind, side: DriverDocumentUploadSide) async throws -> DriverDocumentUploadResult {
        guard let item else { throw DriverDocumentUploadError.missingSelection }
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw DriverDocumentUploadError.unreadableImage
        }
        return try await upload(data: data, kind: kind, side: side)
    }

    static func upload(data: Data, kind: DriverDocumentUploadKind, side: DriverDocumentUploadSide) async throws -> DriverDocumentUploadResult {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DriverDocumentUploadError.notSignedIn
        }

        let uploadData = normalizedImageData(data) ?? data
        let timestamp = Int(Date().timeIntervalSince1970)
        let storagePath = "driverDocuments/\(uid)/\(kind.rawValue)/\(side.rawValue)-\(timestamp)-\(UUID().uuidString).jpg"
        let ref = Storage.storage().reference(withPath: storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(uploadData, metadata: metadata)
        let url = try await ref.downloadURL()
        return DriverDocumentUploadResult(storagePath: storagePath, downloadURL: url)
    }

    private static func normalizedImageData(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 1800
        let largest = max(image.size.width, image.size.height)
        let targetSize: CGSize
        if largest > maxDimension {
            let scale = maxDimension / largest
            targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        } else {
            targetSize = image.size
        }
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetSize)) }
        return resized.jpegData(compressionQuality: 0.82)
    }
}

private struct DriverDocumentsSnapshot {
    var records: [DriverDocumentKind: DriverDocumentRecord]
    var backgroundCheckURL: URL

    static let empty = DriverDocumentsSnapshot(records: [:], backgroundCheckURL: URL(string: "https://rydr.app/driver-background-check")!)

    init(records: [DriverDocumentKind: DriverDocumentRecord], backgroundCheckURL: URL) {
        self.records = records
        self.backgroundCheckURL = backgroundCheckURL
    }

    init(data: [String: Any]) {
        let docs = data["documents"] as? [String: Any] ?? [:]
        var parsed: [DriverDocumentKind: DriverDocumentRecord] = [:]

        for kind in DriverDocumentKind.allCases {
            let raw = docs[kind.rawValue] as? [String: Any] ?? [:]
            parsed[kind] = DriverDocumentRecord(kind: kind, data: raw, driverData: data)
        }

        let rawURL = data["backgroundCheckURL"] as? String
            ?? data["backgroundCheckStatusURL"] as? String
            ?? "https://rydr.app/driver-background-check"
        self.records = parsed
        self.backgroundCheckURL = URL(string: rawURL) ?? URL(string: "https://rydr.app/driver-background-check")!
    }

    var activeCount: Int {
        DriverDocumentKind.allCases.filter { record(for: $0).status.isApproved }.count
    }

    func record(for kind: DriverDocumentKind) -> DriverDocumentRecord {
        records[kind] ?? DriverDocumentRecord(kind: kind, data: [:], driverData: [:])
    }
}

private struct DriverDocumentRecord {
    let status: DriverDocumentStatus
    let updatedAt: Date?
    let expiresAt: Date?
    let completedAt: Date?
    let frontURL: URL?
    let backURL: URL?
    let documentURL: URL?

    init(kind: DriverDocumentKind, data: [String: Any], driverData: [String: Any]) {
        status = DriverDocumentStatus(raw: data["status"] as? String ?? Self.legacyStatus(for: kind, driverData: driverData))
        updatedAt = Self.date(data["updatedAt"])
        expiresAt = Self.date(data["expiresAt"] ?? data["expirationDate"] ?? Self.legacyExpiry(for: kind, driverData: driverData))
        completedAt = Self.date(data["completedAt"] ?? Self.legacyCompletedAt(for: kind, driverData: driverData))
        frontURL = Self.url(data["frontURL"])
        backURL = Self.url(data["backURL"])
        documentURL = Self.url(data["documentURL"])
    }

    var previewURL: URL? {
        documentURL ?? frontURL ?? backURL
    }

    var lastChangedText: String {
        guard let updatedAt else { return "No upload history yet" }
        return "Last changed \(Self.dateFormatter.string(from: updatedAt))"
    }

    func subtitle(for kind: DriverDocumentKind) -> String {
        if kind == .backgroundCheck {
            if let completedAt {
                return "Completed on \(Self.dateFormatter.string(from: completedAt))"
            }
            return status == .missing ? "External check not started" : status.subtitle
        }

        if let expiresAt {
            return "Expires \(Self.dateFormatter.string(from: expiresAt))"
        }

        return status.subtitle
    }

    private static func date(_ raw: Any?) -> Date? {
        if let timestamp = raw as? Timestamp { return timestamp.dateValue() }
        if let date = raw as? Date { return date }
        if let seconds = raw as? TimeInterval { return Date(timeIntervalSince1970: seconds) }
        if let string = raw as? String {
            return isoFormatter.date(from: string) ?? dateFormatter.date(from: string)
        }
        return nil
    }

    private static func url(_ raw: Any?) -> URL? {
        guard let string = raw as? String, !string.isEmpty else { return nil }
        return URL(string: string)
    }

    private static func legacyStatus(for kind: DriverDocumentKind, driverData: [String: Any]) -> String {
        switch kind {
        case .driverLicense:
            return driverData["licenseStatus"] as? String ?? driverData["driverLicenseStatus"] as? String ?? "missing"
        case .insurance:
            return driverData["insuranceStatus"] as? String ?? "missing"
        case .registration:
            return driverData["registrationStatus"] as? String ?? "missing"
        case .backgroundCheck:
            return driverData["backgroundCheckStatus"] as? String ?? "missing"
        }
    }

    private static func legacyExpiry(for kind: DriverDocumentKind, driverData: [String: Any]) -> Any? {
        switch kind {
        case .driverLicense:
            return driverData["licenseExpiresAt"] ?? driverData["driverLicenseExpiresAt"]
        case .insurance:
            return driverData["insuranceExpiresAt"]
        case .registration:
            return driverData["registrationExpiresAt"]
        case .backgroundCheck:
            return nil
        }
    }

    private static func legacyCompletedAt(for kind: DriverDocumentKind, driverData: [String: Any]) -> Any? {
        guard kind == .backgroundCheck else { return nil }
        return driverData["backgroundCheckCompletedAt"] ?? driverData["backgroundCheckClearedAt"]
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

private enum DriverDocumentStatus: Equatable {
    case approved
    case pending
    case rejected
    case missing

    init(raw: String) {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "approved", "verified", "clear", "cleared", "complete", "completed":
            self = .approved
        case "pending", "pending_review", "review", "in_review", "submitted", "beta_deferred":
            self = .pending
        case "rejected", "expired", "failed", "needs_attention", "needs_review":
            self = .rejected
        default:
            self = .missing
        }
    }

    var isApproved: Bool { self == .approved }

    var subtitle: String {
        switch self {
        case .approved: return "Verified"
        case .pending: return "Pending review"
        case .rejected: return "Needs attention"
        case .missing: return "Upload required"
        }
    }

    var icon: String {
        switch self {
        case .approved: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        case .rejected: return "exclamationmark.triangle.fill"
        case .missing: return "plus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .approved: return .green
        case .pending: return .orange
        case .rejected: return .red
        case .missing: return .secondary
        }
    }

    func label(isBackgroundCheck: Bool) -> String {
        if isBackgroundCheck && self == .approved { return "Clear" }
        return subtitle
    }
}
