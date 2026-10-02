const { admin, getFirestore } = require("../config/firebase");

const ACTIVE_RIDE_STATUSES = new Set([
  "accepted",
  "enRouteToPickup",
  "navigatingToPickup",
  "arrivedAtPickup",
  "inProgress",
  "navigatingToStop",
  "arrivedAtStop",
  "navigatingToDropoff"
]);

function error(message, statusCode) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function isApprovedDriver(driver) {
  const approvalStatus = String(driver?.driverApprovalStatus ?? driver?.approvalStatus ?? "pending").toLowerCase();
  const approved = approvalStatus === "approved" || driver?.isApproved === true;
  const accountStatus = String(driver?.accountStatus ?? "").toLowerCase();
  const safetyReviewStatus = String(driver?.safetyReviewStatus ?? "").toLowerCase();
  const safetySuspended = ["suspended", "deletion_requested", "removed"].includes(accountStatus)
    || safetyReviewStatus === "suspended"
    || driver?.safetyHold === true;
  return approved && !safetySuspended;
}

function normalizedRideTypes(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => String(item).trim()).filter(Boolean))].slice(0, 10);
}

function normalizedLocation(value) {
  if (!value || typeof value !== "object") return null;
  const lat = Number(value.lat ?? value.latitude);
  const lng = Number(value.lng ?? value.longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  const location = { lat, lng };
  const speed = Number(value.speed);
  const course = Number(value.course);
  if (Number.isFinite(speed)) location.speed = speed;
  if (Number.isFinite(course)) location.course = course;
  return location;
}

async function activeRideForDriver(db, uid) {
  const snapshot = await db.collection("rides").where("driverId", "==", uid).limit(50).get();
  return snapshot.docs.find((doc) => {
    const ride = doc.data();
    return ACTIVE_RIDE_STATUSES.has(ride.status) && ride.driverQueueStatus !== "queued";
  }) || null;
}

async function updateDriverPresence({ uid, online, selectedRideTypes, location }) {
  if (typeof online !== "boolean") throw error("online must be a boolean", 400);
  const db = getFirestore();
  const driverRef = db.collection("drivers").doc(uid);
  const statusRef = db.collection("driver_status").doc(uid);
  const publicRef = db.collection("publicDriverProfiles").doc(uid);
  const cashHubRef = db.collection("cashHubDriverProfiles").doc(uid);
  const cashHubEligibilityRef = db.collection("cashHubDriverEligibility").doc(uid);
  const [driverSnap, cashHubConfigSnap] = await Promise.all([
    driverRef.get(),
    db.collection("platformConfig").doc("cashRydrHub").get()
  ]);
  if (!driverSnap.exists) throw error("Driver profile not found", 404);

  const driver = driverSnap.data();
  if (online && !isApprovedDriver(driver)) {
    throw error("Driver approval and safety eligibility are required to go online", 403);
  }

  const requestedRideTypes = normalizedRideTypes(selectedRideTypes);
  const storedQualifiedTypes = normalizedRideTypes(driver.qualifiedRideTypes ?? driver.supportedRideTypes ?? driver.eligibleRideTypes);
  const allowedTypes = new Set(storedQualifiedTypes);
  const effectiveRideTypes = requestedRideTypes.filter((type) => allowedTypes.size === 0 || allowedTypes.has(type));
  if (online && effectiveRideTypes.length === 0) {
    throw error("At least one qualified ride type is required to go online", 409);
  }

  const activeRide = await activeRideForDriver(db, uid);
  const hasActiveRide = Boolean(activeRide);
  const availabilityStatus = online ? (hasActiveRide ? "onCurrentRide" : "available") : "offline";
  const now = admin.firestore.Timestamp.now();
  const cleanLocation = normalizedLocation(location);
  const common = {
    online,
    isOnline: online,
    availabilityStatus,
    hasActiveRide,
    selectedRideTypes: effectiveRideTypes,
    rideTypes: effectiveRideTypes,
    updatedAt: now
  };
  const privatePresence = {
    ...common,
    qualifiedRideTypes: storedQualifiedTypes,
    supportedRideTypes: storedQualifiedTypes,
    tierRates: driver.tierRates || {},
    rideFilters: driver.rideFilters || {},
    autoAcceptQueuedRides: driver.autoAcceptQueuedRides === true
  };
  if (cleanLocation) {
    Object.assign(privatePresence, {
      lat: cleanLocation.lat,
      lng: cleanLocation.lng,
      speed: cleanLocation.speed ?? null,
      course: cleanLocation.course ?? null,
      location: { lat: cleanLocation.lat, lng: cleanLocation.lng, updatedAt: now }
    });
  }

  const publicPresence = {
    uid,
    isOnline: online,
    availabilityStatus,
    hasActiveRide,
    eligibleRideTypes: effectiveRideTypes,
    updatedAt: now
  };
  const cashHubConfig = cashHubConfigSnap.exists ? cashHubConfigSnap.data() : {};
  const currentTermsVersion = String(cashHubConfig.cashHubTermsVersion || "legacy");
  const acceptedTermsVersion = String(driver.cashHubTermsVersion || "");
  const cashHubAccessActive = cashHubConfig.termsAcceptanceEnabled === true
    && driver.cashHubTermsAccepted === true
    && driver.cashHubOptedOut !== true
    && !["delinquent", "past_due", "review_required", "suspended", "revoked", "optedout", "opted_out"].includes(String(driver.cashHubAccessStatus || "").toLowerCase())
    && (acceptedTermsVersion === currentTermsVersion || (!acceptedTermsVersion && currentTermsVersion === "legacy"));
  const vehicle = driver.vehicle || {};
  const cashHubPresence = {
    driverUid: uid,
    driverName: String(driver.displayName || [driver.firstName, driver.lastName].filter(Boolean).join(" ") || "Cash Hub Driver").trim(),
    profilePhotoURL: driver.profilePhotoURL || driver.photoURL || "",
    vehicleInfo: [vehicle.color, vehicle.year, vehicle.make, vehicle.model].filter(Boolean).join(" "),
    cashHubRating: Number(driver.cashHubRating ?? driver.rating ?? 5),
    isIdentityVerified: driver.identityVerified === true || driver.stripeIdentityStatus === "verified",
    isLicenseVerified: driver.isLicenseVerified === true || driver.driverLicenseStatus === "approved",
    isRydrVerifiedDriver: isApprovedDriver(driver),
    isOnline: online && cashHubAccessActive,
    availabilityStatus: online && cashHubAccessActive ? availabilityStatus : "offline",
    projectionOwner: "rydr_backend",
    updatedAt: now
  };
  if (cleanLocation) {
    publicPresence.approximateLocation = {
      lat: Math.round(cleanLocation.lat * 1000) / 1000,
      lng: Math.round(cleanLocation.lng * 1000) / 1000,
      updatedAt: now
    };
  }
  const cashHubEligibility = {
    driverUid: uid,
    isOnline: cashHubPresence.isOnline,
    availabilityStatus: cashHubPresence.availabilityStatus,
    approximateLocation: publicPresence.approximateLocation || null,
    updatedAt: now,
    projectionOwner: "rydr_backend"
  };

  const previousStatusSnap = await statusRef.get();
  const previousOnline = previousStatusSnap.exists ? previousStatusSnap.data().isOnline === true : null;
  const batch = db.batch();
  batch.set(statusRef, privatePresence, { merge: true });
  batch.set(driverRef, { ...common, location: privatePresence.location || driver.location || null }, { merge: true });
  batch.set(publicRef, publicPresence, { merge: true });
  batch.set(cashHubRef, cashHubPresence, { merge: true });
  batch.set(cashHubEligibilityRef, cashHubEligibility, { merge: true });
  if (previousOnline !== online) {
    batch.set(db.collection("driverPresenceEvents").doc(), {
      driverId: uid,
      isOnline: online,
      availabilityStatus,
      selectedRideTypes: effectiveRideTypes,
      hasActiveRide,
      createdAt: now,
      recordedBy: "rydr-backend"
    });
  }
  await batch.commit();

  return { online, availabilityStatus, hasActiveRide, selectedRideTypes: effectiveRideTypes };
}

module.exports = { updateDriverPresence, isApprovedDriver, normalizedLocation, normalizedRideTypes };
