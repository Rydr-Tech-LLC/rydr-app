//
//  Settings.swift
//  RydrPlayground
//

import SwiftUI
import LocalAuthentication
import UserNotifications

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @AppStorage("appAppearance") private var appAppearance = RydrAppAppearance.system.rawValue
    @AppStorage("faceIDForLoginEnabled") private var faceIDForLoginEnabled = false
    @AppStorage("locationServicesEnabled") private var locationServicesEnabled = true
    @AppStorage("rideStatusPushEnabled") private var rideStatusPushEnabled = true
    @AppStorage("driverMessagesPushEnabled") private var driverMessagesPushEnabled = true
    @AppStorage("promoPushEnabled") private var promoPushEnabled = false
    @AppStorage("safetyPushEnabled") private var safetyPushEnabled = true
    @AppStorage("reduceMotionPreference") private var reduceMotionPreference = false
    @AppStorage("highContrastPreference") private var highContrastPreference = false
    @AppStorage("largeControlsPreference") private var largeControlsPreference = false

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var biometricMessage: String?

    var body: some View {
        List {
            appearanceSection
            notificationsSection
            privacySection
            accessibilitySection
            supportSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(settingsBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshNotificationStatus() }
        .alert("Face ID", isPresented: Binding(
            get: { biometricMessage != nil },
            set: { if !$0 { biometricMessage = nil } }
        )) {
            Button("OK", role: .cancel) { biometricMessage = nil }
        } message: {
            Text(biometricMessage ?? "")
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $appAppearance) {
                ForEach(RydrAppAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("App appearance")

            settingsToggle(
                title: "High Contrast",
                subtitle: "Increase contrast on supported Rydr screens.",
                icon: "circle.lefthalf.filled",
                isOn: $highContrastPreference
            )
        } header: {
            sectionHeader("Appearance")
        } footer: {
            Text("System follows your iPhone setting. Light and Dark override it inside Rydr.")
        }
    }

    private var notificationsSection: some View {
        Section {
            notificationStatusRow

            settingsToggle(
                title: "Ride Updates",
                subtitle: "Driver arrival, pickup, drop-off, and receipt updates.",
                icon: "car.fill",
                isOn: $rideStatusPushEnabled,
                onChange: handleNotificationPreferenceChange
            )

            settingsToggle(
                title: "Driver Messages",
                subtitle: "Messages from your driver during an active ride.",
                icon: "message.fill",
                isOn: $driverMessagesPushEnabled,
                onChange: handleNotificationPreferenceChange
            )

            settingsToggle(
                title: "Safety Alerts",
                subtitle: "Important trip and account safety notifications.",
                icon: "shield.checkered",
                isOn: $safetyPushEnabled,
                onChange: handleNotificationPreferenceChange
            )

            settingsToggle(
                title: "Promos & RydrBank",
                subtitle: "Rewards, offers, and RydrBank updates.",
                icon: "gift.fill",
                isOn: $promoPushEnabled,
                onChange: handleNotificationPreferenceChange
            )
        } header: {
            sectionHeader("Notifications")
        } footer: {
            Text("These preferences control which Rydr alerts you want. iOS notification permission is managed by your device.")
        }
    }

    private var privacySection: some View {
        Section {
            settingsToggle(
                title: "Location Services",
                subtitle: "Allow Rydr to use location for pickup, drop-off, and ride tracking.",
                icon: "location.fill",
                isOn: $locationServicesEnabled
            )

            Button {
                openAppSettings()
            } label: {
                settingsNavigationRow(
                    title: "Open iOS Permissions",
                    subtitle: "Review Location, Notifications, and Cellular Data.",
                    icon: "gearshape.fill"
                )
            }
            .buttonStyle(.plain)

            settingsToggle(
                title: biometricTitle,
                subtitle: "Require biometric confirmation before quick login.",
                icon: "faceid",
                isOn: Binding(
                    get: { faceIDForLoginEnabled },
                    set: { updateBiometricPreference($0) }
                )
            )
            .disabled(!canUseBiometrics)
        } header: {
            sectionHeader("Privacy & Security")
        }
    }

    private var accessibilitySection: some View {
        Section {
            settingsToggle(
                title: "Reduce Motion",
                subtitle: "Limit decorative movement on supported Rydr screens.",
                icon: "figure.walk.motion",
                isOn: $reduceMotionPreference
            )

            settingsToggle(
                title: "Larger Controls",
                subtitle: "Use roomier tap targets where supported.",
                icon: "hand.tap.fill",
                isOn: $largeControlsPreference
            )

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                settingsNavigationRow(
                    title: "Open Accessibility Settings",
                    subtitle: "Manage VoiceOver, text size, contrast, and motion.",
                    icon: "accessibility"
                )
            }
            .buttonStyle(.plain)
        } header: {
            sectionHeader("Accessibility")
        }
    }

    private var supportSection: some View {
        Section {
            NavigationLink {
                HelpSupportView()
            } label: {
                settingsNavigationRow(
                    title: "Help & Support",
                    subtitle: "Get help with trips, payments, safety, and account issues.",
                    icon: "questionmark.circle.fill",
                    showChevron: false
                )
            }

            settingsStaticRow(
                title: "Rydr",
                subtitle: "Rider app settings are saved on this device.",
                icon: "info.circle.fill"
            )
        } header: {
            sectionHeader("Support")
        }
    }

    private var notificationStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: notificationStatusIcon)
                .foregroundStyle(notificationStatus == .authorized ? Color.green : Color.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("iOS Permission")
                    .foregroundStyle(primaryText)
                Text(notificationStatusText)
                    .font(.caption)
                    .foregroundStyle(secondaryText)
            }

            Spacer()

            Button(notificationStatus == .denied ? "Settings" : "Refresh") {
                if notificationStatus == .denied {
                    openAppSettings()
                } else {
                    Task { await refreshNotificationStatus() }
                }
            }
            .font(.caption.weight(.bold))
            .buttonStyle(.bordered)
            .accessibilityLabel(notificationStatus == .denied ? "Open notification settings" : "Refresh notification permission status")
        }
    }

    private func settingsToggle(
        title: String,
        subtitle: String,
        icon: String,
        isOn: Binding<Bool>,
        onChange: ((Bool) -> Void)? = nil
    ) -> some View {
        Toggle(isOn: Binding(
            get: { isOn.wrappedValue },
            set: { newValue in
                isOn.wrappedValue = newValue
                onChange?(newValue)
            }
        )) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Styles.rydrGradient)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(primaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                }
            }
        }
        .tint(.green)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    private func settingsNavigationRow(
        title: String,
        subtitle: String,
        icon: String,
        showChevron: Bool = true
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(secondaryText)
            }

            Spacer()

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(secondaryText)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func settingsStaticRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(secondaryText)
    }

    private func handleNotificationPreferenceChange(_ isEnabled: Bool) {
        guard isEnabled else { return }
        Task {
            await requestNotificationPermissionIfNeeded()
            await refreshNotificationStatus()
        }
    }

    @MainActor
    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }

    @MainActor
    private func requestNotificationPermissionIfNeeded() async {
        let currentSettings = await UNUserNotificationCenter.current().notificationSettings()
        guard currentSettings.authorizationStatus == .notDetermined else { return }

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            notificationStatus = .denied
        }
    }

    private func updateBiometricPreference(_ enabled: Bool) {
        guard enabled else {
            faceIDForLoginEnabled = false
            return
        }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            faceIDForLoginEnabled = false
            biometricMessage = error?.localizedDescription ?? "Biometric login is not available on this device."
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Enable biometric login for Rydr.") { success, evaluationError in
            Task { @MainActor in
                faceIDForLoginEnabled = success
                if !success {
                    biometricMessage = evaluationError?.localizedDescription ?? "Biometric verification was not completed."
                }
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private var canUseBiometrics: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    private var biometricTitle: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:
            return "Face ID for Login"
        case .touchID:
            return "Touch ID for Login"
        default:
            return "Biometric Login"
        }
    }

    private var notificationStatusIcon: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "checkmark.circle.fill"
        case .denied:
            return "exclamationmark.triangle.fill"
        default:
            return "bell.badge.fill"
        }
    }

    private var notificationStatusText: String {
        switch notificationStatus {
        case .authorized:
            return "Allowed"
        case .provisional:
            return "Allowed quietly"
        case .ephemeral:
            return "Allowed for this session"
        case .denied:
            return "Disabled in iOS Settings"
        case .notDetermined:
            return "Not requested yet"
        @unknown default:
            return "Unknown"
        }
    }

    private var settingsBackground: Color {
        colorScheme == .dark ? .black : Color(.systemGroupedBackground)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : Color(red: 0.05, green: 0.08, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.66) : Color(red: 0.38, green: 0.40, blue: 0.48)
    }
}
