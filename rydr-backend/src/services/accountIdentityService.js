const { admin, getFirestore } = require("../config/firebase");

const ROLES = new Set(["rider", "driver"]);

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

async function syncAccountIdentity({ uid, role, token, db = getFirestore() }) {
  if (!ROLES.has(role)) throw error("role must be rider or driver", 400);
  const phone = normalizePhone(token?.phone_number);
  if (!phone) throw error("A verified Firebase phone number is required", 409);
  const profileCollection = role === "driver" ? "drivers" : "riders";
  const indexCollection = role === "driver" ? "driverPhoneIndex" : "riderPhoneIndex";
  const profileRef = db.collection(profileCollection).doc(uid);
  const indexRef = db.collection(indexCollection).doc(phone);
  const accountLinkRef = db.collection("accountLinks").doc(uid);
  const inviteRef = db.collection("betaInvites").doc(role).collection("phones").doc(phone);

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
      phoneNumber: phone,
      phoneE164: phone,
      linkedAuthProviders: providers,
      accountLinkUpdatedAt: now,
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

module.exports = { syncAccountIdentity, normalizePhone, linkedProviders };
