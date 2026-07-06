import SwiftUI
import MapKit
import _MapKit_SwiftUI
import CoreLocation
import UIKit

private struct RoutePreview {
    let estimate: RideEstimate
    let polyline: MKPolyline
}

struct BookingView: View {
    // Inputs
    let rideType: String
    let userName: String

    // 🔹 Ride flow
    @EnvironmentObject var rideManager: RideManager
    @EnvironmentObject private var session: UserSessionManager
    @State private var showDriverSheet = false
    @State private var showInProgress = false

    // Map / region
    @State private var region = RydrMapDefaults.atlantaRegion
    @State private var mapPosition: MapCameraPosition = .region(RydrMapDefaults.atlantaRegion)
    @StateObject private var locationManager = LocationManager()
    @State private var pickupCoordinate: CLLocationCoordinate2D?
    @State private var dropoffCoordinate: CLLocationCoordinate2D?
    @State private var pickupResolvedAddress = ""
    @State private var dropoffResolvedAddress = ""
    @State private var routeEstimate: RideEstimate?
    @State private var routePolyline: MKPolyline?
    @State private var routeErrorMessage: String?
    @State private var routeRequestID = UUID()
    @State private var isResolvingLocations = false
    @State private var showRoutePreview = false

    // Fields
    @State private var pickupText = ""
    @State private var stopText = ""
    @State private var dropoffText = ""
    @FocusState private var focusedField: Field?
    @State private var showStopField = false
    private enum Field { case pickup, stop, dropoff, shortcut }

    // Search completers
    @StateObject private var pickupCompleter  = SearchCompleter()
    @StateObject private var stopCompleter = SearchCompleter()
    @StateObject private var dropoffCompleter = SearchCompleter()
    @StateObject private var shortcutCompleter = SearchCompleter()

    // Slider (mid-open on appear; snaps top/mid/bottom)
    @State private var sliderOffset: CGFloat = 0
    @State private var sliderMinY: CGFloat = 0
    @State private var sliderMaxY: CGFloat = 0
    @State private var dragBaseline: CGFloat = 0
    @State private var didSetInitialOffset = false

    // Promo code
    @State private var showPromo = false
    @State private var promoCode = ""
    @State private var appliedRydrBankCode = UserDefaults.standard.string(forKey: "appliedRydrBankCode") ?? ""
    @State private var promoBookingId = UserDefaults.standard.string(forKey: "appliedRydrBankBookingId") ?? UUID().uuidString
    @State private var promoRequestID = UUID()
    @State private var requestValidationMessage: String?

    // Promo Application
    private enum PromoStatus: Equatable {
        case idle
        case applying
        case success(String)
        case failure(String)
    }
    @State private var promoStatus: PromoStatus = .idle
    private var isApplyingPromo: Bool { if case .applying = promoStatus { return true } else { return false } }
    private var isPromoApplied: Bool { !appliedRydrBankCode.isEmpty }
    private var currentEstimate: RideEstimate {
        if let routeEstimate { return routeEstimate }
        return fallbackEstimate
    }
    private var hasRequiredAddressText: Bool {
        !pickupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !dropoffText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var canRequestRide: Bool {
        hasRequiredAddressText && !isResolvingLocations
    }
    private var hasBookingDraft: Bool {
        pickupCoordinate != nil
        || dropoffCoordinate != nil
        || !pickupText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !dropoffText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var isCompactSheet: Bool {
        hasBookingDraft
        && focusedField == nil
        && editingShortcutID == nil
        && sliderOffset > sliderMaxY * 0.42
    }
    private var fallbackEstimate: RideEstimate {
        let base: Double = 5.0
        let pm = abs(pickupText.hashValue % 7)
        let dm = abs(dropoffText.hashValue % 9)
        let miles = base + Double(pm + dm) * 0.7
        let minutes = miles * 3.0
        return .init(distanceMiles: (miles * 10).rounded()/10, durationMinutes: round(minutes))
    }

    // Shortcuts (Work / Home / Add)
    struct Shortcut: Identifiable {
        let id = UUID()
        var kind: Kind
        var address: String
        enum Kind: String { case work = "Work", home = "Home", custom = "Add" }
        var label: String { kind.rawValue }
        var icon: String {
            switch kind { case .work: "briefcase.fill"; case .home: "house.fill"; case .custom: "plus" }
        }
        var tint: Color {
            switch kind { case .work: .blue; case .home: .teal; case .custom: .gray }
        }
    }
    @State private var shortcuts: [Shortcut] = [
        .init(kind: .work,  address: ""),
        .init(kind: .home,  address: ""),
        .init(kind: .custom,address: "")
    ]
    @State private var editingShortcutID: Shortcut.ID? = nil
    @State private var newShortcutAddress = ""
    @FocusState private var shortcutFocused: Bool

    // Recents (persisted list of drop-offs)
    @AppStorage("recentDropoffsData") private var recentDropoffsData: Data?
    @State private var recentDropoffs: [String] = []   // newest first

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Map as background
                RydrMapView(
                    position: $mapPosition,
                    pickupCoordinate: pickupCoordinate,
                    dropoffCoordinate: dropoffCoordinate,
                    routePolyline: routePolyline,
                    showsUserLocation: locationManager.authorization == .authorizedWhenInUse || locationManager.authorization == .authorizedAlways,
                    onRecenter: recenterMap
                )
                    .onAppear {
                        locationManager.requestIfNeeded()
                        updateSearchRegion(region)

                        // slider snap points & initial position
                        sliderMinY = 0
                        sliderMaxY = max(0, geo.size.height * 0.58)
                        if !didSetInitialOffset {
                            sliderOffset = (sliderMaxY * 0.5) // MIDWAY on open
                            didSetInitialOffset = true
                        }

                        // load recents
                        recentDropoffs = decodeRecents(from: recentDropoffsData)
                    }
                    .onReceive(locationManager.$lastLocation.compactMap { $0 }) { location in
                        guard pickupCoordinate == nil && dropoffCoordinate == nil else { return }
                        let start = MKCoordinateRegion(
                            center: location.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                        )
                        region = start
                        updateSearchRegion(start)
                        withAnimation(.easeInOut(duration: 0.35)) {
                            mapPosition = .region(start)
                        }
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            dismissBookingKeyboard()
                        }
                    )

                // Slider panel
                slider
                    .offset(y: sliderOffset)
                    .animation(.interactiveSpring(), value: sliderOffset)
                    .contentShape(Rectangle())            // make whole surface draggable
                    .highPriorityGesture(sheetDrag)       // <- key: sheet drag beats ScrollView
            }
        }
        // 🔹 Present driver selection (RideManager-powered)
        .sheet(isPresented: $showDriverSheet) {
            DriverSelectionView(
                rideManager: rideManager,
                rideType: rideType,
                pickup: pickupText,
                dropoff: dropoffText,
                region: region,
                estimate: currentEstimate,
                onAccepted: {
                    showDriverSheet = false
                    showInProgress = true
                },
                onClose: {
                    showDriverSheet = false
                    releaseAppliedRydrBankCodeIfNeeded()
                }
            )
        }
        // 🔹 Present in-progress view
        .fullScreenCover(isPresented: $showInProgress, onDismiss: {
            appliedRydrBankCode = UserDefaults.standard.string(forKey: "appliedRydrBankCode") ?? ""
            if appliedRydrBankCode.isEmpty {
                promoCode = ""
                promoStatus = .idle
                promoBookingId = UUID().uuidString
            }
            if rideManager.state == .selecting {
                DispatchQueue.main.async {
                    showDriverSheet = true
                }
            }
        }) {
            RideInProgressView(rideManager: rideManager)
        }
        .onChange(of: rideManager.state, initial: false) { _, newState in
            syncRidePresentation(with: newState)
        }
        .onChange(of: rideManager.currentRide?.id, initial: false) { _, rideId in
            if rideId == nil && rideManager.state != .completed {
                syncRidePresentation(with: rideManager.state)
            }
        }
        .sheet(isPresented: $showRoutePreview) {
            RoutePreviewSheet(
                rideType: rideType,
                pickup: pickupText,
                stop: stopText,
                dropoff: dropoffText,
                estimate: currentEstimate,
                routePolyline: routePolyline,
                riderName: userName,
                isVerifiedRider: session.verifiedBadge,
                pickupCoordinate: pickupCoordinate,
                dropoffCoordinate: dropoffCoordinate,
                showsUserLocation: locationManager.authorization == .authorizedWhenInUse || locationManager.authorization == .authorizedAlways,
                canRequestRide: canRequestRide,
                isResolving: isResolvingLocations,
                onAddStop: {
                    showRoutePreview = false
                    withAnimation(.spring()) {
                        showStopField = true
                        sliderOffset = sliderMinY
                    }
                    focusedField = .stop
                },
                onRequest: {
                    Task { await requestRide() }
                }
            )
            .presentationDetents([.large])
        }
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    dismissBookingKeyboard()
                }
            }
        }
    }

    private func syncRidePresentation(with state: RideManager.State) {
        switch state {
        case .inProgress:
            if rideManager.currentRide != nil {
                showDriverSheet = false
                showInProgress = true
            }
        case .selecting:
            showInProgress = false
            presentDriverSelectionAfterDismissal()
        case .cancelled, .idle:
            showInProgress = false
        case .awaitingDriver, .completed:
            break
        }
    }

    private func presentDriverSelectionAfterDismissal() {
        guard !showDriverSheet else { return }
        DispatchQueue.main.async {
            guard rideManager.state == .selecting else { return }
            showDriverSheet = true
        }
    }

    // MARK: - High priority drag for snapping panel
    private var sheetDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                if value.translation == .zero { dragBaseline = sliderOffset }
                let proposed = dragBaseline + value.translation.height
                sliderOffset = min(max(sliderMinY, proposed), sliderMaxY)
            }
            .onEnded { _ in
                // snap to top / middle / bottom
                let anchors: [CGFloat] = [sliderMinY, (sliderMaxY * 0.5), sliderMaxY]
                sliderOffset = anchors.min(by: { abs($0 - sliderOffset) < abs($1 - sliderOffset) }) ?? sliderOffset
            }
    }

    private func dismissBookingKeyboard() {
        focusedField = nil
        shortcutFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Slider content (structured like Apple Maps panel)
    private var slider: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                // Grabber
                Capsule().frame(width: 40, height: 5)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                if isCompactSheet {
                    compactBookingSummary
                        .onTapGesture {
                            withAnimation(.spring()) { sliderOffset = sliderMinY }
                        }
                    requestRideSection
                } else {
                    // Search card (extracted to keep type-checker happy)
                    searchCard
                    routeDetailsCard

                    // ── Library (Work / Home / Add) ────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Shortcuts")
                                .font(.headline.weight(.bold))
                            Spacer()
                            Button("Manage") {
                                if let custom = shortcuts.first(where: { $0.kind == .custom }) {
                                    editingShortcutID = custom.id
                                    newShortcutAddress = custom.address
                                    shortcutFocused = true
                                }
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Styles.rydrGradient)
                        }

                        HStack(spacing: 12) {
                            ForEach(shortcuts) { sc in
                                Button {
                                    if sc.address.isEmpty {
                                        editingShortcutID = sc.id
                                        newShortcutAddress = ""
                                        shortcutFocused = true
                                    } else {
                                        if pickupText.isEmpty { pickupText = sc.address } else { dropoffText = sc.address }
                                        clearRouteResolution()
                                        focusedField = nil
                                    }
                                } label: {
                                    ShortcutTile(shortcut: sc)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                                        editingShortcutID = sc.id
                                        newShortcutAddress = sc.address
                                        shortcutFocused = true
                                        shortcutCompleter.setQuery(newShortcutAddress)
                                    }
                                )
                            }
                        }

                        if let editingID = editingShortcutID {
                            if let editingShortcut = shortcuts.first(where: { $0.id == editingID }) {
                                shortcutEditor(for: editingShortcut)
                            }
                        }
                    }
                    .bookingPanelCard()

                    // ── Recents ────────────────────────────────────────────────────
                    if !recentDropoffs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Recents")
                                    .font(.headline.weight(.bold))
                                Spacer()
                                Text("See all")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Styles.rydrGradient)
                            }
                            VStack(spacing: 8) {
                                ForEach(recentDropoffs.prefix(2), id: \.self) { addr in
                                    Button {
                                        handleRecentSelection(addr)
                                    } label: {
                                        recentsRow(addr: addr, city: cityText(for: addr))
                                    }
                                }
                            }
                        }
                        .bookingPanelCard()
                    }

                    // ── Promo + Request button ─────────────────────────────────────
                    promoView
                    requestRideSection
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Color(.systemBackground).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.72), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 24, y: 10)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: focusedField) { _, newValue in
            if newValue == .pickup || newValue == .stop || newValue == .dropoff {
                withAnimation(.spring()) { sliderOffset = sliderMinY }
            }
        }
    }

    private var compactBookingSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ride Preview")
                        .font(.headline)
                    Text(compactSummaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            if let routeEstimate {
                HStack(spacing: 12) {
                    Label("\(routeEstimate.distanceMiles, specifier: "%.1f") mi", systemImage: "road.lanes")
                    Label("\(Int(routeEstimate.durationMinutes)) min", systemImage: "clock.fill")
                    Spacer()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 1))
    }

    private var compactSummaryText: String {
        let pickup = pickupText.trimmingCharacters(in: .whitespacesAndNewlines)
        let stop = stopText.trimmingCharacters(in: .whitespacesAndNewlines)
        let dropoff = dropoffText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (pickup.isEmpty, dropoff.isEmpty) {
        case (false, false):
            if stop.isEmpty {
                return "\(pickup) to \(dropoff)"
            }
            return "\(pickup) to \(stop) to \(dropoff)"
        case (false, true): return "Pickup set. Add a drop-off."
        case (true, false): return "Drop-off set. Add a pickup."
        case (true, true): return "Choose pickup and drop-off."
        }
    }

    @ViewBuilder
    private var routeDetailsCard: some View {
        if let routeEstimate {
            Button {
                showRoutePreview = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Styles.rydrGradient)
                        .frame(width: 54, height: 54)
                        .background(Styles.rydrGradient.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Route Preview")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.primary)
                        HStack(spacing: 7) {
                            Text("\(routeEstimate.distanceMiles, specifier: "%.1f") miles")
                            Text("•")
                            Text("\(Int(routeEstimate.durationMinutes)) min")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        Text(routeViaText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Styles.rydrGradient)
                }
            }
            .buttonStyle(.plain)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 1))
        } else if hasRequiredAddressText {
            Button {
                Task { await openRoutePreview() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isResolvingLocations ? "hourglass" : "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Styles.rydrGradient)
                        .frame(width: 54, height: 54)
                        .background(Styles.rydrGradient.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Route Preview")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.primary)
                        Text(isResolvingLocations ? "Calculating route..." : "Tap to calculate route")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(routeViaText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if isResolvingLocations {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Styles.rydrGradient)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 1))
            .disabled(isResolvingLocations)
        } else if let routeErrorMessage {
            validationBanner(text: routeErrorMessage)
        }
    }

    private var routeViaText: String {
        if !stopText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Includes 1 stop"
        }
        return "Tap to preview route"
    }

    private var bookingRideIcon: String {
        switch rideType.lowercased() {
        case let value where value.contains("eco"):
            return "leaf.fill"
        case let value where value.contains("xl"):
            return "car.2.fill"
        case let value where value.contains("executive"):
            return "briefcase.fill"
        case let value where value.contains("prestine"):
            return "sparkles"
        default:
            return "car.fill"
        }
    }

    @ViewBuilder
    private func recentsRow(addr: String, city: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(addr)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                if let city = city {
                    Text(city)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func handleRecentSelection(_ addr: String) {
        if focusedField == .pickup {
            pickupText = addr
        } else if focusedField == .dropoff {
            dropoffText = addr
        } else {
            if pickupText.trimmingCharacters(in: .whitespaces).isEmpty {
                pickupText = addr
            } else {
                dropoffText = addr
            }
        }
        clearRouteResolution()
        focusedField = nil
    }

    private func cityText(for address: String) -> String? {
        let parts = address.split(separator: ",")
        guard let city = parts.dropFirst().first else { return nil }
        return String(city).trimmingCharacters(in: .whitespaces)
    }

    private func shortcutEditor(for shortcut: Shortcut) -> some View {
        let shortcutNoun = shortcut.kind == .custom ? "custom" : shortcut.label
        let titleText = shortcut.address.isEmpty ? "Add \(shortcutNoun) address" : "Edit \(shortcutNoun) address"
        let addressBinding = Binding<String>(
            get: { newShortcutAddress },
            set: { newValue in
                newShortcutAddress = newValue
                shortcutCompleter.setRegion(region)
                shortcutCompleter.setQuery(newValue)
            }
        )

        return HStack(spacing: 8) {
            bookingField(
                title: titleText,
                text: addressBinding,
                icon: "location.magnifyingglass",
                onIconTap: {
                    shortcutFocused = true
                    shortcutCompleter.setRegion(region)
                    shortcutCompleter.setQuery(newShortcutAddress)
                }
            )
            .focused($shortcutFocused)

            Button {
                saveShortcut(shortcut)
            } label: {
                Image(systemName: "checkmark.circle.fill").font(.title3)
            }

            Button {
                clearShortcutEditor()
            } label: {
                Image(systemName: "xmark.circle.fill").font(.title3)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if shortcutFocused && !newShortcutAddress.isEmpty {
                compactSuggestions(for: shortcutCompleter) { suggestion in
                    newShortcutAddress = suggestion
                    shortcutFocused = false
                }
            }
        }
    }

    private func saveShortcut(_ shortcut: Shortcut) {
        if let idx = shortcuts.firstIndex(where: { $0.id == shortcut.id }),
           !newShortcutAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            shortcuts[idx].address = newShortcutAddress
        }
        clearShortcutEditor()
    }

    private func clearShortcutEditor() {
        newShortcutAddress = ""
        editingShortcutID = nil
        shortcutFocused = false
    }

    // MARK: - Small, self-contained search card
    @ViewBuilder
    private var searchCard: some View {
        let showPickupSuggestions = (focusedField == .pickup && !pickupText.isEmpty)
        let showStopSuggestions = (focusedField == .stop && !stopText.isEmpty)
        let showDropoffSuggestions = (focusedField == .dropoff && !dropoffText.isEmpty)

        VStack(spacing: 8) {
            // Pickup
            bookingField(title: "Pickup", text: $pickupText, icon: "mappin.and.ellipse")
                .focused($focusedField, equals: .pickup)
                .onChange(of: pickupText) { _, new in
                    if new != pickupResolvedAddress {
                        pickupCoordinate = nil
                        pickupResolvedAddress = ""
                        clearRoutePreview()
                    }
                    pickupCompleter.setRegion(region); pickupCompleter.setQuery(new)
                }
            Button {
                useCurrentLocationForPickup()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                    Text("Use Current Location")
                    Spacer()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            if showPickupSuggestions {
                suggestionsList(for: pickupCompleter) { completion in
                    Task { await selectPickup(completion) }
                }
            }

            if showStopField {
                bookingField(
                    title: "Add stop",
                    text: $stopText,
                    icon: "plus.circle",
                    onClear: {
                        stopText = ""
                        stopCompleter.setQuery("")
                        showStopField = false
                        focusedField = nil
                    }
                )
                    .focused($focusedField, equals: .stop)
                    .onChange(of: stopText) { _, new in
                        stopCompleter.setRegion(region)
                        stopCompleter.setQuery(new)
                    }
                if showStopSuggestions {
                    suggestionsList(for: stopCompleter) { completion in
                        stopText = completion.title + (completion.subtitle.isEmpty ? "" : ", " + completion.subtitle)
                        focusedField = nil
                    }
                }
            }

            // Dropoff
            bookingField(
                title: "Dropoff",
                text: $dropoffText,
                icon: "flag.checkered",
                onClear: clearDropoffSelection
            )
                .focused($focusedField, equals: .dropoff)
                .onChange(of: dropoffText) { _, new in
                    if new != dropoffResolvedAddress {
                        dropoffCoordinate = nil
                        dropoffResolvedAddress = ""
                        clearRoutePreview()
                    }
                    dropoffCompleter.setRegion(region); dropoffCompleter.setQuery(new)
                }
            if showDropoffSuggestions {
                suggestionsList(for: dropoffCompleter) { completion in
                    Task { await selectDropoff(completion) }
                }
            }

            if !showStopField {
                Button {
                    withAnimation(.spring()) {
                        showStopField = true
                    }
                    focusedField = .stop
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                        Text("Add stop")
                        Spacer()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Styles.rydrGradient)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .bookingPanelCard()
    }

    // MARK: - Reusable field (icon optionally tappable)
    @ViewBuilder
    private func bookingField(
        title: String,
        text: Binding<String>,
        icon: String,
        onIconTap: (() -> Void)? = nil,
        onClear: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .onTapGesture { onIconTap?() }

            TextField(title, text: text)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .textContentType(.fullStreetAddress)
                .onSubmit {
                    dismissBookingKeyboard()
                }

            if let onClear, !text.wrappedValue.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(title)")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground).opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Suggestions (inline, full-width)
    @ViewBuilder
    private func suggestionsList(
        for completer: SearchCompleter,
        onPick: @escaping (MKLocalSearchCompletion) -> Void
    ) -> some View {
        let items = Array(completer.results.prefix(10))
        if !items.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items.indices, id: \.self) { i in
                        let item = items[i]
                        Button {
                            onPick(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.subheadline).foregroundColor(.primary)
                                if !item.subtitle.isEmpty {
                                    Text(item.subtitle).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        if i < items.count - 1 { Divider() }
                    }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 240)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06), lineWidth: 1))
        } else {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("No suggestions yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06), lineWidth: 1))
        }
    }

    // Compact suggestions used under the inline Library editor
    private func compactSuggestions(
        for completer: SearchCompleter,
        onPick: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(completer.results.prefix(5)).indices, id: \.self) { i in
                let item = completer.results[i]
                Button {
                    onPick(item.title + (item.subtitle.isEmpty ? "" : ", " + item.subtitle))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline).foregroundColor(.primary)
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                if i < 4 { Divider() }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06), lineWidth: 1))
        .padding(.top, 6)
    }

    // MARK: - Promo
    private var promoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring()) { showPromo.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ticket")
                        .font(.subheadline.weight(.bold))
                    Text("Add promo code")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.black))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Styles.rydrGradient)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if showPromo {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Enter promo code", text: $promoCode)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .onSubmit {
                                dismissBookingKeyboard()
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06), lineWidth: 1))
                            .disabled(isApplyingPromo || isPromoApplied)

                        Button {
                            Task { await applyPromo() }
                        } label: {
                            if isApplyingPromo {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(isPromoApplied ? "Applied" : "Apply").bold()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            promoCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isApplyingPromo
                            || isPromoApplied
                        )
                    }

                    // Notice banner
                    Group {
                        switch promoStatus {
                        case .success(let msg):
                            promoBanner(text: msg, isSuccess: true)
                        case .failure(let msg):
                            promoBanner(text: msg, isSuccess: false)
                        default:
                            EmptyView()
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    @ViewBuilder
    private func promoBanner(text: String, isSuccess: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isSuccess ? Color.green : Color.orange)
            Text(text).font(.footnote)
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.06), lineWidth: 1))
    }

    private func validationBanner(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            Text(text)
                .font(.footnote)
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.06), lineWidth: 1))
    }

    private var requestRideSection: some View {
        VStack(spacing: 8) {
            Button {
                Task { await requestRide() }
            } label: {
                HStack {
                    Image(systemName: bookingRideIcon)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if isResolvingLocations {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Request \(rideType)")
                            .font(.headline.weight(.bold))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BookingGradientButtonStyle())
            .disabled(!canRequestRide)
            .opacity(canRequestRide ? 1 : 0.45)

            if let message = requestValidationMessage {
                validationBanner(text: message)
            }
        }
        .padding(.bottom, 8)
    }

    @MainActor
    private func applyPromo() async {
        let code = promoCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else {
            showStatus(.failure("Enter a promo code."))
            return
        }

        let pickup = pickupText.trimmingCharacters(in: .whitespacesAndNewlines)
        let dropoff = dropoffText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pickup.isEmpty, !dropoff.isEmpty else {
            showStatus(.failure("Add a pickup and drop-off before applying a RydrBank code."))
            return
        }
        guard await resolveBookingLocationsIfNeeded(pickup: pickup, dropoff: dropoff) else {
            showStatus(.failure("We could not find that pickup or drop-off on the map."))
            return
        }

        let estimate = currentEstimate
        guard estimate.distanceMiles <= 15 else {
            showStatus(.failure("RydrBank codes can only be applied to rides up to 15 miles."))
            return
        }

        promoStatus = .applying
        let requestID = UUID()
        promoRequestID = requestID

        Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            await MainActor.run {
                guard promoRequestID == requestID, isApplyingPromo else { return }
                promoRequestID = UUID()
                showStatus(.failure("RydrBank is taking too long to respond. Please try again."))
            }
        }

        Task {
            do {
                let response = try await RydrBankAPI.preview(
                    code: code,
                    bookingId: promoBookingId,
                    rideType: rideType,
                    distanceMi: estimate.distanceMiles
                )
                let message = response["message"] as? String ?? "RydrBank applied. This ride is covered."
                await MainActor.run {
                    guard promoRequestID == requestID else { return }
                    appliedRydrBankCode = code
                    UserDefaults.standard.set(code, forKey: "appliedRydrBankCode")
                    UserDefaults.standard.set(promoBookingId, forKey: "appliedRydrBankBookingId")
                    showStatus(.success(message))
                }
            } catch {
                await MainActor.run {
                    guard promoRequestID == requestID else { return }
                    showStatus(.failure(promoErrorMessage(for: error)))
                }
            }
        }
    }

    private func promoErrorMessage(for error: Error) -> String {
        if (error as? URLError)?.code == .timedOut {
            return "RydrBank is taking too long to respond. Please try again."
        }

        guard let bankError = error as? RydrBankAPIError else {
            return "That code could not be applied."
        }

        switch bankError {
        case .server(let message):
            switch message {
            case "ride_too_long":
                return "RydrBank codes can only be applied to rides up to 15 miles."
            case "wrong_ride_type":
                return "That code is for a different Rydr ride type."
            case "not_active", "bad_status":
                return "That code is no longer ready to use."
            case "not_found":
                return "That code was not found."
            default:
                return message.replacingOccurrences(of: "_", with: " ").capitalized
            }
        default:
            return bankError.localizedDescription
        }
    }

    private func showStatus(_ status: PromoStatus) {
        withAnimation(.spring()) { promoStatus = status }
        if case .success = status { return }
        // Auto-dismiss the banner after a short moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut) { promoStatus = .idle }
        }
    }

    // MARK: - Recents persistence
    private func decodeRecents(from data: Data?) -> [String] {
        guard let data = data else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
    private func saveRecents(_ list: [String]) {
        recentDropoffsData = try? JSONEncoder().encode(list)
    }
    private func pushRecent(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = recentDropoffs.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        if list.count > 10 { list = Array(list.prefix(10)) }
        recentDropoffs = list
        saveRecents(list)
    }

    // MARK: - Actions
    @MainActor
    private func openRoutePreview() async {
        let pickup = pickupText.trimmingCharacters(in: .whitespacesAndNewlines)
        let dropoff = dropoffText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !pickup.isEmpty, !dropoff.isEmpty else {
            requestValidationMessage = "Add a pickup and drop-off to preview the route."
            return
        }

        requestValidationMessage = nil
        guard await resolveBookingLocationsIfNeeded(pickup: pickup, dropoff: dropoff) else {
            requestValidationMessage = "Choose a valid pickup and drop-off from the map results."
            return
        }

        showRoutePreview = true
    }

    @MainActor
    private func requestRide() async {
        let pickup = pickupText.trimmingCharacters(in: .whitespacesAndNewlines)
        let dropoff = dropoffText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !pickup.isEmpty, !dropoff.isEmpty else {
            if pickup.isEmpty && dropoff.isEmpty {
                requestValidationMessage = "Add a pickup and drop-off before requesting a ride."
            } else if pickup.isEmpty {
                requestValidationMessage = "Add a pickup before requesting a ride."
            } else {
                requestValidationMessage = "Add a drop-off before requesting a ride."
            }
            return
        }

        requestValidationMessage = nil

        guard await resolveBookingLocationsIfNeeded(pickup: pickup, dropoff: dropoff) else {
            requestValidationMessage = "Choose a valid pickup and drop-off from the map results."
            return
        }

        if isPromoApplied && currentEstimate.distanceMiles > 15 {
            showStatus(.failure("RydrBank codes can only be applied to rides up to 15 miles."))
            return
        }
        let resolvedPickup = pickupText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDropoff = dropoffText.trimmingCharacters(in: .whitespacesAndNewlines)
        pushRecent(resolvedDropoff)
        rideManager.requestDrivers(
            pickup: resolvedPickup,
            dropoff: resolvedDropoff,
            rideType: rideType,
            near: pickupCoordinate ?? region.center,
            pickupCoordinate: pickupCoordinate,
            dropoffCoordinate: dropoffCoordinate,
            estimate: currentEstimate,
            riderVerified: session.verifiedBadge
        )
        showDriverSheet = true
    }

    private func clearRouteResolution() {
        pickupCoordinate = nil
        dropoffCoordinate = nil
        pickupResolvedAddress = ""
        dropoffResolvedAddress = ""
        clearRoutePreview()
        routeRequestID = UUID()
    }

    private func clearRoutePreview() {
        routeEstimate = nil
        routePolyline = nil
        routeErrorMessage = nil
        routeRequestID = UUID()
    }

    private func clearDropoffSelection() {
        dropoffText = ""
        dropoffCoordinate = nil
        dropoffResolvedAddress = ""
        dropoffCompleter.setQuery("")
        requestValidationMessage = nil
        focusedField = nil
        clearRoutePreview()
    }

    private func updateSearchRegion(_ newRegion: MKCoordinateRegion) {
        pickupCompleter.setRegion(newRegion)
        stopCompleter.setRegion(newRegion)
        dropoffCompleter.setRegion(newRegion)
        shortcutCompleter.setRegion(newRegion)
    }

    private func useCurrentLocationForPickup() {
        let coordinate = locationManager.lastLocation?.coordinate ?? region.center
        pickupCoordinate = coordinate
        pickupResolvedAddress = locationManager.lastLocation == nil ? "Atlanta, GA" : "Current Location"
        pickupText = pickupResolvedAddress
        focusedField = nil
        clearRoutePreview()
        updateRouteEstimateIfPossible()
        recenterOnResolvedLocations()
    }

    @MainActor
    private func selectPickup(_ completion: MKLocalSearchCompletion) async {
        do {
            let item = try await searchMapItem(for: completion)
            let address = formattedAddress(for: item, fallback: completion.title + (completion.subtitle.isEmpty ? "" : ", " + completion.subtitle))
            pickupResolvedAddress = address
            pickupCoordinate = item.placemark.coordinate
            pickupText = address
            focusedField = nil
            clearRoutePreview()
            recenterOnResolvedLocations()
            updateRouteEstimateIfPossible()
        } catch {
            showStatus(.failure("That location could not be resolved. Please try another result."))
        }
    }

    @MainActor
    private func selectDropoff(_ completion: MKLocalSearchCompletion) async {
        do {
            let item = try await searchMapItem(for: completion)
            let address = formattedAddress(for: item, fallback: completion.title + (completion.subtitle.isEmpty ? "" : ", " + completion.subtitle))
            dropoffResolvedAddress = address
            dropoffCoordinate = item.placemark.coordinate
            dropoffText = address
            focusedField = nil
            clearRoutePreview()
            recenterOnResolvedLocations()
            updateRouteEstimateIfPossible()
        } catch {
            showStatus(.failure("That location could not be resolved. Please try another result."))
        }
    }

    @MainActor
    private func resolveBookingLocationsIfNeeded(pickup: String, dropoff: String) async -> Bool {
        isResolvingLocations = true
        defer { isResolvingLocations = false }

        do {
            if pickupCoordinate == nil || pickup != pickupResolvedAddress {
                let item = try await searchMapItem(for: pickup)
                pickupResolvedAddress = formattedAddress(for: item, fallback: pickup)
                pickupCoordinate = item.placemark.coordinate
                pickupText = pickupResolvedAddress
            }

            if dropoffCoordinate == nil || dropoff != dropoffResolvedAddress {
                let item = try await searchMapItem(for: dropoff)
                dropoffResolvedAddress = formattedAddress(for: item, fallback: dropoff)
                dropoffCoordinate = item.placemark.coordinate
                dropoffText = dropoffResolvedAddress
            }

            guard let pickupCoordinate, let dropoffCoordinate else { return false }
            let preview = try await calculateRoutePreview(from: pickupCoordinate, to: dropoffCoordinate)
            routeEstimate = preview.estimate
            routePolyline = preview.polyline
            routeErrorMessage = nil
            recenterOnResolvedLocations()
            return true
        } catch {
            routeEstimate = nil
            routePolyline = nil
            routeErrorMessage = "We could not calculate a route for those locations."
            return false
        }
    }

    private func updateRouteEstimateIfPossible() {
        guard let pickupCoordinate, let dropoffCoordinate else { return }
        let requestID = UUID()
        routeRequestID = requestID
        Task {
            do {
                let preview = try await calculateRoutePreview(from: pickupCoordinate, to: dropoffCoordinate)
                await MainActor.run {
                    guard routeRequestID == requestID else { return }
                    routeEstimate = preview.estimate
                    routePolyline = preview.polyline
                    routeErrorMessage = nil
                    recenterOnResolvedLocations()
                }
            } catch {
                await MainActor.run {
                    guard routeRequestID == requestID else { return }
                    routeEstimate = nil
                    routePolyline = nil
                    routeErrorMessage = "We could not calculate a route for those locations."
                }
            }
        }
    }

    private func recenterOnResolvedLocations() {
        let coords = [pickupCoordinate, dropoffCoordinate].compactMap { $0 }
        guard !coords.isEmpty else { return }
        let minLat = coords.map(\.latitude).min() ?? region.center.latitude
        let maxLat = coords.map(\.latitude).max() ?? region.center.latitude
        let minLon = coords.map(\.longitude).min() ?? region.center.longitude
        let maxLon = coords.map(\.longitude).max() ?? region.center.longitude
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.03, (maxLat - minLat) * 1.8),
            longitudeDelta: max(0.03, (maxLon - minLon) * 1.8)
        )
        region = MKCoordinateRegion(center: center, span: span)
        updateSearchRegion(region)
        withAnimation(.easeInOut(duration: 0.35)) {
            mapPosition = .region(region)
        }
    }

    private func recenterMap() {
        if ![pickupCoordinate, dropoffCoordinate].compactMap({ $0 }).isEmpty {
            recenterOnResolvedLocations()
            return
        }

        let center = locationManager.lastLocation?.coordinate ?? RydrMapDefaults.atlantaCoordinate
        let nextRegion = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        )
        region = nextRegion
        updateSearchRegion(nextRegion)
        withAnimation(.easeInOut(duration: 0.35)) {
            mapPosition = .region(nextRegion)
        }
    }

    private func searchMapItem(for completion: MKLocalSearchCompletion) async throws -> MKMapItem {
        let request = MKLocalSearch.Request(completion: completion)
        request.region = region
        return try await firstMapItem(for: request)
    }

    private func searchMapItem(for query: String) async throws -> MKMapItem {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        return try await firstMapItem(for: request)
    }

    private func firstMapItem(for request: MKLocalSearch.Request) async throws -> MKMapItem {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MKMapItem, Error>) in
            MKLocalSearch(request: request).start { response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let item = response?.mapItems.first {
                    continuation.resume(returning: item)
                } else {
                    continuation.resume(throwing: NSError(domain: "RydrLocationSearch", code: 1, userInfo: nil))
                }
            }
        }
    }

    private func calculateRoutePreview(from pickup: CLLocationCoordinate2D, to dropoff: CLLocationCoordinate2D) async throws -> RoutePreview {
        let request = MKDirections.Request()
        request.source = routeMapItem(for: pickup)
        request.destination = routeMapItem(for: dropoff)
        request.transportType = .automobile

        let route: MKRoute = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MKRoute, Error>) in
            MKDirections(request: request).calculate { response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let route = response?.routes.first {
                    continuation.resume(returning: route)
                } else {
                    continuation.resume(throwing: NSError(domain: "RydrRouteEstimate", code: 1, userInfo: nil))
                }
            }
        }

        return RoutePreview(
            estimate: RideEstimate(
                distanceMiles: ((route.distance / 1609.344) * 10).rounded() / 10,
                durationMinutes: max(1, (route.expectedTravelTime / 60).rounded())
            ),
            polyline: route.polyline
        )
    }

    private func routeMapItem(for coordinate: CLLocationCoordinate2D) -> MKMapItem {
        if #available(iOS 26.0, *) {
            return MKMapItem(
                location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                address: nil
            )
        } else {
            return MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }
    }

    private func formattedAddress(for item: MKMapItem, fallback: String) -> String {
        let placemark = item.placemark
        let parts = [
            placemark.name,
            placemark.locality,
            placemark.administrativeArea
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        let formatted = parts.joined(separator: ", ")
        return formatted.isEmpty ? fallback : formatted
    }

    private func releaseAppliedRydrBankCodeIfNeeded() {
        let code = appliedRydrBankCode
        guard !code.isEmpty else { return }
        appliedRydrBankCode = ""
        promoCode = ""
        promoStatus = .idle
        promoRequestID = UUID()
        UserDefaults.standard.removeObject(forKey: "appliedRydrBankCode")
        UserDefaults.standard.removeObject(forKey: "appliedRydrBankBookingId")
        promoBookingId = UUID().uuidString

        Task {
            try? await RydrBankAPI.release(code: code)
        }
    }
}

private struct ShortcutTile: View {
    let shortcut: BookingView.Shortcut

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tileBackground)
                    .frame(height: 84)

                VStack(spacing: 7) {
                    shortcutIcon
                    Text(shortcut.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var shortcutIcon: some View {
        if shortcut.kind == .custom {
            Image(systemName: shortcut.icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(shortcut.tint)
                .frame(width: 46, height: 46)
                .overlay(
                    Circle()
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(Color.purple.opacity(0.35))
                )
        } else {
            Image(systemName: shortcut.icon)
                .font(.title2.weight(.bold))
                .foregroundStyle(shortcut.tint)
                .frame(width: 46, height: 46)
        }
    }

    private var tileBackground: LinearGradient {
        switch shortcut.kind {
        case .work:
            return LinearGradient(colors: [Color.blue.opacity(0.18), Color.blue.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .home:
            return LinearGradient(colors: [Color.teal.opacity(0.18), Color.green.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .custom:
            return LinearGradient(colors: [Color.purple.opacity(0.16), Color.purple.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct BookingGradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 60)
            .background(Styles.rydrGradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: Color.red.opacity(configuration.isPressed ? 0.12 : 0.24), radius: 16, x: 0, y: 9)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private extension View {
    func bookingPanelCard() -> some View {
        self
            .padding(12)
            .background(Color(.systemBackground).opacity(0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
    }
}

private extension MKPolyline {
    var rydrCoordinates: [CLLocationCoordinate2D] {
        var coordinates = Array(repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}

private struct RoutePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let rideType: String
    let pickup: String
    let stop: String
    let dropoff: String
    let estimate: RideEstimate
    let routePolyline: MKPolyline?
    let riderName: String
    let isVerifiedRider: Bool
    let pickupCoordinate: CLLocationCoordinate2D?
    let dropoffCoordinate: CLLocationCoordinate2D?
    let showsUserLocation: Bool
    let canRequestRide: Bool
    let isResolving: Bool
    let onAddStop: () -> Void
    let onRequest: () -> Void

    @State private var position: MapCameraPosition = .region(RydrMapDefaults.atlantaRegion)

    var body: some View {
        ZStack(alignment: .bottom) {
            RydrMapView(
                position: $position,
                pickupCoordinate: pickupCoordinate,
                dropoffCoordinate: dropoffCoordinate,
                routePolyline: routePolyline,
                showsUserLocation: showsUserLocation,
                onRecenter: fitRoute
            )

            VStack(spacing: 0) {
                topControls
                    .padding(.horizontal, 18)
                    .padding(.top, 58)
                Spacer()
                previewPanel
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: fitRoute)
    }

    private var topControls: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 50, height: 50)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to booking")

            Spacer()

            Button(action: fitRoute) {
                Image(systemName: "scope")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 50, height: 50)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Center route")
        }
    }

    private var previewPanel: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Color.black.opacity(0.22))
                .frame(width: 42, height: 5)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Route Preview")
                        .font(.headline.weight(.bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                Text(routeSummaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    metricPill(icon: "road.lanes", value: String(format: "%.1f mi", estimate.distanceMiles))
                    metricPill(icon: "clock.fill", value: "\(Int(estimate.durationMinutes)) min")
                    Spacer()
                }
            }

            bestRouteCard

            riderProfileRow

            Button {
                dismiss()
                onRequest()
            } label: {
                HStack {
                    Image(systemName: rideIcon)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if isResolving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Request \(rideType)")
                            .font(.headline.weight(.bold))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 58)
                .background(Styles.rydrGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.red.opacity(0.25), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(!canRequestRide || isResolving)
            .opacity(canRequestRide ? 1 : 0.45)
            .accessibilityLabel("Request \(rideType)")

            Button {
                dismiss()
                onAddStop()
            } label: {
                HStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "plus.circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Styles.rydrGradient)
                    Text(stop.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add stop" : "Edit stop")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(.primary)
                .frame(height: 50)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(stop.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add stop" : "Edit stop")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 22, x: 0, y: 10)
    }

    private var bestRouteCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.16))
                    .frame(width: 42, height: 42)
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(Color.green)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Best route")
                    .font(.subheadline.weight(.bold))
                Text(routeDescriptor)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(routeVehicleAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 116, height: 58)
                .padding(.trailing, -8)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color.white, Color.red.opacity(0.08)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var riderProfileRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Styles.rydrGradient.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Styles.rydrGradient)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(riderName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text("Rider profile")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isVerifiedRider {
                Label("Verified Rider", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.11), in: Capsule())
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func metricPill(icon: String, value: String) -> some View {
        Label(value, systemImage: icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.black.opacity(0.78))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.08), in: Capsule())
            .accessibilityLabel(value)
    }

    private var routeSummaryText: String {
        let pickup = clean(pickup, fallback: "Pickup")
        let stop = clean(stop, fallback: "")
        let dropoff = clean(dropoff, fallback: "Drop-off")
        if stop.isEmpty {
            return "\(pickup) -> \(dropoff)"
        }
        return "\(pickup) -> \(stop) -> \(dropoff)"
    }

    private var routeDescriptor: String {
        if clean(stop, fallback: "").isEmpty {
            return "Fastest available route"
        }
        return "Includes 1 stop • Fastest available"
    }

    private var rideIcon: String {
        switch rideType.lowercased() {
        case let value where value.contains("eco"):
            return "leaf.fill"
        case let value where value.contains("xl"):
            return "car.2.fill"
        case let value where value.contains("executive"):
            return "briefcase.fill"
        case let value where value.contains("prestine"):
            return "sparkles"
        default:
            return "car.fill"
        }
    }

    private var routeVehicleAssetName: String {
        switch rideType.lowercased() {
        case let value where value.contains("eco"):
            return "RydrEcoVehicle"
        case let value where value.contains("xl"):
            return "RydrXLVehicle"
        case let value where value.contains("executive"):
            return "RydrExecutiveVehicle"
        case let value where value.contains("prestine"):
            return "RydrPrestineVehicle"
        case let value where value.contains("cash"):
            return "CashRydrFleet"
        default:
            return "RydrGoVehicle"
        }
    }

    private func clean(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func fitRoute() {
        let routeCoords = routePolyline?.rydrCoordinates ?? []
        let endpointCoords = [pickupCoordinate, dropoffCoordinate].compactMap { $0 }
        let coords = routeCoords.isEmpty ? endpointCoords : routeCoords + endpointCoords
        guard !coords.isEmpty else {
            position = .region(RydrMapDefaults.atlantaRegion)
            return
        }

        let minLat = coords.map(\.latitude).min() ?? RydrMapDefaults.atlantaCoordinate.latitude
        let maxLat = coords.map(\.latitude).max() ?? RydrMapDefaults.atlantaCoordinate.latitude
        let minLon = coords.map(\.longitude).min() ?? RydrMapDefaults.atlantaCoordinate.longitude
        let maxLon = coords.map(\.longitude).max() ?? RydrMapDefaults.atlantaCoordinate.longitude
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(0.045, (maxLat - minLat) * 2.35),
                longitudeDelta: max(0.045, (maxLon - minLon) * 2.35)
            )
        )

        withAnimation(.easeInOut(duration: 0.3)) {
            position = .region(region)
        }
    }
}
