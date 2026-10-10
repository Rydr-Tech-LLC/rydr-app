const { admin, getFirestore } = require("../config/firebase");
const { tierFor } = require("./rideFinancialService");

function error(message, statusCode) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function canonical(value) {
  const text = String(value || "").trim().toLowerCase();
  if (text.includes("eco")) return "Rydr Eco";
  if (text.includes("xl")) return "Rydr XL";
  if (text.includes("executive")) return "Rydr Executive";
  if (text.includes("prestine") || text.includes("pristine")) return "Rydr Prestine";
  return text.includes("go") ? "Rydr Go" : String(value || "").trim();
}

function validRate(value, field) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0 || number > 1_000_000) throw error(`${field} must be a nonnegative amount`, 400);
  return Math.round(number * 100) / 100;
}

function normalizeTierRates(value) {
  if (!value || typeof value !== "object") return {};
  return Object.fromEntries(Object.entries(value).map(([key, rate]) => [tierFor(key), rate]));
}

function timestampMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.toDate === "function") return value.toDate().getTime();
  if (Number.isFinite(value._seconds)) return value._seconds * 1000;
  if (Number.isFinite(value.seconds)) return value.seconds * 1000;
  return 0;
}

async function getDriverRateCard({ uid, db = getFirestore() }) {
  const driverRef = db.collection("drivers").doc(uid);
  const publicRef = db.collection("publicDriverProfiles").doc(uid);
  return db.runTransaction(async (tx) => {
    const [driverSnap, publicSnap] = await Promise.all([tx.get(driverRef), tx.get(publicRef)]);
    if (!driverSnap.exists) throw error("Driver profile not found", 404);

    const driver = driverSnap.data() || {};
    const publicProfile = publicSnap.exists ? (publicSnap.data() || {}) : {};
    const driverRates = normalizeTierRates(driver.tierRates);
    const publicRates = normalizeTierRates(publicProfile.tierRates);
    const publicIsCanonical = Object.keys(publicRates).length > 0 && (
      Object.keys(driverRates).length === 0
      || timestampMillis(publicProfile.rateCardUpdatedAt) >= timestampMillis(driver.rateCardUpdatedAt)
    );
    const tierRates = publicIsCanonical ? publicRates : driverRates;

    // Older clients could leave the private and public copies out of sync.
    // Reconcile them on authenticated reads so driver UI and rider quotes use
    // the same backend-owned rate card.
    if (Object.keys(tierRates).length > 0) {
      const rateCardUpdatedAt = publicIsCanonical
        ? (publicProfile.rateCardUpdatedAt || admin.firestore.Timestamp.now())
        : (driver.rateCardUpdatedAt || admin.firestore.Timestamp.now());
      tx.set(driverRef, { tierRates, rateCardUpdatedAt }, { merge: true });
      tx.set(publicRef, { tierRates, rateCardUpdatedAt }, { merge: true });
    }
    return { tierRates };
  });
}

async function updateDriverRateCard({ uid, payload, db = getFirestore() }) {
  const rideType = canonical(payload?.rideType);
  const rateKey = tierFor(rideType);
  if (!rideType) throw error("rideType is required", 400);
  const driverRef = db.collection("drivers").doc(uid);
  const statusRef = db.collection("driver_status").doc(uid);
  const publicRef = db.collection("publicDriverProfiles").doc(uid);
  return db.runTransaction(async (tx) => {
    const [driverSnap, statusSnap] = await Promise.all([tx.get(driverRef), tx.get(statusRef)]);
    if (!driverSnap.exists) throw error("Driver profile not found", 404);
    const driver = driverSnap.data();
    if (driver.isOnline === true || driver.online === true || statusSnap.data()?.isOnline === true) {
      throw error("Rates may only be changed while offline", 409);
    }
    const qualified = (driver.qualifiedRideTypes ?? driver.supportedRideTypes ?? driver.eligibleRideTypes ?? []).map(tierFor);
    if (!qualified.includes(rateKey)) throw error("Driver is not eligible for this ride type", 403);
    const rate = {
      rideType,
      minimumFare: validRate(payload?.minimumFare, "minimumFare"),
      perMile: validRate(payload?.perMile, "perMile"),
      perMinute: validRate(payload?.perMinute, "perMinute"),
      useSuggestedPricing: payload?.useSuggestedPricing === true,
      pricingOwner: "rydr_backend",
      updatedAt: admin.firestore.Timestamp.now()
    };
    const tierRates = { ...normalizeTierRates(driver.tierRates), [rateKey]: rate };
    const now = admin.firestore.Timestamp.now();
    tx.set(driverRef, { tierRates, rateCardUpdatedAt: now, updatedAt: now }, { merge: true });
    tx.set(publicRef, { tierRates, rateCardUpdatedAt: now, updatedAt: now }, { merge: true });
    return { rideType, rate };
  });
}

module.exports = { getDriverRateCard, updateDriverRateCard, canonical, validRate, normalizeTierRates, timestampMillis };
