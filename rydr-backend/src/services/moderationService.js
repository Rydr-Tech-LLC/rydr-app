const { getVisionClient } = require("../config/vision");
const { getStorageBucketsForReads } = require("../config/firebase");

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
  NotFoundError
};
