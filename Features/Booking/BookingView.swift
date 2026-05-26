import SwiftUI
import MapKit
import _MapKit_SwiftUI
import CoreLocation

// MARK: - Async location fetcher (non-blocking; avoids analyzer warning)
final class LocationFetcher: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onUpdate: ((CLLocationCoordinate2D) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        Task.detached {
            let enabled = CLLocationManager.locationServicesEnabled()
            await MainActor.run {
                guard enabled else { return }
                switch self.manager.authorizationStatus {
                case .notDetermined: self.manager.requestWhenInUseAuthorization()
                case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
                default: break
                }
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let coord = locations.first?.coordinate { onUpdate?(coord) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

struct BookingView: View {
    // Inputs
    let rideType: String
    let userName: String

    // 🔹 Ride flow
    @EnvironmentObject var rideManager: RideManager
    @State private var showDriverSheet = false
    @State private var showInProgress = false

    // Map / region
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
    )
    @StateObject private var locationFetcher = LocationFetcher()
    @State private var pickupCoordinate: CLLocationCoordinate2D?
    @State private var dropoffCoordinate: CLLocationCoordinate2D?
    @State private var pickupResolvedAddress = ""
    @State private var dropoffResolvedAddress = ""
    @State private var routeEstimate: RideEstimate?
    @State private var routeRequestID = UUID()
    @State private var isResolvingLocations = false

    // Fields
    @State private var pickupText = ""
    @State private var dropoffText = ""
    @FocusState private var focusedField: Field?
    private enum Field { case pickup, dropoff, shortcut }

    // Search completers
    @StateObject private var pickupCompleter  = SearchCompleter()
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
                Map(initialPosition: .region(region)) {
                    UserAnnotation()
                    if let pickupCoordinate {
                        Marker("Pickup", coordinate: pickupCoordinate).tint(.red)
                    }
                    if let dropoffCoordinate {
                        Marker("Drop-off", coordinate: dropoffCoordinate).tint(.blue)
                    }
                }
                    .ignoresSafeArea()
                    .onAppear {
                        // async location update
                        locationFetcher.onUpdate = { coord in
                            let start = MKCoordinateRegion(
                                center: coord,
                                span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                            )
                            region = start
                            pickupCompleter.setRegion(start)
                            dropoffCompleter.setRegion(start)
                            shortcutCompleter.setRegion(start)
                        }
                        locationFetcher.start()

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
        .navigationBarBackButtonHidden(false)
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

    // MARK: - Slider content (structured like Apple Maps panel)
    private var slider: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                // Grabber
                Capsule().frame(width: 40, height: 5)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                // Search card (extracted to keep type-checker happy)
                searchCard

                // ── Library (Work / Home / Add) ────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shortcuts").font(.headline)
                    HStack(spacing: 14) {
                        ForEach(shortcuts) { sc in
                            VStack(spacing: 6) {
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
                                    ZStack {
                                        Circle().fill(sc.tint.opacity(0.18)).frame(width: 58, height: 58)
                                        Image(systemName: sc.icon)
                                            .font(.title2.weight(.semibold))
                                            .foregroundStyle(sc.tint)
                                    }
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

                                Text(sc.label).font(.subheadline).foregroundColor(.primary.opacity(0.95))
                            }
                        }
                    }

                    if let editingID = editingShortcutID {
                        if let editingShortcut = shortcuts.first(where: { $0.id == editingID }) {
                            shortcutEditor(for: editingShortcut)
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 1))

                // ── Recents ────────────────────────────────────────────────────
                if !recentDropoffs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Recents").font(.headline); Spacer() }
                        VStack(spacing: 8) {
                            ForEach(recentDropoffs.prefix(5), id: \.self) { addr in
                                Button {
                                    handleRecentSelection(addr)
                                } label: {
                                    recentsRow(addr: addr, city: cityText(for: addr))
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 1))
                }

                // ── Promo + Request button ─────────────────────────────────────
                promoView
                requestRideSection
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.black.opacity(0.06), lineWidth: 1))
        .frame(maxHeight: .infinity, alignment: .bottom)
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: focusedField) { _, newValue in
            if newValue == .pickup || newValue == .dropoff {
                withAnimation(.spring()) { sliderOffset = sliderMinY }
            }
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
        let titleText = shortcut.address.isEmpty ? "Add \(shortcut.label) address" : "Edit \(shortcut.label) address"
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
        let showDropoffSuggestions = (focusedField == .dropoff && !dropoffText.isEmpty)

        VStack(spacing: 8) {
            // Pickup
            bookingField(title: "Pickup", text: $pickupText, icon: "mappin.and.ellipse")
                .focused($focusedField, equals: .pickup)
                .onChange(of: pickupText) { _, new in
                    if new != pickupResolvedAddress {
                        pickupCoordinate = nil
                        pickupResolvedAddress = ""
                        routeEstimate = nil
                    }
                    pickupCompleter.setRegion(region); pickupCompleter.setQuery(new)
                }
            if showPickupSuggestions {
                suggestionsList(for: pickupCompleter) { completion in
                    Task { await selectPickup(completion) }
                }
            }

            // Dropoff
            bookingField(title: "Dropoff", text: $dropoffText, icon: "flag.checkered")
                .focused($focusedField, equals: .dropoff)
                .onChange(of: dropoffText) { _, new in
                    if new != dropoffResolvedAddress {
                        dropoffCoordinate = nil
                        dropoffResolvedAddress = ""
                        routeEstimate = nil
                    }
                    dropoffCompleter.setRegion(region); dropoffCompleter.setQuery(new)
                }
                .overlay(alignment: .trailing) {
                    if !dropoffText.isEmpty {
                        Button {
                            dropoffText = ""
                            dropoffCoordinate = nil
                            dropoffResolvedAddress = ""
                            routeEstimate = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 10)
                        }
                        .buttonStyle(.plain)
                    }
            }
            if showDropoffSuggestions {
                suggestionsList(for: dropoffCompleter) { completion in
                    Task { await selectDropoff(completion) }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Reusable field (icon optionally tappable)
    @ViewBuilder
    private func bookingField(
        title: String,
        text: Binding<String>,
        icon: String,
        onIconTap: (() -> Void)? = nil
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
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.thinMaterial))
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
            .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
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
                    Image(systemName: "plus.circle")
                    Text("Add promo code")
                    Spacer()
                }
                .font(.subheadline)
            }

            if showPromo {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Enter promo code", text: $promoCode)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
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
                if isResolvingLocations {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Request \(rideType)")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(GradientButtonStyle())
            .disabled(isResolvingLocations)

            if let message = requestValidationMessage {
                validationBanner(text: message)
            }
        }
        .padding(.horizontal)
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
            estimate: currentEstimate
        )
        showDriverSheet = true
    }

    private func clearRouteResolution() {
        pickupCoordinate = nil
        dropoffCoordinate = nil
        pickupResolvedAddress = ""
        dropoffResolvedAddress = ""
        routeEstimate = nil
        routeRequestID = UUID()
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
            routeEstimate = try await calculateRouteEstimate(from: pickupCoordinate, to: dropoffCoordinate)
            recenterOnResolvedLocations()
            return true
        } catch {
            return false
        }
    }

    private func updateRouteEstimateIfPossible() {
        guard let pickupCoordinate, let dropoffCoordinate else { return }
        let requestID = UUID()
        routeRequestID = requestID
        Task {
            do {
                let estimate = try await calculateRouteEstimate(from: pickupCoordinate, to: dropoffCoordinate)
                await MainActor.run {
                    guard routeRequestID == requestID else { return }
                    routeEstimate = estimate
                }
            } catch {
                await MainActor.run {
                    guard routeRequestID == requestID else { return }
                    routeEstimate = nil
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

    private func calculateRouteEstimate(from pickup: CLLocationCoordinate2D, to dropoff: CLLocationCoordinate2D) async throws -> RideEstimate {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: pickup))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: dropoff))
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

        return RideEstimate(
            distanceMiles: ((route.distance / 1609.344) * 10).rounded() / 10,
            durationMinutes: max(1, (route.expectedTravelTime / 60).rounded())
        )
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
