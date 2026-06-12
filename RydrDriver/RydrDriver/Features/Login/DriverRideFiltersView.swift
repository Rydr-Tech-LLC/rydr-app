import SwiftUI
import CoreLocation

enum DriverWorkRadius: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var id: String { rawValue }

    var miles: Double {
        switch self {
        case .small: return 5
        case .medium: return 12
        case .large: return 25
        }
    }

    var label: String {
        "\(rawValue) • \(Int(miles)) mi"
    }
}

struct DriverRideFilterPreferences: Equatable {
    var pickupRadius: DriverWorkRadius = .medium
    var destinationText: String = ""
    var destinationRadius: DriverWorkRadius = .medium

    var hasDestinationFilter: Bool {
        !destinationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct DriverRideFiltersView: View {
    @Binding var preferences: DriverRideFilterPreferences
    var onClose: () -> Void

    @State private var draftPickupRadius: DriverWorkRadius
    @State private var draftDestinationText: String
    @State private var draftDestinationRadius: DriverWorkRadius

    init(
        preferences: Binding<DriverRideFilterPreferences>,
        onClose: @escaping () -> Void
    ) {
        _preferences = preferences
        self.onClose = onClose
        _draftPickupRadius = State(initialValue: preferences.wrappedValue.pickupRadius)
        _draftDestinationText = State(initialValue: preferences.wrappedValue.destinationText)
        _draftDestinationRadius = State(initialValue: preferences.wrappedValue.destinationRadius)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    filterSection("Work Area") {
                        Text("Pickup Radius")
                            .font(.subheadline.weight(.semibold))
                        radiusPicker(selection: $draftPickupRadius)
                    }

                    filterSection("Destination Mode") {
                        TextField("Where are you heading?", text: $draftDestinationText)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground)))

                        Text("Destination Radius")
                            .font(.subheadline.weight(.semibold))
                        radiusPicker(selection: $draftDestinationRadius)
                    }

                    Button {
                        preferences = DriverRideFilterPreferences(
                            pickupRadius: draftPickupRadius,
                            destinationText: draftDestinationText.trimmingCharacters(in: .whitespacesAndNewlines),
                            destinationRadius: draftDestinationRadius
                        )
                        onClose()
                    } label: {
                        Label("Save Filters", systemImage: "slider.horizontal.3")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Styles.rydrGradient))
                            .foregroundStyle(.white)
                    }
                }
                .padding()
            }
            .navigationTitle("Ride Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onClose() }
                }
            }
        }
    }

    private func filterSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private func radiusPicker(selection: Binding<DriverWorkRadius>) -> some View {
        Picker("Radius", selection: selection) {
            ForEach(DriverWorkRadius.allCases) { radius in
                Text(radius.label).tag(radius)
            }
        }
        .pickerStyle(.segmented)
    }
}
