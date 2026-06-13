import SwiftUI
import MapKit
import CoreLocation
import Combine

enum DriverWorkRadius: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    case custom = "Custom"

    var id: String { rawValue }

    var defaultMiles: Double {
        switch self {
        case .small: return 5
        case .medium: return 10
        case .large: return 15
        case .custom: return 20
        }
    }

    var chipSubtitle: String {
        switch self {
        case .small: return "5 mi"
        case .medium: return "10 mi"
        case .large: return "15 mi"
        case .custom: return "20 mi"
        }
    }
}

enum DriverRouteCorridor: String, CaseIterable, Identifiable {
    case tight = "Tight"
    case balanced = "Balanced"
    case flexible = "Flexible"

    var id: String { rawValue }

    var miles: Double {
        switch self {
        case .tight: return 2
        case .balanced: return 5
        case .flexible: return 10
        }
    }

    var subtitle: String { "\(Int(miles)) mi" }
}

struct DriverRideFilterPreferences: Equatable {
    static let minimumWorkZoneMiles: Double = 5
    static let maximumWorkZoneMiles: Double = 20
    static let workZoneStepMiles: Double = 5

    var workZoneEnabled: Bool = false
    var pickupRadius: DriverWorkRadius = .medium
    var customPickupMiles: Double = DriverWorkRadius.medium.defaultMiles
    var destinationText: String = ""
    var destinationCoordinate: CLLocationCoordinate2D?
    var destinationModeEnabled: Bool = false
    var destinationCorridor: DriverRouteCorridor = .balanced
    var prioritizeLongerRides: Bool = true
    var avoidShortPickups: Bool = false
    var showPremiumFirst: Bool = true

    var effectivePickupMiles: Double {
        pickupRadius == .custom ? customPickupMiles : pickupRadius.defaultMiles
    }

    var hasDestinationFilter: Bool {
        destinationModeEnabled
            && destinationCoordinate != nil
            && !destinationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func == (lhs: DriverRideFilterPreferences, rhs: DriverRideFilterPreferences) -> Bool {
        lhs.pickupRadius == rhs.pickupRadius
            && lhs.customPickupMiles == rhs.customPickupMiles
            && lhs.workZoneEnabled == rhs.workZoneEnabled
            && lhs.destinationText == rhs.destinationText
            && lhs.destinationModeEnabled == rhs.destinationModeEnabled
            && lhs.destinationCorridor == rhs.destinationCorridor
            && lhs.prioritizeLongerRides == rhs.prioritizeLongerRides
            && lhs.avoidShortPickups == rhs.avoidShortPickups
            && lhs.showPremiumFirst == rhs.showPremiumFirst
            && lhs.destinationCoordinate?.latitude == rhs.destinationCoordinate?.latitude
            && lhs.destinationCoordinate?.longitude == rhs.destinationCoordinate?.longitude
    }
}

struct DriverRideFiltersView: View {
    @Binding var preferences: DriverRideFilterPreferences
    var onClose: () -> Void

    @StateObject private var destinationSearch = DriverDestinationSearchModel()
    @State private var draft: DriverRideFilterPreferences

    init(
        preferences: Binding<DriverRideFilterPreferences>,
        onClose: @escaping () -> Void
    ) {
        _preferences = preferences
        self.onClose = onClose
        _draft = State(initialValue: preferences.wrappedValue)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    grabber
                    header
                    WorkZoneRadiusControl(preferences: $draft)
                    DestinationModeControl(
                        preferences: $draft,
                        search: destinationSearch
                    )
                    RidePreferenceControl(preferences: $draft)
                    Color.clear.frame(height: 92)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            saveButton
        }
        .presentationBackground(.clear)
        .onAppear {
            destinationSearch.setRegion(DriverMapDefaults.pilotRegion)
            destinationSearch.setQuery(draft.destinationText)
        }
        .onChange(of: draft.destinationText) { _, newValue in
            destinationSearch.setQuery(newValue)
        }
        .onChange(of: draft) { _, newValue in
            preferences = newValue
        }
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.32))
            .frame(width: 46, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Ride Filters")
                    .font(.title3.weight(.black))
                    .foregroundStyle(.primary)
                Text("Your zone. Your route. Your rules.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary.opacity(0.58))
            }

            Spacer()

            Button("Done", action: onClose)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.red)
        }
        .padding(.bottom, 4)
    }

    private var saveButton: some View {
        Button {
            preferences = draft
            onClose()
        } label: {
            Label("Save Filters", systemImage: "slider.horizontal.3")
                .font(.headline.weight(.black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Styles.rydrGradient))
                .foregroundStyle(.white)
                .shadow(color: Color.red.opacity(0.30), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
    }
}

private struct WorkZoneRadiusControl: View {
    @Binding var preferences: DriverRideFilterPreferences

    var body: some View {
        RydrFilterSection(
            icon: "scope",
            title: "Work Zone",
            subtitle: "Set the area where you want to receive ride requests."
        ) {
            Toggle(isOn: $preferences.workZoneEnabled) {
                Text("Limit rides to this zone")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }
            .tint(.red)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preferences.workZoneEnabled ? "\(Int(preferences.effectivePickupMiles.rounded())) miles" : "Off")
                        .font(.title3.weight(.black))
                        .foregroundStyle(.primary)
                    Text("Current radius")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }

                Spacer()

                WorkZonePulseBadge()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))

            RadiusChipGrid(selection: $preferences.pickupRadius)
                .onChange(of: preferences.pickupRadius) { _, radius in
                    preferences.workZoneEnabled = true
                    if radius != .custom {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                            preferences.customPickupMiles = radius.defaultMiles
                        }
                    }
                }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Custom Radius")
                    Spacer()
                    Text("\(Int(preferences.effectivePickupMiles.rounded())) mi")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.secondary.opacity(0.78))

                HStack(spacing: 10) {
                    Text("5 mi")
                    Slider(value: Binding(
                        get: { preferences.customPickupMiles },
                        set: { newValue in
                            preferences.workZoneEnabled = true
                            preferences.pickupRadius = .custom
                            preferences.customPickupMiles = newValue
                        }
                    ), in: DriverRideFilterPreferences.minimumWorkZoneMiles...DriverRideFilterPreferences.maximumWorkZoneMiles, step: DriverRideFilterPreferences.workZoneStepMiles)
                    .tint(.red)
                    Text("20 mi")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary.opacity(0.62))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Color(.tertiarySystemBackground)))

            Text(preferences.workZoneEnabled
                 ? "Showing ride requests within \(Int(preferences.effectivePickupMiles.rounded())) miles."
                 : "Showing ride requests from all nearby service areas.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary.opacity(0.62))
        }
    }
}

private struct DestinationModeControl: View {
    @Binding var preferences: DriverRideFilterPreferences
    @ObservedObject var search: DriverDestinationSearchModel

    var body: some View {
        RydrFilterSection(
            icon: "location.north.line.fill",
            title: "Destination Mode",
            subtitle: "Only show rides heading toward your destination."
        ) {
            Toggle(isOn: $preferences.destinationModeEnabled) {
                Text("Head your way")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }
            .tint(.red)

            destinationSearchField

            if preferences.destinationModeEnabled && !search.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(search.results.prefix(4), id: \.self) { completion in
                        Button {
                            Task { await select(completion) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(Color.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.primary)
                                    Text(completion.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(Color.secondary.opacity(0.55))
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Color.black.opacity(0.08))
                    }
                }
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.tertiarySystemBackground)))
            }

            if preferences.hasDestinationFilter {
                HStack(spacing: 12) {
                    Image(systemName: "airplane.departure")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.red.opacity(0.38)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Destination")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.secondary.opacity(0.48))
                        Text(preferences.destinationText)
                            .font(.subheadline.weight(.bold))
                            .lineLimit(2)
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Button {
                        clearDestination()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.black))
                            .foregroundStyle(Color.secondary.opacity(0.8))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.black.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear destination")
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Route Corridor")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.primary)
                CorridorChipRow(selection: $preferences.destinationCorridor)
            }

            Button(role: .destructive) {
                clearDestination()
            } label: {
                Label("Clear Destination", systemImage: "trash")
                    .font(.caption.weight(.black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.red)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color(.tertiarySystemBackground)))
        }
    }

    private var destinationSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.secondary.opacity(0.62))

            TextField("Set destination", text: $preferences.destinationText)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .foregroundStyle(.primary)

            if !preferences.destinationText.isEmpty {
                Button {
                    clearDestination(keepMode: true)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary.opacity(0.48))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    @MainActor
    private func select(_ completion: MKLocalSearchCompletion) async {
        let request = MKLocalSearch.Request(completion: completion)
        request.region = DriverMapDefaults.pilotRegion

        do {
            let response = try await MKLocalSearch(request: request).start()
            if let item = response.mapItems.first {
                preferences.destinationText = item.name ?? completion.title
                preferences.destinationCoordinate = item.location.coordinate
                preferences.destinationModeEnabled = true
                search.results = []
            }
        } catch {
            preferences.destinationText = completion.title
        }
    }

    private func clearDestination(keepMode: Bool = false) {
        preferences.destinationText = ""
        preferences.destinationCoordinate = nil
        preferences.destinationModeEnabled = keepMode
        search.results = []
    }
}

private struct RidePreferenceControl: View {
    @Binding var preferences: DriverRideFilterPreferences

    var body: some View {
        RydrFilterSection(
            icon: "slider.horizontal.3",
            title: "Ride Preferences",
            subtitle: "Fine tune what gets surfaced first."
        ) {
            PreferenceToggleRow(
                title: "Prioritize longer rides",
                subtitle: "Show higher paying, longer trips first.",
                isOn: $preferences.prioritizeLongerRides
            )
            PreferenceToggleRow(
                title: "Avoid short pickups",
                subtitle: "Filter out pickups under 1.5 miles.",
                isOn: $preferences.avoidShortPickups
            )
            PreferenceToggleRow(
                title: "Show premium ride types first",
                subtitle: "Prioritize XL, Prestine, and Executive.",
                isOn: $preferences.showPremiumFirst
            )
        }
    }
}

private struct RydrFilterSection<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.headline.weight(.black))
                    .foregroundStyle(Color.red)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.red.opacity(0.15)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.weight(.black))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }

                Spacer()
            }

            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))
        )
        .shadow(color: Color.black.opacity(0.06), radius: 12, y: 6)
    }
}

private struct RadiusChipGrid: View {
    @Binding var selection: DriverWorkRadius

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DriverWorkRadius.allCases) { radius in
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        selection = radius
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text(radius.rawValue)
                            .font(.caption.weight(.black))
                        Text(radius.chipSubtitle)
                            .font(.caption2.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selection == radius ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color(.secondarySystemBackground)))
                    )
                    .foregroundStyle(selection == radius ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CorridorChipRow: View {
    @Binding var selection: DriverRouteCorridor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DriverRouteCorridor.allCases) { corridor in
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        selection = corridor
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text(corridor.rawValue)
                            .font(.caption.weight(.black))
                        Text(corridor.subtitle)
                            .font(.caption2.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selection == corridor ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color(.secondarySystemBackground)))
                    )
                    .foregroundStyle(selection == corridor ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct PreferenceToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary.opacity(0.52))
            }
        }
        .tint(.red)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

private struct WorkZonePulseBadge: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach([40.0, 58.0, 76.0], id: \.self) { size in
                Circle()
                    .stroke(Color.red.opacity(pulse ? 0.04 : 0.22), lineWidth: 2)
                    .frame(width: size, height: size)
                    .scaleEffect(pulse ? 1.06 : 0.90)
            }
            Circle()
                .fill(Styles.rydrGradient)
                .frame(width: 34, height: 34)
            Image(systemName: "car.fill")
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
        }
        .frame(width: 84, height: 64)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

final class DriverDestinationSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = DriverMapDefaults.pilotRegion
    }

    func setRegion(_ region: MKCoordinateRegion) {
        completer.region = region
    }

    func setQuery(_ text: String) {
        completer.queryFragment = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}
