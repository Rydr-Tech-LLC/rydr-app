const { admin, getFirestore } = require("../config/firebase");

function error(message, statusCode) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function clean(value, max = 200) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

async function recordBackgroundCheckIntent({ uid, payload, redirected = false, db = getFirestore() }) {
  const profileRef = db.collection("drivers").doc(uid);
  const profileSnap = await profileRef.get();
  if (!profileSnap.exists) throw error("Driver profile not found", 404);
  const firstName = clean(payload?.firstName, 80);
  const lastName = clean(payload?.lastName, 80);
  const email = clean(payload?.email, 254);
  const phone = clean(payload?.phone, 24);
  const licenseState = clean(payload?.licenseState, 2).toUpperCase();
  const licenseLast4 = clean(payload?.licenseLast4, 4);
  if (!firstName || !lastName || !email || !phone || !licenseState) throw error("Background-check identity fields are required", 400);
  if (!redirected && payload?.acknowledged !== true) throw error("Background-check acknowledgement is required", 400);
  const now = admin.firestore.Timestamp.now();
  const update = {
    backgroundCheckProvider: "checkr",
    backgroundCheckFlow: "external_redirect",
    backgroundCheckStatus: "manual_pending",
    backgroundCheckManualReviewRequired: true,
    backgroundCheckLegalFirstName: firstName,
    backgroundCheckLegalLastName: lastName,
    backgroundCheckEmail: email,
    backgroundCheckPhone: phone,
    backgroundCheckLicenseState: licenseState,
    backgroundCheckSource: "rydr_backend",
    updatedAt: now
  };
  if (licenseLast4) update.backgroundCheckLicenseNumberLast4 = licenseLast4;
  if (redirected) {
    update.backgroundCheckRedirectURL = "https://candidate.checkr.com/";
    update.backgroundCheckRedirectedAt = now;
  } else {
    update.backgroundCheckAcknowledged = true;
    update.backgroundCheckAcknowledgedAt = now;
    update.backgroundAcknowledgementVersion = 1;
    update.backgroundCheckStepCompleted = true;
    update.betaAgreementAccepted = true;
    update.betaAgreementAcceptedAt = now;
    if (typeof payload?.dob === "string" && payload.dob) update.backgroundCheckDob = payload.dob.slice(0, 10);
  }
  await profileRef.set(update, { merge: true });
  return { status: update.backgroundCheckStatus, acknowledged: !redirected };
}

module.exports = { recordBackgroundCheckIntent };
