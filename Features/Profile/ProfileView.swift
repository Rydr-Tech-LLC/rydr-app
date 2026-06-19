//
//  ProfileView.swift
//  RydrPlayground
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - ProfileView
struct ProfileView: View {
    @EnvironmentObject var session: UserSessionManager
    @StateObject private var bankVM = RydrBankVM()

    @State private var showImagePicker = false
    @State private var showRiderUpgrade = false
    @State private var pickedUIImage: UIImage?
    @State private var profileImage: Image? = Image(systemName: "person.crop.circle.fill")
    @State private var previousProfileImage: Image?
    @State private var isUploadingPhoto = false
    @State private var photoErrorMessage: String?

    // Preferences (local for now; wire to Firestore later)
    @State private var musicType: String = "No preference"
    @State private var climate: String = "Neutral"
    @State private var conversation: String = "Light"
    @State private var driverPref: String = "No preference"

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {

                profileHeader

                if !session.isCashHubOnly {
                    rydrBankBalanceCard
                }

                if session.isCashHubOnly {
                    cashHubOnlyAccountContent
                } else {
                    riderAccountContent
                    preferencesCard
                }

                // Logout
                Button {
                    session.logout()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.headline.weight(.semibold))
                        Text("Log Out")
                            .font(.headline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(Styles.rydrGradient)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Styles.rydrGradient, lineWidth: 1.5)
                    )
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
        }
        .navigationTitle("Profile")
        .background(Color(.systemGroupedBackground))
        .onAppear {
            session.loadUserProfile()
            loadExistingProfilePhoto()
            if !session.isCashHubOnly { bankVM.start() }
        }
        .onDisappear { bankVM.stop() }
        .sheet(isPresented: $showImagePicker, onDismiss: didPickPhoto) {
            ImagePicker(selectedImage: $pickedUIImage, sourceType: .photoLibrary)
        }
        .fullScreenCover(isPresented: $showRiderUpgrade) {
            SignupCoordinator(upgradingCashHubAccount: true)
                .environmentObject(session)
        }
        .alert(
            "Photo Not Approved",
            isPresented: Binding(
                get: { photoErrorMessage != nil },
                set: { if !$0 { photoErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { photoErrorMessage = nil }
        } message: {
            Text(photoErrorMessage ?? "")
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        HStack(spacing: 16) {
            Button { showImagePicker = true } label: {
                ZStack {
                    (profileImage ?? Image(systemName: "person.crop.circle.fill"))
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Styles.rydrGradient, lineWidth: 2))
                        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                        .opacity(isUploadingPhoto ? 0.4 : 1)

                    if isUploadingPhoto {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isUploadingPhoto)

            VStack(alignment: .leading, spacing: 6) {
                Text("Hello, \(session.userName)")
                    .font(.title3.weight(.bold))
                Text("View and manage your account")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(session.isCashHubOnly ? "Cash Rydr Hub Member" : "Rydr Member")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Styles.rydrGradient)
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - RydrBank balance summary card

    private var rydrBankBalanceCard: some View {
        let progress = bankVM.summary.eligibleCount % 10
        let remaining = max(0, 10 - progress)

        return NavigationLink {
            RydrBankView()
        } label: {
            ZStack(alignment: .topTrailing) {
                Styles.rydrGradient

                Image(systemName: "gift.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
                    .padding(16)

                VStack(alignment: .leading, spacing: 10) {
                    Text("RydrBank Balance")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(bankVM.summary.codesAvailable)")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text(bankVM.summary.codesAvailable == 1 ? "free ride" : "free rides")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Next Reward")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Text("\(progress)/10")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white.opacity(0.85))
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.22))
                                Capsule()
                                    .fill(Color.white)
                                    .frame(width: geo.size.width * CGFloat(progress) / 10.0)
                            }
                        }
                        .frame(height: 8)

                        Text(remaining == 0
                             ? "Reward ready on your next eligible ride."
                             : "\(remaining) more eligible \(remaining == 1 ? "ride" : "rides") to go.")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.red.opacity(0.22), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var cashHubOnlyAccountContent: some View {
        Group {
            SectionHeader(title: "Account")
            TileGrid(tiles: [
                .init(title: "Personal Information",
                      subtitle: "Name, contact, and account details",
                      icon: "person.text.rectangle",
                      destination: AnyView(PersonalInfoView())),
                .init(title: "Cash Rydr Hub",
                      subtitle: "Posts, offers, and ride activity",
                      icon: "rectangle.on.rectangle.angled",
                      destination: AnyView(CashRydrHubView())),
                .init(title: "Help & Support",
                      subtitle: "FAQs and contact support",
                      icon: "questionmark.circle",
                      destination: AnyView(HelpSupportView()))
            ])

            settingsRow

            VStack(alignment: .leading, spacing: 12) {
                Text("Want standard Rydr rides?")
                    .font(.headline)
                Text("Complete rider signup to access ride booking, payment methods, ride history, and eligible rider features. Your saved information will be filled in for you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    showRiderUpgrade = true
                } label: {
                    Text("Become a Rydr Rider")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(GradientButtonStyle())
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
        }
    }

    private var riderAccountContent: some View {
        Group {
            SectionHeader(title: "Account")
            TileGrid(tiles: [
                .init(title: "Personal Information",
                      subtitle: "Name, contact, and account details",
                      icon: "person.text.rectangle",
                      destination: AnyView(PersonalInfoView())),
                .init(title: "Ride History & Receipts",
                      subtitle: "Past rides and receipts",
                      icon: "clock.arrow.circlepath",
                      destination: AnyView(RideHistoryView()
                        .navigationTitle("Ride History"))),
                .init(title: "Payment Methods",
                      subtitle: "Cards and billing",
                      icon: "creditcard",
                      destination: AnyView(PaymentMethodView()
                        .navigationTitle("Payment Methods"))),
                .init(title: "Notifications",
                      subtitle: "Alerts and updates",
                      icon: "bell.badge",
                      destination: AnyView(Text("Coming soon").navigationTitle("Notifications")))
            ])

            settingsRow

            SectionHeader(title: "Features")
            TileGrid(tiles: [
                .init(title: "Cash Rydr Hub",
                      subtitle: "Posts, offers, and ride activity",
                      icon: "rectangle.on.rectangle.angled",
                      destination: AnyView(CashRydrHubView())),
                .init(title: "RydrBank",
                      subtitle: "Banked free rides and rewards",
                      icon: "banknote",
                      destination: AnyView(RydrBankView())),
                .init(title: "Help & Support",
                      subtitle: "FAQs and contact support",
                      icon: "questionmark.circle",
                      destination: AnyView(HelpSupportView())),
                .init(title: "Community",
                      subtitle: "Local events near you",
                      icon: "person.3.sequence",
                      destination: AnyView(Text("Coming soon").navigationTitle("Community")))
            ])
        }
    }

    // MARK: - Settings row (full-width)

    private var settingsRow: some View {
        NavigationLink {
            SettingsView()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Styles.rydrGradient.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: "gearshape")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Styles.rydrGradient)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("App preferences and privacy")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    // MARK: - Preferences card
    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Styles.rydrGradient)
                    Text("Preferences")
                        .font(.headline)
                        .foregroundStyle(Styles.rydrGradient)
                }

                Spacer()

                Button {
                    musicType = "No preference"
                    climate = "Neutral"
                    conversation = "Light"
                    driverPref = "No preference"
                } label: {
                    Text("Reset to Default")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }
            }

            VStack(spacing: 10) {
                PreferencePicker(title: "Type of Music", selection: $musicType,
                                 options: ["No preference", "Hip-Hop", "R&B", "Pop", "Country", "Jazz", "Podcast"])
                PreferencePicker(title: "Climate Control", selection: $climate,
                                 options: ["Cool", "Neutral", "Warm"])
                PreferencePicker(title: "Conversation", selection: $conversation,
                                 options: ["Silence", "Light", "Talkative"])
                PreferencePicker(title: "Driver", selection: $driverPref,
                                 options: ["No preference", "Male", "Female"])
            }

            Button {
                // TODO: Persist to Firestore (users/{uid}/preferences)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                    Text("Save Preferences")
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Styles.rydrGradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal)
    }

    // MARK: - Image picker handler
    private func didPickPhoto() {
        guard let ui = pickedUIImage else { return }

        // Show the picked photo immediately (optimistic UI), but remember
        // what was there before in case moderation rejects it.
        previousProfileImage = profileImage
        profileImage = Image(uiImage: ui)
        isUploadingPhoto = true

        Task {
            do {
                _ = try await ImageModerationService.shared.submitProfilePhoto(ui)
            } catch {
                await MainActor.run {
                    profileImage = previousProfileImage
                    photoErrorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isUploadingPhoto = false
                pickedUIImage = nil
            }
        }
    }

    // MARK: - Load a previously-approved photo on appear
    private func loadExistingProfilePhoto() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        Firestore.firestore().collection("riders").document(uid).getDocument { snapshot, _ in
            guard
                let urlString = snapshot?.data()?["photoURL"] as? String,
                let url = URL(string: urlString)
            else { return }

            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let uiImage = UIImage(data: data) else { return }
                Task { @MainActor in
                    profileImage = Image(uiImage: uiImage)
                }
            }.resume()
        }
    }
}

// MARK: - Section header with gradient
struct SectionHeader: View {
    let title: String
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Styles.rydrGradient)
            Spacer()
        }
        .padding(.horizontal)
    }
}

// MARK: - Tile Grid + Card
struct TileItem: Identifiable {
    let id = UUID()
    let title: String
    var subtitle: String = ""
    let icon: String
    let destination: AnyView
}

struct TileGrid: View {
    let tiles: [TileItem]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(tiles) { tile in
                NavigationLink {
                    tile.destination
                } label: {
                    TileCard(title: tile.title, subtitle: tile.subtitle, icon: tile.icon)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
}

struct TileCard: View {
    let title: String
    var subtitle: String = ""
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Styles.rydrGradient.opacity(0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Styles.rydrGradient)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
        )
    }
}

// MARK: - Preference Picker row
struct PreferencePicker: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)

            Spacer()

            Menu {
                ForEach(options, id: \.self) { opt in
                    Button(opt) { selection = opt }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selection)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Styles.rydrGradient)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Styles.rydrGradient)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Styles.rydrGradient.opacity(0.10))
                .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings (placeholder)
struct SettingsView: View {
    var body: some View {
        List {
            Toggle("Dark Mode", isOn: .constant(false))
            Toggle("Location Services", isOn: .constant(true))
            Toggle("Face ID for Login", isOn: .constant(true))
        }
        .navigationTitle("Settings")
    }
}





