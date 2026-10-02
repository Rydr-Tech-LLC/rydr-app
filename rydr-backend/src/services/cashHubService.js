const { admin, getFirestore } = require("../config/firebase");
const { isApprovedDriver } = require("./driverPresenceService");
const { getDirections } = require("./appleMapsService");

const PUBLIC_VISIBILITY = "Public CashRydr Hub Community";
const FAVORITES_VISIBILITY = "Favorite Drivers";
const VALID_VISIBILITIES = new Set([PUBLIC_VISIBILITY, FAVORITES_VISIBILITY]);
// CashRydr Hub is an independent, pre-arranged marketplace. These values
// describe the arrangement, not a Rydr Dispatch service tier.
const VALID_TRIP_FORMATS = new Set(["One-way", "Round trip", "Scheduled", "Flexible"]);
const MINIMUM_LEAD_TIME_MS = 2 * 60 * 60 * 1000;
const TERMINAL_CONVERSATION_STATUSES = new Set(["cancelled", "completed", "declined", "ended", "expired", "released", "removed", "unavailable"]);
const BLOCKED_ACCESS_STATUSES = new Set(["delinquent", "past_due", "review_required", "suspended", "revoked", "optedout", "opted_out"]);
const DRIVER_QUEUE_TRANSITIONS = {
  scheduled: new Set(["confirmed", "arrived"]),
  confirmed: new Set(["arrived"]),
  arrived: new Set(["started"]),
  started: new Set(["completed"])
};
const CASH_HUB_FEE_CENTS = 499;
const CASH_HUB_GRACE_DAYS = 5;
const CASH_HUB_TIME_ZONE = "America/New_York";
const CASH_HUB_AUDIENCE_LIMIT = 100;
const CASH_HUB_PUBLIC_RADIUS_MILES = 50;
const CASH_HUB_SUGGESTED_PER_MILE = 0.90;
const CASH_HUB_SUGGESTED_PER_MINUTE = 0.28;

function error(message, statusCode) { const err = new Error(message); err.statusCode = statusCode; return err; }
function text(value, max = 500) { return typeof value === "string" ? value.trim().slice(0, max) : ""; }
function amount(value) { const n = Number(value); return Number.isFinite(n) && n > 0 ? Math.round(n * 100) / 100 : null; }
function idempotencyKey(value) {
  const candidate = text(value, 160);
  return /^[A-Za-z0-9_-]{8,160}$/.test(candidate) ? candidate : null;
}
function coordinate(value) {
  if (!value || typeof value !== "object") return null;
  const latitude = Number(value.latitude ?? value.lat);
  const longitude = Number(value.longitude ?? value.lng);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
  return { latitude, longitude };
}
function distanceMilesBetween(a, b) {
  const first = coordinate(a); const second = coordinate(b);
  if (!first || !second) return null;
  const radians = (degrees) => degrees * Math.PI / 180;
  const dLat = radians(second.latitude - first.latitude);
  const dLng = radians(second.longitude - first.longitude);
  const lat1 = radians(first.latitude); const lat2 = radians(second.latitude);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 3958.7613 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}
function suggestedContribution(distanceMiles, durationMinutes) {
  const miles = Number(distanceMiles); const minutes = Number(durationMinutes);
  if (!Number.isFinite(miles) || miles < 0 || !Number.isFinite(minutes) || minutes < 0) return null;
  return Math.round((miles * CASH_HUB_SUGGESTED_PER_MILE + minutes * CASH_HUB_SUGGESTED_PER_MINUTE) * 100) / 100;
}
function date(value) { const d = new Date(value); return Number.isFinite(d.getTime()) ? admin.firestore.Timestamp.fromDate(d) : null; }
function timestampMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.toDate === "function") return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  return null;
}
function billingPeriod(now = new Date()) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: CASH_HUB_TIME_ZONE,
    year: "numeric",
    month: "2-digit"
  }).formatToParts(now);
  const year = parts.find((part) => part.type === "year")?.value;
  const month = parts.find((part) => part.type === "month")?.value;
  return `${year}-${month}`;
}
function normalizeVisibility(value, fallback = PUBLIC_VISIBILITY) {
  const candidate = text(value, 80) || fallback;
  if (!VALID_VISIBILITIES.has(candidate)) throw error("Invalid Cash Rydr Hub visibility", 400);
  return candidate;
}
function normalizeTripFormat(value) {
  const candidate = text(value, 80) || "One-way";
  if (!VALID_TRIP_FORMATS.has(candidate)) throw error("Invalid CashRydr Hub trip format", 400);
  return candidate;
}
function driverCanAccessRequest(request, driverUid) {
  if (!request || request.status !== "open") return false;
  if (request.visibility === PUBLIC_VISIBILITY) {
    return !Array.isArray(request.eligibleDriverUids) || request.eligibleDriverUids.includes(driverUid);
  }
  return request.visibility === FAVORITES_VISIBILITY
    && Array.isArray(request.allowedDriverUids)
    && request.allowedDriverUids.includes(driverUid);
}

async function eligibleDriverAudience(db, pickupCoordinate, visibility, favoriteUids = []) {
  if (visibility === FAVORITES_VISIBILITY) return favoriteUids.slice(0, CASH_HUB_AUDIENCE_LIMIT);
  const [publicProfiles, privateEligibility] = await Promise.all([
    db.collection("cashHubDriverProfiles").where("isOnline", "==", true).limit(200).get(),
    db.collection("cashHubDriverEligibility").where("isOnline", "==", true).limit(200).get()
  ]);
  const eligibilityByUid = new Map(privateEligibility.docs.map((doc) => [doc.id, doc.data()]));
  return publicProfiles.docs.filter((doc) => {
    const profile = eligibilityByUid.get(doc.id) || doc.data();
    if (profile.availabilityStatus && profile.availabilityStatus !== "available") return false;
    const driverCoordinate = coordinate(profile.approximateLocation);
    if (!pickupCoordinate || !driverCoordinate) return true;
    const miles = distanceMilesBetween(pickupCoordinate, driverCoordinate);
    return miles !== null && miles <= CASH_HUB_PUBLIC_RADIUS_MILES;
  }).map((doc) => doc.id).slice(0, CASH_HUB_AUDIENCE_LIMIT);
}

async function routeEvidence(payload, scheduledTime) {
  const pickupCoordinate = coordinate(payload?.pickupCoordinate);
  const destinationCoordinate = coordinate(payload?.destinationCoordinate);
  if (!pickupCoordinate || !destinationCoordinate) return {};
  const result = await getDirections({
    origin: pickupCoordinate,
    destination: destinationCoordinate,
    departureDate: scheduledTime.toDate().toISOString()
  });
  const route = result.route;
  return {
    pickupCoordinate,
    destinationCoordinate,
    routeDistanceMiles: Math.round(route.distanceMiles * 100) / 100,
    routeDurationMinutes: Math.round(route.durationMinutes * 10) / 10,
    suggestedContribution: suggestedContribution(route.distanceMiles, route.durationMinutes),
    suggestedPricing: { perMile: CASH_HUB_SUGGESTED_PER_MILE, perMinute: CASH_HUB_SUGGESTED_PER_MINUTE },
    routeProvider: result.provider,
    routeCalculatedAt: admin.firestore.Timestamp.now()
  };
}

function validateLifecycleEvidence(request, next, driver, nowMillis) {
  if (next === "confirmed") return null;
  const location = coordinate(driver?.location);
  const locationUpdatedAt = timestampMillis(driver?.location?.updatedAt ?? driver?.updatedAt);
  if (!location || !locationUpdatedAt || nowMillis - locationUpdatedAt > 10 * 60 * 1000) {
    throw error("A recent driver location is required for this trip update", 409);
  }
  const scheduledMillis = timestampMillis(request.scheduledTime);
  if (next === "arrived") {
    if (scheduledMillis && nowMillis < scheduledMillis - 90 * 60 * 1000) throw error("Arrival cannot be recorded more than 90 minutes before pickup", 409);
    const miles = distanceMilesBetween(location, request.pickupCoordinate);
    if (miles !== null && miles > 2) throw error("Arrival can only be recorded near the pickup", 409);
  }
  if (next === "started") {
    const miles = distanceMilesBetween(location, request.pickupCoordinate);
    if (miles !== null && miles > 2) throw error("The trip can only start near the pickup", 409);
  }
  if (next === "completed") {
    const startedMillis = timestampMillis(request.cashRideStartedAt);
    if (!startedMillis || nowMillis - startedMillis < 60 * 1000) throw error("A trip must be in progress before it can be completed", 409);
    const miles = distanceMilesBetween(location, request.destinationCoordinate);
    if (miles !== null && miles > 3) throw error("The trip can only be completed near the destination", 409);
  }
  return { latitude: location.latitude, longitude: location.longitude };
}
function driverVehicleSummary(driver) {
  const vehicle = driver?.vehicle && typeof driver.vehicle === "object" ? driver.vehicle : {};
  return [vehicle.color, vehicle.year, vehicle.make, vehicle.model]
    .map((value) => text(String(value ?? ""), 80)).filter(Boolean).join(" ");
}
function validateScheduledTime(value, nowMillis = Date.now()) {
  const scheduledTime = date(value);
  if (!scheduledTime) throw error("A valid scheduled time is required", 400);
  if (scheduledTime.toMillis() < nowMillis + MINIMUM_LEAD_TIME_MS) {
    throw error("Cash Rydr Hub requests must be scheduled at least 2 hours ahead", 400);
  }
  return scheduledTime;
}
function hasCurrentTerms(profile, config) {
  if (!profile || !config || config.termsAcceptanceEnabled !== true || profile.cashHubTermsAccepted !== true) return false;
  const currentVersion = text(config.cashHubTermsVersion, 120) || "legacy";
  const acceptedVersion = text(profile.cashHubTermsVersion, 120);
  return acceptedVersion === currentVersion || (!acceptedVersion && currentVersion === "legacy");
}
function canTransitionDriverQueue(current, next) {
  return DRIVER_QUEUE_TRANSITIONS[String(current || "scheduled")]?.has(next) === true;
}
function isCashHubConnectedStatus(status) {
  return ["connected", "accepted"].includes(text(status, 30).toLowerCase());
}
function cashHubRemovalUpdate(request, now) {
  const status = text(request?.status, 30).toLowerCase();
  const hasAgreement = ["connected", "accepted", "completed"].includes(status)
    || Boolean(text(request?.connectedDriverUid, 160))
    || Boolean(text(request?.acceptedByUid, 160))
    || Boolean(request?.connectedAt)
    || Boolean(request?.acceptedAt)
    || amount(request?.agreedPrice) !== null;
  const update = {
    riderHiddenFromMyPosts: true,
    riderRemovedAt: now
  };
  // Removing a marketplace card must not destroy an accepted arrangement.
  // The connected driver can still finish it, and the completed request stays
  // available to the rider's Activity history.
  if (!hasAgreement && status === "open") {
    update.status = "removed";
    update.removedAt = now;
  }
  return update;
}
function cashHubReleaseVisibilityUpdate(canReopen, now) {
  if (!canReopen) return {};
  return {
    riderHiddenFromMyPosts: false,
    riderRestoredToMyPostsAt: now
  };
}
function cashHubRiderCancellationUpdate(request, now) {
  const status = text(request?.status, 30).toLowerCase();
  if (!["open", "connected", "accepted"].includes(status)) {
    throw error("Only an active Cash Hub listing may be cancelled", 409);
  }
  return {
    status: "cancelled",
    riderCancelledAt: now,
    riderHiddenFromMyPosts: false,
    driverQueueStatus: admin.firestore.FieldValue.delete(),
    connectedDriverUid: admin.firestore.FieldValue.delete(),
    connectedDriverName: admin.firestore.FieldValue.delete(),
    connectedVehicleInfo: admin.firestore.FieldValue.delete(),
    acceptedByUid: admin.firestore.FieldValue.delete(),
    acceptedByName: admin.firestore.FieldValue.delete(),
    selectedOfferId: admin.firestore.FieldValue.delete(),
    agreedPrice: admin.firestore.FieldValue.delete(),
    connectedAt: admin.firestore.FieldValue.delete(),
    acceptedAt: admin.firestore.FieldValue.delete(),
    expiresAt: now
  };
}
function cashHubActionRequiresActiveAccess(action) {
  return action === "driver_connect";
}
function normalizeCashHubOffer(payload) {
  const offerAmount = amount(payload?.offerAmount);
  if (offerAmount === null) throw error("Enter a valid offer amount", 400);
  return {
    offerAmount,
    message: text(payload?.message, 2000)
  };
}
function cashHubOfferOpeningMessage(riderName, offerAmount, note = "") {
  const firstName = text(riderName, 80).split(/\s+/).filter(Boolean)[0] || "there";
  const price = offerAmount.toLocaleString("en-US", { style: "currency", currency: "USD" });
  const opening = `Hi ${firstName}, would you be open to a fare of ${price} for this trip?`;
  const trimmedNote = text(note, 2000);
  return trimmedNote ? `${opening} ${trimmedNote}` : opening;
}

async function closeCompetingCashHubNegotiations({ tx, db, requestId, selectedConversationId, riderUid, selectedDriverUid, now }) {
  const conversations = await tx.get(db.collection("cashHubConversations").where("requestId", "==", requestId));
  for (const doc of conversations.docs) {
    if (doc.id === selectedConversationId) continue;
    const conversation = doc.data();
    if (conversation.status !== "open" || conversation.chatStatus === "ended") continue;
    const explanation = "This negotiation ended because the rider connected with another driver.";
    tx.set(doc.ref, { status:"unavailable", offerStatus:"unavailable", chatStatus:"ended", closedReason:"another_driver_connected", lastMessage:explanation, lastMessageAt:now, closedAt:now, updatedAt:now }, { merge:true });
    tx.create(doc.ref.collection("messages").doc(), { requestId, conversationId:doc.id, senderUid:"system", senderName:"CashRydr Hub", senderRole:"system", kind:"listingTaken", text:explanation, auditVisibleToAdmin:true, createdAt:now });
  }
}
function cashHubAccessAllowed(profile, config, role) {
  if (!hasCurrentTerms(profile, config)) return false;
  const accountStatus = text(profile.accountStatus, 40).toLowerCase();
  if (["deletion_requested", "removed", "suspended"].includes(accountStatus)) return false;
  if (role === "driver") {
    const accessStatus = text(profile.cashHubAccessStatus, 40).toLowerCase();
    if (profile.cashHubOptedOut === true || BLOCKED_ACCESS_STATUSES.has(accessStatus)) return false;
    if (!isApprovedDriver(profile)) return false;
  }
  return true;
}

async function requireAccess(db, uid, role) {
  const [profileSnap, configSnap] = await Promise.all([
    db.collection(role === "driver" ? "drivers" : "riders").doc(uid).get(),
    db.collection("platformConfig").doc("cashRydrHub").get()
  ]);
  const profile = profileSnap.exists ? profileSnap.data() : null;
  const config = configSnap.exists ? configSnap.data() : null;
  if (!cashHubAccessAllowed(profile, config, role)) {
    throw error(role === "driver" ? "Cash Rydr Hub driver access is not active" : "Current Cash Rydr Hub terms must be accepted", 403);
  }
  return profile;
}

function normalizeRole(value) {
  const role = text(value, 20).toLowerCase();
  if (!new Set(["rider", "driver"]).has(role)) throw error("CashRydr Hub role must be rider or driver", 400);
  return role;
}

async function acceptCashHubTerms({ uid, role: rawRole, db = getFirestore(), nowMillis = Date.now() }) {
  const role = normalizeRole(rawRole);
  const profileRef = db.collection(role === "driver" ? "drivers" : "riders").doc(uid);
  const configRef = db.collection("platformConfig").doc("cashRydrHub");
  const [profileSnap, configSnap] = await Promise.all([profileRef.get(), configRef.get()]);
  if (!profileSnap.exists) throw error(`${role === "driver" ? "Driver" : "Rider"} profile not found`, 404);
  const config = configSnap.exists ? configSnap.data() : {};
  if (config.termsAcceptanceEnabled !== true) throw error("CashRydr Hub is not currently accepting terms", 409);
  const termsVersion = text(config.cashHubTermsVersion, 120) || "legacy";
  const profile = profileSnap.data();
  if (profile.cashHubTermsAccepted === true && profile.cashHubTermsVersion === termsVersion && profile.cashHubOptedOut !== true) {
    return { role, termsVersion, duplicate: true, accessStatus: text(profile.cashHubAccessStatus, 40) || "active" };
  }

  const now = admin.firestore.Timestamp.fromMillis(nowMillis);
  const batch = db.batch();
  const update = {
    cashHubTermsAccepted: true,
    cashHubTermsAcceptedAt: now,
    cashHubTermsVersion: termsVersion,
    cashHubRole: role,
    cashHubOptedOut: false,
    cashHubOptedOutAt: admin.firestore.FieldValue.delete(),
    updatedAt: now
  };

  if (role === "driver") {
    const periodId = billingPeriod(new Date(nowMillis));
    const billingRef = profileRef.collection("cashHubBilling").doc(periodId);
    const priorBilling = await profileRef.collection("cashHubBilling").limit(24).get();
    const hasOutstandingPeriod = priorBilling.docs.some((doc) => {
      const value = doc.data();
      return (Number(value.remainingCents) || 0) > 0 && ["fee_pending", "partially_collected", "past_due"].includes(String(value.status || ""));
    });
    Object.assign(update, {
      cashHubAccessStatus: hasOutstandingPeriod ? "past_due" : "active",
      cashHubDriverAccessFeeAcknowledged: true,
      cashHubDriverAccessFeeAcknowledgedAt: now,
      cashHubDriverAccessFeeCents: Math.max(0, Number(config.cashHubMonthlyFeeCents) || CASH_HUB_FEE_CENTS),
      cashHubDriverAccessFeeVersion: termsVersion
    });
    if (config.cashHubBillingEnabled === true && !hasOutstandingPeriod && !(await billingRef.get()).exists) {
      const graceEndsAt = admin.firestore.Timestamp.fromMillis(nowMillis + CASH_HUB_GRACE_DAYS * 24 * 60 * 60 * 1000);
      batch.create(billingRef, {
        periodId,
        feeCents: update.cashHubDriverAccessFeeCents,
        collectedCents: 0,
        remainingCents: update.cashHubDriverAccessFeeCents,
        reservedCents: 0,
        status: "fee_pending",
        collectionSource: "dispatch_earnings",
        graceStartedAt: now,
        graceEndsAt,
        createdAt: now,
        updatedAt: now
      });
    }
  }

  batch.set(profileRef, update, { merge: true });
  batch.create(db.collection("cashHubAccessReceipts").doc(), {
    uid, role, action: "terms_accepted", termsVersion,
    feeCents: role === "driver" ? update.cashHubDriverAccessFeeCents : null,
    acceptedAt: now,
    source: "rydr_backend"
  });
  await batch.commit();
  return { role, termsVersion, accessStatus: update.cashHubAccessStatus || "active" };
}

async function optOutCashHub({ uid, role: rawRole, db = getFirestore(), nowMillis = Date.now() }) {
  const role = normalizeRole(rawRole);
  const profileRef = db.collection(role === "driver" ? "drivers" : "riders").doc(uid);
  if (!(await profileRef.get()).exists) throw error(`${role === "driver" ? "Driver" : "Rider"} profile not found`, 404);
  const now = admin.firestore.Timestamp.fromMillis(nowMillis);
  const update = {
    cashHubTermsAccepted: false,
    cashHubOptedOut: true,
    cashHubOptedOutAt: now,
    cashHubRole: role,
    updatedAt: now,
    ...(role === "driver" ? { cashHubAccessStatus: "opted_out" } : {})
  };
  const batch = db.batch();
  batch.set(profileRef, update, { merge: true });
  batch.create(db.collection("cashHubAccessReceipts").doc(), {
    uid, role, action: "opted_out", createdAt: now, source: "rydr_backend"
  });
  await batch.commit();
  return { role, accessStatus: role === "driver" ? "opted_out" : "inactive" };
}

async function assertParticipantsNotBlocked(db, riderUid, driverUid) {
  const [riderBlock, driverBlock] = await Promise.all([
    db.collection("riders").doc(riderUid).collection("cashHubBlockedDrivers").doc(driverUid).get(),
    db.collection("drivers").doc(driverUid).collection("cashHubBlockedRiders").doc(riderUid).get()
  ]);
  if (riderBlock.exists || driverBlock.exists) throw error("Cash Rydr Hub contact is blocked", 403);
}

async function favoriteDriverUids(db, riderUid) {
  const snapshot = await db.collection("riders").doc(riderUid).collection("cashHubFavoriteDrivers").limit(10).get();
  return snapshot.docs.map((doc) => doc.id).filter(Boolean);
}

async function updateCashHubRelationship({ uid, action, payload, db = getFirestore() }) {
  const targetUid = text(payload?.targetUid, 160);
  if (!targetUid || targetUid === uid) throw error("A valid Cash Hub user is required", 400);
  const riderActions = new Set(["add_favorite_driver", "remove_favorite_driver", "block_driver"]);
  const driverActions = new Set(["block_rider"]);
  if (!riderActions.has(action) && !driverActions.has(action)) throw error("Unknown Cash Hub relationship action", 400);
  const operationKey = idempotencyKey(payload?.idempotencyKey);
  const receiptRef = operationKey ? db.collection("cashHubOperationReceipts").doc(`${uid}_${operationKey}`) : null;
  const operation = `relationship:${action}:${targetUid}`;
  if (receiptRef) {
    const receipt = await receiptRef.get();
    if (receipt.exists) {
      if (receipt.data().operation !== operation) throw error("Idempotency key was already used for another operation", 409);
      return { ...receipt.data().result, duplicate: true };
    }
  }
  const role = riderActions.has(action) ? "rider" : "driver";
  await requireAccess(db, uid, role);
  const now = admin.firestore.Timestamp.now();
  const batch = db.batch();

  if (action === "add_favorite_driver") {
    const [driverSnap, blockedSnap, favorites] = await Promise.all([
      db.collection("cashHubDriverProfiles").doc(targetUid).get(),
      db.collection("riders").doc(uid).collection("cashHubBlockedDrivers").doc(targetUid).get(),
      db.collection("riders").doc(uid).collection("cashHubFavoriteDrivers").limit(11).get()
    ]);
    if (!driverSnap.exists || driverSnap.data().isRydrVerifiedDriver !== true) throw error("This driver is not eligible for Cash Hub favorites", 409);
    if (blockedSnap.exists) throw error("Unblock this driver before adding them to favorites", 409);
    const favoriteRef = db.collection("riders").doc(uid).collection("cashHubFavoriteDrivers").doc(targetUid);
    if (!favorites.docs.some((doc) => doc.id === targetUid) && favorites.size >= 10) throw error("You can save up to 10 favorite drivers", 409);
    const driver = driverSnap.data();
    batch.set(favoriteRef, {
      driverUid: targetUid,
      driverName: text(driver.driverName, 80) || "Cash Hub Driver",
      profilePhotoURL: text(driver.profilePhotoURL, 1000),
      vehicleInfo: text(driver.vehicleInfo, 200),
      cashHubRating: Number(driver.cashHubRating) || 5,
      isIdentityVerified: driver.isIdentityVerified === true,
      isLicenseVerified: driver.isLicenseVerified === true,
      isRydrVerifiedDriver: true,
      addedAt: now,
      managedBy: "rydr_backend"
    }, { merge: true });
  } else if (action === "remove_favorite_driver") {
    batch.delete(db.collection("riders").doc(uid).collection("cashHubFavoriteDrivers").doc(targetUid));
  } else {
    const targetCollection = action === "block_driver" ? "drivers" : "riders";
    if (!(await db.collection(targetCollection).doc(targetUid).get()).exists) throw error("Cash Hub user not found", 404);
    if (action === "block_driver") {
      batch.set(db.collection("riders").doc(uid).collection("cashHubBlockedDrivers").doc(targetUid), {
        driverUid: targetUid, blockedAt: now, managedBy: "rydr_backend"
      }, { merge: true });
      batch.delete(db.collection("riders").doc(uid).collection("cashHubFavoriteDrivers").doc(targetUid));
    } else {
      batch.set(db.collection("drivers").doc(uid).collection("cashHubBlockedRiders").doc(targetUid), {
        riderUid: targetUid, blockedAt: now, managedBy: "rydr_backend"
      }, { merge: true });
    }
    const conversationId = text(payload?.conversationId, 300);
    if (conversationId) {
      const conversationRef = db.collection("cashHubConversations").doc(conversationId);
      const conversationSnap = await conversationRef.get();
      if (conversationSnap.exists) {
        const conversation = conversationSnap.data();
        if (![conversation.riderUid, conversation.driverUid].includes(uid) || ![conversation.riderUid, conversation.driverUid].includes(targetUid)) throw error("Conversation does not match these users", 403);
        const explanation = "This chat was closed after a participant was blocked.";
        batch.set(conversationRef, { status:"ended", offerStatus:"ended", chatStatus:"ended", closedReason:"participant_blocked", lastMessage:explanation, lastMessageAt:now, closedAt:now, updatedAt:now }, { merge:true });
        batch.create(conversationRef.collection("messages").doc(), { requestId:conversation.requestId, conversationId, senderUid:"system", senderName:"CashRydr Hub", senderRole:"system", kind:"chatEnded", text:explanation, auditVisibleToAdmin:true, createdAt:now });
      }
    }
  }
  const result = { action, targetUid };
  if (receiptRef) batch.create(receiptRef, { uid, operation, result, createdAt: now });
  await batch.commit();
  return result;
}

function requestFields(payload, nowMillis, fallbackVisibility = PUBLIC_VISIBILITY) {
  const pickup = text(payload?.pickup, 300);
  const destination = text(payload?.destination, 300);
  if (!pickup || !destination) throw error("Pickup and destination are required", 400);
  const scheduledTime = validateScheduledTime(payload?.scheduledTime, nowMillis);
  return {
    pickup,
    destination,
    scheduledTime,
    expiresAt: scheduledTime,
    passengers: Math.max(1, Math.min(20, Number(payload?.passengers) || 1)),
    notes: text(payload?.notes, 2000),
    budgetRange: text(payload?.budgetRange, 100),
    tripFormat: normalizeTripFormat(payload?.tripFormat ?? payload?.rideType),
    visibility: normalizeVisibility(payload?.visibility, fallbackVisibility)
  };
}

async function createCashHubRequest({ uid, payload, db = getFirestore(), nowMillis = Date.now() }) {
  const operationKey = idempotencyKey(payload?.idempotencyKey);
  if (operationKey) {
    const receipt = await db.collection("cashHubOperationReceipts").doc(`${uid}_${operationKey}`).get();
    if (receipt.exists && receipt.data().operation === "create_request") return { ...receipt.data().result, duplicate: true };
  }
  const rider = await requireAccess(db, uid, "rider");
  const fields = requestFields(payload, nowMillis);
  const allowedDriverUids = fields.visibility === FAVORITES_VISIBILITY ? await favoriteDriverUids(db, uid) : [];
  if (fields.visibility === FAVORITES_VISIBILITY && allowedDriverUids.length === 0) throw error("Add at least one favorite driver before using favorite-only visibility", 409);
  const evidence = await routeEvidence(payload, fields.scheduledTime);
  const eligibleDriverUids = await eligibleDriverAudience(db, evidence.pickupCoordinate, fields.visibility, allowedDriverUids);
  const ref = db.collection("cashRydrRequests").doc();
  const now = admin.firestore.Timestamp.fromMillis(nowMillis);
  const result = { requestId: ref.id, status: "open" };
  const batch = db.batch();
  batch.create(ref, {
    riderUid: uid,
    riderName: text(rider.preferredName ?? rider.displayName, 80) || "Cash Hub Rider",
    ...fields,
    ...evidence,
    eligibleDriverUids,
    backendAudienceVersion: 1,
    ...(allowedDriverUids.length > 0 ? { allowedDriverUids } : {}),
    status: "open", stateOwner: "rydr_backend", createdAt: now, updatedAt: now
  });
  if (operationKey) batch.create(db.collection("cashHubOperationReceipts").doc(`${uid}_${operationKey}`), { uid, operation: "create_request", result, createdAt: now });
  await batch.commit();
  return result;
}

async function commandCashHubRequest({ uid, requestId, action, payload, db = getFirestore(), nowMillis = Date.now() }) {
  const requestRef = db.collection("cashRydrRequests").doc(requestId);
  const operationKey = idempotencyKey(payload?.idempotencyKey);
  const receiptRef = operationKey ? db.collection("cashHubOperationReceipts").doc(`${uid}_${operationKey}`) : null;
  const operation = `request_command:${requestId}:${action}`;
  if (receiptRef) {
    const receipt = await receiptRef.get();
    if (receipt.exists) {
      if (receipt.data().operation !== operation) throw error("Idempotency key was already used for another operation", 409);
      return { ...receipt.data().result, duplicate: true };
    }
  }
  let actorProfile = null;
  if (cashHubActionRequiresActiveAccess(action)) actorProfile = await requireAccess(db, uid, "driver");
  if (action === "driver_status") {
    const actorSnap = await db.collection("drivers").doc(uid).get();
    actorProfile = actorSnap.exists ? actorSnap.data() : null;
  }
  if (["edit", "visibility", "remove", "accept_offer", "decline_offer", "cancel_connection", "rider_cancel"].includes(action)) await requireAccess(db, uid, "rider");
  const favoriteAudience = ["edit", "visibility"].includes(action) ? await favoriteDriverUids(db, uid) : [];
  let preparedEdit = null;
  let preparedVisibility = null;
  if (action === "edit") {
    const fields = requestFields(payload, nowMillis);
    const evidence = await routeEvidence(payload, fields.scheduledTime);
    preparedEdit = {
      ...fields,
      ...evidence,
      eligibleDriverUids: await eligibleDriverAudience(db, evidence.pickupCoordinate, fields.visibility, favoriteAudience),
      backendAudienceVersion: 1
    };
  } else if (action === "visibility") {
    const preflightRequest = await requestRef.get();
    if (!preflightRequest.exists) throw error("Cash Hub request not found", 404);
    const visibility = normalizeVisibility(payload?.visibility, preflightRequest.data().visibility);
    preparedVisibility = {
      visibility,
      eligibleDriverUids: await eligibleDriverAudience(db, preflightRequest.data().pickupCoordinate, visibility, favoriteAudience),
      backendAudienceVersion: 1
    };
  }
  // Cross-document access and safety checks happen before the transaction. The
  // transaction still revalidates request/offer state so concurrent accepts are safe.
  if (action === "driver_connect") {
    const preflightRequest = await requestRef.get();
    if (!preflightRequest.exists) throw error("Cash Hub request not found", 404);
    if (!driverCanAccessRequest(preflightRequest.data(), uid)) throw error("This CashRydr Hub request is not available to this driver", 403);
    await assertParticipantsNotBlocked(db, preflightRequest.data().riderUid, uid);
  } else if (action === "accept_offer") {
    const offerId = text(payload?.offerId, 160);
    if (!offerId) throw error("Offer ID is required", 400);
    const [preflightRequest, preflightOffer] = await Promise.all([
      requestRef.get(),
      db.collection("cashHubConversations").doc(offerId).get()
    ]);
    if (!preflightRequest.exists || !preflightOffer.exists || preflightOffer.data().requestId !== requestId) throw error("Offer not found", 404);
    await Promise.all([
      assertParticipantsNotBlocked(db, preflightRequest.data().riderUid, preflightOffer.data().driverUid),
      requireAccess(db, preflightOffer.data().driverUid, "driver")
    ]);
  }
  return db.runTransaction(async (tx) => {
    const [requestSnap, receiptSnap] = await Promise.all([
      tx.get(requestRef),
      receiptRef ? tx.get(receiptRef) : Promise.resolve(null)
    ]);
    if (receiptSnap?.exists) {
      if (receiptSnap.data().operation !== operation) throw error("Idempotency key was already used for another operation", 409);
      return { ...receiptSnap.data().result, duplicate: true };
    }
    if (!requestSnap.exists) throw error("Cash Hub request not found", 404);
    const request = requestSnap.data();
    const isRider = request.riderUid === uid;
    const isDriver = request.connectedDriverUid === uid || request.acceptedByUid === uid;
    const now = admin.firestore.Timestamp.fromMillis(nowMillis);
    let update = { updatedAt: now, stateOwner: "rydr_backend" };
    if (["edit", "visibility", "remove", "accept_offer", "decline_offer", "cancel_connection", "rider_cancel"].includes(action) && !isRider) throw error("Only the request owner may perform this action", 403);

    if (action === "edit") {
      if (request.status !== "open") throw error("Only open requests may be edited", 409);
      update = { ...update, ...preparedEdit };
      if (update.visibility === FAVORITES_VISIBILITY) {
        if (favoriteAudience.length === 0) throw error("Add at least one favorite driver before using favorite-only visibility", 409);
        update.allowedDriverUids = favoriteAudience;
      } else update.allowedDriverUids = admin.firestore.FieldValue.delete();
    } else if (action === "visibility") {
      if (request.status !== "open") throw error("Only open requests may change visibility", 409);
      update = { ...update, ...preparedVisibility };
      if (update.visibility === FAVORITES_VISIBILITY) {
        if (favoriteAudience.length === 0) throw error("Add at least one favorite driver before using favorite-only visibility", 409);
        update.allowedDriverUids = favoriteAudience;
      } else update.allowedDriverUids = admin.firestore.FieldValue.delete();
    } else if (action === "remove") {
      update = { ...update, ...cashHubRemovalUpdate(request, now) };
    } else if (action === "driver_connect") {
      if (request.status !== "open" || request.connectedDriverUid) throw error("Request is no longer available", 409);
      if (!driverCanAccessRequest(request, uid)) throw error("This CashRydr Hub request is not available to this driver", 403);
      const driver = actorProfile;
      const driverName = text(driver.displayName ?? `${driver.firstName ?? ""} ${driver.lastName ?? ""}`, 80) || "Cash Hub Driver";
      const vehicleInfo = driverVehicleSummary(driver);
      if (!vehicleInfo) throw error("Add your current vehicle to the Driver app before connecting to a CashRydr Hub request", 409);
      const selectedConversationId = `${requestId}_${uid}`;
      await closeCompetingCashHubNegotiations({ tx, db, requestId, selectedConversationId, riderUid:request.riderUid, selectedDriverUid:uid, now });
      update = { ...update, status: "connected", driverQueueStatus: "scheduled", connectedDriverUid: uid, connectedDriverName: driverName, connectedVehicleInfo: vehicleInfo, acceptedByUid: uid, acceptedByName: driverName, connectedAt: now, acceptedAt: now, expiresAt: admin.firestore.Timestamp.fromMillis((timestampMillis(request.scheduledTime) || nowMillis) + 24 * 60 * 60 * 1000) };
      const agreed = amount(request.budgetRange); if (agreed !== null) update.agreedPrice = agreed;
      tx.set(db.collection("cashHubConversations").doc(`${requestId}_${uid}`), { requestId, riderUid: request.riderUid, riderName: request.riderName, driverUid: uid, driverName, vehicleInfo, participants: [request.riderUid, uid].sort(), status: "connected", offerStatus: "accepted", cashHubOnly: true, managedByRydr: false, paymentHandledBy: "rider_driver_direct", channelOwner: "rydr_backend", createdAt: now, updatedAt: now }, { merge: true });
    } else if (action === "accept_offer") {
      if (request.status !== "open") throw error("Request is already connected", 409);
      const offerId = text(payload?.offerId, 160);
      if (!offerId) throw error("Offer ID is required", 400);
      const conversationRef = db.collection("cashHubConversations").doc(offerId);
      const offerSnap = await tx.get(conversationRef);
      if (!offerSnap.exists || offerSnap.data().riderUid !== uid || offerSnap.data().requestId !== requestId) throw error("Offer not found", 404);
      const offer = offerSnap.data();
      if (offer.offerStatus !== "pending" || offer.status !== "open") throw error("Offer is no longer pending", 409);
      if (offer.priceProposedByUid === uid) throw error("The other participant must respond to this price", 409);
      await closeCompetingCashHubNegotiations({ tx, db, requestId, selectedConversationId:offerId, riderUid:request.riderUid, selectedDriverUid:offer.driverUid, now });
      update = { ...update, status: "connected", driverQueueStatus: "scheduled", connectedDriverUid: offer.driverUid, connectedDriverName: offer.driverName, connectedVehicleInfo: offer.vehicleInfo, acceptedByUid: offer.driverUid, acceptedByName: offer.driverName, selectedOfferId: offerId, connectedAt: now, acceptedAt: now, expiresAt: admin.firestore.Timestamp.fromMillis((timestampMillis(request.scheduledTime) || nowMillis) + 24 * 60 * 60 * 1000) };
      if (amount(offer.offerAmount) !== null) update.agreedPrice = amount(offer.offerAmount);
      tx.set(conversationRef, { status: "connected", offerStatus: "accepted", connectedAt: now, updatedAt: now }, { merge: true });
    } else if (action === "decline_offer") {
      const offerId = text(payload?.offerId, 160);
      if (!offerId) throw error("Offer ID is required", 400);
      const conversationRef = db.collection("cashHubConversations").doc(offerId);
      const offerSnap = await tx.get(conversationRef);
      if (!offerSnap.exists || offerSnap.data().riderUid !== uid || offerSnap.data().requestId !== requestId) throw error("Offer not found", 404);
      if (offerSnap.data().offerStatus !== "pending") throw error("Offer is no longer pending", 409);
      if (offerSnap.data().priceProposedByUid === uid) throw error("The other participant must respond to this price", 409);
      const systemMessageRef = conversationRef.collection("messages").doc();
      tx.set(conversationRef, { status: "open", offerStatus: "negotiating", lastMessage:"Price declined — conversation remains open.", lastMessageAt:now, updatedAt:now }, { merge: true });
      tx.create(systemMessageRef, { requestId, conversationId:offerId, senderUid:"system", senderName:"CashRydr Hub", senderRole:"system", recipientUid:offerSnap.data().priceProposedByUid, kind:"offerDeclined", text:"Price declined — conversation remains open.", auditVisibleToAdmin:true, createdAt:now });
      const result = { status: request.status };
      if (receiptRef) tx.create(receiptRef, { uid, operation, result, createdAt: now });
      return result;
    } else if (action === "cancel_connection") {
      if (!isCashHubConnectedStatus(request.status)) throw error("Request is not connected", 409);
      const conversationId = request.selectedOfferId || (request.connectedDriverUid ? `${requestId}_${request.connectedDriverUid}` : null);
      if ((timestampMillis(request.scheduledTime) || 0) <= nowMillis) throw error("This listing's pickup time has passed", 409);
      update = { ...update, status: "open", expiresAt: request.scheduledTime, driverQueueStatus: admin.firestore.FieldValue.delete(), connectedDriverUid: admin.firestore.FieldValue.delete(), connectedDriverName: admin.firestore.FieldValue.delete(), connectedVehicleInfo: admin.firestore.FieldValue.delete(), acceptedByUid: admin.firestore.FieldValue.delete(), acceptedByName: admin.firestore.FieldValue.delete(), selectedOfferId: admin.firestore.FieldValue.delete(), agreedPrice: admin.firestore.FieldValue.delete(), connectedAt: admin.firestore.FieldValue.delete(), acceptedAt: admin.firestore.FieldValue.delete() };
      if (conversationId) tx.set(db.collection("cashHubConversations").doc(conversationId), { status: "cancelled", offerStatus: "cancelled", closedAt: now, updatedAt: now }, { merge: true });
    } else if (action === "rider_cancel") {
      const conversationId = request.selectedOfferId || (request.connectedDriverUid ? `${requestId}_${request.connectedDriverUid}` : null);
      update = { ...update, ...cashHubRiderCancellationUpdate(request, now) };
      if (request.connectedDriverUid) update.cancelledDriverUid = request.connectedDriverUid;
      if (request.connectedDriverName) update.cancelledDriverName = request.connectedDriverName;
      if (request.selectedOfferId) update.cancelledOfferId = request.selectedOfferId;
      if (amount(request.agreedPrice) !== null) update.cancelledAgreedPrice = amount(request.agreedPrice);
      if (conversationId) tx.set(db.collection("cashHubConversations").doc(conversationId), { status: "cancelled", offerStatus: "cancelled", closedAt: now, updatedAt: now }, { merge: true });
    } else if (action === "driver_status") {
      if (!isDriver || !isCashHubConnectedStatus(request.status)) throw error("Only the connected driver may update status", 403);
      const next = text(payload?.status, 30);
      const fields = { confirmed: "driverConfirmedAt", arrived: "driverArrivedAt", started: "cashRideStartedAt", completed: "cashCompletedAt" };
      if (!fields[next] || !canTransitionDriverQueue(request.driverQueueStatus, next)) throw error("Invalid Cash Hub status transition", 409);
      const evidenceLocation = validateLifecycleEvidence(request, next, actorProfile, nowMillis);
      update.driverQueueStatus = next; update[fields[next]] = now;
      if (evidenceLocation) {
        update[`${next}Evidence`] = { location: evidenceLocation, recordedAt: now, source: "backend_driver_presence" };
      }
      if (next === "completed") {
        update.status = "completed";
        const conversationId = request.selectedOfferId || `${requestId}_${uid}`;
        tx.set(db.collection("cashHubConversations").doc(conversationId), { status: "completed", closedAt: now, updatedAt: now }, { merge: true });
      }
    } else if (action === "release") {
      if (!isDriver || !isCashHubConnectedStatus(request.status)) throw error("Only the connected driver may release this request", 403);
      const scheduledMillis = timestampMillis(request.scheduledTime) || 0;
      const late = scheduledMillis - nowMillis <= 3600000;
      const conversationId = request.selectedOfferId || `${requestId}_${uid}`;
      const canReopen = scheduledMillis > nowMillis;
      update = { ...update, status: canReopen ? "open" : "expired", expiresAt: canReopen ? request.scheduledTime : now, ...cashHubReleaseVisibilityUpdate(canReopen, now), driverQueueStatus: admin.firestore.FieldValue.delete(), releasedByUid: uid, releasedByName: request.connectedDriverName || "Cash Hub Driver", releasedAt: now, lateReleasePenalty: late, connectedDriverUid: admin.firestore.FieldValue.delete(), connectedDriverName: admin.firestore.FieldValue.delete(), connectedVehicleInfo: admin.firestore.FieldValue.delete(), acceptedByUid: admin.firestore.FieldValue.delete(), acceptedByName: admin.firestore.FieldValue.delete(), selectedOfferId: admin.firestore.FieldValue.delete(), agreedPrice: admin.firestore.FieldValue.delete(), connectedAt: admin.firestore.FieldValue.delete(), acceptedAt: admin.firestore.FieldValue.delete() };
      tx.set(db.collection("cashHubConversations").doc(conversationId), { status: "released", offerStatus: "released", closedAt: now, updatedAt: now }, { merge: true });
      if (late) {
        update.lateReleasePenaltyReason = "Released within 1 hour of scheduled pickup.";
        tx.set(db.collection("cashHubLateReleaseMarkers").doc(`${requestId}_${uid}`), { requestId, driverId: uid, riderId: request.riderUid, scheduledTime: request.scheduledTime, reason: update.lateReleasePenaltyReason, status: "open", createdAt: now }, { merge: true });
      }
    } else throw error("Unknown Cash Hub action", 400);
    tx.set(requestRef, update, { merge: true });
    const result = { status: update.status ?? request.status, lateReleasePenalty: update.lateReleasePenalty === true };
    if (receiptRef) tx.create(receiptRef, { uid, operation, result, createdAt: now });
    return result;
  });
}

async function createCashHubOffer({ uid, requestId, payload, db = getFirestore() }) {
  const driver = await requireAccess(db, uid, "driver");
  const now = admin.firestore.Timestamp.now(); const conversationId = `${requestId}_${uid}`;
  const requestRef = db.collection("cashRydrRequests").doc(requestId);
  const conversationRef = db.collection("cashHubConversations").doc(conversationId);
  const operationKey = idempotencyKey(payload?.idempotencyKey);
  const messageRef = conversationRef.collection("messages").doc(operationKey || undefined);
  const driverName = text(driver.displayName ?? `${driver.firstName ?? ""} ${driver.lastName ?? ""}`, 80) || "Cash Hub Driver";
  const vehicleInfo = driverVehicleSummary(driver);
  const { offerAmount, message } = normalizeCashHubOffer(payload);
  if (!vehicleInfo) throw error("Add your current vehicle to the Driver app before making a CashRydr Hub offer", 409);
  return db.runTransaction(async (tx) => {
    const requestSnap = await tx.get(requestRef);
    if (!requestSnap.exists || requestSnap.data().status !== "open") throw error("Request is no longer accepting offers", 409);
    const request = requestSnap.data();
    if (!driverCanAccessRequest(request, uid)) throw error("This CashRydr Hub request is not available to this driver", 403);
    const riderBlockRef = db.collection("riders").doc(request.riderUid).collection("cashHubBlockedDrivers").doc(uid);
    const driverBlockRef = db.collection("drivers").doc(uid).collection("cashHubBlockedRiders").doc(request.riderUid);
    const [existingConversation, riderBlock, driverBlock, existingMessage] = await Promise.all([
      tx.get(conversationRef), tx.get(riderBlockRef), tx.get(driverBlockRef), operationKey ? tx.get(messageRef) : Promise.resolve(null)
    ]);
    if (existingMessage?.exists) return { conversationId, duplicate: true };
    if (riderBlock.exists || driverBlock.exists) throw error("Cash Rydr Hub contact is blocked", 403);
    if (existingConversation.exists) {
      const existing = existingConversation.data();
      if (!["pending", "negotiating"].includes(existing.offerStatus) || existing.status !== "open" || existing.chatStatus === "ended") throw error("This offer conversation is no longer open", 409);
      const offerMessage = cashHubOfferOpeningMessage(request.riderName, offerAmount, message);
      tx.set(conversationRef, {
        offerAmount,
        offerStatus: "pending",
        chatStatus: "active",
        priceProposedByUid: uid,
        priceProposedByRole: "driver",
        lastMessage: offerMessage,
        lastMessageAt: now,
        updatedAt: now
      }, { merge: true });
      tx.create(messageRef, { requestId, conversationId, senderUid:uid, senderName:driverName, senderRole:"driver", kind:"offer", text:offerMessage, offerAmount, auditVisibleToAdmin:true, createdAt:now });
      return { conversationId, revised: true };
    }
    const offerMessage = cashHubOfferOpeningMessage(request.riderName, offerAmount, message);
    tx.set(conversationRef, { requestId, riderUid:request.riderUid, riderName:request.riderName, driverUid:uid, driverName, participants:[request.riderUid,uid].sort(), status:"open", offerStatus:"pending", chatStatus:"active", vehicleInfo, offerAmount, priceProposedByUid:uid, priceProposedByRole:"driver", lastMessage:offerMessage, lastMessageAt:now, cashHubRating:Number(driver.cashHubRating ?? driver.rating ?? 5), isIdentityVerified:driver.identityVerified===true||driver.stripeIdentityStatus==="verified", isLicenseVerified:driver.isLicenseVerified===true||driver.driverLicenseStatus==="approved", isRydrVerifiedDriver:true, cashHubOnly:true, managedByRydr:false, paymentHandledBy:"rider_driver_direct", channelOwner:"rydr_backend", createdAt:now, updatedAt:now }, {merge:true});
    tx.create(messageRef, { requestId, conversationId, senderUid:uid, senderName:driverName, senderRole:"driver", kind:"offer", text:offerMessage, offerAmount, auditVisibleToAdmin:true, createdAt:now });
    return { conversationId };
  });
}

async function sendCashHubMessage({ uid, conversationId, payload, db = getFirestore() }) {
  const conversationRef=db.collection("cashHubConversations").doc(conversationId); const snap=await conversationRef.get();
  if(!snap.exists) throw error("Conversation not found",404); const c=snap.data();
  const role=uid===c.riderUid?"rider":uid===c.driverUid?"driver":null; if(!role) throw error("Not a conversation participant",403);
  await requireAccess(db, uid, role);
  await assertParticipantsNotBlocked(db, c.riderUid, c.driverUid);
  if (c.chatStatus === "ended" || TERMINAL_CONVERSATION_STATUSES.has(c.status) || TERMINAL_CONVERSATION_STATUSES.has(c.offerStatus)) throw error("This Cash Rydr Hub conversation is closed", 409);
  const requestSnap = await db.collection("cashRydrRequests").doc(c.requestId).get();
  if (!requestSnap.exists || !["open", "connected", "accepted"].includes(requestSnap.data().status)) throw error("This Cash Rydr Hub request is no longer active", 409);
  const message=text(payload?.message,2000); if(!message) throw error("Message is required",400);
  const kind=["message","directMessage"].includes(payload?.kind)?payload.kind:"message"; const now=admin.firestore.Timestamp.now();
  const operationKey = idempotencyKey(payload?.idempotencyKey);
  const ref=operationKey ? conversationRef.collection("messages").doc(operationKey) : conversationRef.collection("messages").doc();
  if (operationKey && (await ref.get()).exists) return { messageId: ref.id };
  const batch=db.batch(); batch.create(ref,{requestId:c.requestId,conversationId,senderUid:uid,senderName:role==="rider"?c.riderName:c.driverName,senderRole:role,kind,text:message,auditVisibleToAdmin:true,createdAt:now}); batch.set(conversationRef,{lastMessage:message,lastMessageAt:now,updatedAt:now},{merge:true}); await batch.commit(); return {messageId:ref.id};
}

async function commandCashHubConversation({ uid, conversationId, action, payload, db = getFirestore(), nowMillis = Date.now() }) {
  if (!["end_chat", "propose_price", "accept_price", "decline_price"].includes(action)) throw error("Unknown Cash Hub conversation action", 400);
  const conversationRef = db.collection("cashHubConversations").doc(conversationId);
  const operationKey = idempotencyKey(payload?.idempotencyKey);
  const receiptRef = operationKey ? db.collection("cashHubOperationReceipts").doc(`${uid}_${operationKey}`) : null;
  const operation = `conversation_command:${conversationId}:${action}`;
  if (receiptRef) {
    const receipt = await receiptRef.get();
    if (receipt.exists) {
      if (receipt.data().operation !== operation) throw error("Idempotency key was already used for another operation", 409);
      return { ...receipt.data().result, duplicate: true };
    }
  }
  const preliminary = await conversationRef.get();
  if (!preliminary.exists) throw error("Conversation not found", 404);
  const preliminaryConversation = preliminary.data();
  const preliminaryRole = uid === preliminaryConversation.riderUid ? "rider" : uid === preliminaryConversation.driverUid ? "driver" : null;
  if (!preliminaryRole) throw error("Not a conversation participant", 403);
  if (["propose_price", "accept_price"].includes(action)) await requireAccess(db, uid, preliminaryRole);
  return db.runTransaction(async (tx) => {
    const [snap, receiptSnap] = await Promise.all([
      tx.get(conversationRef),
      receiptRef ? tx.get(receiptRef) : Promise.resolve(null)
    ]);
    if (receiptSnap?.exists) {
      if (receiptSnap.data().operation !== operation) throw error("Idempotency key was already used for another operation", 409);
      return { ...receiptSnap.data().result, duplicate: true };
    }
    if (!snap.exists) throw error("Conversation not found", 404);
    const conversation = snap.data();
    const role = uid === conversation.riderUid ? "rider" : uid === conversation.driverUid ? "driver" : null;
    if (!role) throw error("Not a conversation participant", 403);
    const now = admin.firestore.Timestamp.fromMillis(nowMillis);
    const messageRef = conversationRef.collection("messages").doc();

    if (action === "end_chat") {
      if (conversation.chatStatus === "ended") return { status: conversation.status, duplicate: true };
      const connected = isCashHubConnectedStatus(conversation.status);
      const update = { chatStatus:"ended", endedByUid:uid, chatEndedAt:now, updatedAt:now };
      if (!connected) Object.assign(update, { status:"ended", offerStatus:"ended", closedAt:now });
      tx.set(conversationRef, update, { merge:true });
      tx.create(messageRef, { requestId:conversation.requestId, conversationId, senderUid:"system", senderName:"CashRydr Hub", senderRole:"system", recipientUid:uid === conversation.riderUid ? conversation.driverUid : conversation.riderUid, kind:"chatEnded", text:"This chat was ended by a participant.", auditVisibleToAdmin:true, createdAt:now });
      const result = { status:update.status || conversation.status };
      if (receiptRef) tx.create(receiptRef, { uid, operation, result, createdAt: now });
      return result;
    }

    if (conversation.chatStatus === "ended" || conversation.status !== "open") throw error("This price conversation is closed", 409);
    const requestRef = db.collection("cashRydrRequests").doc(conversation.requestId);
    const requestSnap = await tx.get(requestRef);
    if (!requestSnap.exists || requestSnap.data().status !== "open") throw error("This Cash Hub request is no longer open", 409);
    const request = requestSnap.data();

    if (action === "propose_price") {
      const offerAmount = amount(payload?.offerAmount);
      if (offerAmount === null) throw error("Enter a valid proposed price", 400);
      const recipientName = role === "driver" ? conversation.riderName : conversation.driverName;
      const proposalText = cashHubOfferOpeningMessage(recipientName, offerAmount, payload?.message);
      tx.set(conversationRef, { offerAmount, offerStatus:"pending", priceProposedByUid:uid, priceProposedByRole:role, lastMessage:proposalText, lastMessageAt:now, updatedAt:now }, { merge:true });
      tx.create(messageRef, { requestId:conversation.requestId, conversationId, senderUid:uid, senderName:role === "rider" ? conversation.riderName : conversation.driverName, senderRole:role, kind:"priceProposal", text:proposalText, offerAmount, auditVisibleToAdmin:true, createdAt:now });
      const result = { status:"pending", offerAmount };
      if (receiptRef) tx.create(receiptRef, { uid, operation, result, createdAt: now });
      return result;
    }

    if (conversation.offerStatus !== "pending" || amount(conversation.offerAmount) === null) throw error("There is no pending price to respond to", 409);
    if (conversation.priceProposedByUid === uid) throw error("The other participant must respond to this price", 409);

    if (action === "decline_price") {
      tx.set(conversationRef, { offerStatus:"negotiating", lastMessage:"Price declined — conversation remains open.", lastMessageAt:now, updatedAt:now }, { merge:true });
      tx.create(messageRef, { requestId:conversation.requestId, conversationId, senderUid:"system", senderName:"CashRydr Hub", senderRole:"system", recipientUid:conversation.priceProposedByUid, kind:"offerDeclined", text:"Price declined — conversation remains open.", auditVisibleToAdmin:true, createdAt:now });
      const result = { status:"negotiating" };
      if (receiptRef) tx.create(receiptRef, { uid, operation, result, createdAt: now });
      return result;
    }

    const agreedPrice = amount(conversation.offerAmount);
    const driverUid = conversation.driverUid;
    const scheduledMillis = timestampMillis(request.scheduledTime) || nowMillis;
    await closeCompetingCashHubNegotiations({ tx, db, requestId:conversation.requestId, selectedConversationId:conversationId, riderUid:conversation.riderUid, selectedDriverUid:driverUid, now });
    tx.set(requestRef, { status:"connected", driverQueueStatus:"scheduled", connectedDriverUid:driverUid, connectedDriverName:conversation.driverName, connectedVehicleInfo:conversation.vehicleInfo, acceptedByUid:driverUid, acceptedByName:conversation.driverName, selectedOfferId:conversationId, agreedPrice, connectedAt:now, acceptedAt:now, expiresAt:admin.firestore.Timestamp.fromMillis(scheduledMillis + 24 * 60 * 60 * 1000), updatedAt:now, stateOwner:"rydr_backend" }, { merge:true });
    tx.set(conversationRef, { status:"connected", offerStatus:"accepted", chatStatus:"active", connectedAt:now, updatedAt:now }, { merge:true });
    tx.create(messageRef, { requestId:conversation.requestId, conversationId, senderUid:"system", senderName:"CashRydr Hub", senderRole:"system", kind:"priceAccepted", text:`Price accepted at ${agreedPrice.toLocaleString("en-US", { style:"currency", currency:"USD" })}. The trip is now connected.`, offerAmount:agreedPrice, auditVisibleToAdmin:true, createdAt:now });
    const result = { status:"connected", agreedPrice };
    if (receiptRef) tx.create(receiptRef, { uid, operation, result, createdAt: now });
    return result;
  });
}

module.exports = {
  acceptCashHubTerms, optOutCashHub, createCashHubRequest, commandCashHubRequest, createCashHubOffer, sendCashHubMessage, commandCashHubConversation, updateCashHubRelationship,
  normalizeVisibility, normalizeTripFormat, driverCanAccessRequest, driverVehicleSummary, validateScheduledTime, hasCurrentTerms, canTransitionDriverQueue, isCashHubConnectedStatus, cashHubRemovalUpdate, cashHubReleaseVisibilityUpdate, cashHubRiderCancellationUpdate, cashHubActionRequiresActiveAccess, normalizeCashHubOffer, cashHubOfferOpeningMessage, cashHubAccessAllowed,
  coordinate, distanceMilesBetween, suggestedContribution, validateLifecycleEvidence,
  PUBLIC_VISIBILITY, FAVORITES_VISIBILITY, MINIMUM_LEAD_TIME_MS
};
