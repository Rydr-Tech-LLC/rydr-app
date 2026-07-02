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
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var bankVM = RydrBankVM()

    @State private var showImagePicker = false
    @State private var showRiderUpgrade = false
    @State private var pickedUIImage: UIImage?
    @State private var profileImage: Image? = Image(systemName: "person.crop.circle.fill")
    @State private var previousProfileImage: Image?
    @State private var isUploadingPhoto = false
    @State private var photoErrorMessage: String?
    @State private var isVerifiedRider = false
    @State private var isCheckingRiderVerification = false
    @State private var riderVerificationMessage: String?
    @State private var riderVerificationIsError = false

    @State private var musicType: String = "No preference"
    @State private var climate: String = "Neutral"
    @State private var conversation: String = "Light"
    @State private var driverPref: String = "No preference"
    @State private var isSavingPreferences = false
    @State private var preferenceSaveError: String?
    @State private var showPreferencesSavedPopup = false

    private let preferenceStore = RiderRidePreferenceStore()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
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

                logoutButton
            }
            .padding(.top, 14)
            .padding(.bottom, 118)
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .background(profileBackground.ignoresSafeArea())
        .overlay(alignment: .center) {
            if showPreferencesSavedPopup {
                preferencesSavedPopup
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(primaryText)
                            .frame(width: 42, height: 42)
                            .background(adaptiveCardBackground, in: Circle())
                            .shadow(color: softShadow, radius: 12, x: 0, y: 6)

                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .offset(x: -7, y: 8)
                    }
                }
                .accessibilityLabel("Notifications")
            }
        }
        .onAppear {
            session.loadUserProfile()
            loadExistingProfilePhoto()
            loadRiderIdentityStatus()
            loadRidePreferences()
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
        .alert(
            "Preferences Not Saved",
            isPresented: Binding(
                get: { preferenceSaveError != nil },
                set: { if !$0 { preferenceSaveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { preferenceSaveError = nil }
        } message: {
            Text(preferenceSaveError ?? "")
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
                        .frame(width: 82, height: 82)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Styles.rydrGradient, lineWidth: 2))
                        .shadow(color: Color.red.opacity(colorScheme == .dark ? 0.18 : 0.16), radius: 15, x: 0, y: 8)
                        .opacity(isUploadingPhoto ? 0.4 : 1)

                    if isUploadingPhoto {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isUploadingPhoto)

            NavigationLink {
                PersonalInfoView()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hello, \(session.userName)")
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(primaryText)
                        Text("View and manage your account")
                            .font(.footnote)
                            .foregroundStyle(secondaryText)

                        HStack(spacing: 6) {
                            Label(session.isCashHubOnly ? "Cash Rydr Hub Member" : "Rydr Member", systemImage: "star.circle.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Styles.rydrGradient)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Styles.rydrGradient.opacity(0.11), in: Capsule())

                            if session.studentAmbassadorBadge {
                                Label("Student Ambassador", systemImage: "graduationcap.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.red)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.10), in: Capsule())
                            }

                            if session.verifiedBadge || isVerifiedRider {
                                Label("Verified", systemImage: "checkmark.seal.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.11), in: Capsule())
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(secondaryText)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - RydrBank balance summary card

    private var rydrBankBalanceCard: some View {
        let progress = bankVM.summary.eligibleCount % 10
        let remaining = max(0, 10 - progress)

        return NavigationLink {
            RydrBankView()
        } label: {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RydrBank Balance")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(primaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(bankVM.summary.codesAvailable)")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(primaryText)
                        Image("RydrBankWalletR")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                    Text(bankVM.summary.codesAvailable == 1 ? "1 free ride" : "\(bankVM.summary.codesAvailable) free rides")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 1, height: 62)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Next Reward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(primaryText)
                    Text(remaining == 0 ? "Ready" : "\(remaining) rides to go")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(primaryText)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.red.opacity(0.16))
                            Capsule()
                                .fill(Styles.rydrGradient)
                                .frame(width: geo.size.width * CGFloat(progress) / 10.0)
                        }
                    }
                    .frame(height: 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "gift.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Styles.rydrGradient)
                    .frame(width: 48, height: 48)
                    .background(Styles.rydrGradient.opacity(0.10), in: Circle())
            }
            .padding(18)
            .background(rewardCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.red.opacity(colorScheme == .dark ? 0.16 : 0.14), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    private var cashHubOnlyAccountContent: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "Account")
            TileGrid(tiles: [
                .init(title: "Personal Information",
                      subtitle: "Update your details and preferences",
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
            .background(adaptiveCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: softShadow, radius: 14, x: 0, y: 8)
            .padding(.horizontal, 24)
        }
    }

    private var riderAccountContent: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "Account")
            TileGrid(tiles: [
                .init(title: "Personal Information",
                      subtitle: "Update your details and preferences",
                      icon: "person.text.rectangle",
                      destination: AnyView(PersonalInfoView())),
                .init(title: "Ride History & Receipts",
                      subtitle: "View your past rides and receipts",
                      icon: "clock.arrow.circlepath",
                      destination: AnyView(RideHistoryView()
                        .navigationTitle("Ride History"))),
                .init(title: "Payment Methods",
                      subtitle: "Manage cards and payment options",
                      icon: "creditcard",
                      destination: AnyView(PaymentMethodView()
                        .navigationTitle("Payment Methods"))),
                .init(title: "Notifications",
                      subtitle: "Manage your alerts and updates",
                      icon: "bell.badge",
                      destination: AnyView(Text("Coming soon").navigationTitle("Notifications")))
            ])

            settingsRow

            SectionHeader(title: "Features")
            if session.studentAmbassadorBadge {
                studentAmbassadorCard
            }
            verifiedRiderCard
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
                      subtitle: "Get help, view FAQs, and contact support",
                      icon: "questionmark.circle",
                      destination: AnyView(HelpSupportView())),
                .init(title: "Community",
                      subtitle: "Find Atlanta events and tickets",
                      icon: "person.3.sequence",
                      destination: AnyView(CommunityView()))
            ])
        }
    }

    private var studentAmbassadorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image("StudentAmbassadorBadge")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .shadow(color: Color.red.opacity(0.24), radius: 14, x: 0, y: 8)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Student Ambassador")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(primaryText)
                    Text("Recognized as a campus liaison helping Rydr build a student beta testing community.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(adaptiveCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.red.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: softShadow, radius: 14, x: 0, y: 8)
        .padding(.horizontal, 24)
    }

    private var verifiedRiderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 13) {
                Image(systemName: isVerifiedRider ? "checkmark.seal.fill" : "checkmark.seal")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(isVerifiedRider ? Color.green : Color.red)
                    .frame(width: 46, height: 46)
                    .background((isVerifiedRider ? Color.green : Color.red).opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(isVerifiedRider ? "Verified Rider" : "Become a Verified Rider")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(primaryText)
                    Text("Verify your identity to earn a Verified Badge that lets drivers know you've confirmed your identity through Rydr.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            if let riderVerificationMessage {
                Text(riderVerificationMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(riderVerificationIsError ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await startRiderVerification() }
            } label: {
                HStack(spacing: 8) {
                    if isCheckingRiderVerification {
                        ProgressView().tint(isVerifiedRider ? .secondary : .white)
                    } else {
                        Image(systemName: isVerifiedRider ? "checkmark" : "shield.lefthalf.filled")
                    }
                    Text(isVerifiedRider ? "Verified Rider" : "Verify Identity")
                }
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background {
                    if isVerifiedRider {
                        Color(.secondarySystemBackground)
                    } else {
                        Styles.rydrGradient
                    }
                }
                .foregroundStyle(isVerifiedRider ? .green : .white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isVerifiedRider || isCheckingRiderVerification)
        }
        .padding(16)
        .background(adaptiveCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: softShadow, radius: 14, x: 0, y: 8)
        .padding(.horizontal, 24)
    }

    // MARK: - Settings row (full-width)

    private var settingsRow: some View {
        NavigationLink {
            SettingsView()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Styles.rydrGradient.opacity(0.12))
                        .frame(width: 58, height: 58)
                    Image(systemName: "gearshape")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(Styles.rydrGradient)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Manage app settings and preferences")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ZStack {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 39, weight: .bold))
                        .foregroundStyle(Styles.rydrGradient.opacity(0.10))
                    VStack(spacing: 5) {
                        settingsSliderDot(active: true)
                        settingsSliderDot(active: false)
                        settingsSliderDot(active: false)
                    }
                    .offset(x: 20)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(adaptiveCardBackground)
                    .shadow(color: softShadow, radius: 14, x: 0, y: 8)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    private func settingsSliderDot(active: Bool) -> some View {
        HStack(spacing: 3) {
            Capsule()
                .fill(Color.red.opacity(active ? 0.95 : 0.18))
                .frame(width: 21, height: 4)
            Circle()
                .fill(active ? Color.red : Color(.systemGray4))
                .frame(width: 10, height: 10)
        }
    }

    // MARK: - Preferences card
    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Styles.rydrGradient)
                    Text("Preferences")
                            .font(.title3.weight(.heavy))
                        .foregroundStyle(Styles.rydrGradient)
                    }
                    Text("Customize your ride experience")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(secondaryText)
                }

                Spacer()

                Button {
                    musicType = "No preference"
                    climate = "Neutral"
                    conversation = "Light"
                    driverPref = "No preference"
            } label: {
                    Label("Reset to Default", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Styles.rydrGradient)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(adaptiveCardBackground, in: Capsule())
                        .overlay(Capsule().stroke(Color.red.opacity(0.16), lineWidth: 1))
                }
            }

            VStack(spacing: 10) {
                PreferencePicker(title: "Type of Music", selection: $musicType,
                                 subtitle: "What kind of music do you enjoy?",
                                 icon: "music.note",
                                 options: ["No preference", "Hip-Hop", "R&B", "Pop", "Country", "Jazz", "Podcast"])
                PreferencePicker(title: "Climate Control", selection: $climate,
                                 subtitle: "How would you like the climate?",
                                 icon: "fanblades",
                                 options: ["Cool", "Neutral", "Warm"])
                PreferencePicker(title: "Conversation", selection: $conversation,
                                 subtitle: "How much would you like to chat?",
                                 icon: "bubble.left.and.bubble.right",
                                 options: ["Silence", "Light", "Talkative"])
                PreferencePicker(title: "Gender Preference", selection: $driverPref,
                                 subtitle: "Prioritize driver cards by gender",
                                 icon: "person.2",
                                 options: ["No preference", "Male", "Female"])
            }

            Button {
                saveRidePreferences()
            } label: {
                HStack(spacing: 8) {
                    if isSavingPreferences {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                    }
                    Text(isSavingPreferences ? "Saving" : "Save Preferences")
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Styles.rydrGradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(isSavingPreferences)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(adaptiveCardBackground)
                .shadow(color: softShadow, radius: 18, x: 0, y: 10)
        )
        .padding(.horizontal, 24)
    }

    private var currentRidePreferences: RiderRidePreferences {
        RiderRidePreferences(
            musicType: musicType,
            climate: climate,
            conversation: conversation,
            genderPreference: driverPref
        )
    }

    private var preferencesSavedPopup: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Styles.rydrGradient)
                    .frame(width: 66, height: 66)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.white)
            }

            Text("Preferences Saved!")
                .font(.title3.weight(.black))

            Text("Your preferences will be shared with your driver.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        )
        .shadow(color: Color.red.opacity(0.25), radius: 24, y: 12)
        .padding(.horizontal, 24)
        .onTapGesture {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                showPreferencesSavedPopup = false
            }
        }
    }

    private func loadRidePreferences() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            do {
                let preferences = try await preferenceStore.load(uid: uid)
                await MainActor.run {
                    musicType = preferences.musicType
                    climate = preferences.climate
                    conversation = preferences.conversation
                    driverPref = preferences.genderPreference
                }
            } catch {
                await MainActor.run {
                    preferenceSaveError = error.localizedDescription
                }
            }
        }
    }

    private func saveRidePreferences() {
        guard let uid = Auth.auth().currentUser?.uid else {
            preferenceSaveError = "Sign in before saving ride preferences."
            return
        }
        let preferences = currentRidePreferences
        isSavingPreferences = true
        preferenceSaveError = nil

        Task {
            do {
                try await preferenceStore.save(preferences, uid: uid)
                await MainActor.run {
                    isSavingPreferences = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        showPreferencesSavedPopup = true
                    }
                }
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showPreferencesSavedPopup = false
                    }
                }
            } catch {
                await MainActor.run {
                    isSavingPreferences = false
                    preferenceSaveError = error.localizedDescription
                }
            }
        }
    }

    private var profileBackground: Color {
        colorScheme == .dark ? .black : Color(.systemGroupedBackground)
    }

    private var adaptiveCardBackground: Color {
        colorScheme == .dark ? Color(red: 0.085, green: 0.085, blue: 0.095) : .white
    }

    private var rewardCardBackground: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.055, blue: 0.065),
                    Color(red: 0.09, green: 0.065, blue: 0.075)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.88, blue: 0.90),
                Color(red: 1.0, green: 0.96, blue: 0.97)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : Color(red: 0.05, green: 0.08, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.64) : Color(red: 0.38, green: 0.40, blue: 0.48)
    }

    private var softShadow: Color {
        colorScheme == .dark ? Color.black.opacity(0.32) : Color.black.opacity(0.055)
    }

    private var logoutButton: some View {
        Button {
            session.logout()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.headline.weight(.semibold))
                Text("Log Out")
                    .font(.headline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(Styles.rydrGradient)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Styles.rydrGradient, lineWidth: 1.5)
            )
        }
        .padding(.horizontal, 24)
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

    private func loadRiderIdentityStatus() {
        Task {
            do {
                let status = try await RiderIdentityVerificationService.shared.fetchStatus()
                await MainActor.run {
                    isVerifiedRider = status.verifiedRider || status.verifiedBadge || status.identityStatus == "verified"
                }
            } catch {
                // Profile status refresh is best-effort; verification itself surfaces errors.
            }
        }
    }

    @MainActor
    private func startRiderVerification() async {
        isCheckingRiderVerification = true
        riderVerificationMessage = nil
        riderVerificationIsError = false
        defer { isCheckingRiderVerification = false }

        do {
            let clientSecret = try await RiderIdentityVerificationService.shared.createSession()
            let result = try await RiderIdentityVerificationService.shared.presentVerification(clientSecret: clientSecret)

            switch result {
            case .flowCompleted:
                riderVerificationMessage = "Verification submitted. Confirming with Stripe..."
                try await confirmRiderVerifiedStatus()
            case .flowCanceled:
                riderVerificationIsError = true
                riderVerificationMessage = "Verification was canceled. You can try again anytime."
            case .flowFailed(let error):
                riderVerificationIsError = true
                riderVerificationMessage = error.localizedDescription
            }
        } catch {
            riderVerificationIsError = true
            riderVerificationMessage = error.localizedDescription
        }
    }

    @MainActor
    private func confirmRiderVerifiedStatus() async throws {
        for _ in 0..<8 {
            let status = try await RiderIdentityVerificationService.shared.fetchStatus()
            if status.verifiedRider || status.verifiedBadge || status.identityStatus == "verified" {
                isVerifiedRider = true
                riderVerificationIsError = false
                riderVerificationMessage = "Verified Badge added to your profile."
                session.loadUserProfile()
                return
            }
            if status.identityStatus == "requires_input" || status.identityStatus == "canceled" {
                riderVerificationIsError = true
                riderVerificationMessage = "Stripe needs more information before verification can be completed."
                return
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }

        riderVerificationIsError = false
        riderVerificationMessage = "Stripe is still processing your verification. Check back shortly."
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
        .padding(.horizontal, 24)
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
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(tiles) { tile in
                NavigationLink {
                    tile.destination
                } label: {
                    TileCard(title: tile.title, subtitle: tile.subtitle, icon: tile.icon)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
    }
}

struct TileCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var subtitle: String = ""
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            iconBubble

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Styles.rydrGradient, in: Circle())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color(red: 0.085, green: 0.085, blue: 0.095) : .white)
                .shadow(color: colorScheme == .dark ? .black.opacity(0.28) : .black.opacity(0.055), radius: 14, x: 0, y: 8)
        )
    }

    private var iconBubble: some View {
        Image(systemName: icon)
            .font(.system(size: 23, weight: .semibold))
            .foregroundStyle(Styles.rydrGradient)
            .frame(width: 54, height: 54)
            .background(Styles.rydrGradient.opacity(0.10), in: Circle())
            .shadow(color: Color.red.opacity(colorScheme == .dark ? 0.12 : 0.10), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Preference Picker row
struct PreferencePicker: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    @Binding var selection: String
    let subtitle: String
    let icon: String
    let options: [String]

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 52, height: 52)
                .background(Styles.rydrGradient.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Menu {
                ForEach(options, id: \.self) { opt in
                    Button(opt) { selection = opt }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selection)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Styles.rydrGradient)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Styles.rydrGradient)
                }
                .frame(width: 138)
                .padding(.vertical, 12)
                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : .white)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }
}
