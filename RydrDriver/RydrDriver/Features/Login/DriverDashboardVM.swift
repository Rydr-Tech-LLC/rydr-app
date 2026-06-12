//
//  DriverDashboardVM.swift
//  Rydr Driver
//
//  Driver dashboard for online presence, standard ride requests, and active ride state.
//

import SwiftUI
import Combine
import MapKit
import CoreLocation
import PhotosUI
#if canImport(_MapKit_SwiftUI)
import _MapKit_SwiftUI
#endif
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - ViewModel

final class DriverDashboardVM: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isOnline: Bool = false
    @Published var showMenu: Bool = false
    @Published var earningsToday: Decimal = 0
    @Published var mapRegion: MKCoordinateRegion = DriverMapDefaults.pilotRegion
    @Published var lastLocation: CLLocation? = DriverMapDefaults.pilotLocation
    @Published var canGoOnline: Bool = false
    @Published var selectedRideTypes: Set<String> = []
    @Published var eligibleRideTypes: [String] = ["Rydr Go"]
    @Published var tierRates: [String: DriverRateSetting] = [:]
    @Published var hasSavedRateSettings: Bool = false
    @Published var isSearchingForRides: Bool = false
    @Published var pendingRequests: [DriverRideRequest] = []
    @Published var mapRideRequestBlips: [DriverRideRadarBlip] = []
    @Published var rideFilterPreferences = DriverRideFilterPreferences()
    @Published var activeRide: DriverActiveRide?
    @Published var completedRideForRating: DriverActiveRide?
    @Published var statusMessage: String = "Ready to receive standard Rydr requests."
    @Published var profilePhotoURL: String?
    @Published var pendingProfilePhotoURL: String?
    @Published var profilePhotoReviewStatus: String = "approved"
    @Published var isUploadingProfilePhoto: Bool = false
    @Published var profilePhotoMessage: String?
    #if DEBUG
    @Published var debugApprovalBypassEnabled: Bool = DriverApprovalDebugBypass.isEnabled
    #endif

    static let availableRideTypes = RydrRideTierCatalog.orderedRideTypes

    var isReadyToGoOnline: Bool {
        canGoOnline && hasSavedRateSettings && !selectedRideTypes.isEmpty
    }

    var goOnlineBlockReason: String? {
        if !canGoOnline { return "Driver approval is still pending." }
        if !hasSavedRateSettings { return "Save your rate before going online." }
        if selectedRideTypes.isEmpty { return "Select at least one approved ride type." }
        return nil
    }

    private let locationManager = CLLocationManager()
    private var locationTimer: Timer?
    private let db = Firestore.firestore()
    private var driverListener: ListenerRegistration?
    private var requestListener: ListenerRegistration?
    private var mapRequestBlipListener: ListenerRegistration?
    private var activeRideListener: ListenerRegistration?
    #if DEBUG
    private var didCreateMockRideThisOnlineSession = false

    private var shouldUseAtlantaPilotLocationInSimulator: Bool {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["RYDR_USE_SIMULATOR_CORE_LOCATION"] != "1"
        #else
        false
        #endif
    }
    #endif

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
    }

    deinit {
        driverListener?.remove()
        requestListener?.remove()
        mapRequestBlipListener?.remove()
        activeRideListener?.remove()
        locationTimer?.invalidate()
    }

    func startDashboard() {
        #if DEBUG
        if shouldUseAtlantaPilotLocationInSimulator {
            applyAtlantaPilotLocation()
        }
        #endif
        requestLocationAuth()
        startObservingDriverEligibility()
        startMapRequestBlipListener()
        startActiveRideListener()
        publishDriverProfile()
    }

    func requestLocationAuth() {
        #if DEBUG
        if shouldUseAtlantaPilotLocationInSimulator {
            statusMessage = "Simulator using Atlanta pilot location."
            return
        }
        #endif
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .restricted, .denied:
            statusMessage = "Location permission is required before you can receive nearby rides."
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        #if DEBUG
        if shouldUseAtlantaPilotLocationInSimulator {
            applyAtlantaPilotLocation()
            return
        }
        #endif
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
            statusMessage = "Location is enabled. Go online when you are ready."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        #if DEBUG
        if shouldUseAtlantaPilotLocationInSimulator {
            applyAtlantaPilotLocation()
            return
        }
        #endif
        lastLocation = loc
        mapRegion.center = loc.coordinate

        guard isOnline else { return }
        updateDriverPresence(online: true)
        updateActiveRideLocation(loc)
    }

    func toggleRideType(_ rideType: String) {
        guard eligibleRideTypes.contains(rideType) else {
            statusMessage = "\(rideType) requires vehicle eligibility or manual approval."
            return
        }
        if selectedRideTypes.contains(rideType), selectedRideTypes.count > 1 {
            selectedRideTypes.remove(rideType)
        } else {
            selectedRideTypes.insert(rideType)
        }
        startMapRequestBlipListener()
        if isOnline {
            updateDriverPresence(online: true)
        }
    }

    func rate(for rideType: String) -> DriverRateSetting {
        tierRates[rideType] ?? .defaultValue(for: rideType)
    }

    func saveRate(rideType: String, perMile: Double, perMinute: Double) {
        guard !isOnline else {
            statusMessage = "Rates may only be adjusted while offline."
            return
        }
        let pricing = RydrRideTierCatalog.pricing(for: rideType)
        var setting = rate(for: rideType)
        setting.perMile = pricing.clampedPerMile(perMile)
        setting.perMinute = pricing.clampedPerMinute(perMinute)
        tierRates[rideType] = setting
        hasSavedRateSettings = true
        statusMessage = "\(rideType) rate saved. You can go online when ready."
        publishDriverProfile()
        if isOnline { updateDriverPresence(online: true) }
    }

    func toggleOnline() {
        guard canGoOnline else {
            statusMessage = "Go Online unlocks after your driver approval is complete."
            return
        }
        guard hasSavedRateSettings else {
            statusMessage = "Set and save a rate before going online."
            return
        }
        guard !selectedRideTypes.isEmpty else {
            statusMessage = "Select at least one approved ride type before going online."
            return
        }

        isOnline.toggle()
        if isOnline {
            isSearchingForRides = true
            #if DEBUG
            if shouldUseAtlantaPilotLocationInSimulator {
                applyAtlantaPilotLocation()
            } else {
                locationManager.startUpdatingLocation()
            }
            #else
            locationManager.startUpdatingLocation()
            #endif
            startPushingDriverPresence()
            startRequestListener()
            statusMessage = "Standby. Searching for rides."
            #if DEBUG
            createMockRideRequestIfNeeded()
            #endif
        } else {
            isSearchingForRides = false
            #if DEBUG
            didCreateMockRideThisOnlineSession = false
            #endif
            stopPushingDriverPresence()
            stopRequestListener()
            updateDriverPresence(online: false)
            pendingRequests = []
            statusMessage = "Offline. You will not receive new ride requests."
        }
    }

    func refreshMapRequestBlips() {
        startMapRequestBlipListener()
    }

    #if DEBUG
    private func applyAtlantaPilotLocation() {
        lastLocation = DriverMapDefaults.pilotLocation
        mapRegion = DriverMapDefaults.pilotRegion
    }
    #endif

    #if DEBUG
    func setDebugApprovalBypass(_ enabled: Bool) {
        DriverApprovalDebugBypass.setEnabled(enabled)
        debugApprovalBypassEnabled = enabled
        canGoOnline = enabled || canGoOnline

        guard let uid = Auth.auth().currentUser?.uid else { return }
        let payload: [String: Any] = enabled ? [
            "backgroundCheckPassed": true,
            "backgroundCheckStatus": "approved",
            "debugApprovalBypassEnabled": true,
            "debugApprovalBypassUpdatedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ] : [
            "debugApprovalBypassEnabled": false,
            "debugApprovalBypassUpdatedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        db.collection("drivers").document(uid).setData(payload, merge: true) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.statusMessage = "Could not update test approval: \(error.localizedDescription)"
                } else {
                    self?.statusMessage = enabled ? "Test approval bypass enabled." : "Test approval bypass disabled."
                }
            }
        }
    }
    #endif

    func submitProfilePhotoForReview(_ image: UIImage) {
        guard let uid = Auth.auth().currentUser?.uid else {
            profilePhotoMessage = "Sign in before updating your profile photo."
            return
        }
        guard let data = image.jpegData(compressionQuality: 0.82) else {
            profilePhotoMessage = "Could not prepare that image."
            return
        }

        isUploadingProfilePhoto = true
        profilePhotoMessage = nil
        let path = "driverProfilePhotos/\(uid)/pending-\(Int(Date().timeIntervalSince1970)).jpg"
        let ref = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        ref.putData(data, metadata: metadata) { [weak self] _, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.isUploadingProfilePhoto = false
                    self.profilePhotoMessage = "Photo upload failed: \(error.localizedDescription)"
                }
                return
            }

            ref.downloadURL { url, error in
                if let error {
                    DispatchQueue.main.async {
                        self.isUploadingProfilePhoto = false
                        self.profilePhotoMessage = "Photo upload failed: \(error.localizedDescription)"
                    }
                    return
                }

                guard let url else {
                    DispatchQueue.main.async {
                        self.isUploadingProfilePhoto = false
                        self.profilePhotoMessage = "Photo upload failed."
                    }
                    return
                }

                let payload: [String: Any] = [
                    "pendingProfilePhotoURL": url.absoluteString,
                    "pendingProfilePhotoPath": path,
                    "profilePhotoReviewStatus": "pending",
                    "profilePhotoSubmittedAt": FieldValue.serverTimestamp(),
                    "profilePhotoUpdatedAt": FieldValue.serverTimestamp()
                ]

                self.db.collection("drivers").document(uid).setData(payload, merge: true) { error in
                    DispatchQueue.main.async {
                        self.isUploadingProfilePhoto = false
                        if let error {
                            self.profilePhotoMessage = "Photo review submission failed: \(error.localizedDescription)"
                        } else {
                            self.pendingProfilePhotoURL = url.absoluteString
                            self.profilePhotoReviewStatus = "pending"
                            self.profilePhotoMessage = "Profile photo submitted for approval."
                        }
                    }
                }
            }
        }
    }

    func accept(_ request: DriverRideRequest) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let rideRef = db.collection("rides").document(request.id)
        let requestRef = db.collection("rideRequests").document(request.id)
        var rideData: [String: Any] = [
            "id": request.id,
            "requestId": request.id,
            "driverId": uid,
            "riderId": request.riderId,
            "riderName": request.riderName,
            "pickup": request.pickup,
            "dropoff": request.dropoff,
            "rideType": request.rideType,
            "status": "accepted",
            "acceptedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let estimatedFare = request.estimatedFare {
            rideData["estimatedFare"] = estimatedFare
        }
        if let riderPhotoURL = request.riderPhotoURL {
            rideData["riderPhotoURL"] = riderPhotoURL
        }
        if let riderRating = request.riderRating {
            rideData["riderRating"] = riderRating
        }
        if let distance = request.estimatedDistanceMiles {
            rideData["estimatedDistanceMiles"] = distance
        }
        if let duration = request.estimatedDurationMinutes {
            rideData["estimatedDurationMinutes"] = duration
        }
        if let pickupCoordinate = request.pickupCoordinate {
            rideData["pickupCoordinate"] = [
                "lat": pickupCoordinate.latitude,
                "lng": pickupCoordinate.longitude
            ]
            rideData["pickupGeoPoint"] = GeoPoint(latitude: pickupCoordinate.latitude, longitude: pickupCoordinate.longitude)
        }
        if let dropoffCoordinate = request.dropoffCoordinate {
            rideData["dropoffCoordinate"] = [
                "lat": dropoffCoordinate.latitude,
                "lng": dropoffCoordinate.longitude
            ]
            rideData["dropoffGeoPoint"] = GeoPoint(latitude: dropoffCoordinate.latitude, longitude: dropoffCoordinate.longitude)
        }
        if let loc = lastLocation {
            rideData["driverLocation"] = [
                "lat": loc.coordinate.latitude,
                "lng": loc.coordinate.longitude,
                "updatedAt": FieldValue.serverTimestamp()
            ]
        }

        let batch = db.batch()
        batch.updateData([
            "status": "accepted",
            "acceptedAt": FieldValue.serverTimestamp(),
            "rideId": request.id,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: requestRef)
        batch.setData(rideData, forDocument: rideRef, merge: true)
        batch.commit { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.statusMessage = "Could not accept ride: \(error.localizedDescription)"
                    return
                }
                self?.pendingRequests.removeAll { $0.id == request.id }
                self?.activeRide = DriverActiveRide(id: request.id, data: rideData)
                self?.statusMessage = "Ride accepted. Head to pickup."
                self?.updateDriverPresence(online: true)
            }
        }
    }

    func decline(_ request: DriverRideRequest) {
        decline(request, message: "You have chosen to decline this ride.")
    }

    func miss(_ request: DriverRideRequest) {
        decline(request, status: "missed", timestampField: "missedAt", message: "Looks like you missed this ride.")
    }

    private func decline(
        _ request: DriverRideRequest,
        status: String = "declined",
        timestampField: String = "declinedAt",
        message: String
    ) {
        db.collection("rideRequests").document(request.id).updateData([
            "status": status,
            timestampField: FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.statusMessage = "Could not decline ride: \(error.localizedDescription)"
                    return
                }
                self?.pendingRequests.removeAll { $0.id == request.id }
                self?.statusMessage = message
            }
        }
    }

    func advanceActiveRide() {
        guard let ride = activeRide else { return }
        let nextStatus: String
        let timestampField: String
        switch ride.status {
        case "accepted":
            nextStatus = "enRouteToPickup"
            timestampField = "enRouteToPickupAt"
        case "enRouteToPickup":
            nextStatus = "arrived"
            timestampField = "arrivedAt"
        case "arrived":
            nextStatus = "inProgress"
            timestampField = "startedAt"
        default:
            completeActiveRide()
            return
        }

        db.collection("rides").document(ride.id).setData([
            "status": nextStatus,
            timestampField: FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true) { [weak self] error in
            DispatchQueue.main.async {
                self?.statusMessage = error?.localizedDescription ?? Self.driverMessage(for: nextStatus)
            }
        }
    }

    func markPickupComplete() {
        guard let ride = activeRide else { return }
        db.collection("rides").document(ride.id).setData([
            "status": "inProgress",
            "arrivedAt": FieldValue.serverTimestamp(),
            "startedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true) { [weak self] error in
            DispatchQueue.main.async {
                self?.statusMessage = error?.localizedDescription ?? "Pickup confirmed. Navigate to drop-off."
            }
        }
    }

    func markDropoffComplete() {
        completeActiveRide()
    }

    #if DEBUG
    func debugMoveToActiveRideDestination() {
        guard let ride = activeRide else { return }
        let destination = ride.status == "inProgress" ? ride.dropoffCoordinate : ride.pickupCoordinate
        guard let destination else {
            statusMessage = "Mock ride is missing its next destination."
            return
        }

        let location = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        lastLocation = location
        mapRegion.center = destination
        updateActiveRideLocation(location)
        statusMessage = ride.status == "inProgress"
            ? "Mock driver moved to drop-off."
            : "Mock driver moved to pickup."
    }

    func debugMoveActiveRideDriver(to coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        lastLocation = location
        mapRegion.center = coordinate
        updateActiveRideLocation(location)
    }
    #endif

    func completeActiveRide() {
        guard let ride = activeRide else { return }
        let batch = db.batch()
        let rideRef = db.collection("rides").document(ride.id)
        let requestRef = db.collection("rideRequests").document(ride.id)
        batch.setData([
            "status": "completed",
            "completedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: rideRef, merge: true)
        batch.setData([
            "status": "completed",
            "completedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: requestRef, merge: true)
        batch.commit { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.statusMessage = "Could not complete ride: \(error.localizedDescription)"
                    return
                }
                self?.completedRideForRating = ride
                self?.activeRide = nil
                self?.statusMessage = "Ride completed. You are ready for the next request."
                self?.updateDriverPresence(online: self?.isOnline ?? false)
            }
        }
    }

    func dismissCompletedRideRating() {
        completedRideForRating = nil
        statusMessage = "Ride completed."
    }

    func submitRiderRating(ride: DriverActiveRide, rating: Int?, feedback: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var payload: [String: Any] = [
            "rideId": ride.id,
            "driverId": uid,
            "riderId": ride.riderId,
            "feedback": feedback.trimmingCharacters(in: .whitespacesAndNewlines),
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let rating {
            payload["rating"] = rating
        }

        let batch = db.batch()
        let ratingRef = db.collection("riderRatings").document()
        batch.setData(payload, forDocument: ratingRef, merge: true)
        batch.setData([
            "driverRiderRating": payload,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: db.collection("rides").document(ride.id), merge: true)
        batch.commit { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.statusMessage = "Could not save rider rating: \(error.localizedDescription)"
                } else {
                    self?.completedRideForRating = nil
                    self?.statusMessage = "Thanks. Rider feedback saved."
                }
            }
        }
    }

    func sendMessageToRider(ride: DriverActiveRide, text: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let chatRef = db.collection("rideChats").document(ride.id)
        try await chatRef.setData([
            "rideId": ride.id,
            "riderId": ride.riderId,
            "driverId": uid,
            "status": "active",
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        try await chatRef.collection("messages").addDocument(data: [
            "senderId": uid,
            "senderRole": "driver",
            "text": trimmed,
            "createdAt": FieldValue.serverTimestamp(),
            "isRead": false
        ])
    }

    #if DEBUG
    private func createMockRideRequestIfNeeded() {
        guard !didCreateMockRideThisOnlineSession,
              pendingRequests.isEmpty,
              activeRide == nil,
              let uid = Auth.auth().currentUser?.uid else { return }
        didCreateMockRideThisOnlineSession = true

        let id = "mock-\(UUID().uuidString)"
        let pickup = CLLocationCoordinate2D(latitude: 33.7550, longitude: -84.3900)
        let dropoff = CLLocationCoordinate2D(latitude: 33.7765, longitude: -84.3897)
        let driver = lastLocation?.coordinate ?? mapRegion.center
        let pickupMiles = CLLocation(latitude: driver.latitude, longitude: driver.longitude)
            .distance(from: CLLocation(latitude: pickup.latitude, longitude: pickup.longitude)) / 1609.344
        let tripMiles = CLLocation(latitude: pickup.latitude, longitude: pickup.longitude)
            .distance(from: CLLocation(latitude: dropoff.latitude, longitude: dropoff.longitude)) / 1609.344
        let adjustedTripMiles = ((tripMiles * 1.25) * 10).rounded() / 10
        let duration = max(6, (adjustedTripMiles / 22.0 * 60).rounded())
        let rideType = selectedRideTypes.sorted().first ?? "Rydr Go"
        let rate = self.rate(for: rideType)
        let fare = (((adjustedTripMiles * rate.perMile) + (duration * rate.perMinute)) * 100).rounded() / 100

        db.collection("rideRequests").document(id).setData([
            "id": id,
            "driverId": uid,
            "riderId": "mock-rider",
            "riderName": "Maya Test",
            "riderRating": 4.92,
            "pickup": "Ponce City Market, Atlanta, GA",
            "dropoff": "Piedmont Park, Atlanta, GA",
            "rideType": rideType,
            "estimatedFare": fare,
            "estimatedDistanceMiles": adjustedTripMiles,
            "estimatedDurationMinutes": duration,
            "pickupDistanceFromDriverMiles": ((pickupMiles * 10).rounded() / 10),
            "pickupCoordinate": ["lat": pickup.latitude, "lng": pickup.longitude],
            "dropoffCoordinate": ["lat": dropoff.latitude, "lng": dropoff.longitude],
            "status": "pending",
            "source": "debugMockRide",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
    #endif

    func cancelActiveRide() {
        guard let ride = activeRide else { return }
        db.collection("rides").document(ride.id).setData([
            "status": "driverCancelled",
            "cancelledAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.statusMessage = "Could not cancel ride: \(error.localizedDescription)"
                    return
                }
                self?.activeRide = nil
                self?.statusMessage = "Ride cancelled."
                self?.updateDriverPresence(online: self?.isOnline ?? false)
            }
        }
    }

    private func startPushingDriverPresence() {
        updateDriverPresence(online: true)
        locationTimer?.invalidate()
        locationTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.updateDriverPresence(online: true)
        }
    }

    private func stopPushingDriverPresence() {
        locationTimer?.invalidate()
        locationTimer = nil
    }

    private func startObservingDriverEligibility() {
        driverListener?.remove()
        guard let uid = Auth.auth().currentUser?.uid else {
            canGoOnline = false
            return
        }

        driverListener = db.collection("drivers").document(uid).addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            guard let data = snapshot?.data(), error == nil else {
                DispatchQueue.main.async { self.canGoOnline = false }
                return
            }

            DispatchQueue.main.async {
                #if DEBUG
                self.debugApprovalBypassEnabled = DriverApprovalDebugBypass.isEnabled
                self.canGoOnline = DriverApprovalDebugBypass.isApproved(data: data)
                #else
                let passed = data["backgroundCheckPassed"] as? Bool ?? false
                let status = (data["backgroundCheckStatus"] as? String)?.lowercased() ?? ""
                let allowedByString = ["passed", "clear", "approved", "complete", "completed"].contains(status)
                self.canGoOnline = passed || allowedByString
                #endif
                self.applyVehicleEligibility(from: data)
                self.profilePhotoURL = data["profilePhotoURL"] as? String
                self.pendingProfilePhotoURL = data["pendingProfilePhotoURL"] as? String
                self.profilePhotoReviewStatus = data["profilePhotoReviewStatus"] as? String ?? (self.pendingProfilePhotoURL == nil ? "approved" : "pending")
            }
        }
    }

    private func startRequestListener() {
        requestListener?.remove()
        guard let uid = Auth.auth().currentUser?.uid else { return }

        requestListener = db.collection("rideRequests")
            .whereField("driverId", isEqualTo: uid)
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    if let error {
                        self?.statusMessage = "Request listener error: \(error.localizedDescription)"
                        return
                    }
                    self?.pendingRequests = snapshot?.documents.map(DriverRideRequest.init(document:)) ?? []
                    if self?.pendingRequests.isEmpty == false {
                        self?.isSearchingForRides = false
                    }
                }
            }
    }

    private func stopRequestListener() {
        requestListener?.remove()
        requestListener = nil
    }

    private func startMapRequestBlipListener() {
        mapRequestBlipListener?.remove()
        #if DEBUG && targetEnvironment(simulator)
        mapRideRequestBlips = privacySafeRadarBlips(from: simulatorTestRideRequests())
        #endif
        mapRequestBlipListener = db.collection("rideRequests")
            .whereField("status", isEqualTo: "pending")
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error {
                        self.statusMessage = "Map request listener error: \(error.localizedDescription)"
                        #if DEBUG && targetEnvironment(simulator)
                        self.mapRideRequestBlips = self.privacySafeRadarBlips(from: self.simulatorTestRideRequests())
                        #endif
                        return
                    }

                    let liveRequests = snapshot?.documents
                        .map(DriverRideRequest.init(document:))
                        .filter { request in
                            self.canShowRadarBlip(for: request)
                        } ?? []
                    #if DEBUG && targetEnvironment(simulator)
                    self.mapRideRequestBlips = self.mergedMapBlips(
                        self.privacySafeRadarBlips(from: liveRequests + self.simulatorTestRideRequests())
                    )
                    #else
                    self.mapRideRequestBlips = self.privacySafeRadarBlips(from: liveRequests)
                    #endif
                }
            }
    }

    #if DEBUG && targetEnvironment(simulator)
    private func simulatorTestRideRequests() -> [DriverRideRequest] {
        [
            DriverRideRequest(
                id: "sim-blip-ponce",
                riderId: "sim-rider-ponce",
                riderName: "Sim Rider",
                pickup: "Ponce City Market",
                dropoff: "Piedmont Park",
                rideType: "Rydr Go",
                pickupCoordinate: CLLocationCoordinate2D(latitude: 33.7726, longitude: -84.3656),
                dropoffCoordinate: CLLocationCoordinate2D(latitude: 33.7851, longitude: -84.3737),
                createdAt: Date()
            ),
            DriverRideRequest(
                id: "sim-blip-mercedes",
                riderId: "sim-rider-mercedes",
                riderName: "Sim Rider",
                pickup: "Mercedes-Benz Stadium",
                dropoff: "Georgia Aquarium",
                rideType: "Rydr Go",
                pickupCoordinate: CLLocationCoordinate2D(latitude: 33.7554, longitude: -84.4008),
                dropoffCoordinate: CLLocationCoordinate2D(latitude: 33.7634, longitude: -84.3951),
                createdAt: Date()
            ),
            DriverRideRequest(
                id: "sim-blip-buckhead",
                riderId: "sim-rider-buckhead",
                riderName: "Sim Rider",
                pickup: "Buckhead Village",
                dropoff: "Atlantic Station",
                rideType: "Rydr Go",
                pickupCoordinate: CLLocationCoordinate2D(latitude: 33.8386, longitude: -84.3799),
                dropoffCoordinate: CLLocationCoordinate2D(latitude: 33.7932, longitude: -84.3973),
                createdAt: Date()
            ),
            DriverRideRequest(
                id: "sim-blip-airport",
                riderId: "sim-rider-airport",
                riderName: "Sim Rider",
                pickup: "Hartsfield-Jackson ATL",
                dropoff: "Downtown Atlanta",
                rideType: "Rydr Go",
                pickupCoordinate: CLLocationCoordinate2D(latitude: 33.6407, longitude: -84.4277),
                dropoffCoordinate: CLLocationCoordinate2D(latitude: 33.7550, longitude: -84.3900),
                createdAt: Date()
            )
        ]
    }

    private func mergedMapBlips(_ blips: [DriverRideRadarBlip]) -> [DriverRideRadarBlip] {
        var seen = Set<String>()
        return blips.filter { blip in
            guard !seen.contains(blip.id), !blip.isExpired else { return false }
            seen.insert(blip.id)
            return true
        }
    }
    #endif

    private func canShowRadarBlip(for request: DriverRideRequest) -> Bool {
        guard request.pickupCoordinate != nil else { return false }
        guard !isRadarBlipExpired(request) else { return false }

        let eligible = Set(eligibleRideTypes.map(RydrRideTierCatalog.canonicalRideType))
        guard eligible.contains(RydrRideTierCatalog.canonicalRideType(request.rideType)) else { return false }

        let selected = Set(selectedRideTypes.map(RydrRideTierCatalog.canonicalRideType))
        guard selected.isEmpty || selected.contains(RydrRideTierCatalog.canonicalRideType(request.rideType)) else { return false }

        return matchesRideFilters(request)
    }

    private func isRadarBlipExpired(_ request: DriverRideRequest) -> Bool {
        guard let createdAt = request.createdAt else { return false }
        return Date().timeIntervalSince(createdAt) > radarBlipLifetime(for: request)
    }

    private func privacySafeRadarBlips(from requests: [DriverRideRequest]) -> [DriverRideRadarBlip] {
        requests
            .filter(canShowRadarBlip(for:))
            .compactMap { request in
                guard let pickupCoordinate = request.pickupCoordinate else { return nil }
                let createdAt = request.createdAt ?? Date()
                return DriverRideRadarBlip(
                    id: request.id,
                    coordinate: fuzzedRadarCoordinate(for: request.id, pickupCoordinate: pickupCoordinate),
                    expiresAt: createdAt.addingTimeInterval(radarBlipLifetime(for: request))
                )
            }
    }

    private func matchesRideFilters(_ request: DriverRideRequest) -> Bool {
        guard let pickupCoordinate = request.pickupCoordinate else { return false }
        let driverCoordinate = lastLocation?.coordinate ?? mapRegion.center
        let driverLocation = CLLocation(latitude: driverCoordinate.latitude, longitude: driverCoordinate.longitude)
        let pickupLocation = CLLocation(latitude: pickupCoordinate.latitude, longitude: pickupCoordinate.longitude)
        let pickupMiles = driverLocation.distance(from: pickupLocation) / 1609.344
        if rideFilterPreferences.workZoneEnabled {
            guard pickupMiles <= rideFilterPreferences.effectivePickupMiles else { return false }
        }

        guard rideFilterPreferences.hasDestinationFilter,
              let destinationCoordinate = rideFilterPreferences.destinationCoordinate else {
            return true
        }

        guard let dropoffCoordinate = request.dropoffCoordinate else { return false }
        let dropoffLocation = CLLocation(latitude: dropoffCoordinate.latitude, longitude: dropoffCoordinate.longitude)
        let destinationLocation = CLLocation(latitude: destinationCoordinate.latitude, longitude: destinationCoordinate.longitude)
        let pickupToDestinationMiles = pickupLocation.distance(from: destinationLocation) / 1609.344
        let dropoffToDestinationMiles = dropoffLocation.distance(from: destinationLocation) / 1609.344
        let corridorMiles = distanceFromPointToSegmentMiles(
            point: dropoffCoordinate,
            start: driverCoordinate,
            end: destinationCoordinate
        )

        return dropoffToDestinationMiles <= pickupToDestinationMiles
            && corridorMiles <= rideFilterPreferences.destinationCorridor.miles
    }

    private func distanceFromPointToSegmentMiles(
        point: CLLocationCoordinate2D,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> Double {
        let centerLatitude = start.latitude * .pi / 180
        func xy(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(
                x: coordinate.longitude * 69.0 * cos(centerLatitude),
                y: coordinate.latitude * 69.0
            )
        }

        let p = xy(point)
        let a = xy(start)
        let b = xy(end)
        let dx = b.x - a.x
        let dy = b.y - a.y
        guard dx != 0 || dy != 0 else {
            return hypot(p.x - a.x, p.y - a.y)
        }

        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)))
        let projected = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - projected.x, p.y - projected.y)
    }

    private func fuzzedRadarCoordinate(for id: String, pickupCoordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let zoneSize = 0.01
        let roundedLat = (pickupCoordinate.latitude / zoneSize).rounded() * zoneSize
        let roundedLng = (pickupCoordinate.longitude / zoneSize).rounded() * zoneSize

        let hash = abs(id.hashValue)
        let bearing = Double(hash % 360) * .pi / 180
        let distanceMiles = 0.25 + (Double((hash / 360) % 25) / 100.0)
        let latOffset = (distanceMiles / 69.0) * cos(bearing)
        let lngOffset = (distanceMiles / max(1, 69.0 * cos(roundedLat * .pi / 180))) * sin(bearing)

        return CLLocationCoordinate2D(latitude: roundedLat + latOffset, longitude: roundedLng + lngOffset)
    }

    private func radarBlipLifetime(for request: DriverRideRequest) -> TimeInterval {
        30 + Double(abs(request.id.hashValue) % 31)
    }

    private func stopMapRequestBlipListener() {
        mapRequestBlipListener?.remove()
        mapRequestBlipListener = nil
        mapRideRequestBlips = []
    }

    private func startActiveRideListener() {
        activeRideListener?.remove()
        guard let uid = Auth.auth().currentUser?.uid else { return }

        activeRideListener = db.collection("rides")
            .whereField("driverId", isEqualTo: uid)
            .whereField("status", in: ["accepted", "enRouteToPickup", "arrived", "inProgress"])
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard error == nil else {
                        self?.statusMessage = "Active ride listener error: \(error?.localizedDescription ?? "Unknown error")"
                        return
                    }
                    guard let doc = snapshot?.documents.first else {
                        self?.activeRide = nil
                        return
                    }
                    self?.activeRide = DriverActiveRide(id: doc.documentID, data: doc.data())
                }
            }
    }

    private func publishDriverProfile() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let user = Auth.auth().currentUser
        db.collection("drivers").document(uid).setData([
            "uid": uid,
            "displayName": user?.displayName ?? "Rydr Driver",
            "email": user?.email ?? "",
            "standardDispatchEnabled": true,
            "qualifiedRideTypes": eligibleRideTypes,
            "supportedRideTypes": eligibleRideTypes,
            "selectedRideTypes": Array(selectedRideTypes).sorted(),
            "rideTypes": Array(selectedRideTypes).sorted(),
            "tierRates": tierRatesPayload(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    private func updateDriverPresence(online: Bool) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var statusPayload: [String: Any] = [
            "online": online,
            "isOnline": online,
            "availabilityStatus": online ? "available" : "offline",
            "rideTypes": Array(selectedRideTypes).sorted(),
            "selectedRideTypes": Array(selectedRideTypes).sorted(),
            "qualifiedRideTypes": eligibleRideTypes,
            "supportedRideTypes": eligibleRideTypes,
            "tierRates": tierRatesPayload(),
            "hasActiveRide": activeRide != nil,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        var driverPayload = statusPayload

        if let loc = lastLocation {
            let location: [String: Any] = [
                "lat": loc.coordinate.latitude,
                "lng": loc.coordinate.longitude,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            statusPayload["lat"] = loc.coordinate.latitude
            statusPayload["lng"] = loc.coordinate.longitude
            statusPayload["speed"] = loc.speed
            statusPayload["course"] = loc.course
            statusPayload["location"] = location
            driverPayload["location"] = location
            driverPayload["geoPoint"] = GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        }

        db.collection("driver_status").document(uid).setData(statusPayload, merge: true) { [weak self] error in
            if let error {
                DispatchQueue.main.async {
                    self?.statusMessage = "Could not update online status: \(error.localizedDescription)"
                }
            }
        }
        db.collection("drivers").document(uid).setData(driverPayload, merge: true)
    }

    private func applyVehicleEligibility(from data: [String: Any]) {
        let vehicle = data["vehicle"] as? [String: Any]
        let vehicleEligibility = vehicle.map {
            DriverVehicleEligibility.evaluate(
                make: $0["make"] as? String ?? "",
                model: $0["model"] as? String ?? "",
                year: $0["year"] as? String ?? "",
                fuelType: $0["fuelType"] as? String ?? DriverVehicleFuelType.gas.rawValue
            )
        }
        let manuallyApprovedRideTypes = normalizeRideTypes(data["approvedRideTypes"] as? [String] ?? [])
        let storedQualifiedRideTypes = data["qualifiedRideTypes"] as? [String]
            ?? data["supportedRideTypes"] as? [String]
            ?? (data["vehicleEligibility"] as? [String: Any])?["rideTypes"] as? [String]
        let legacyRideTypes = data["rideTypes"] as? [String]

        let baseRideTypes: [String]
        if let vehicleEligibility {
            baseRideTypes = vehicleEligibility.expandedEligibleRideTypes(with: manuallyApprovedRideTypes)
        } else if let storedQualifiedRideTypes, !storedQualifiedRideTypes.isEmpty {
            baseRideTypes = RydrRideTierCatalog.expandedRideTypes(
                for: storedQualifiedRideTypes + manuallyApprovedRideTypes,
                hasXLVehicle: normalizeRideTypes(storedQualifiedRideTypes).contains("Rydr XL")
            )
        } else if let legacyRideTypes, !legacyRideTypes.isEmpty {
            baseRideTypes = normalizeRideTypes(legacyRideTypes)
        } else if let vehicle = data["vehicle"] as? [String: Any] {
            let eligibility = DriverVehicleEligibility.evaluate(
                make: vehicle["make"] as? String ?? "",
                model: vehicle["model"] as? String ?? "",
                year: vehicle["year"] as? String ?? "",
                fuelType: vehicle["fuelType"] as? String ?? DriverVehicleFuelType.gas.rawValue
            )
            baseRideTypes = eligibility.eligibleRideTypes.isEmpty ? ["Rydr Go"] : eligibility.eligibleRideTypes
        } else {
            baseRideTypes = ["Rydr Go"]
        }

        let computedRideTypes = baseRideTypes.isEmpty ? ["Rydr Go"] : baseRideTypes
        eligibleRideTypes = computedRideTypes
        applyStoredRates(data["tierRates"] as? [String: Any])

        let storedSelectedRideTypes = normalizeRideTypes(data["selectedRideTypes"] as? [String] ?? data["rideTypes"] as? [String] ?? [])
        if selectedRideTypes.isEmpty, !storedSelectedRideTypes.isEmpty {
            selectedRideTypes = Set(storedSelectedRideTypes).intersection(Set(computedRideTypes))
        } else {
            selectedRideTypes = selectedRideTypes.intersection(Set(computedRideTypes))
        }
        if selectedRideTypes.isEmpty {
            selectedRideTypes = Set(computedRideTypes)
        }
        ensureDefaultRates(for: computedRideTypes)
    }

    private func normalizeRideTypes(_ rideTypes: [String]) -> [String] {
        RydrRideTierCatalog.normalizedRideTypes(rideTypes)
    }

    private func applyStoredRates(_ rawRates: [String: Any]?) {
        guard let rawRates else { return }
        var nextRates = tierRates
        var didLoadStoredRate = false
        for rideType in DriverDashboardVM.availableRideTypes {
            let key = RydrRideTierCatalog.canonicalRideType(rideType)
            let raw = rawRates[rideType] as? [String: Any] ?? rawRates[key] as? [String: Any]
            guard let raw else { continue }
            didLoadStoredRate = true
            let pricing = RydrRideTierCatalog.pricing(for: rideType)
            let perMile = Self.doubleValue(raw["perMile"]) ?? pricing.minPerMile
            let perMinute = Self.doubleValue(raw["perMinute"]) ?? pricing.minPerMinute
            nextRates[rideType] = DriverRateSetting(
                perMile: pricing.clampedPerMile(perMile),
                perMinute: pricing.clampedPerMinute(perMinute)
            )
        }
        tierRates = nextRates
        if didLoadStoredRate {
            hasSavedRateSettings = true
        }
    }

    private func ensureDefaultRates(for rideTypes: [String]) {
        for rideType in rideTypes where tierRates[rideType] == nil {
            tierRates[rideType] = .defaultValue(for: rideType)
        }
    }

    private func tierRatesPayload() -> [String: Any] {
        var payload: [String: Any] = [:]
        for rideType in eligibleRideTypes {
            let key = RydrRideTierCatalog.canonicalRideType(rideType)
            payload[key] = rate(for: rideType).dictionary(for: rideType)
        }
        return payload
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private func updateActiveRideLocation(_ location: CLLocation) {
        guard let ride = activeRide else { return }
        db.collection("rides").document(ride.id).setData([
            "driverLocation": [
                "lat": location.coordinate.latitude,
                "lng": location.coordinate.longitude,
                "speed": location.speed,
                "course": location.course,
                "updatedAt": FieldValue.serverTimestamp()
            ],
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    private static func driverMessage(for status: String) -> String {
        switch status {
        case "enRouteToPickup": return "Navigation started. Head to pickup."
        case "arrived": return "Marked arrived. Wait for the rider."
        case "inProgress": return "Trip started."
        default: return "Ride updated."
        }
    }
}

// MARK: - Main Dashboard

struct DriverDashboardView: View {
    @EnvironmentObject var session: DriverSessionManager
    @StateObject private var vm = DriverDashboardVM()
    @State private var mapPosition: MapCameraPosition = .region(DriverMapDefaults.pilotRegion)
    @State private var activeSheet: DriverDashboardSheet?

    var body: some View {
        ZStack {
            RydrDriverMapView(
                position: $mapPosition,
                filterPreferences: $vm.rideFilterPreferences,
                driverCoordinate: vm.lastLocation?.coordinate,
                isOnline: vm.isOnline,
                pendingRequests: vm.mapRideRequestBlips,
                onRecenter: recenterDriverMap
            )
            .onReceive(vm.$mapRegion) { newRegion in
                mapPosition = .region(newRegion)
            }
            .onReceive(session.$canGoOnline) { allowed in
                vm.canGoOnline = allowed
            }

            VStack(spacing: 12) {
                DriverTopBar(
                    vm: vm,
                    onFareInsights: { activeSheet = .fareInsights },
                    onNotifications: { activeSheet = .menu(.notifications) }
                )
                Spacer()
                DriverRideWorkPanel(vm: vm) { rideType in
                    activeSheet = .rideType(rideType)
                }
                if vm.isSearchingForRides {
                    OnlineSearchIndicator()
                }
                DriverGoOnlineButton(vm: vm) {
                    activeSheet = .rideFilters
                }
                DriverBottomStatusBar(vm: vm)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)

            VStack(spacing: 14) {
                Spacer()
                FloatingCircleButton(systemName: "chart.bar.fill") { activeSheet = .fareInsights }
                FloatingCircleButton(systemName: "shield.fill") { activeSheet = .menu(.safety) }
            }
            .padding(.trailing, 10)
            .padding(.bottom, 360)
            .frame(maxWidth: .infinity, alignment: .trailing)

            SideMenuView(vm: vm, isOpen: $vm.showMenu, onSelect: handleMenu(_:))
        }
        .onAppear {
            vm.startDashboard()
        }
        .sheet(item: $activeSheet, content: sheetContent(_:))
        .fullScreenCover(isPresented: Binding(
            get: { vm.activeRide != nil },
            set: { _ in }
        )) {
            if let ride = vm.activeRide {
                #if DEBUG
                DriverRideInProgressView(
                    ride: ride,
                    driverCoordinate: vm.lastLocation?.coordinate,
                    onPickup: vm.markPickupComplete,
                    onDropoff: vm.markDropoffComplete,
                    onCancel: vm.cancelActiveRide,
                    onReportIncident: { activeSheet = .menu(.safety) },
                    onSendMessage: { text in
                        try await vm.sendMessageToRider(ride: ride, text: text)
                    },
                    onDebugMoveToDestination: vm.debugMoveToActiveRideDestination,
                    onDebugMoveDriver: vm.debugMoveActiveRideDriver(to:)
                )
                #else
                DriverRideInProgressView(
                    ride: ride,
                    driverCoordinate: vm.lastLocation?.coordinate,
                    onPickup: vm.markPickupComplete,
                    onDropoff: vm.markDropoffComplete,
                    onCancel: vm.cancelActiveRide,
                    onReportIncident: { activeSheet = .menu(.safety) },
                    onSendMessage: { text in
                        try await vm.sendMessageToRider(ride: ride, text: text)
                    }
                )
                #endif
            }
        }
        .sheet(item: $vm.completedRideForRating) { ride in
            DriverEndRideView(
                ride: ride,
                onClose: vm.dismissCompletedRideRating,
                onSubmit: { rating, feedback in
                    vm.submitRiderRating(ride: ride, rating: rating, feedback: feedback)
                }
            )
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: DriverDashboardSheet) -> some View {
        switch sheet {
        case .fareInsights:
            FareInsightsView(vm: vm)
        case .rideFilters:
            DriverRideFiltersView(preferences: $vm.rideFilterPreferences) {
                activeSheet = nil
                vm.refreshMapRequestBlips()
            }
            .presentationDetents([.medium, .large])
        case .rideType(let rideType):
            RideTypeConfigurationView(
                rideType: rideType,
                isOnline: vm.isOnline,
                isEligible: vm.eligibleRideTypes.contains(rideType),
                isSelected: vm.selectedRideTypes.contains(rideType),
                hasSavedRate: vm.hasSavedRateSettings,
                rate: vm.rate(for: rideType),
                onToggle: { vm.toggleRideType(rideType) },
                onSaveRate: { perMile, perMinute in
                    vm.saveRate(rideType: rideType, perMile: perMile, perMinute: perMinute)
                }
            )
            .presentationDetents([.medium, .large])
        case .menu(let item):
            DrawerDestinationView(item: item, vm: vm)
        }
    }

    private func handleMenu(_ item: SideMenuItem) {
        withAnimation(.spring) { vm.showMenu = false }
        switch item {
        case .dashboard:
            activeSheet = nil
        case .fareInsights:
            activeSheet = .fareInsights
        case .logout:
            try? Auth.auth().signOut()
            session.isLoggedIn = false
            session.canGoOnline = false
        default:
            activeSheet = .menu(item)
        }
    }

    private func recenterDriverMap() {
        let center = vm.lastLocation?.coordinate ?? DriverMapDefaults.pilotCoordinate
        let nextRegion = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
        vm.mapRegion = nextRegion
        withAnimation(.easeInOut(duration: 0.35)) {
            mapPosition = .region(nextRegion)
        }
    }
}

#Preview {
    DriverDashboardView()
}
