const { admin, getFirestore } = require("../config/firebase");

function error(message, statusCode) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function normalizeRating(value) {
  if (value == null) return null;
  const rating = Number(value);
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) throw error("rating must be an integer from 1 to 5", 400);
  return rating;
}

function cleanText(value, maxLength) {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

function cleanCompliments(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => cleanText(item, 50)).filter(Boolean))].slice(0, 8);
}

function nextReputation(profile, previousRating, nextRating, compliments) {
  const reputation = profile?.reputation && typeof profile.reputation === "object" ? profile.reputation : {};
  const fallbackCount = Math.max(0, Number(profile?.ratingCount) || 0);
  const fallbackRating = Number(profile?.rating);
  let count = Math.max(0, Number(reputation.ratingCount) || fallbackCount);
  let sum = Math.max(0, Number(reputation.ratingSum) || (Number.isFinite(fallbackRating) ? fallbackRating * fallbackCount : 0));
  if (previousRating == null && nextRating != null) {
    count += 1;
    sum += nextRating;
  } else if (previousRating != null && nextRating != null) {
    sum += nextRating - previousRating;
  }
  const complimentCounts = { ...(reputation.complimentCounts || {}) };
  for (const compliment of compliments) complimentCounts[compliment] = Math.max(0, Number(complimentCounts[compliment]) || 0) + 1;
  const topCompliments = Object.entries(complimentCounts)
    .sort((a, b) => Number(b[1]) - Number(a[1]) || a[0].localeCompare(b[0]))
    .slice(0, 6)
    .map(([name]) => name);
  return {
    rating: count > 0 ? Math.round((sum / count) * 100) / 100 : 5,
    ratingCount: count,
    ratingSum: sum,
    complimentCounts,
    topCompliments
  };
}

async function submitRideRating({ rideId, actorUid, payload, db = getFirestore() }) {
  const rating = normalizeRating(payload?.rating);
  const feedback = cleanText(payload?.feedback, 2000);
  const compliments = cleanCompliments(payload?.compliments);
  const favoriteDriver = payload?.favoriteDriver === true;
  if (rating == null && !feedback && compliments.length === 0 && !favoriteDriver) throw error("Rating feedback is empty", 400);

  const rideRef = db.collection("rides").doc(rideId);
  return db.runTransaction(async (tx) => {
    const rideSnap = await tx.get(rideRef);
    if (!rideSnap.exists) throw error("Ride not found", 404);
    const ride = rideSnap.data();
    if (ride.status !== "completed") throw error("Ratings are only accepted after a completed ride", 409);

    const actorRole = actorUid === ride.riderId ? "rider" : actorUid === ride.driverId ? "driver" : null;
    if (!actorRole) throw error("Only ride participants may submit a rating", 403);
    const subjectRole = actorRole === "rider" ? "driver" : "rider";
    const subjectUid = subjectRole === "driver" ? ride.driverId : ride.riderId;
    if (!subjectUid) throw error("Ride participant is missing", 409);
    const ratingsCollection = subjectRole === "driver" ? "driverRatings" : "riderRatings";
    const profileCollection = subjectRole === "driver" ? "drivers" : "riders";
    const ratingRef = db.collection(ratingsCollection).doc(rideId);
    const profileRef = db.collection(profileCollection).doc(subjectUid);
    const [existingSnap, profileSnap] = await Promise.all([tx.get(ratingRef), tx.get(profileRef)]);
    if (!profileSnap.exists) throw error(`${subjectRole} profile not found`, 404);
    const existing = existingSnap.exists ? existingSnap.data() : {};
    const previousRating = normalizeRating(existing.rating);
    const now = admin.firestore.Timestamp.now();
    const record = {
      rideId,
      riderId: ride.riderId,
      driverId: ride.driverId,
      actorUid,
      actorRole,
      subjectUid,
      subjectRole,
      rating,
      feedback,
      compliments: subjectRole === "driver" ? compliments : [],
      favoriteDriver: subjectRole === "driver" && favoriteDriver,
      source: "rydr_backend",
      updatedAt: now,
      ...(existingSnap.exists ? {} : { createdAt: now })
    };
    const reputation = nextReputation(profileSnap.data(), previousRating, rating, existingSnap.exists ? [] : record.compliments);
    tx.set(ratingRef, record, { merge: true });
    tx.set(profileRef, {
      rating: reputation.rating,
      ratingCount: reputation.ratingCount,
      reputation: {
        ratingSum: reputation.ratingSum,
        ratingCount: reputation.ratingCount,
        complimentCounts: reputation.complimentCounts,
        updatedAt: now
      },
      ...(subjectRole === "driver" ? { compliments: reputation.topCompliments } : {}),
      updatedAt: now
    }, { merge: true });
    if (subjectRole === "driver") {
      tx.set(db.collection("publicDriverProfiles").doc(subjectUid), {
        rating: reputation.rating,
        ratingCount: reputation.ratingCount,
        compliments: reputation.topCompliments,
        updatedAt: now
      }, { merge: true });
    }
    tx.set(rideRef, {
      [actorRole === "rider" ? "riderDriverRating" : "driverRiderRating"]: record,
      updatedAt: now
    }, { merge: true });
    return { actorRole, subjectRole, rating: reputation.rating, ratingCount: reputation.ratingCount };
  });
}

module.exports = { submitRideRating, normalizeRating, cleanCompliments, nextReputation };
