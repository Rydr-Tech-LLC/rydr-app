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
                Map(initialPosition: .region(region)) { UserAnnotation() }
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

                    if let editingID = editingShortcutID,
                       let sc = shortcuts.first(where: { $0.id == editingID }) {
                        HStack(spacing: 8) {
                            bookingField(
                                title: sc.address.isEmpty ? "Add \(sc.label) address" : "Edit \(sc.label) address",
                                text: Binding(
                                    get: { newShortcutAddress },
                                    set: { newValue in
                                        newShortcutAddress = newValue
                                        shortcutCompleter.setRegion(region)
                                        shortcutCompleter.setQuery(newValue)
                                    }),
                                icon: "location.magnifyingglass",
                                onIconTap: {
                                    shortcutFocused = true
                                    shortcutCompleter.setRegion(region)
                                    shortcutCompleter.setQuery(newShortcutAddress)
                                }
                            )
                            .focused($shortcutFocused)

                            Button {
                                if let idx = shortcuts.firstIndex(where: { $0.id == sc.id }),
                                   !newShortcutAddress.trimmingCharacters(in: .whitespaces).isEmpty {
                                    shortcuts[idx].address = newShortcutAddress
                                }
                                newShortcutAddress = ""
                                editingShortcutID = nil
                                shortcutFocused = false
                            } label: { Image(systemName: "checkmark.circle.fill").font(.title3) }

                            Button {
                                newShortcutAddress = ""
                                editingShortcutID = nil
                                shortcutFocused = false
                            } label: { Image(systemName: "xmark.circle.fill").font(.title3) }
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
                                    focusedField = nil
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "mappin.circle.fill").font(.title3).foregroundStyle(Color.red)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(addr).lineLimit(1).foregroundColor(.primary)
                                            if let city = addr.split(separator: ",").dropFirst().first {
                                                Text(city.trimmingCharacters(in: .whitespaces))
                                                    .font(.caption).foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.06), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 1))
                }

                // ── Promo + Request button ─────────────────────────────────────
                promoView

                Button { requestRide() } label: {
                    Text("Request \(rideType)").frame(maxWidth: .infinity)
                }
                .buttonStyle(GradientButtonStyle())
                .padding(.horizontal)
                .padding(.bottom, 8)
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
                    pickupCompleter.setRegion(region); pickupCompleter.setQuery(new)
                }
            if showPickupSuggestions {
                suggestionsList(for: pickupCompleter) { selection in
                    pickupText = selection; focusedField = nil
                }
            }

            // Dropoff
            bookingField(title: "Dropoff", text: $dropoffText, icon: "flag.checkered")
                .focused($focusedField, equals: .dropoff)
                .onChange(of: dropoffText) { _, new in
                    dropoffCompleter.setRegion(region); dropoffCompleter.setQuery(new)
                }
                .overlay(alignment: .trailing) {
                    if !dropoffText.isEmpty {
                        Button {
                            dropoffText = ""
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
                suggestionsList(for: dropoffCompleter) { selection in
                    dropoffText = selection; focusedField = nil
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
        onPick: @escaping (String) -> Void
    ) -> some View {
        let items = Array(completer.results.prefix(10))
        if !items.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items.indices, id: \.self) { i in
                        let item = items[i]
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

                        Button(action: applyPromo) {
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

    private func applyPromo() {
        let code = promoCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else {
            showStatus(.failure("Enter a promo code."))
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
        guard let data else { return [] }
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
    private func requestRide() {
        if isPromoApplied && currentEstimate.distanceMiles > 15 {
            showStatus(.failure("RydrBank codes can only be applied to rides up to 15 miles."))
            return
        }
        if !dropoffText.trimmingCharacters(in: .whitespaces).isEmpty {
            pushRecent(dropoffText)
        }
        rideManager.requestDrivers(
            pickup: pickupText,
            dropoff: dropoffText,
            rideType: rideType,
            near: region.center
        )
        showDriverSheet = true
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
