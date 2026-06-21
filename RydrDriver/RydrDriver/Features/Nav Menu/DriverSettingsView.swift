import SwiftUI

struct DriverSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DriverNavigationHandoff.preferenceKey) private var defaultNavigationProvider = DriverNavigationProvider.rydr.rawValue

    var body: some View {
        List {
            navigationSection
            driverAppSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var navigationSection: some View {
        Section {
            ForEach(DriverNavigationProvider.allCases) { provider in
                Button {
                    defaultNavigationProvider = provider.rawValue
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: provider.icon)
                            .foregroundStyle(Styles.rydrGradient)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(provider.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(provider.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 12)

                        if defaultNavigationProvider == provider.rawValue {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(provider.title), \(defaultNavigationProvider == provider.rawValue ? "selected" : "not selected")")
                .accessibilityHint(provider.subtitle)
            }
        } header: {
            Text("Navigation")
        } footer: {
            Text("Rydr Map is the default in-app driver map. External apps are optional handoffs for turn-by-turn navigation.")
        }
    }

    private var driverAppSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Driver App")
                        .font(.body.weight(.semibold))
                    Text("Navigation settings apply only while driving rides.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "steeringwheel")
                    .foregroundStyle(Styles.rydrGradient)
                    .frame(width: 28)
            }
        } header: {
            Text("About")
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : Color(.systemGroupedBackground)
    }
}

