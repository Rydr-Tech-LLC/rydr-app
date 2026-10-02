const { getVisionClient } = require("../config/vision");
const { admin, getFirestore, getStorageBucketsForReads } = require("../config/firebase");
const { randomUUID } = require("crypto");

// SafeSearch returns a likelihood for each category: UNKNOWN, VERY_UNLIKELY,
// UNLIKELY, POSSIBLE, LIKELY, VERY_LIKELY.
const REJECT_LIKELIHOODS = new Set(["LIKELY", "VERY_LIKELY"]);
const REVIEW_LIKELIHOODS = new Set(["POSSIBLE"]);

// "medical" and "spoof" are returned by SafeSearch but aren't relevant to
// profile-photo moderation, so they're left out of the verdict calculation.
const CATEGORIES = ["adult", "violence", "racy"];

class NotFoundError extends Error {
  constructor(message) {
    super(message);
    this.statusCode = 404;
  }
}

async function fetchImageBytes(storagePath) {
  const buckets = getStorageBucketsForReads();
  const checkedBuckets = [];

  for (const bucket of buckets) {
    checkedBuckets.push(bucket.name);
    const file = bucket.file(storagePath);
    const [exists] = await file.exists();
    if (exists) {
      const [buffer] = await file.download();
      return buffer;
    }
  }

  throw new NotFoundError(
    `No file found at storage path: ${storagePath}. Checked buckets: ${checkedBuckets.join(", ")}`
  );
}

async function findStoredFile(storagePath) {
  for (const bucket of getStorageBucketsForReads()) {
    const file = bucket.file(storagePath);
    const [exists] = await file.exists();
    if (exists) return { bucket, file };
  }
  throw new NotFoundError(`No file found at storage path: ${storagePath}`);
}

async function finalizeProfilePhoto({ storagePath, uid }) {
  const isDriver = storagePath.startsWith(`driverProfilePhotos/${uid}/`);
  const isRider = storagePath.startsWith(`pendingProfilePhotos/${uid}/`);
  if (!isDriver && !isRider) throw Object.assign(new Error("Profile photo path is not allowed"), { statusCode: 403 });
  const { bucket, file } = await findStoredFile(storagePath);
  const [buffer] = await file.download();
  const token = randomUUID();
  const finalPath = isDriver ? `driverProfilePhotos/${uid}.jpg` : `profilePhotos/${uid}.jpg`;
  const finalFile = bucket.file(finalPath);
  const db = getFirestore();
  const profileRef = db.collection(isDriver ? "drivers" : "riders").doc(uid);
  const profileSnap = await profileRef.get();
  if (!profileSnap.exists) throw Object.assign(new Error("Profile not found"), { statusCode: 404 });
  await finalFile.save(buffer, {
    resumable: false,
    metadata: {
      contentType: "image/jpeg",
      cacheControl: "public,max-age=3600",
      metadata: { firebaseStorageDownloadTokens: token }
    }
  });
  const photoURL = `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucket.name)}/o/${encodeURIComponent(finalPath)}?alt=media&token=${token}`;
  const now = admin.firestore.Timestamp.now();
  const profileUpdate = isDriver
    ? {
        profilePhotoURL: photoURL,
        profilePhotoReviewStatus: "approved",
        pendingProfilePhotoURL: admin.firestore.FieldValue.delete(),
        pendingProfilePhotoPath: admin.firestore.FieldValue.delete(),
        profilePhotoUpdatedAt: now,
        updatedAt: now
      }
    : { photoURL, profilePhotoUpdatedAt: now, updatedAt: now };
  const batch = db.batch();
  batch.set(profileRef, profileUpdate, { merge: true });
  if (isDriver) batch.set(db.collection("publicDriverProfiles").doc(uid), { profilePhotoURL: photoURL, updatedAt: now }, { merge: true });
  await batch.commit();
  await file.delete({ ignoreNotFound: true });
  return { photoURL, finalPath, role: isDriver ? "driver" : "rider" };
}

async function discardPendingPhoto(storagePath) {
  try {
    const { file } = await findStoredFile(storagePath);
    await file.delete({ ignoreNotFound: true });
  } catch (err) {
    if (!(err instanceof NotFoundError)) throw err;
  }
}

function evaluateSafeSearch(safeSearchAnnotation = {}) {
  const flagged = [];
  let verdict = "approved";

  for (const category of CATEGORIES) {
    const likelihood = safeSearchAnnotation[category] || "UNKNOWN";

    if (REJECT_LIKELIHOODS.has(likelihood)) {
      verdict = "rejected";
      flagged.push({ category, likelihood });
    } else if (REVIEW_LIKELIHOODS.has(likelihood) && verdict !== "rejected") {
      verdict = "needs_review";
      flagged.push({ category, likelihood });
    }
  }

  return { verdict, flagged, raw: safeSearchAnnotation };
}

/**
 * Downloads the image at the given Firebase Storage path and runs it
 * through Google Cloud Vision's SafeSearch detector.
 *
 * @param {string} storagePath e.g. "pendingProfilePhotos/<uid>/<uuid>.jpg"
 * @returns {Promise<{verdict: "approved"|"needs_review"|"rejected", flagged: Array, raw: object}>}
 */
async function checkImage(storagePath) {
  const imageBuffer = await fetchImageBytes(storagePath);
  const client = getVisionClient();

  const [result] = await client.safeSearchDetection({
    image: { content: imageBuffer }
  });

  return evaluateSafeSearch(result.safeSearchAnnotation);
}

module.exports = {
  checkImage,
  evaluateSafeSearch,
  NotFoundError,
  finalizeProfilePhoto,
  discardPendingPhoto
};
