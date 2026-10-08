const { admin, getFirestore } = require("../config/firebase");

const ROLES = new Set(["rider", "driver"]);
const RIDER_TERMS_VERSION = "2026-10-07";
const BETA_WAIVER_VERSION = "2026-07-04";

function error(message, statusCode, details) {
  const err = new Error(message);
  err.statusCode = statusCode;
  if (details) err.details = details;
  return err;
}

function normalizePhone(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return /^\+[1-9]\d{7,14}$/.test(trimmed) ? trimmed : null;
}

function linkedProviders(token) {
  const identities = token?.firebase?.identities;
  const providers = identities && typeof identities === "object" ? Object.keys(identities) : [];
  const signInProvider = token?.firebase?.sign_in_provider;
  if (typeof signInProvider === "string" && signInProvider) providers.push(signInProvider);
  return [...new Set(providers)].sort();
}

function cleanText(value, maxLength = 120) {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

function cleanEmail(value) {
  const email = cleanText(value, 320).toLowerCase();
  if (!/^\S+@\S+\.\S+$/.test(email)) throw error("A valid email is required", 400);
  return email;
}

function cleanAddress(value) {
  const address = value && typeof value === "object" ? value : {};
  const result = {
    street: cleanText(address.street, 160),
    line2: cleanText(address.line2, 120),
    city: cleanText(address.city, 100),
    state: cleanText(address.state, 40),
    zip: cleanText(address.zip, 20)
  };
  if (!result.street || !result.city || !result.state || !result.zip) {
    throw error("A complete rider address is required", 400);
  }
  return result;
}

function canonicalRiderProfile(payload) {
  const firstName = cleanText(payload?.firstName, 80);
  const lastName = cleanText(payload?.lastName, 80);
  if (!firstName || !lastName) throw error("First and last name are required", 400);
  if (payload?.agreedToTerms !== true || payload?.betaWaiverAccepted !== true) {
    throw error("The current rider terms and beta waiver must be accepted", 400);
  }
  const preferredName = cleanText(payload?.preferredName, 100) || firstName;
  return {
    firstName,
    lastName,
    preferredName,
    displayName: preferredName,
    email: cleanEmail(payload?.email),
    address: cleanAddress(payload?.address),
    verificationRequested: payload?.verificationRequested === true
  };
}

function validateDriverFinalization(existing) {
  const vehicle = existing?.vehicle || {};
  const license = existing?.license || {};
  if (!cleanText(existing?.firstName, 80) || !cleanText(existing?.lastName, 80) || !cleanText(existing?.email, 320)) {
    throw error("Complete the driver name and email steps first", 409);
  }
  if (!cleanText(license.number, 40) || !cleanText(license.state, 20) || existing.licenseStepCompleted !== true) {
    throw error("Complete the backend-verified driver license step first", 409);
  }
  if (!cleanText(vehicle.make, 80) || !cleanText(vehicle.model, 80) || !Number.isFinite(Number(vehicle.year)) || !cleanText(vehicle.plate, 20) || existing.vehicleStepCompleted !== true) {
    throw error("Complete the backend-verified vehicle step first", 409);
  }
  if (existing.betaWaiverAccepted !== true || existing.betaWaiverVersion !== BETA_WAIVER_VERSION) {
    throw error("Accept the current driver beta waiver first", 409);
  }
  if (existing.identityVerified !== true || existing.identityVerificationStepCompleted !== true) {
    throw error("Complete server-verified identity verification first", 409);
  }
  if (existing.backgroundCheckStepCompleted !== true) {
    throw error("Complete the background-check acknowledgement first", 409);
  }
  if (existing.stripePayoutsEnabled !== true || existing.payoutsStepCompleted !== true) {
    throw error("Complete Stripe payout onboarding first", 409);
  }
}

async function finalizeAccountProfile({ uid, role, token, payload, db = getFirestore() }) {
  if (!ROLES.has(role)) throw error("role must be rider or driver", 400);
  const phone = normalizePhone(token?.phone_number);
  if (!phone) throw error("A verified Firebase phone number is required", 409);
  const profileCollection = role === "driver" ? "drivers" : "riders";
  const indexCollection = role === "driver" ? "driverPhoneIndex" : "riderPhoneIndex";
  const profileRef = db.collection(profileCollection).doc(uid);
  const indexRef = db.collection(indexCollection).doc(phone);
  const accountLinkRef = db.collection("accountLinks").doc(uid);
  const inviteRef = db.collection("betaInvites").doc(role).collection("phones").doc(phone);
  const riderProfile = role === "rider" ? canonicalRiderProfile(payload) : null;

  return db.runTransaction(async (tx) => {
    const [profileSnap, indexSnap, accountLinkSnap, inviteSnap] = await Promise.all([
      tx.get(profileRef),
      tx.get(indexRef),
      tx.get(accountLinkRef),
      tx.get(inviteRef)
    ]);
    if (!inviteSnap.exists || inviteSnap.data().status !== "approved") {
      throw error(`This phone number is not approved for the Rydr ${role} beta`, 403);
    }
    if (indexSnap.exists && indexSnap.data().uid !== uid) {
      throw error("This verified phone number is linked to another account", 409, { code: "phone_index_conflict", role });
    }

    const existing = profileSnap.data() || {};
    if (role === "driver") {
      validateDriverFinalization(existing);
    }

    const now = admin.firestore.Timestamp.now();
    const providers = linkedProviders(token);
    const existingRoles = Array.isArray(accountLinkSnap.data()?.roles) ? accountLinkSnap.data().roles : [];
    const roles = [...new Set([...existingRoles.filter((item) => ROLES.has(item)), role])].sort();
    const canonical = role === "rider"
      ? {
          ...riderProfile,
          agreedToTerms: true,
          riderTermsVersion: RIDER_TERMS_VERSION,
          riderTermsAcceptedAt: now,
          betaWaiverAccepted: true,
          betaWaiverVersion: BETA_WAIVER_VERSION,
          betaWaiverAcceptedAt: now,
          hasRydrRiderAccess: true,
          cashHubRole: "rider",
          riderSignupCompleted: true,
          riderSignupCompletedAt: now
        }
      : {
          driverSignupCompleted: true,
          driverSignupCompletedAt: now,
          driverOnboardingStatus: "completed"
        };

    tx.set(profileRef, {
      uid,
      ...canonical,
      phoneNumber: phone,
      phoneE164: phone,
      linkedAuthProviders: providers,
      accountLinkUpdatedAt: now,
      createdAt: existing.createdAt || now,
      updatedAt: now
    }, { merge: true });
    tx.set(indexRef, {
      uid,
      role,
      phoneE164: phone,
      managedBy: "rydr_backend",
      createdAt: indexSnap.exists ? indexSnap.data().createdAt || now : now,
      updatedAt: now
    }, { merge: true });
    tx.set(accountLinkRef, {
      uid,
      roles,
      phoneE164: phone,
      email: typeof token?.email === "string" ? token.email : canonical.email || existing.email || null,
      emailVerified: token?.email_verified === true,
      providers,
      managedBy: "rydr_backend",
      createdAt: accountLinkSnap.exists ? accountLinkSnap.data().createdAt || now : now,
      updatedAt: now
    }, { merge: true });
    return { uid, role, roles, phoneE164: phone, completedAt: now.toDate().toISOString() };
  });
}

async function syncAccountIdentity({ uid, role, token, profileData = null, acceptBetaWaiver = false, db = getFirestore() }) {
  if (!ROLES.has(role)) throw error("role must be rider or driver", 400);
  const phone = normalizePhone(token?.phone_number);
  if (!phone) throw error("A verified Firebase phone number is required", 409);
  const profileCollection = role === "driver" ? "drivers" : "riders";
  const indexCollection = role === "driver" ? "driverPhoneIndex" : "riderPhoneIndex";
  const profileRef = db.collection(profileCollection).doc(uid);
  const indexRef = db.collection(indexCollection).doc(phone);
  const accountLinkRef = db.collection("accountLinks").doc(uid);
  const inviteRef = db.collection("betaInvites").doc(role).collection("phones").doc(phone);
  let canonicalProfile = {};
  if (profileData !== null) {
    if (role !== "rider" || typeof profileData !== "object") throw error("Cash Hub profile data is only supported for riders", 400);
    const firstName = String(profileData.firstName || "").trim().slice(0, 80);
    const lastName = String(profileData.lastName || "").trim().slice(0, 80);
    const email = String(profileData.email || "").trim().toLowerCase().slice(0, 320);
    if (!firstName || !lastName || !/^\S+@\S+\.\S+$/.test(email)) throw error("First name, last name, and a valid email are required", 400);
    canonicalProfile = {
      firstName,
      lastName,
      preferredName: `${firstName} ${lastName}`,
      displayName: `${firstName} ${lastName}`,
      email,
      cashHubRole: "rider",
      hasRydrRiderAccess: false
    };
  }

  return db.runTransaction(async (tx) => {
    const [profileSnap, indexSnap, accountLinkSnap, inviteSnap] = await Promise.all([
      tx.get(profileRef),
      tx.get(indexRef),
      tx.get(accountLinkRef),
      tx.get(inviteRef)
    ]);
    if (!profileSnap.exists && (!inviteSnap.exists || inviteSnap.data().status !== "approved")) {
      throw error(`This phone number is not approved for the Rydr ${role} beta`, 403);
    }
    const existingUid = indexSnap.exists ? indexSnap.data().uid : null;
    if (existingUid && existingUid !== uid) {
      throw error("This verified phone number is linked to another account", 409, {
        code: "phone_index_conflict",
        role
      });
    }
    const now = admin.firestore.Timestamp.now();
    const previousPhone = normalizePhone(profileSnap.data()?.phoneE164 ?? profileSnap.data()?.phoneNumber);
    if (previousPhone && previousPhone !== phone) {
      const previousIndexRef = db.collection(indexCollection).doc(previousPhone);
      const previousIndexSnap = await tx.get(previousIndexRef);
      if (previousIndexSnap.exists && previousIndexSnap.data().uid === uid) tx.delete(previousIndexRef);
    }
    const providers = linkedProviders(token);
    const existingRoles = Array.isArray(accountLinkSnap.data()?.roles) ? accountLinkSnap.data().roles : [];
    const roles = [...new Set([...existingRoles.filter((item) => ROLES.has(item)), role])].sort();
    tx.set(indexRef, {
      uid,
      role,
      phoneE164: phone,
      managedBy: "rydr_backend",
      createdAt: indexSnap.exists ? indexSnap.data().createdAt ?? now : now,
      updatedAt: now
    }, { merge: true });
    tx.set(profileRef, {
      uid,
      ...canonicalProfile,
      ...(role === "driver" && acceptBetaWaiver === true ? {
        betaWaiverAccepted: true,
        betaWaiverVersion: BETA_WAIVER_VERSION,
        betaWaiverAcceptedAt: now
      } : {}),
      phoneNumber: phone,
      phoneE164: phone,
      linkedAuthProviders: providers,
      accountLinkUpdatedAt: now,
      createdAt: profileSnap.exists ? profileSnap.data().createdAt ?? now : now,
      updatedAt: now
    }, { merge: true });
    tx.set(accountLinkRef, {
      uid,
      roles,
      phoneE164: phone,
      email: typeof token?.email === "string" ? token.email : null,
      emailVerified: token?.email_verified === true,
      providers,
      managedBy: "rydr_backend",
      createdAt: accountLinkSnap.exists ? accountLinkSnap.data().createdAt ?? now : now,
      updatedAt: now
    }, { merge: true });
    return { uid, role, roles, phoneE164: phone, providers };
  });
}

module.exports = {
  syncAccountIdentity,
  finalizeAccountProfile,
  canonicalRiderProfile,
  validateDriverFinalization,
  normalizePhone,
  linkedProviders,
  RIDER_TERMS_VERSION,
  BETA_WAIVER_VERSION
};
