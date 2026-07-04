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
    // Real Earnings Hub data, computed from completed `rides` / `rideRequests`
    // documents via DriverEarningsService — replaces all previously hardcoded
    // weekly/monthly/acceptance/completion/recent-trip values.
    @Published var earningsSummary: DriverEarningsSummary = .empty
    @Published var isLoadingEarningsSummary: Bool = false
    @Published var mapRegion: MKCoordinateRegion = DriverMapDefaults.pilotRegion
    @Published var lastLocation: CLLocation? = DriverMapDefaults.pilotLocation
    @Published var locationPermissionDenied: Bool = false
    @Published var canGoOnline: Bool = false
    @Published var selectedRideTypes: Set<String> = []
    @Published var eligibleRideTypes: [String] = ["Rydr Go"]
    @Published var tierRates: [String: DriverRateSetting] = [:]
    @Published var hasSavedRateSettings: Bool = false
    @Published var isSearchingForRides: Bool = false
    @Published var pendingRequests: [DriverRideRequest] = []
    @Published var respondingRequestIDs: Set<String> = []
    @Published var mapRideRequestBlips: [DriverRideRadarBlip] = []
    @Published var demandSnapshot = DriverDemandSnapshot()
    @Published var rideFilterPreferences = DriverRideFilterPreferences()
    @Published var activeRide: DriverActiveRide?
    @Published var isUpdatingActiveRide: Bool = false
    @Published var completedRideForRating: DriverActiveRide?
    @Published var statusMessage: String = "Ready to receive standard Rydr requests."
    @Published var profilePhotoURL: String?
    @Published var pendingProfilePhotoURL: String?
    // Vehicle Library System — generic factory-style vehicle image info, kept
    // in sync from drivers/{uid}.vehicle so it can be republished onto
    // publicDriverProfiles/{uid} for the rider app to display. Never a photo
    // of the driver's actual vehicle.
    @Published var vehicleImageURL: String?
    @Published var vehicleColor: String?
    @Published var vehicleSummaryText: String?
    @Published var vehicleDetailText: String?
    @Published var vehiclePlateText: String?
    @Published var insuranceStatus: String = "missing"
    @Published var registrationStatus: String = "missing"
    @Published var profilePhotoReviewStatus: String = "approved"
    @Published var isUploadingProfilePhoto: Bool = false
    @Published var profilePhotoMessage: String?
    @Published var accountDeletionMessage: String?
    @Published var isRequestingAccountDeletion: Bool = false
    @Published var driverNotifications: [DriverNotificationItem] = []
    @Published var unreadNotificationCount: Int = 0
    @Published var notificationErrorMessage: String?
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

    var notificationBadgeText: String {
        unreadNotificationCount > 99 ? "99+" : "\(unreadNotificationCount)"
    }

    private let locationManager = CLLocationManager()
    private var locationTimer: Timer?
    private let db = Firestore.firestore()
    private var driverListener: ListenerRegistration?
    private var requestListener: ListenerRegistration?
    private var mapRequestBlipListener: ListenerRegistration?
    private var activeRideListener: ListenerRegistration?
    private var notificationListener: ListenerRegistration?
    private var safetyPenaltyNotificationListener: ListenerRegistration?
    private var appealNotificationListener: ListenerRegistration?
    private var systemNotifications: [DriverNotificationItem] = []
    private var localNotifications: [String: DriverNotificationItem] = [:]
    private var seenPendingRideRequestIDs = Set<String>()
    private var seenDemandNotificationBuckets = Set<String>()
    private var readLocalNotificationIDs: Set<String> = []
    private let readLocalNotificationIDsKey = "rydr.driver.notifications.readLocalNotificationIDs"
    private var lastTripTelemetryAt: Date?
    private var lastTripTelemetryLocation: CLLocation?
    #if DEBUG
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
        notificationListener?.remove()
        safetyPenaltyNotificationListener?.remove()
        appealNotificationListener?.remove()
        locationTimer?.invalidate()
    }

    func startDashboard() {
        loadReadLocalNotificationIDs()
        #if DEBUG
        if shouldUseAtlantaPilotLocationInSimulator {
            applyAtlantaPilotLocation()
        }
        #endif
        requestLocationAuth()
        startObservingDriverEligibility()
        startMapRequestBlipListener()
        startActiveRideListener()
        startNotificationListeners()
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
            locationPermissionDenied = false
            locationManager.startUpdatingLocation()
        case .restricted, .denied:
            locationPermissionDenied = true
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
            locationPermissionDenied = false
            manager.startUpdatingLocation()
            statusMessage = "Location is enabled. Go online when you are ready."
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            locationPermissionDenied = true
            statusMessage = "Location access is needed to receive and complete rides."
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
            resumeStandbyIfWaiting(statusMessage: "Standby. Searching for rides.")
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
            recordDriverPresenceEvent(online: true)
        } else {
            isSearchingForRides = false
            stopPushingDriverPresence()
            stopRequestListener()
            updateDriverPresence(online: false)
            recordDriverPresenceEvent(online: false)
            pendingRequests = []
            statusMessage = "Offline. You will not receive new ride requests."
        }
    }

    func refreshMapRequestBlips() {
        startMapRequestBlipListener()
    }

    func refreshRideFilters() {
        pendingRequests = pendingRequests.filter(canPresentAssignedRequest)
        startMapRequestBlipListener()
        resumeStandbyIfWaiting()
        if isOnline {
            updateDriverPresence(online: true)
        }
    }

    #if DEBUG
    private func applyAtlantaPilotLocation() {
        lastLocation = DriverMapDefaults.pilotLocation
        mapRegion = DriverMapDefaults.pilotRegion
    }
    #endif

    func submitProfilePhotoForReview(_ image: UIImage) {
        guard Auth.auth().currentUser != nil else {
            profilePhotoMessage = "Sign in before updating your profile photo."
            return
        }

        isUploadingProfilePhoto = true
        profilePhotoMessage = nil
        profilePhotoReviewStatus = "pending"

        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await DriverImageModerationService.shared.submitProfilePhoto(image)
                await MainActor.run {
                    self.isUploadingProfilePhoto = false
                    self.pendingProfilePhotoURL = nil
                    self.profilePhotoURL = url.absoluteString
                    self.profilePhotoReviewStatus = "approved"
                    self.profilePhotoMessage = "Profile photo updated."
                }
            } catch {
                RydrCrashReporter.record(error, context: "submit_driver_profile_photo")
                await MainActor.run {
                    self.isUploadingProfilePhoto = false
                    self.pendingProfilePhotoURL = nil
                    self.profilePhotoReviewStatus = "approved"
                    self.profilePhotoMessage = error.localizedDescription
                }
            }
        }
    }

    func accept(_ request: DriverRideRequest) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard !respondingRequestIDs.contains(request.id) else { return }
        respondingRequestIDs.insert(request.id)
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
        if let ridePreferences = request.ridePreferences {
            rideData["ridePreferences"] = [
                "summaryItems": ridePreferences.summaryItems,
                "summaryText": ridePreferences.summaryText
            ]
        }
        if let pickupCoordinate = request.pickupCoordinate {
            rideData["pickupCoordinate"] = [
                "lat": pickupCoordinate.latitude,
                "lng": pickupCoordinate.longitude
            ]
            rideData["pickupGeoPoint"] = GeoPoint(latitude: pickupCoordinate.latitude, longitude: pickupCoordinate.longitude)
        }
        if let stop = request.stop?.trimmingCharacters(in: .whitespacesAndNewlines), !stop.isEmpty {
            rideData["stop"] = stop
        }
        if let stopCoordinate = request.stopCoordinate {
            rideData["stopCoordinate"] = [
                "lat": stopCoordinate.latitude,
                "lng": stopCoordinate.longitude
            ]
            rideData["stopGeoPoint"] = GeoPoint(latitude: stopCoordinate.latitude, longitude: stopCoordinate.longitude)
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

        db.runTransaction({ transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(requestRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            let data = snapshot.data() ?? [:]
            let status = (data["status"] as? String ?? "pending").lowercased()
            let acceptedDriverId = data["acceptedDriverId"] as? String ?? data["connectedDriverUid"] as? String
            let existingRideId = data["rideId"] as? String
            guard status == "pending", acceptedDriverId == nil, existingRideId == nil else {
                errorPointer?.pointee = NSError(
                    domain: "RydrDriver.AcceptRide",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "Ride no longer available."]
                )
                return nil
            }

            var transactionRideData = rideData
            Self.copyAuthoritativePricingFields(from: data, into: &transactionRideData)

            transaction.updateData([
                "status": "accepted",
                "acceptedAt": FieldValue.serverTimestamp(),
                "acceptedDriverId": uid,
                "rideId": request.id,
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: requestRef)
            transaction.setData(transactionRideData, forDocument: rideRef, merge: true)
            return transactionRideData
        }) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.respondingRequestIDs.remove(request.id)
                if let error {
                    let message = (error as NSError).code == 409
                        ? "Ride no longer available."
                        : "Could not accept ride: \(error.localizedDescription)"
                    self?.pendingRequests.removeAll { $0.id == request.id && (error as NSError).code == 409 }
                    self?.statusMessage = message
                    self?.resumeStandbyIfWaiting()
                    return
                }
                self?.pendingRequests.removeAll { $0.id == request.id }
                self?.isSearchingForRides = false
                self?.activeRide = DriverActiveRide(id: request.id, data: (result as? [String: Any]) ?? rideData)
                self?.statusMessage = "Ride accepted. Head to pickup."
                self?.updateDriverPresence(online: true)
            }
        }
    }

    private static func copyAuthoritativePricingFields(from source: [String: Any], into destination: inout [String: Any]) {
        let keys = [
            "pricingVersion",
            "fareEstimateSource",
            "fareEstimateCreatedAt",
            "driverRatePerMileCents",
            "driverRatePerMinuteCents",
            "distanceCostCents",
            "timeCostCents",
            "calculatedSubtotalCents",
            "minimumFareAdjustmentCents",
            "rideSubtotalCents",
            "bookingFeeCents",
            "estimatedRiderTotalCents",
            "estimatedDriverPayoutCents",
            "estimatedPlatformShareCents",
            "promoDiscountCents",
            "authorizedRiderChargeCents",
            "finalRiderChargeCents",
            "estimatedRiderTotal",
            "bookingFee",
            "upfrontFare",
            "estimatedFare"
        ]
        for key in keys {
            if let value = source[key] {
                destination[key] = value
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
        guard !respondingRequestIDs.contains(request.id) else { return }
        respondingRequestIDs.insert(request.id)
        db.collection("rideRequests").document(request.id).updateData([
            "status": status,
            timestampField: FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]) { [weak self] error in
            DispatchQueue.main.async {
                self?.respondingRequestIDs.remove(request.id)
                if let error {
                    self?.statusMessage = "Could not decline ride: \(error.localizedDescription)"
                    return
                }
                self?.pendingRequests.removeAll { $0.id == request.id }
                if status == "missed" {
                    self?.upsertLocalNotification(
                        DriverNotificationItem(
                            id: "missed-ride-\(request.id)",
                            type: "missed_ride_request",
                            title: "Missed ride request",
                            message: "\(request.rideType) request from \(request.pickup) expired before you accepted.",
                            createdAt: Date(),
                            isRead: false,
                            source: .local,
                            priority: .high,
                            relatedId: request.id
                        )
                    )
                }
                self?.statusMessage = message
                self?.resumeStandbyIfWaiting()
            }
        }
    }

    func startActiveRideNavigation() {
        updateActiveRideStatus(
            status: "enRouteToPickup",
            fields: [
                "navigationProvider": "rydr",
                "navigationStartedAt": FieldValue.serverTimestamp(),
                "enRouteToPickupAt": FieldValue.serverTimestamp()
            ]
        )
    }

    func markArrivedAtPickup() {
        guard let ride = activeRide else { return }
        let riderState = DriverRideLifecyclePolicy.riderState(forDriverStatus: "arrivedAtPickup")
        updateActiveRideStatus(
            status: "arrivedAtPickup",
            fields: [
                "arrivedAtPickupAt": FieldValue.serverTimestamp(),
                "pickupWaitStartedAt": FieldValue.serverTimestamp(),
                "riderRideState": riderState,
                "riderStatusMessage": "Your driver has arrived at pickup."
            ]
        )
        recordWaitTimeEvent(ride: ride, waitStage: "pickup_grace_started")
        // TODO: trigger rider push notification when notification service is available.
    }

    func markPickupPaidWaitActive() {
        guard let ride = activeRide else { return }
        updateActiveRideStatus(
            status: "arrivedAtPickup",
            fields: [
                "pickupPaidWaitStartedAt": FieldValue.serverTimestamp(),
                "pickupComplimentaryWaitSeconds": DriverActiveRide.pickupComplimentaryWaitSeconds,
                "riderRideState": DriverRideLifecyclePolicy.riderState(forDriverStatus: "arrivedAtPickup"),
                "riderStatusMessage": "Paid wait time is active."
            ]
        )
        recordWaitTimeEvent(ride: ride, waitStage: "pickup_paid_started")
    }

    func startPassengerRide() {
        guard let ride = activeRide else { return }
        let nextStatus = ride.hasAddedStop ? "navigatingToStop" : "inProgress"
        var fields: [String: Any] = [
            "rideStartedAt": FieldValue.serverTimestamp(),
            "startedAt": FieldValue.serverTimestamp(),
            "navigationProvider": "rydr",
            "riderRideState": DriverRideLifecyclePolicy.riderState(forDriverStatus: nextStatus),
            "riderStatusMessage": ride.hasAddedStop ? "Your ride is headed to the added stop." : "Your ride is headed to drop-off."
        ]
        if ride.hasAddedStop {
            fields["navigatingToStopAt"] = FieldValue.serverTimestamp()
        } else {
            fields["navigatingToDropoffAt"] = FieldValue.serverTimestamp()
        }
        updateActiveRideStatus(status: nextStatus, fields: fields)
        recordWaitTimeEvent(ride: ride, waitStage: "wait_ended")
        // TODO: trigger rider push notification when notification service is available.
    }

    func markArrivedAtStop() {
        guard let ride = activeRide else { return }
        updateActiveRideStatus(
            status: "arrivedAtStop",
            fields: [
                "arrivedAtStopAt": FieldValue.serverTimestamp(),
                "stopWaitStartedAt": FieldValue.serverTimestamp(),
                "riderRideState": DriverRideLifecyclePolicy.riderState(forDriverStatus: "arrivedAtStop"),
                "riderStatusMessage": "Your driver is waiting at the added stop."
            ]
        )
        recordWaitTimeEvent(ride: ride, waitStage: "stop_paid_started")
    }

    func headToDropoffFromStop() {
        guard let ride = activeRide else { return }
        updateActiveRideStatus(
            status: "inProgress",
            fields: [
                "headedToDropoffAt": FieldValue.serverTimestamp(),
                "navigatingToDropoffAt": FieldValue.serverTimestamp(),
                "navigationProvider": "rydr",
                "riderRideState": DriverRideLifecyclePolicy.riderState(forDriverStatus: "inProgress"),
                "riderStatusMessage": "Your ride is headed to drop-off."
            ]
        )
        recordWaitTimeEvent(ride: ride, waitStage: "wait_ended")
    }

    private func updateActiveRideStatus(status: String, fields: [String: Any]) {
        guard let ride = activeRide else { return }
        guard !isUpdatingActiveRide else { return }
        isUpdatingActiveRide = true

        var payload = fields
        payload["status"] = status
        payload["updatedAt"] = FieldValue.serverTimestamp()

        let batch = db.batch()
        let rideRef = db.collection("rides").document(ride.id)
        let requestRef = db.collection("rideRequests").document(ride.id)
        batch.setData(payload, forDocument: rideRef, merge: true)
        batch.setData(payload, forDocument: requestRef, merge: true)
        batch.commit { [weak self] error in
            DispatchQueue.main.async {
                self?.isUpdatingActiveRide = false
                if let error {
                    RydrCrashReporter.record(error, context: "update_active_ride_status_\(status)")
                    self?.statusMessage = "Could not update ride: \(error.localizedDescription)"
                    return
                }
                self?.statusMessage = Self.driverMessage(for: status)
            }
        }
    }

    /// Computes the real final fare at ride completion, using the driver's
    /// saved per-mile/per-minute rate for the ride's tier together with the
    /// actual elapsed ride time (rideStartedAt → now) rather than the
    /// pre-ride duration estimate. Trip distance still comes from the
    /// request's routed pickup→dropoff distance, since the app has no live
    /// odometer/GPS-trace distance tracking during the ride; that distance
    /// is real routing data, not a fabricated number, so this is the most
    /// accurate fare achievable without adding live distance tracking.
    /// Falls back to the original estimated fare if a rate or distance isn't
    /// available, and returns nil only if there's no usable data at all.
    private func computeFinalFare(for ride: DriverActiveRide) -> Decimal? {
        guard let distanceMiles = ride.estimatedDistanceMiles else {
            return ride.estimatedFare.map { Decimal($0) }
        }

        // tierRates/rate(for:) are keyed by the display-form ride type
        // ("Rydr Go", "Rydr XL", etc.), not the lowercase canonical form, so
        // map the ride's stored rideType onto the matching display string
        // before looking up the rate.
        let canonical = RydrRideTierCatalog.canonicalRideType(ride.rideType)
        let rideTypeKey = DriverDashboardVM.availableRideTypes.first {
            RydrRideTierCatalog.canonicalRideType($0) == canonical
        } ?? ride.rideType
        let rate = self.rate(for: rideTypeKey)

        let actualDurationMinutes: Double
        if let startedAt = ride.rideStartedAt {
            actualDurationMinutes = max(0, Date().timeIntervalSince(startedAt) / 60)
        } else {
            actualDurationMinutes = ride.estimatedDurationMinutes ?? 0
        }

        let rawFare = (distanceMiles * rate.perMile) + (actualDurationMinutes * rate.perMinute)
        guard rawFare > 0 else {
            return ride.estimatedFare.map { Decimal($0) }
        }

        let roundedFare = (rawFare * 100).rounded() / 100
        return Decimal(roundedFare)
    }

    func completeActiveRide() {
        guard let ride = activeRide else { return }
        guard !isUpdatingActiveRide else { return }
        isUpdatingActiveRide = true

        let finalFare = computeFinalFare(for: ride)

        let batch = db.batch()
        let rideRef = db.collection("rides").document(ride.id)
        let requestRef = db.collection("rideRequests").document(ride.id)
        var completionFields: [String: Any] = [
            "status": "completed",
            "completedAt": FieldValue.serverTimestamp(),
            "riderRideState": DriverRideLifecyclePolicy.riderState(forDriverStatus: "completed"),
            "riderStatusMessage": "Your ride is complete.",
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let finalFare {
            // Real final fare, computed from the actual elapsed ride time and
            // the driver's saved per-mile/per-minute rate — this is what
            // DriverEarningsService and Earnings Hub read going forward,
            // rather than only ever the pre-ride estimate.
            completionFields["fare"] = NSDecimalNumber(decimal: finalFare).doubleValue
        }
        batch.setData(completionFields, forDocument: rideRef, merge: true)
        batch.setData(completionFields, forDocument: requestRef, merge: true)
        batch.commit { [weak self] error in
            DispatchQueue.main.async {
                self?.isUpdatingActiveRide = false
                if let error {
                    RydrCrashReporter.record(error, context: "complete_active_ride")
                    self?.statusMessage = "Could not complete ride: \(error.localizedDescription)"
                    return
                }
                self?.completedRideForRating = ride
                self?.activeRide = nil
                self?.statusMessage = "Ride completed. You are ready for the next request."
                self?.resumeStandbyIfWaiting()
                self?.updateDriverPresence(online: self?.isOnline ?? false)
            }
        }
    }

    func dismissCompletedRideRating() {
        completedRideForRating = nil
        resumeStandbyIfWaiting(statusMessage: "Ride completed. You are ready for the next request.")
    }

    /// Loads real Earnings Hub data (weekly/monthly earnings, acceptance rate,
    /// completion rate, recent trips) from completed rides — call when Fare
    /// Insights is opened or pulled-to-refresh. No hardcoded fallback values.
    @MainActor
    func refreshEarningsSummary() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoadingEarningsSummary = true
        Task {
            defer { isLoadingEarningsSummary = false }
            do {
                earningsSummary = try await DriverEarningsService.shared.fetchSummary(uid: uid)
                earningsToday = earningsSummary.todayEarnings
            } catch {
                // Leave earningsSummary at its last-known value rather than
                // silently resetting to zero on a transient network error.
            }
        }
    }

    private func recordWaitTimeEvent(ride: DriverActiveRide, waitStage: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let now = Date()
        let paidWaitSeconds: Int
        let complimentaryWaitSeconds: Int

        if waitStage == "pickup_grace_started" {
            paidWaitSeconds = 0
            complimentaryWaitSeconds = Int(DriverRideLifecyclePolicy.pickupComplimentaryWaitSeconds)
        } else if waitStage == "pickup_paid_started" {
            paidWaitSeconds = DriverRideLifecyclePolicy.pickupPaidWaitSeconds(
                waitStartedAt: ride.pickupWaitStartedAt,
                paidWaitStartedAt: ride.pickupPaidWaitStartedAt,
                now: now
            )
            complimentaryWaitSeconds = Int(DriverRideLifecyclePolicy.pickupComplimentaryWaitSeconds)
        } else if waitStage == "stop_paid_started" {
            paidWaitSeconds = DriverRideLifecyclePolicy.stopPaidWaitSeconds(stopWaitStartedAt: ride.stopWaitStartedAt, now: now)
            complimentaryWaitSeconds = 0
        } else {
            if ride.normalizedStatus == "arrivedAtStop" {
                paidWaitSeconds = DriverRideLifecyclePolicy.stopPaidWaitSeconds(stopWaitStartedAt: ride.stopWaitStartedAt, now: now)
                complimentaryWaitSeconds = 0
            } else {
                paidWaitSeconds = DriverRideLifecyclePolicy.pickupPaidWaitSeconds(
                    waitStartedAt: ride.pickupWaitStartedAt,
                    paidWaitStartedAt: ride.pickupPaidWaitStartedAt,
                    now: now
                )
                complimentaryWaitSeconds = Int(DriverRideLifecyclePolicy.pickupComplimentaryWaitSeconds)
            }
        }

        let event = RydrBackendService.WaitTimeEvent(
            rideId: ride.id,
            driverId: uid,
            riderId: ride.riderId,
            waitStage: waitStage,
            complimentarySeconds: complimentaryWaitSeconds,
            paidWaitSeconds: paidWaitSeconds,
            timestamp: ISO8601DateFormatter().string(from: now)
        )

        Task {
            await RydrBackendService.recordWaitTimeEvent(event)
        }
    }

    func requestAccountDeletion() {
        guard !isRequestingAccountDeletion else { return }
        guard let user = Auth.auth().currentUser else {
            accountDeletionMessage = "Sign in before requesting account deletion."
            return
        }

        isRequestingAccountDeletion = true
        accountDeletionMessage = nil

        let request = RydrBackendService.AccountDeletionRequest(
            uid: user.uid,
            role: "driver",
            email: user.email,
            reason: nil,
            requestedAt: ISO8601DateFormatter().string(from: Date())
        )

        Task { [weak self] in
            do {
                if RydrBackendService.isConfigured {
                    try await RydrBackendService.requestAccountDeletion(request)
                }

                try await Firestore.firestore().collection("accountDeletionRequests").document(user.uid).setData([
                    "uid": user.uid,
                    "email": user.email ?? "",
                    "source": "ios-driver",
                    "status": "requested",
                    "requestedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)

                await MainActor.run {
                    self?.isRequestingAccountDeletion = false
                    self?.accountDeletionMessage = "Your account deletion request has been submitted."
                }
            } catch {
                RydrCrashReporter.record(error, context: "request_account_deletion")
                await MainActor.run {
                    self?.isRequestingAccountDeletion = false
                    self?.accountDeletionMessage = "We could not submit your request right now. Please try again."
                }
            }
        }
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
                    RydrCrashReporter.record(error, context: "submit_rider_rating")
                    self?.statusMessage = "Could not save rider rating: \(error.localizedDescription)"
                } else {
                    self?.completedRideForRating = nil
                    self?.resumeStandbyIfWaiting(statusMessage: "Thanks. Rider feedback saved.")
                }
            }
        }
    }

    func sendMessageToRider(ride: DriverActiveRide, text: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let encrypted = try DriverRideChatCrypto.encrypt(trimmed, rideId: ride.id, riderId: ride.riderId, driverId: uid)

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
            "ciphertext": encrypted.ciphertext,
            "nonce": encrypted.nonce,
            "algorithm": encrypted.algorithm,
            "keyVersion": encrypted.keyVersion,
            "recipientKeyIds": encrypted.recipientKeyIds,
            "createdAt": FieldValue.serverTimestamp(),
            "isRead": false
        ])
    }

    func recordDriverOnlyRidePreferenceNote(ride: DriverActiveRide, preferences: DriverVisibleRidePreferences) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task { [weak self] in
            do {
                try await DriverRideChatService().addDriverPrivatePreferenceNote(
                    rideId: ride.id,
                    riderId: ride.riderId,
                    driverId: uid,
                    summaryText: preferences.summaryText
                )
            } catch {
                await MainActor.run {
                    RydrCrashReporter.record(error, context: "record_driver_private_preference_note")
                    self?.statusMessage = "Preferences shown, but the driver-only note was not saved."
                }
            }
        }
    }

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
                self?.resumeStandbyIfWaiting()
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
                self.canGoOnline = DriverApprovalPolicy.isApproved(data: data)
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
                    let requests = snapshot?.documents
                        .map(DriverRideRequest.init(document:))
                        .filter { self?.canPresentAssignedRequest($0) == true } ?? []
                    self?.applyPendingRideNotifications(requests)
                    self?.pendingRequests = (self?.isOnline == true && self?.activeRide == nil) ? requests : []
                    if self?.pendingRequests.isEmpty == false {
                        self?.isSearchingForRides = false
                    } else {
                        self?.resumeStandbyIfWaiting()
                    }
                }
            }
    }

    private func stopRequestListener() {
        requestListener?.remove()
        requestListener = nil
    }

    private func startNotificationListeners() {
        notificationListener?.remove()
        safetyPenaltyNotificationListener?.remove()
        appealNotificationListener?.remove()

        guard let uid = Auth.auth().currentUser?.uid else {
            systemNotifications = []
            localNotifications = [:]
            refreshNotifications()
            return
        }

        notificationListener = db.collection("drivers")
            .document(uid)
            .collection("notifications")
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error {
                        self.notificationErrorMessage = "Notifications could not be loaded: \(error.localizedDescription)"
                        return
                    }
                    self.notificationErrorMessage = nil
                    self.systemNotifications = (snapshot?.documents ?? [])
                        .map(DriverNotificationItem.init(document:))
                    self.refreshNotifications()
                }
            }

        safetyPenaltyNotificationListener = db.collection("driverSafetyPenalties")
            .whereField("driverId", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self, error == nil else { return }
                    let penalties = (snapshot?.documents ?? []).compactMap(DriverSafetyPenalty.init(document:))
                    penalties.forEach { penalty in
                        self.upsertLocalNotification(
                            DriverNotificationItem(
                                id: "safety-penalty-\(penalty.id)",
                                type: "safety_penalty",
                                title: "Safety marker added",
                                message: "\(penalty.categoryLabel): \(penalty.description)",
                                createdAt: penalty.createdAt ?? Date(),
                                isRead: self.readLocalNotificationIDs.contains("safety-penalty-\(penalty.id)"),
                                source: .local,
                                priority: penalty.requiresInvestigationHold ? .urgent : .high,
                                relatedId: penalty.id
                            )
                        )
                    }
                }
            }

        appealNotificationListener = db.collection("driverSafetyPenaltyAppeals")
            .whereField("driverId", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self, error == nil else { return }
                    let appeals = (snapshot?.documents ?? []).compactMap(DriverPenaltyAppeal.init(document:))
                    appeals
                        .filter { $0.status.lowercased() != "submitted" }
                        .forEach { appeal in
                            self.upsertLocalNotification(
                                DriverNotificationItem(
                                    id: "appeal-decision-\(appeal.id)",
                                    type: "appeal_decision",
                                    title: "Appeal decision updated",
                                    message: "Your safety appeal status changed to \(appeal.status.replacingOccurrences(of: "_", with: " ")).",
                                    createdAt: appeal.createdAt ?? Date(),
                                    isRead: self.readLocalNotificationIDs.contains("appeal-decision-\(appeal.id)"),
                                    source: .local,
                                    priority: .high,
                                    relatedId: appeal.id
                                )
                            )
                        }
                }
            }
    }

    private func applyPendingRideNotifications(_ requests: [DriverRideRequest]) {
        for request in requests where !seenPendingRideRequestIDs.contains(request.id) {
            seenPendingRideRequestIDs.insert(request.id)
            upsertLocalNotification(
                DriverNotificationItem(
                    id: "new-ride-\(request.id)",
                    type: "new_ride_request",
                    title: "New ride request",
                    message: "\(request.rideType) request from \(request.pickup).",
                    createdAt: request.createdAt ?? Date(),
                    isRead: readLocalNotificationIDs.contains("new-ride-\(request.id)"),
                    source: .local,
                    priority: .urgent,
                    relatedId: request.id
                )
            )
        }
    }

    private func applyDemandNotification(_ demand: DriverDemandSnapshot) {
        guard demand.level == .high || demand.level == .moderate else { return }
        let levelKey = demand.level == .high ? "high" : "moderate"
        let bucket = Int(Date().timeIntervalSince1970 / 900)
        let id = "demand-\(levelKey)-\(bucket)"
        guard !seenDemandNotificationBuckets.contains(id) else { return }
        seenDemandNotificationBuckets.insert(id)
        upsertLocalNotification(
            DriverNotificationItem(
                id: id,
                type: demand.level == .high ? "demand_high" : "demand_moderate",
                title: demand.level == .high ? "High demand nearby" : "Demand building nearby",
                message: "\(demand.nearbyRequestCount) recent requests within \(Int(demand.radiusMiles.rounded())) miles. \(demand.paceText).",
                createdAt: Date(),
                isRead: readLocalNotificationIDs.contains(id),
                source: .local,
                priority: demand.level == .high ? .high : .normal
            )
        )
    }

    private func upsertLocalNotification(_ item: DriverNotificationItem) {
        var next = item
        if readLocalNotificationIDs.contains(item.id) {
            next.isRead = true
        }
        localNotifications[item.id] = next
        refreshNotifications()
    }

    private func refreshNotifications() {
        let combined = systemNotifications + Array(localNotifications.values)
        driverNotifications = combined.sorted(by: DriverNotificationItem.sort)
        unreadNotificationCount = driverNotifications.filter { !$0.isRead }.count
    }

    func markNotificationRead(_ notification: DriverNotificationItem) {
        guard !notification.isRead else { return }

        switch notification.source {
        case .system:
            guard let uid = Auth.auth().currentUser?.uid else { return }
            db.collection("drivers")
                .document(uid)
                .collection("notifications")
                .document(notification.id)
                .updateData([
                    "isRead": true,
                    "readAt": FieldValue.serverTimestamp()
                ])
        case .local:
            readLocalNotificationIDs.insert(notification.id)
            persistReadLocalNotificationIDs()
            if var existing = localNotifications[notification.id] {
                existing.isRead = true
                localNotifications[notification.id] = existing
                refreshNotifications()
            }
        }
    }

    func markAllNotificationsRead() {
        driverNotifications.forEach { markNotificationRead($0) }
    }

    private func loadReadLocalNotificationIDs() {
        let stored = UserDefaults.standard.stringArray(forKey: readLocalNotificationIDsKey) ?? []
        readLocalNotificationIDs = Set(stored)
    }

    private func persistReadLocalNotificationIDs() {
        UserDefaults.standard.set(Array(readLocalNotificationIDs), forKey: readLocalNotificationIDsKey)
    }

    private func startMapRequestBlipListener() {
        mapRequestBlipListener?.remove()
        #if DEBUG && targetEnvironment(simulator)
        mapRideRequestBlips = simulatorRadarBlips()
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
                        self.mapRideRequestBlips = self.simulatorRadarBlips()
                        #endif
                        return
                    }

                    var liveRequests = snapshot?.documents
                        .map(DriverRideRequest.init(document:)) ?? []
                    #if DEBUG && targetEnvironment(simulator)
                    liveRequests += self.simulatorTestRideRequests()
                    #endif
                    let demand = self.demandSnapshot(from: liveRequests)
                    self.demandSnapshot = demand
                    self.applyDemandNotification(demand)

                    let visibleRequests = liveRequests
                        .filter { request in
                            self.canShowRadarBlip(for: request)
                        }
                    #if DEBUG && targetEnvironment(simulator)
                    self.mapRideRequestBlips = self.mergedMapBlips(
                        self.privacySafeRadarBlips(from: visibleRequests) + self.simulatorRadarBlips()
                    )
                    #else
                    self.mapRideRequestBlips = self.privacySafeRadarBlips(from: visibleRequests)
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

    private func simulatorRadarBlips() -> [DriverRideRadarBlip] {
        simulatorTestRideRequests().compactMap { request in
            guard let pickupCoordinate = request.pickupCoordinate else { return nil }
            return DriverRideRadarBlip(
                id: request.id,
                coordinate: fuzzedRadarCoordinate(for: request.id, pickupCoordinate: pickupCoordinate),
                expiresAt: Date().addingTimeInterval(60 * 60)
            )
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

    private func demandSnapshot(from requests: [DriverRideRequest]) -> DriverDemandSnapshot {
        let radiusMiles = 5.0
        let driverCoordinate = lastLocation?.coordinate ?? mapRegion.center
        let driverLocation = CLLocation(latitude: driverCoordinate.latitude, longitude: driverCoordinate.longitude)
        let selected = Set(selectedRideTypes.map(RydrRideTierCatalog.canonicalRideType))
        let eligible = Set(eligibleRideTypes.map(RydrRideTierCatalog.canonicalRideType))

        let nearbyRequests = requests.filter { request in
            guard let pickupCoordinate = request.pickupCoordinate else { return false }
            let rideType = RydrRideTierCatalog.canonicalRideType(request.rideType)
            guard eligible.contains(rideType) else { return false }
            guard selected.isEmpty || selected.contains(rideType) else { return false }

            let pickupLocation = CLLocation(latitude: pickupCoordinate.latitude, longitude: pickupCoordinate.longitude)
            let pickupMiles = driverLocation.distance(from: pickupLocation) / 1609.344
            return pickupMiles <= radiusMiles
        }

        let level: DriverDemandLevel
        let paceText: String
        switch nearbyRequests.count {
        case 3...:
            level = .high
            paceText = "1-3 min since last request"
        case 1...2:
            level = .moderate
            paceText = "3-5 min since last request"
        default:
            level = .low
            paceText = "5+ min since last request"
        }

        return DriverDemandSnapshot(
            level: level,
            paceText: paceText,
            nearbyRequestCount: nearbyRequests.count,
            radiusMiles: radiusMiles
        )
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
        let routeProgress = projectedRouteProgress(
            point: dropoffCoordinate,
            start: driverCoordinate,
            end: destinationCoordinate
        )
        guard routeProgress >= 0, routeProgress <= 1 else { return false }

        let destinationLocation = CLLocation(latitude: destinationCoordinate.latitude, longitude: destinationCoordinate.longitude)
        let pickupToDestinationMiles = pickupLocation.distance(from: destinationLocation) / 1609.344
        let dropoffLocation = CLLocation(latitude: dropoffCoordinate.latitude, longitude: dropoffCoordinate.longitude)
        let dropoffToDestinationMiles = dropoffLocation.distance(from: destinationLocation) / 1609.344
        let corridorMiles = distanceFromPointToSegmentMiles(
            point: dropoffCoordinate,
            start: driverCoordinate,
            end: destinationCoordinate
        )

        return dropoffToDestinationMiles <= pickupToDestinationMiles
            && corridorMiles <= rideFilterPreferences.destinationCorridor.miles
    }

    private func canPresentAssignedRequest(_ request: DriverRideRequest) -> Bool {
        let eligible = Set(eligibleRideTypes.map(RydrRideTierCatalog.canonicalRideType))
        guard eligible.contains(RydrRideTierCatalog.canonicalRideType(request.rideType)) else { return false }

        let selected = Set(selectedRideTypes.map(RydrRideTierCatalog.canonicalRideType))
        guard selected.isEmpty || selected.contains(RydrRideTierCatalog.canonicalRideType(request.rideType)) else { return false }

        guard rideFilterPreferences.workZoneEnabled || rideFilterPreferences.hasDestinationFilter else { return true }
        return matchesRideFilters(request)
    }

    private func projectedRouteProgress(
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
        guard dx != 0 || dy != 0 else { return 0 }
        return ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)
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
            .whereField("status", in: ["accepted", "enRouteToPickup", "navigatingToPickup", "arrived", "arrivedAtPickup", "waitingForRider", "inProgress", "navigatingToStop", "arrivedAtStop", "waitingAtStop"])
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard error == nil else {
                        self?.statusMessage = "Active ride listener error: \(error?.localizedDescription ?? "Unknown error")"
                        return
                    }
                    guard let doc = snapshot?.documents.first else {
                        self?.activeRide = nil
                        self?.resumeStandbyIfWaiting()
                        return
                    }
                    self?.activeRide = DriverActiveRide(id: doc.documentID, data: doc.data())
                    self?.isSearchingForRides = false
                }
            }
    }

    private func resumeStandbyIfWaiting(statusMessage: String? = nil) {
        if let statusMessage {
            self.statusMessage = statusMessage
        }

        guard isOnline else {
            isSearchingForRides = false
            return
        }

        isSearchingForRides = activeRide == nil && pendingRequests.isEmpty
    }

    private func publishDriverProfile() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let user = Auth.auth().currentUser
        let displayName = user?.displayName ?? "Rydr Driver"
        db.collection("drivers").document(uid).setData([
            "uid": uid,
            "displayName": displayName,
            "email": user?.email ?? "",
            "standardDispatchEnabled": true,
            "qualifiedRideTypes": eligibleRideTypes,
            "supportedRideTypes": eligibleRideTypes,
            "selectedRideTypes": Array(selectedRideTypes).sorted(),
            "rideTypes": Array(selectedRideTypes).sorted(),
            "tierRates": tierRatesPayload(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        publishPublicDriverProfile(uid: uid, displayName: displayName, online: isOnline)
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
        let filterPayload = rideFilterPayload()
        statusPayload["rideFilters"] = filterPayload
        driverPayload["rideFilters"] = filterPayload

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
        publishPublicDriverProfile(uid: uid, displayName: Auth.auth().currentUser?.displayName ?? "Rydr Driver", online: online)
    }

    private func recordDriverPresenceEvent(online: Bool) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("driverPresenceEvents").addDocument(data: [
            "driverId": uid,
            "isOnline": online,
            "availabilityStatus": online ? "available" : "offline",
            "selectedRideTypes": Array(selectedRideTypes).sorted(),
            "hasActiveRide": activeRide != nil,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    private func publishPublicDriverProfile(uid: String, displayName: String, online: Bool) {
        var payload: [String: Any] = [
            "uid": uid,
            "displayName": displayName,
            "profilePhotoURL": profilePhotoURL ?? "",
            "vehicleSummary": vehicleSummaryText ?? publicVehicleSummary(),
            // Generic factory-style vehicle image (Vehicle Library System) —
            // never a photo of the driver's actual car. Riders see this in
            // place of a vehicle photo upload.
            "vehicleImageURL": vehicleImageURL ?? "",
            "vehicleColor": vehicleColor ?? "",
            "isOnline": online,
            "eligibleRideTypes": Array(selectedRideTypes).sorted(),
            "tierRates": tierRatesPayload(),
            "rideFilters": rideFilterPayload(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let loc = lastLocation {
            payload["approximateLocation"] = [
                "lat": roundedCoordinate(loc.coordinate.latitude),
                "lng": roundedCoordinate(loc.coordinate.longitude),
                "updatedAt": FieldValue.serverTimestamp()
            ]
        }

        db.collection("publicDriverProfiles").document(uid).setData(payload, merge: true)
    }

    private func publicVehicleSummary() -> String {
        let selected = selectedRideTypes.sorted().first
        return selected ?? "Rydr vehicle"
    }

    private func roundedCoordinate(_ value: CLLocationDegrees) -> Double {
        (value * 1000).rounded() / 1000
    }

    /// `vehicle.year` is written by the `submitVehicleVin` Cloud Function as
    /// NHTSA's decoded `modelYear`, a number — not the String the old
    /// manual-entry form used to write. Handles both so eligibility/summary
    /// text keep working regardless of which form wrote the record.
    private static func vehicleYearString(_ raw: Any?) -> String {
        if let year = raw as? String { return year }
        if let year = raw as? Int { return String(year) }
        if let year = raw as? NSNumber { return year.stringValue }
        return ""
    }

    private func applyVehicleEligibility(from data: [String: Any]) {
        let vehicle = data["vehicle"] as? [String: Any]

        // Vehicle Library System fields, written server-side by the
        // `submitVehicleVin` Cloud Function (see VehicleLibraryClient.swift /
        // VehicleInfoView.swift). Mirrored here so they can be republished
        // onto publicDriverProfiles/{uid} for the rider app.
        vehicleImageURL = vehicle?["imageUrl"] as? String
        vehicleColor = vehicle?["color"] as? String
        if let vehicle {
            let make = vehicle["make"] as? String ?? ""
            let model = vehicle["model"] as? String ?? ""
            let year = Self.vehicleYearString(vehicle["year"])
            let summary = [year, make, model].filter { !$0.isEmpty }.joined(separator: " ")
            vehicleSummaryText = summary.isEmpty ? nil : summary
            vehiclePlateText = vehicle["plate"] as? String
            let trim = vehicle["trim"] as? String
            let bodyStyle = vehicle["bodyStyle"] as? String
            vehicleDetailText = [trim, bodyStyle].compactMap { value in
                guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return value
            }.joined(separator: " ")
            if vehicleDetailText?.isEmpty == true {
                vehicleDetailText = nil
            }
        } else {
            vehicleSummaryText = nil
            vehicleDetailText = nil
            vehiclePlateText = nil
        }
        insuranceStatus = data["insuranceStatus"] as? String ?? "missing"
        registrationStatus = data["registrationStatus"] as? String ?? "missing"

        let vehicleEligibility = vehicle.map {
            DriverVehicleEligibility.evaluate(
                make: $0["make"] as? String ?? "",
                model: $0["model"] as? String ?? "",
                year: Self.vehicleYearString($0["year"]),
                fuelType: $0["fuelType"] as? String ?? DriverVehicleFuelType.gas.rawValue
            )
        }
        let manuallyApprovedRideTypes = normalizeRideTypes(data["approvedRideTypes"] as? [String] ?? [])
        let storedQualifiedRideTypes = data["qualifiedRideTypes"] as? [String]
            ?? data["supportedRideTypes"] as? [String]
            ?? (data["vehicleEligibility"] as? [String: Any])?["rideTypes"] as? [String]
        let legacyRideTypes = data["rideTypes"] as? [String]

        let baseRideTypes: [String]
        if let storedQualifiedRideTypes, !storedQualifiedRideTypes.isEmpty {
            baseRideTypes = RydrRideTierCatalog.expandedRideTypes(
                for: storedQualifiedRideTypes + manuallyApprovedRideTypes,
                hasXLVehicle: normalizeRideTypes(storedQualifiedRideTypes).contains("Rydr XL")
            )
        } else if let vehicleEligibility {
            baseRideTypes = vehicleEligibility.expandedEligibleRideTypes(with: manuallyApprovedRideTypes)
        } else if let legacyRideTypes, !legacyRideTypes.isEmpty {
            baseRideTypes = normalizeRideTypes(legacyRideTypes)
        } else if let vehicle = data["vehicle"] as? [String: Any] {
            let eligibility = DriverVehicleEligibility.evaluate(
                make: vehicle["make"] as? String ?? "",
                model: vehicle["model"] as? String ?? "",
                year: Self.vehicleYearString(vehicle["year"]),
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

    private func rideFilterPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "workZoneEnabled": rideFilterPreferences.workZoneEnabled,
            "workZoneRadiusMiles": rideFilterPreferences.effectivePickupMiles,
            "destinationModeEnabled": rideFilterPreferences.hasDestinationFilter,
            "destinationText": rideFilterPreferences.destinationText,
            "destinationCorridorMiles": rideFilterPreferences.destinationCorridor.miles
        ]

        if let destination = rideFilterPreferences.destinationCoordinate {
            payload["destinationCoordinate"] = [
                "lat": destination.latitude,
                "lng": destination.longitude
            ]
            payload["destinationGeoPoint"] = GeoPoint(latitude: destination.latitude, longitude: destination.longitude)
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
        recordTripTelemetryIfNeeded(ride: ride, location: location)
    }

    private func recordTripTelemetryIfNeeded(ride: DriverActiveRide, location: CLLocation) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let now = Date()
        let movedMeters = lastTripTelemetryLocation?.distance(from: location) ?? .greatestFiniteMagnitude
        if let lastTripTelemetryAt, now.timeIntervalSince(lastTripTelemetryAt) < 30, movedMeters < 100 {
            return
        }

        lastTripTelemetryAt = now
        lastTripTelemetryLocation = location

        db.collection("rides").document(ride.id).collection("telemetry").addDocument(data: [
            "rideId": ride.id,
            "driverId": uid,
            "riderId": ride.riderId,
            "status": ride.status,
            "lat": location.coordinate.latitude,
            "lng": location.coordinate.longitude,
            "speed": location.speed,
            "course": location.course,
            "horizontalAccuracy": location.horizontalAccuracy,
            "recordedAt": FieldValue.serverTimestamp()
        ])
    }

    private static func driverMessage(for status: String) -> String {
        switch status {
        case "enRouteToPickup", "navigatingToPickup": return "Navigation started. Head to pickup."
        case "arrived", "arrivedAtPickup", "waitingForRider": return "Waiting for rider. They have been notified that you arrived."
        case "navigatingToStop": return "Trip started. Navigate to the added stop."
        case "arrivedAtStop", "waitingAtStop": return "Waiting at stop. Paid wait time is active."
        case "inProgress", "navigatingToDropoff": return "Trip started. Navigate to drop-off."
        case "completed": return "Ride completed. You are ready for the next request."
        default: return "Ride updated."
        }
    }
}

// MARK: - Main Dashboard

private struct DashboardLayoutMetrics {
    let size: CGSize

    var compactHeight: Bool { size.height < 760 }
    var narrowWidth: Bool { size.width < 380 }

    var horizontalPadding: CGFloat { narrowWidth ? 12 : 16 }
    var bottomDockHeight: CGFloat { compactHeight ? 72 : 78 }
    var bottomDockLift: CGFloat { compactHeight ? 58 : 72 }
    var bottomDockClearance: CGFloat { bottomDockHeight + bottomDockLift + 18 }
    var floatingPanelBottomPadding: CGFloat { bottomDockClearance + (compactHeight ? 8 : 12) }
    var sideButtonSpacing: CGFloat { compactHeight ? 10 : 14 }
    var sideControlsBottomPadding: CGFloat { bottomDockClearance + (compactHeight ? 100 : 124) }
    var recenterButtonBottomPadding: CGFloat { bottomDockClearance + (compactHeight ? 126 : 150) }
    var workZoneControlBottomPadding: CGFloat { bottomDockClearance + 10 }
    var contentBottomPadding: CGFloat { compactHeight ? 8 : 12 }
}

struct DriverDashboardView: View {
    @EnvironmentObject var session: DriverSessionManager
    @StateObject private var vm = DriverDashboardVM()
    @State private var mapPosition: MapCameraPosition = .region(DriverMapDefaults.pilotRegion)
    @State private var activeSheet: DriverDashboardSheet?

    var body: some View {
        GeometryReader { proxy in
            let metrics = DashboardLayoutMetrics(size: proxy.size)

            ZStack {
                RydrDriverMapView(
                    position: $mapPosition,
                    filterPreferences: $vm.rideFilterPreferences,
                    driverCoordinate: vm.lastLocation?.coordinate,
                    isOnline: vm.isOnline,
                    pendingRequests: vm.mapRideRequestBlips,
                    recenterButtonBottomPadding: metrics.recenterButtonBottomPadding,
                    workZoneControlBottomPadding: metrics.workZoneControlBottomPadding,
                    onRecenter: recenterDriverMap
                )
                .onReceive(vm.$mapRegion) { newRegion in
                    mapPosition = .region(newRegion)
                }
                .onReceive(session.$canGoOnline) { allowed in
                    vm.canGoOnline = allowed
                }
                .onChange(of: vm.rideFilterPreferences) { _, _ in
                    vm.refreshRideFilters()
                }

                DriverTopBar(
                    vm: vm,
                    buttonSize: metrics.compactHeight ? 40 : 42,
                    isCompact: metrics.compactHeight,
                    onFareInsights: { activeSheet = .fareInsights },
                    onNotifications: { activeSheet = .menu(.notifications) }
                )
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.compactHeight ? 6 : 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if vm.locationPermissionDenied {
                    DriverLocationPermissionBanner()
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.top, metrics.compactHeight ? 62 : 68)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }

                VStack(spacing: metrics.compactHeight ? 8 : 12) {
                    DriverRideWorkPanel(vm: vm) { rideType in
                        activeSheet = .rideType(rideType)
                    }

                    if vm.isSearchingForRides {
                        OnlineSearchIndicator(demand: vm.demandSnapshot)
                            .padding(.bottom, metrics.contentBottomPadding)
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.bottom, metrics.floatingPanelBottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                VStack(spacing: metrics.sideButtonSpacing) {
                    FloatingCircleButton(systemName: "chart.bar.fill") { activeSheet = .fareInsights }
                    FloatingCircleButton(systemName: "shield.fill") { activeSheet = .menu(.safety) }
                }
                .padding(.trailing, metrics.horizontalPadding - 6)
                .padding(.bottom, metrics.sideControlsBottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

                SideMenuView(vm: vm, isOpen: $vm.showMenu, onSelect: handleMenu(_:))

                DriverDashboardActionDock(
                    vm: vm,
                    isCompact: metrics.compactHeight || metrics.narrowWidth,
                    onFiltersTapped: { activeSheet = .rideFilters },
                    onRateCardTapped: { openPrimaryRateCard() },
                    onCashHubTapped: { activeSheet = .menu(.community) },
                    onProfileTapped: { activeSheet = .menu(.profile) }
                )
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, 4)
                .padding(.bottom, metrics.bottomDockLift)
                .background(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            vm.startDashboard()
        }
        .sheet(item: $activeSheet, content: sheetContent(_:))
        .fullScreenCover(isPresented: Binding(
            get: { vm.activeRide != nil },
            set: { _ in }
        )) {
            if let ride = vm.activeRide {
                DriverRideInProgressView(
                    ride: ride,
                    currentDriverId: Auth.auth().currentUser?.uid ?? "",
                    driverCoordinate: vm.lastLocation?.coordinate,
                    driverSpeedMetersPerSecond: vm.lastLocation?.speed,
                    isUpdatingRide: vm.isUpdatingActiveRide,
                    onStartNavigation: vm.startActiveRideNavigation,
                    onArrivedAtPickup: vm.markArrivedAtPickup,
                    onStartRide: vm.startPassengerRide,
                    onArrivedAtStop: vm.markArrivedAtStop,
                    onHeadToDropoff: vm.headToDropoffFromStop,
                    onCompleteRide: vm.completeActiveRide,
                    onPickupPaidWaitStarted: vm.markPickupPaidWaitActive,
                    onCancel: vm.cancelActiveRide,
                    onReportIncident: { activeSheet = .menu(.safety) },
                    onRidePreferencesDismissed: { preferences in
                        vm.recordDriverOnlyRidePreferenceNote(ride: ride, preferences: preferences)
                    },
                    onSendMessage: { text in
                        try await vm.sendMessageToRider(ride: ride, text: text)
                    }
                )
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
            EarningsHubView(vm: vm)
        case .rideFilters:
            DriverRideFiltersView(preferences: $vm.rideFilterPreferences) {
                activeSheet = nil
                vm.refreshRideFilters()
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
            session.logout()
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

    private func openPrimaryRateCard() {
        let selected = vm.selectedRideTypes.sorted(by: tierSort).first
        let eligible = vm.eligibleRideTypes.sorted(by: tierSort).first
        activeSheet = .rideType(selected ?? eligible ?? "Rydr Go")
    }

    private func tierSort(_ lhs: String, _ rhs: String) -> Bool {
        let ordered = DriverDashboardVM.availableRideTypes
        return (ordered.firstIndex(of: lhs) ?? ordered.endIndex) < (ordered.firstIndex(of: rhs) ?? ordered.endIndex)
    }
}

#Preview("Driver Dashboard - SE") {
    DriverDashboardView()
        .environmentObject(DriverSessionManager())
}

#Preview("Driver Dashboard - Standard") {
    DriverDashboardView()
        .environmentObject(DriverSessionManager())
}

#Preview("Driver Dashboard - Pro") {
    DriverDashboardView()
        .environmentObject(DriverSessionManager())
}

#Preview("Driver Dashboard - Pro Max") {
    DriverDashboardView()
        .environmentObject(DriverSessionManager())
}
