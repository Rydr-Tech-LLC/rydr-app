import SwiftUI
import PhotosUI
import FirebaseAuth

enum SideMenuItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case profile = "Profile"
    case vehicleRideTypes = "Vehicle & Rydr Hub"
    case fareInsights = "Earnings Hub"
    case walletPayouts = "Wallet & Payouts"
    case cashRydrHub = "Cash Rydr Hub"
    case documents = "Documents"
    case rewards = "Rewards"
    case community = "Community"
    case safety = "Safety"
    case helpSupport = "Help & Support"
    case settings = "Settings"
    case notifications = "Notifications"
    case logout = "Log Out"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "map.fill"
        case .profile: return "person.crop.circle"
        case .vehicleRideTypes: return "car.2.fill"
        case .fareInsights: return "dollarsign.circle.fill"
        case .walletPayouts: return "creditcard.fill"
        case .cashRydrHub: return "banknote.fill"
        case .documents: return "doc.text"
        case .rewards: return "gift"
        case .community: return "person.3.fill"
        case .safety: return "shield.fill"
        case .helpSupport: return "questionmark.circle.fill"
        case .settings: return "gearshape.fill"
        case .notifications: return "bell.fill"
        case .logout: return "rectangle.portrait.and.arrow.right"
        }
    }
}

struct SideMenuView: View {
    @ObservedObject var vm: DriverDashboardVM
    @Binding var isOpen: Bool
    var onSelect: (SideMenuItem) -> Void

    @State private var selectedProfilePhoto: PhotosPickerItem?

    private let width: CGFloat = 310

    var body: some View {
        ZStack(alignment: .leading) {
            if isOpen {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring) { isOpen = false } }
            }

            VStack(alignment: .leading, spacing: 8) {
                profileHeader

                ForEach(SideMenuItem.allCases.filter { $0 != .logout }) { item in
                    Button { onSelect(item) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.body.weight(.semibold))
                                .frame(width: 24)
                            Text(item.rawValue)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        .padding(.vertical, 9)
                        .padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground).opacity(0.001)))
                    }
                    .foregroundStyle(.primary)
                }

                Spacer()
                Divider()
                Button { onSelect(.logout) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: SideMenuItem.logout.icon).frame(width: 22)
                        Text(SideMenuItem.logout.rawValue).font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
                .foregroundStyle(.red)

                Text("Help · Learning Center")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)
            .offset(x: isOpen ? 0 : -width)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: isOpen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .allowsHitTesting(isOpen)
        .onChange(of: selectedProfilePhoto) { _, item in
            guard let item else { return }
            Task {
                do {
                    if let data = try await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            vm.submitProfilePhotoForReview(image)
                            selectedProfilePhoto = nil
                        }
                    } else {
                        await MainActor.run {
                            vm.profilePhotoMessage = "Could not read that image."
                            selectedProfilePhoto = nil
                        }
                    }
                } catch {
                    await MainActor.run {
                        vm.profilePhotoMessage = "Could not read that image: \(error.localizedDescription)"
                        selectedProfilePhoto = nil
                    }
                }
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $selectedProfilePhoto, matching: .images) {
                DriverProfilePhotoButton(
                    photoURL: displayedProfilePhotoURL,
                    isPending: vm.profilePhotoReviewStatus == "pending",
                    isUploading: vm.isUploadingProfilePhoto
                )
            }
            .buttonStyle(.plain)
            .disabled(vm.isUploadingProfilePhoto)
            VStack(alignment: .leading, spacing: 2) {
                Text(Auth.auth().currentUser?.displayName ?? "Driver")
                    .font(.headline.weight(.bold))
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text("4.93")
                        .font(.caption.weight(.semibold))
                }
                Text("Approved Driver")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                if vm.profilePhotoReviewStatus == "pending" {
                    Text("Photo pending approval")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if let message = vm.profilePhotoMessage {
                    Text(message)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(message.localizedCaseInsensitiveContains("failed") ? .red : .secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.bottom, 14)
    }

    private var displayedProfilePhotoURL: String? {
        if vm.profilePhotoReviewStatus == "pending" {
            return vm.pendingProfilePhotoURL ?? vm.profilePhotoURL
        }
        return vm.profilePhotoURL
    }
}

struct DriverProfilePhotoButton: View {
    let photoURL: String?
    let isPending: Bool
    let isUploading: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatar
                .frame(width: 54, height: 54)
                .clipShape(Circle())
                .overlay(Circle().stroke(Styles.rydrGradient, lineWidth: 2))
                .opacity(isUploading ? 0.55 : 1)

            ZStack {
                Circle()
                    .fill(isPending ? Color.orange : Color(.systemBackground))
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                Image(systemName: isUploading ? "arrow.triangle.2.circlepath" : (isPending ? "clock.fill" : "camera.fill"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isPending ? AnyShapeStyle(Color.white) : AnyShapeStyle(Styles.rydrGradient))
            }
            .offset(x: 2, y: 2)
        }
        .accessibilityLabel("Change profile photo")
    }

    @ViewBuilder
    private var avatar: some View {
        if let photoURL, let url = URL(string: photoURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFill()
            .foregroundStyle(Styles.rydrGradient)
    }
}
