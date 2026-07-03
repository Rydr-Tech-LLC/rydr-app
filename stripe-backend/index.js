// index.js
"use strict";

const express = require("express");
const cors = require("cors");
const dotenv = require("dotenv");
const admin = require("firebase-admin");
const Stripe = require("stripe");

dotenv.config();

if (!process.env.STRIPE_SECRET_KEY) {
  console.error("❌ Missing STRIPE_SECRET_KEY");
  process.exit(1);
}

const app = express();
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY, { apiVersion: "2024-06-20" });
const identityFlows = {
  driver: process.env.STRIPE_DRIVER_VERIFICATION_FLOW_ID,
  verified_rider: process.env.STRIPE_RIDER_VERIFICATION_FLOW_ID,
};

function isValidIdentityRole(role) {
  return role === "driver" || role === "verified_rider";
}

function identityFlowForRole(role) {
  if (!isValidIdentityRole(role)) return null;
  return identityFlows[role] || null;
}

function identitySessionErrorPayload(err) {
  const code = err?.code || err?.type || "identity_session_failed";
  const message = String(err?.message || "");

  if (code === "resource_missing" || message.includes("No such verification_flow")) {
    return {
      status: 500,
      body: {
        error: "identity_verification_flow_invalid",
        message: "Stripe could not find the configured rider verification flow. Confirm STRIPE_RIDER_VERIFICATION_FLOW_ID in the Stripe backend environment.",
      },
    };
  }

  if (code === "parameter_unknown" || code === "parameter_invalid_empty") {
    return {
      status: 500,
      body: {
        error: "stripe_identity_request_invalid",
        message: message || "Stripe rejected the Identity session request.",
      },
    };
  }

  if (code === "api_key_expired" || code === "authentication_error") {
    return {
      status: 500,
      body: {
        error: "stripe_identity_auth_failed",
        message: "Stripe rejected the backend API key. Check STRIPE_SECRET_KEY on the Stripe backend.",
      },
    };
  }

  if (isFirebaseAdminConfigError(err)) {
    return {
      status: 500,
      body: {
        error: "firebase_admin_misconfigured",
        message: "The Stripe backend Firebase Admin credentials are not configured correctly.",
      },
    };
  }

  return {
    status: 500,
    body: {
      error: "identity_session_failed",
      message: message || "Stripe Identity could not create a verification session.",
      code,
    },
  };
}

function firebaseCredential() {
  const FIREBASE_PROJECT_ID =
    process.env.FIREBASE_PROJECT_ID || process.env.FIREBASE_ADMIN_PROJECT_ID;
  const FIREBASE_CLIENT_EMAIL =
    process.env.FIREBASE_CLIENT_EMAIL || process.env.FIREBASE_ADMIN_CLIENT_EMAIL;
  const FIREBASE_PRIVATE_KEY =
    process.env.FIREBASE_PRIVATE_KEY || process.env.FIREBASE_ADMIN_PRIVATE_KEY;

  if (FIREBASE_PROJECT_ID && FIREBASE_CLIENT_EMAIL && FIREBASE_PRIVATE_KEY) {
    return admin.credential.cert({
      projectId: FIREBASE_PROJECT_ID,
      clientEmail: FIREBASE_CLIENT_EMAIL,
      privateKey: FIREBASE_PRIVATE_KEY.replace(/\\n/g, "\n")
    });
  }

  return admin.credential.applicationDefault();
}

function initializeFirebase() {
  if (admin.apps.length > 0) return admin.app();
  return admin.initializeApp({ credential: firebaseCredential() });
}

function isFirebaseAdminConfigError(err) {
  const message = String(err?.message || "");
  return (
    message.includes("Could not load the default credentials") ||
    message.includes("Failed to parse private key") ||
    message.includes("Invalid PEM formatted message") ||
    message.includes("Service account object must contain") ||
    message.includes("app/invalid-credential")
  );
}

async function verifiedFirebaseUid(req) {
  const authorization = req.header("authorization") || "";
  const match = authorization.match(/^Bearer (.+)$/);
  if (!match) return null;

  initializeFirebase();
  const decoded = await admin.auth().verifyIdToken(match[1]);
  return decoded.uid;
}

async function requireFirebaseUid(req, res) {
  try {
    const uid = await verifiedFirebaseUid(req);
    if (!uid) {
      res.status(401).json({ error: "unauthorized" });
      return null;
    }
    return uid;
  } catch (err) {
    console.warn("⚠️ Firebase auth failed", err.message);
    if (isFirebaseAdminConfigError(err)) {
      res.status(500).json({ error: "firebase_admin_misconfigured" });
      return null;
    }
    res.status(401).json({ error: "unauthorized" });
    return null;
  }
}

// Admin-claim auth — mirrors the `isAdmin()` check in Rydr_Firebase's
// Firestore rules and Mission Control's session role check. Used only by
// the account-deletion cleanup endpoint below, which is the one place in
// this service that needs to act on a Stripe customer/Connect account on
// someone else's behalf (a human admin, not the account owner).
//
// Mission Control authenticates its admins with a session *cookie*, not a
// Firebase ID token, so it has nothing to put in an `Authorization: Bearer`
// header to satisfy `verifyIdToken`. Rather than minting custom tokens
// across services (which still requires a client-side exchange step and
// would NOT work from a server route), this also accepts a static shared
// secret for trusted server-to-server calls between our own backends. The
// secret is never exposed to a browser — only Mission Control's server-side
// route handler holds it (see RYDR_INTERNAL_ADMIN_SECRET in both services'
// env). A request still works the normal Firebase-admin-claim way for any
// future direct-from-app admin tooling.
async function requireAdminUid(req, res) {
  try {
    const sharedSecret = req.header("x-internal-admin-secret");
    if (sharedSecret && process.env.RYDR_INTERNAL_ADMIN_SECRET && sharedSecret === process.env.RYDR_INTERNAL_ADMIN_SECRET) {
      const onBehalfOf = req.header("x-admin-uid") || "mission-control";
      return onBehalfOf;
    }

    const authorization = req.header("authorization") || "";
    const match = authorization.match(/^Bearer (.+)$/);
    if (!match) {
      res.status(401).json({ error: "unauthorized" });
      return null;
    }

    initializeFirebase();
    const decoded = await admin.auth().verifyIdToken(match[1]);
    const isAdminClaim = decoded.admin === true || decoded.role === "admin";
    if (!isAdminClaim) {
      res.status(403).json({ error: "admin_required" });
      return null;
    }
    return decoded.uid;
  } catch (err) {
    console.warn("⚠️ Admin auth failed", err.message);
    res.status(401).json({ error: "unauthorized" });
    return null;
  }
}

async function persistStripeCustomerId(uid, customerId) {
  if (!uid || !customerId) return;
  initializeFirebase();
  await admin.firestore().collection("riders").doc(uid).set(
    {
      stripeCustomerId: customerId,
      stripeCustomerUpdatedAt: admin.firestore.FieldValue.serverTimestamp()
    },
    { merge: true }
  );
}

async function updateRider(uid, payload) {
  if (!uid) return;
  initializeFirebase();
  await admin.firestore().collection("riders").doc(uid).set(
    {
      ...payload,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function authUserProfile(uid) {
  initializeFirebase();
  const user = await admin.auth().getUser(uid);
  return {
    email: user.email || undefined,
    name: user.displayName || undefined,
  };
}

// --- Driver Connect helpers ---
function appBaseURL() {
  const base = process.env.APP_BASE_URL;
  if (!base) {
    throw new Error("APP_BASE_URL is required for hosted Stripe return URLs");
  }
  return base.replace(/\/+$/, "");
}

async function updateDriver(uid, payload) {
  if (!uid) return;
  initializeFirebase();
  await admin.firestore().collection("drivers").doc(uid).set(
    {
      ...payload,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

function missionControlIdentityStatus(status) {
  if (status === "verified") return "verified";
  if (status === "processing") return "pending";
  if (status === "requires_input" || status === "canceled") return "failed";
  return "not_started";
}

function missionControlConnectStatus(account) {
  if (!account?.id) return "not_started";
  return account.charges_enabled && account.payouts_enabled ? "completed" : "pending";
}

async function driverData(uid) {
  if (!uid) return null;
  initializeFirebase();
  const snapshot = await admin.firestore().collection("drivers").doc(uid).get();
  return snapshot.exists ? snapshot.data() : null;
}

async function identityProfile(uid, role) {
  initializeFirebase();
  const collection = role === "driver" ? "drivers" : "riders";
  const snapshot = await admin.firestore().collection(collection).doc(uid).get();
  const data = snapshot.exists ? snapshot.data() : {};
  const firstName = data?.firstName || "";
  const lastName = data?.lastName || "";
  const displayName = data?.displayName || data?.name || [firstName, lastName].filter(Boolean).join(" ");
  return {
    email: data?.email || undefined,
    name: displayName || undefined,
  };
}

async function updateIdentityStatus(session, status) {
  const uid = session.metadata?.uid;
  const role = session.metadata?.role;
  if (!uid || !role) return;

  const timestamp = admin.firestore.FieldValue.serverTimestamp();
  const base = {
    identityStatus: status,
    stripeIdentityStatus: missionControlIdentityStatus(status),
    stripeIdentityVerificationId: session.id,
    stripeIdentityFlow: role,
    stripeIdentityLastEventAt: timestamp,
  };
  const lastError = session.last_error?.reason || session.last_error?.code || null;

  if (role === "driver") {
    if (status === "verified") {
      await updateDriver(uid, {
        ...base,
        identityVerified: true,
        identityVerifiedAt: timestamp,
      });
    } else {
      await updateDriver(uid, {
        ...base,
        identityVerified: false,
        identityLastError: lastError,
      });
    }
    return;
  }

  if (role === "verified_rider") {
    if (status === "verified") {
      await updateRider(uid, {
        ...base,
        verifiedRider: true,
        identityVerified: true,
        verifiedBadge: true,
        identityVerifiedAt: timestamp,
      });
    } else {
      await updateRider(uid, {
        ...base,
        verifiedRider: false,
        identityVerified: false,
        verifiedBadge: false,
        identityLastError: lastError,
      });
    }
  }
}

// Denormalize the subset of Connect status the rider app needs (to build a
// destination charge) onto the driver's public profile, which riders can read.
async function updatePublicDriverConnectStatus(uid, { stripeAccountId, stripeChargesEnabled }) {
  if (!uid) return;
  initializeFirebase();
  await admin.firestore().collection("publicDriverProfiles").doc(uid).set(
    {
      stripeAccountId,
      stripeChargesEnabled: !!stripeChargesEnabled,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

// --- Payment ownership + idempotency helpers ---------------------------------
//
// Phase 2 (Payment Hardening) rule: never trust a client-provided
// customerId / paymentMethodId / driverAccountId. Every payment-affecting
// route below re-derives these from Firestore/Stripe using the verified
// Firebase uid, and only ever falls back to a client value to detect +
// reject a mismatch (defense in depth), never to authorize an action.

/** The Stripe customerId actually on file for this rider, or null. */
async function ownedCustomerId(uid) {
  if (!uid) return null;
  initializeFirebase();
  const snap = await admin.firestore().collection("riders").doc(uid).get();
  return snap.exists ? (snap.data().stripeCustomerId || null) : null;
}

function suppliedValue(req, key) {
  const bodyValue = req.body && Object.prototype.hasOwnProperty.call(req.body, key)
    ? req.body[key]
    : undefined;
  if (bodyValue !== undefined && bodyValue !== null && String(bodyValue).trim() !== "") {
    return String(bodyValue);
  }
  const queryValue = req.query && Object.prototype.hasOwnProperty.call(req.query, key)
    ? req.query[key]
    : undefined;
  if (queryValue !== undefined && queryValue !== null && String(queryValue).trim() !== "") {
    return String(queryValue);
  }
  return null;
}

function requireRequestId(req, res, operation) {
  const requestId = suppliedValue(req, "requestId");
  if (!requestId || !/^[A-Za-z0-9_-]{8,80}$/.test(requestId)) {
    res.status(400).json({ error: "requestId_required", operation });
    return null;
  }
  return requestId;
}

function rejectIfSuppliedUidMismatch(req, res, uid) {
  const suppliedUid = suppliedValue(req, "uid");
  if (suppliedUid && suppliedUid !== uid) {
    res.status(403).json({ error: "uid_mismatch" });
    return true;
  }
  return false;
}

async function rejectIfSuppliedCustomerMismatch(req, res, uid) {
  const suppliedCustomerId = suppliedValue(req, "customerId");
  if (!suppliedCustomerId) return false;

  const customerId = await ownedCustomerId(uid);
  if (!customerId || suppliedCustomerId !== customerId) {
    res.status(403).json({ error: "customer_not_owned" });
    return true;
  }
  return false;
}

function rejectIfSuppliedAccountMismatch(req, res, accountId) {
  const suppliedAccountId = suppliedValue(req, "accountId") || suppliedValue(req, "connectedAccountId");
  if (suppliedAccountId && suppliedAccountId !== accountId) {
    res.status(403).json({ error: "connect_account_not_owned" });
    return true;
  }
  return false;
}

/**
 * Loads a ride the authenticated rider owns. Returns null (and never
 * throws) if the ride doesn't exist or belongs to someone else, so callers
 * can respond 404/403 without leaking which case it was.
 */
async function ownedRide(uid, rideId) {
  if (!uid || !rideId) return null;
  initializeFirebase();
  const snap = await admin.firestore().collection("rides").doc(rideId).get();
  if (!snap.exists) return null;
  const data = snap.data();
  if (data.riderId !== uid) return null;
  return { ref: snap.ref, data };
}

/** Driver's Connect account, looked up server-side from the ride's driverId — never from the client. */
async function driverAccountForRide(rideData) {
  if (!rideData?.driverId) return null;
  const driver = await driverData(rideData.driverId);
  if (!driver?.stripeAccountId || !driver?.stripeChargesEnabled) return null;
  return driver.stripeAccountId;
}

// Matches RydrPricing.driverPayoutShare in Features/Booking/RideManager.swift —
// the platform keeps 30% of the ride fare (plus, on the client's existing fare
// breakdown, the full booking fee). Used as a safety ceiling so a tampered
// applicationFeeAmount can never let a rider's full charge bypass the
// platform's cut entirely.
const PLATFORM_MIN_FEE_SHARE = 0.30;

const PAYMENT_STATUSES = new Set(["pending", "processing", "succeeded", "failed", "refunded"]);
const CHARGEABLE_RIDE_STATUSES = new Set(["completed"]);

function integerField(data, key) {
  const value = data?.[key];
  if (Number.isInteger(value)) return value;
  if (typeof value === "number" && Number.isFinite(value)) return Math.round(value);
  if (typeof value === "string" && /^-?\d+$/.test(value.trim())) return Number.parseInt(value, 10);
  return null;
}

function positiveIntegerField(data, key) {
  const value = integerField(data, key);
  return value !== null && value > 0 ? value : null;
}

function nonNegativeIntegerField(data, key) {
  const value = integerField(data, key);
  return value !== null && value >= 0 ? value : null;
}

function authorizedRideChargeCents(ride) {
  return nonNegativeIntegerField(ride, "finalRiderChargeCents")
    ?? nonNegativeIntegerField(ride, "authorizedRiderChargeCents");
}

function timestampMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.toDate === "function") return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  if (Number.isFinite(value?._seconds)) return value._seconds * 1000 + Math.round((value._nanoseconds || 0) / 1_000_000);
  if (Number.isFinite(value?.seconds)) return value.seconds * 1000 + Math.round((value.nanoseconds || 0) / 1_000_000);
  return null;
}

function pickupPaidWaitSeconds(ride) {
  const explicitPaidStart = timestampMillis(ride?.pickupPaidWaitStartedAt);
  const waitStart = timestampMillis(ride?.pickupWaitStartedAt) || timestampMillis(ride?.arrivedAtPickupAt);
  const rideStart = timestampMillis(ride?.rideStartedAt) || timestampMillis(ride?.startedAt);
  const completedAt = timestampMillis(ride?.completedAt);
  const waitEnd = rideStart || completedAt;

  if (explicitPaidStart && waitEnd && waitEnd > explicitPaidStart) {
    return Math.floor((waitEnd - explicitPaidStart) / 1000);
  }
  if (waitStart && waitEnd && waitEnd > waitStart) {
    const complimentarySeconds = positiveIntegerField(ride, "pickupComplimentaryWaitSeconds") ?? 180;
    return Math.max(0, Math.floor((waitEnd - waitStart) / 1000) - complimentarySeconds);
  }
  return 0;
}

function pickupWaitChargeCents(ride) {
  const seconds = pickupPaidWaitSeconds(ride);
  if (seconds <= 0) return { seconds: 0, cents: 0 };
  const perMinuteCents = positiveIntegerField(ride, "driverRatePerMinuteCents");
  if (!perMinuteCents) return { seconds, cents: 0 };
  return { seconds, cents: Math.round((seconds / 60) * perMinuteCents) };
}

function resolvedRideCharge(ride) {
  const baseAmount = authorizedRideChargeCents(ride);
  if (baseAmount === null) return null;
  const wait = pickupWaitChargeCents(ride);
  return {
    amount: baseAmount + wait.cents,
    baseAmount,
    pickupPaidWaitSeconds: wait.seconds,
    pickupWaitChargeCents: wait.cents,
  };
}

function platformFeeCents(ride, chargeAmountCents, resolvedCharge = null) {
  const explicitPlatformShare = nonNegativeIntegerField(ride, "estimatedPlatformShareCents");
  const promoDiscount = nonNegativeIntegerField(ride, "promoDiscountCents") ?? 0;
  const waitCharge = resolvedCharge?.pickupWaitChargeCents ?? 0;
  const waitPlatformShare = Math.round(waitCharge * PLATFORM_MIN_FEE_SHARE);
  if (explicitPlatformShare !== null) {
    return Math.min(Math.max(0, explicitPlatformShare - promoDiscount) + waitPlatformShare, chargeAmountCents);
  }
  return Math.round(chargeAmountCents * PLATFORM_MIN_FEE_SHARE);
}

/** Persists payment state onto the ride document the rider/driver apps already listen to. */
async function recordPaymentStatus(rideRef, status, fields = {}) {
  if (!PAYMENT_STATUSES.has(status)) {
    throw new Error(`invalid paymentStatus "${status}"`);
  }
  initializeFirebase();
  await rideRef.set(
    {
      paymentStatus: status,
      lastPaymentAttempt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...fields,
    },
    { merge: true }
  );
}

async function rideByPaymentIntentMetadata(rideId) {
  if (!rideId) return null;
  initializeFirebase();
  const ref = admin.firestore().collection("rides").doc(rideId);
  const snap = await ref.get();
  return snap.exists ? ref : null;
}

// --- CORS (optional; iOS native calls don't need it, web would) ---
const allowed = (process.env.CORS_ORIGINS || "")
  .split(",").map(s => s.trim()).filter(Boolean);
app.use(cors({
  origin: (origin, cb) =>
    !origin || allowed.length === 0 || allowed.includes(origin)
      ? cb(null, true)
      : cb(new Error("Not allowed by CORS")),
}));

// --- Health ---
app.get("/", (_req, res) => res.send("✅ Rydr Stripe backend is running"));

// --- Webhook (RAW body; mount BEFORE json parser) ---
app.post("/webhook", express.raw({ type: "application/json" }), async (req, res) => {
  const sig = req.headers["stripe-signature"];
  try {
    const event = stripe.webhooks.constructEvent(
      req.body,
      sig,
      process.env.STRIPE_WEBHOOK_SECRET
    );

    switch (event.type) {
      case "setup_intent.succeeded":
        console.log("💳 setup_intent.succeeded:", event.data.object.id);
        break;
      case "payment_intent.succeeded": {
        const pi = event.data.object;
        console.log("💰 payment_intent.succeeded:", pi.id);
        const rideId = pi.metadata?.rideId;
        const rideRef = await rideByPaymentIntentMetadata(rideId);
        if (rideRef) {
          if (pi.metadata?.paymentType === "driver_tip") {
            await rideRef.set(
              {
                tipPaymentStatus: "succeeded",
                stripeTipPaymentIntentId: pi.id,
                tipAmountCents: pi.amount_received || pi.amount,
                pendingTipAmountCents: admin.firestore.FieldValue.delete(),
                tipFailureReason: null,
                tipFailureCode: null,
                tippedAt: admin.firestore.FieldValue.serverTimestamp(),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true }
            );
          } else {
            await recordPaymentStatus(rideRef, "succeeded", {
              stripePaymentIntentId: pi.id,
              failureReason: null,
              failureCode: null,
            });
          }
        }
        break;
      }
      case "payment_intent.payment_failed": {
        const pi = event.data.object;
        console.log("⚠️ payment_intent.payment_failed:", pi.id);
        const rideId = pi.metadata?.rideId;
        const rideRef = await rideByPaymentIntentMetadata(rideId);
        if (rideRef) {
          if (pi.metadata?.paymentType === "driver_tip") {
            await rideRef.set(
              {
                tipPaymentStatus: "failed",
                stripeTipPaymentIntentId: pi.id,
                tipFailureReason: pi.last_payment_error?.message || "Tip payment failed",
                tipFailureCode: pi.last_payment_error?.code || null,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true }
            );
          } else {
            await recordPaymentStatus(rideRef, "failed", {
              stripePaymentIntentId: pi.id,
              failureReason: pi.last_payment_error?.message || "Payment failed",
              failureCode: pi.last_payment_error?.code || null,
            });
          }
        }
        break;
      }
      case "account.updated": {
        const acct = event.data.object;
        console.log("ℹ️ account.updated", acct.id, {
          charges_enabled: acct.charges_enabled,
          payouts_enabled: acct.payouts_enabled,
        });
        await updateDriver(acct.metadata?.uid, {
          stripeAccountId: acct.id,
          stripeConnectStatus: missionControlConnectStatus(acct),
          stripeChargesEnabled: acct.charges_enabled,
          stripePayoutsEnabled: acct.payouts_enabled,
          stripeRequirementsDue: acct.requirements?.currently_due || [],
        });
        await updatePublicDriverConnectStatus(acct.metadata?.uid, {
          stripeAccountId: acct.id,
          stripeChargesEnabled: acct.charges_enabled,
        });
        break;
      }
      case "identity.verification_session.verified":
        await updateIdentityStatus(event.data.object, "verified");
        break;
      case "identity.verification_session.processing":
        await updateIdentityStatus(event.data.object, "processing");
        break;
      case "identity.verification_session.requires_input":
        await updateIdentityStatus(event.data.object, "requires_input");
        break;
      case "identity.verification_session.canceled":
        await updateIdentityStatus(event.data.object, "canceled");
        break;
      default:
        console.log("ℹ️ Unhandled event:", event.type);
    }
    res.sendStatus(200);
  } catch (err) {
    console.error("❌ Webhook verify failed:", err.message);
    res.status(400).send(`Webhook Error: ${err.message}`);
  }
});

// --- JSON parser for all OTHER routes ---
app.use(express.json());

// --- Stripe Identity verification sessions ---
// Body: { role: "driver" | "verified_rider" } -> { id, client_secret, status }
app.post("/identity/create-session", async (req, res) => {
  try {
    const uid = await requireFirebaseUid(req, res);
    if (!uid) return;

    const { role } = req.body || {};
    const requestId = requireRequestId(req, res, "identity_create_session");
    if (!requestId) return;
    if (!isValidIdentityRole(role)) {
      return res.status(400).json({ error: "invalid_identity_role" });
    }

    const verificationFlow = identityFlowForRole(role);
    if (!verificationFlow) {
      return res.status(500).json({ error: "identity_flow_not_configured" });
    }

    const profile = await identityProfile(uid, role);
    const session = await stripe.identity.verificationSessions.create(
      {
        verification_flow: verificationFlow,
        provided_details: {
          email: profile.email,
        },
        metadata: {
          uid,
          role,
          verification_flow: verificationFlow,
          requestId,
        },
      },
      { idempotencyKey: `identity_session_${role}_${uid}_${requestId}` }
    );

    if (!session.client_secret) {
      return res.status(500).json({ error: "missing_client_secret" });
    }

    await updateIdentityStatus(session, "requires_input");

    res.json({
      id: session.id,
      client_secret: session.client_secret,
      status: session.status,
    });
  } catch (err) {
    console.error("❌ identity/create-session error", err);
    const payload = identitySessionErrorPayload(err);
    res.status(payload.status).json(payload.body);
  }
});

app.get("/identity/status", async (req, res) => {
  try {
    const uid = await requireFirebaseUid(req, res);
    if (!uid) return;

    const role = String(req.query.role || "");
    if (!isValidIdentityRole(role)) {
      return res.status(400).json({ error: "invalid_identity_role" });
    }

    initializeFirebase();
    const collection = role === "driver" ? "drivers" : "riders";
    const snapshot = await admin.firestore().collection(collection).doc(uid).get();
    const data = snapshot.exists ? snapshot.data() : {};
    res.json({
      identityVerified: !!data.identityVerified,
      verifiedRider: !!data.verifiedRider,
      verifiedBadge: !!data.verifiedBadge,
      identityStatus: data.identityStatus || "not_started",
      stripeIdentityVerificationId: data.stripeIdentityVerificationId || null,
    });
  } catch (err) {
    console.error("❌ identity/status error", err);
    res.status(500).json({ error: "identity_status_failed" });
  }
});

// --- Create-or-get Customer (idempotent) ---
// Auth required. Body: { email?: string, name?: string } -> { customerId }
// The Stripe customer is always looked up/created against the *authenticated*
// uid — a client can no longer hand us an arbitrary uid/customerId.
app.post("/create-customer", async (req, res) => {
  try {
    const uid = await requireFirebaseUid(req, res);
    if (!uid) return;
    if (rejectIfSuppliedUidMismatch(req, res, uid)) return;
    if (await rejectIfSuppliedCustomerMismatch(req, res, uid)) return;

    const { name } = req.body || {};
    const authProfile = await authUserProfile(uid);
    const customerEmail = authProfile.email;
    const customerName = authProfile.name || name || undefined;

    // 0) Already on file for this rider — fast path, no Stripe round trip.
    const existing = await ownedCustomerId(uid);
    if (existing) {
      return res.json({ customerId: existing });
    }

    // 1) Lookup by metadata.firebase_uid
    const byUid = await stripe.customers.search({
      query: `metadata['firebase_uid']:'${uid}'`,
    });
    if (byUid.data.length) {
      await persistStripeCustomerId(uid, byUid.data[0].id);
      return res.json({ customerId: byUid.data[0].id });
    }

    // 2) Fallback by Firebase Auth email only — never by a client-supplied email.
    if (customerEmail) {
      const byEmail = await stripe.customers.search({ query: `email:'${customerEmail}'` });
      if (byEmail.data.length) {
        if (byEmail.data[0].metadata?.firebase_uid !== uid) {
          await stripe.customers.update(
            byEmail.data[0].id,
            {
              metadata: { ...byEmail.data[0].metadata, firebase_uid: uid },
            },
            { idempotencyKey: `customer_backfill_uid_${uid}` }
          );
        }
        await persistStripeCustomerId(uid, byEmail.data[0].id);
        return res.json({ customerId: byEmail.data[0].id });
      }
    }

    // 3) Create new customer, keyed to this uid so retries can't create duplicates.
    const customer = await stripe.customers.create(
      {
        email: customerEmail,
        name: customerName,
        metadata: { firebase_uid: uid },
      },
      { idempotencyKey: `customer_create_${uid}` }
    );
    await persistStripeCustomerId(uid, customer.id);
    return res.json({ customerId: customer.id });
  } catch (e) {
    console.error("❌ create-customer:", e);
    res.status(500).json({ error: "create_customer_failed" });
  }
});

// --- Ephemeral Key ---
// Auth required. Headers: "Stripe-Version" required.
// The customerId is always the authenticated rider's own Stripe customer —
// a client-supplied customerId is no longer accepted.
app.post("/ephemeral-key", async (req, res) => {
  try {
    const uid = await requireFirebaseUid(req, res);
    if (!uid) return;
    if (rejectIfSuppliedUidMismatch(req, res, uid)) return;
    if (await rejectIfSuppliedCustomerMismatch(req, res, uid)) return;

    const apiVer = req.headers["stripe-version"];
    if (!apiVer) return res.status(400).json({ error: "stripe_version_required" });

    const customerId = await ownedCustomerId(uid);
    if (!customerId) return res.status(404).json({ error: "no_stripe_customer_on_file" });

    const key = await stripe.ephemeralKeys.create(
      { customer: customerId },
      { apiVersion: String(apiVer) }
    );
    res.json(key);
  } catch (e) {
    console.error("❌ ephemeral-key:", e);
    res.status(500).json({ error: "ephemeral_key_failed" });
  }
});

// --- SetupIntent (save a card) ---
// Auth required -> { clientSecret }. customerId is derived from the
// authenticated rider, never accepted from the client.
app.post("/create-setup-intent", async (req, res) => {
  try {
    const uid = await requireFirebaseUid(req, res);
    if (!uid) return;
    if (rejectIfSuppliedUidMismatch(req, res, uid)) return;
    if (await rejectIfSuppliedCustomerMismatch(req, res, uid)) return;

    const customerId = await ownedCustomerId(uid);
    if (!customerId) return res.status(404).json({ error: "no_stripe_customer_on_file" });
    const requestId = requireRequestId(req, res, "create_setup_intent");
    if (!requestId) return;

    const si = await stripe.setupIntents.create(
      {
        customer: customerId,
        payment_method_types: ["card"],
        usage: "off_session",
        metadata: { firebase_uid: uid, requestId },
      },
      { idempotencyKey: `setup_intent_${uid}_${requestId}` }
    );
    res.json({ clientSecret: si.client_secret });
  } catch (e) {
    console.error("❌ create-setup-intent:", e);
    res.status(500).json({ error: "setup_intent_failed" });
  }
});

// --- PaymentIntent (charge a ride) ---------------------------------------
//
// Shared by /create-payment-intent (first attempt) and /payments/retry
// (subsequent attempts after a failure). Every identity and charge amount used
// to build the PaymentIntent is re-derived server-side from Firestore/Stripe
// using the verified Firebase uid. The app may still send `amount` as a stale
// client-side consistency check, but it is never the source of truth.
async function chargeRideAttempt({
  uid,
  rideId,
  amount,
  currency = "usd",
  paymentMethodId,
  suppliedCustomerId,
  suppliedDriverAccountId,
}) {
  const owned = await ownedRide(uid, rideId);
  if (!owned) {
    return { httpStatus: 404, body: { error: "ride_not_found_or_not_owned" } };
  }
  const { ref: rideRef, data: ride } = owned;
  const attempt = (ride.retryCount || 0) + 1;
  const resolvedCharge = resolvedRideCharge(ride);

  if (!CHARGEABLE_RIDE_STATUSES.has(ride.status)) {
    return {
      httpStatus: 409,
      body: { error: "ride_not_completed", rideStatus: ride.status || "unknown" },
    };
  }
  if (resolvedCharge === null) {
    const message = "Ride is missing an authoritative fare. Payment was not attempted.";
    await recordPaymentStatus(rideRef, "failed", {
      retryCount: attempt,
      failureReason: message,
      failureCode: "fare_not_authoritative",
    });
    return { httpStatus: 409, body: { error: "fare_not_authoritative", message } };
  }
  const authoritativeAmount = resolvedCharge.amount;
  if (authoritativeAmount <= 0) {
    await recordPaymentStatus(rideRef, "succeeded", {
      retryCount: attempt,
      paymentFailureReason: null,
      failureReason: null,
      failureCode: null,
      stripePaymentIntentId: null,
      noCharge: true,
      authorizedRiderChargeCents: resolvedCharge.baseAmount,
      finalRiderChargeCents: 0,
      pickupPaidWaitSeconds: resolvedCharge.pickupPaidWaitSeconds,
      pickupWaitChargeCents: resolvedCharge.pickupWaitChargeCents,
    });
    return {
      httpStatus: 200,
      body: { clientSecret: null, paymentIntentId: null, status: "succeeded", noCharge: true },
    };
  }
  if (amount !== undefined && amount !== null) {
    const suppliedAmount = Number(amount);
    if (!Number.isInteger(suppliedAmount) || suppliedAmount !== authoritativeAmount) {
      const message = "Client fare does not match the authorized ride fare.";
      await recordPaymentStatus(rideRef, "failed", {
        retryCount: attempt,
        failureReason: message,
        failureCode: "amount_mismatch",
        suppliedAmountCents: Number.isFinite(suppliedAmount) ? suppliedAmount : null,
        authorizedAmountCents: authoritativeAmount,
        authorizedBaseAmountCents: resolvedCharge.baseAmount,
        pickupPaidWaitSeconds: resolvedCharge.pickupPaidWaitSeconds,
        pickupWaitChargeCents: resolvedCharge.pickupWaitChargeCents,
      });
      return {
        httpStatus: 409,
        body: {
          error: "amount_mismatch",
          message,
          suppliedAmountCents: Number.isFinite(suppliedAmount) ? suppliedAmount : null,
          authorizedAmountCents: authoritativeAmount,
          authorizedBaseAmountCents: resolvedCharge.baseAmount,
          pickupPaidWaitSeconds: resolvedCharge.pickupPaidWaitSeconds,
          pickupWaitChargeCents: resolvedCharge.pickupWaitChargeCents,
        },
      };
    }
  }

  const customerId = await ownedCustomerId(uid);
  if (!customerId) {
    const message = "No Stripe customer is on file for this rider.";
    await recordPaymentStatus(rideRef, "failed", {
      retryCount: attempt,
      failureReason: message,
      failureCode: "no_stripe_customer_on_file",
    });
    return { httpStatus: 404, body: { error: "no_stripe_customer_on_file", message } };
  }
  if (suppliedCustomerId && suppliedCustomerId !== customerId) {
    return { httpStatus: 403, body: { error: "customer_not_owned" } };
  }

  // Resolve which saved card to charge, and confirm it actually belongs to
  // this rider's customer — a paymentMethodId is never trusted at face value.
  let resolvedPaymentMethodId = paymentMethodId || null;
  if (resolvedPaymentMethodId) {
    const pm = await stripe.paymentMethods.retrieve(resolvedPaymentMethodId);
    if (pm.customer !== customerId) {
      return { httpStatus: 403, body: { error: "payment_method_not_owned" } };
    }
  } else {
    const customer = await stripe.customers.retrieve(customerId);
    resolvedPaymentMethodId = customer?.invoice_settings?.default_payment_method || null;
  }
  if (!resolvedPaymentMethodId) {
    const message = "No default payment method is on file.";
    await recordPaymentStatus(rideRef, "failed", {
      retryCount: attempt,
      failureReason: message,
      failureCode: "no_payment_method_on_file",
    });
    return { httpStatus: 400, body: { error: "no_payment_method_on_file", message } };
  }

  const driverAccountId = await driverAccountForRide(ride);
  if (suppliedDriverAccountId && suppliedDriverAccountId !== driverAccountId) {
    return { httpStatus: 403, body: { error: "driver_account_not_owned" } };
  }
  let applicationFeeAmount;
  if (driverAccountId) {
    // Prefer the pricing snapshot's platform share; fall back to the minimum
    // documented 30% share so stale ride docs cannot bypass the platform cut.
    applicationFeeAmount = platformFeeCents(ride, authoritativeAmount, resolvedCharge);
  }

  const idempotencyKey = attempt === 1 ? rideId : `${rideId}_attempt${attempt}`;

  await recordPaymentStatus(rideRef, "processing", {
    retryCount: ride.retryCount || 0,
    failureReason: null,
    failureCode: null,
    authorizedRiderChargeCents: resolvedCharge.baseAmount,
    finalRiderChargeCents: authoritativeAmount,
    pickupPaidWaitSeconds: resolvedCharge.pickupPaidWaitSeconds,
    pickupWaitChargeCents: resolvedCharge.pickupWaitChargeCents,
  });

  const params = {
    amount: authoritativeAmount,
    currency,
    customer: customerId,
    payment_method: resolvedPaymentMethodId,
    confirm: true,
    off_session: true,
    metadata: { rideId, riderId: uid, driverId: ride.driverId || "", attempt: String(attempt) },
  };
  if (driverAccountId) {
    params.application_fee_amount = applicationFeeAmount;
    params.transfer_data = { destination: driverAccountId };
  }

  try {
    const pi = await stripe.paymentIntents.create(params, { idempotencyKey });
    await recordPaymentStatus(rideRef, pi.status === "succeeded" ? "succeeded" : "processing", {
      stripePaymentIntentId: pi.id,
      retryCount: attempt,
    });
    return {
      httpStatus: 200,
      body: { clientSecret: pi.client_secret, paymentIntentId: pi.id, status: pi.status },
    };
  } catch (e) {
    const code = e?.raw?.code || e?.code;
    const message = e?.raw?.message || e.message || "payment_intent_failed";
    await recordPaymentStatus(rideRef, "failed", {
      retryCount: attempt,
      failureReason: message,
      failureCode: code || null,
      stripePaymentIntentId: e?.raw?.payment_intent?.id || null,
    });
    if (code === "authentication_required") {
      return {
        httpStatus: 402,
        body: { error: "authentication_required", paymentIntentId: e?.raw?.payment_intent?.id || null },
      };
    }
    return { httpStatus: 402, body: { error: message } };
  }
}

// Body: { rideId, amount?: <int cents>, currency?, paymentMethodId? } -> { clientSecret, paymentIntentId, status }
// Auth required. The optional `amount` is only checked against Firestore's
// authoritative fare; it never controls the PaymentIntent amount.
app.post("/create-payment-intent", async (req, res) => {
  try {
    const uid = await requireFirebaseUid(req, res);
    if (!uid) return;
    if (rejectIfSuppliedUidMismatch(req, res, uid)) return;

    const { rideId, amount, currency, paymentMethodId } = req.body || {};
    if (!rideId) return res.status(400).json({ error: "rideId_required" });

    const result = await chargeRideAttempt({
      uid,
      rideId,
      amount,
      currency,
      paymentMethodId,
      suppliedCustomerId: suppliedValue(req, "customerId"),
      suppliedDriverAccountId: suppliedValue(req, "driverAccountId") || suppliedValue(req, "connectedAccountId"),
    });
    res.status(result.httpStatus).json(result.body);
  } catch (e) {
    console.error("❌ create-payment-intent:", e);
    res.status(500).json({ error: "payment_intent_failed" });
  }
});

// --- Retry a failed ride payment -----------------------------------------
// Body: { rideId, amount?: <int cents>, currency?, paymentMethodId? } (paymentMethodId
// lets the rider pick a different saved card after updating their payment method).
// `amount` is optional and only checked against the authoritative Firestore fare.
// Auth required. Only allowed when the ride's current paymentStatus is "failed",
// so this can never be used to double-charge a ride that already succeeded.
app.post("/payments/retry", async (req, res) => {
  try {
    const uid = await requireFirebaseUid(req, res);
    if (!uid) return;
    if (rejectIfSuppliedUidMismatch(req, res, uid)) return;

    const { rideId, amount, currency, paymentMethodId } = req.body || {};
    if (!rideId) return res.status(400).json({ error: "rideId_required" });

    const owned = await ownedRide(uid, rideId);
    if (!owned) return res.status(404).json({ error: "ride_not_found_or_not_owned" });
    if (owned.data.paymentStatus !== "failed") {
      return res.status(409).json({ error: "ride_not_in_failed_state", paymentStatus: owned.data.paymentStatus || "pending" });
    }

    const result = await chargeRideAttempt({
      uid,
      rideId,
      amount,
      currency,
      paymentMethodId,
      suppliedCustomerId: suppliedValue(req, "customerId"),
      suppliedDriverAccountId: suppliedValue(req, "driverAccountId") || suppliedValue(req, "connectedAccountId"),
    });
    res.status(result.httpStatus).json(result.body);
  } catch (e) {
    console.error("❌ payments/retry:", e);
    res.status(500).json({ error: "retry_failed" });
  }
});

// --- Charge a post-ride driver tip ---------------------------------------
// Body: { rideId, amountCents, currency?, paymentMethodId? }
// Auth required. Tips are separate from the authoritative fare so riders can
// never mutate trip pricing from the client. A ride can only receive one
// successful tip, and only after the base ride payment has succeeded.
app.post("/payments/tip", async (req, res) => {
  try {
    const uid = await requireFirebaseUid(req, res);
    if (!uid) return;
    if (rejectIfSuppliedUidMismatch(req, res, uid)) return;

    const { rideId, amountCents, currency = "usd", paymentMethodId } = req.body || {};
    if (!rideId) return res.status(400).json({ error: "rideId_required" });

    const tipAmount = Number(amountCents);
    if (!Number.isInteger(tipAmount) || tipAmount <= 0) {
      return res.status(400).json({ error: "invalid_tip_amount" });
    }
    if (tipAmount > 50000) {
      return res.status(400).json({ error: "tip_amount_too_large" });
    }

    const owned = await ownedRide(uid, rideId);
    if (!owned) return res.status(404).json({ error: "ride_not_found_or_not_owned" });
    const { ref: rideRef, data: ride } = owned;

    if (!CHARGEABLE_RIDE_STATUSES.has(ride.status)) {
      return res.status(409).json({ error: "ride_not_completed", rideStatus: ride.status || "unknown" });
    }
    if (ride.paymentStatus !== "succeeded") {
      return res.status(409).json({ error: "ride_payment_not_succeeded", paymentStatus: ride.paymentStatus || "pending" });
    }
    if (ride.tipPaymentStatus === "succeeded" || positiveIntegerField(ride, "tipAmountCents")) {
      return res.status(409).json({ error: "tip_already_charged" });
    }
    if (ride.tipPaymentStatus === "processing") {
      return res.status(409).json({ error: "tip_payment_processing" });
    }

    const customerId = await ownedCustomerId(uid);
    if (!customerId) {
      return res.status(404).json({ error: "no_stripe_customer_on_file" });
    }

    let resolvedPaymentMethodId = paymentMethodId || null;
    if (resolvedPaymentMethodId) {
      const pm = await stripe.paymentMethods.retrieve(resolvedPaymentMethodId);
      if (pm.customer !== customerId) {
        return res.status(403).json({ error: "payment_method_not_owned" });
      }
    } else {
      const customer = await stripe.customers.retrieve(customerId);
      resolvedPaymentMethodId = customer?.invoice_settings?.default_payment_method || null;
    }
    if (!resolvedPaymentMethodId) {
      return res.status(400).json({ error: "no_payment_method_on_file", message: "No default payment method is on file." });
    }

    const driverAccountId = await driverAccountForRide(ride);
    if (!driverAccountId) {
      return res.status(409).json({ error: "driver_connect_account_unavailable" });
    }

    let tipAttempt;
    try {
      tipAttempt = await admin.firestore().runTransaction(async (tx) => {
        const fresh = await tx.get(rideRef);
        const current = fresh.data() || {};
        if (current.tipPaymentStatus === "succeeded" || positiveIntegerField(current, "tipAmountCents")) {
          throw { httpStatus: 409, body: { error: "tip_already_charged" } };
        }
        if (current.tipPaymentStatus === "processing") {
          throw { httpStatus: 409, body: { error: "tip_payment_processing" } };
        }
        const attempt = (current.tipRetryCount || 0) + 1;
        tx.set(
          rideRef,
          {
            tipPaymentStatus: "processing",
            tipRetryCount: current.tipRetryCount || 0,
            tipFailureReason: null,
            tipFailureCode: null,
            pendingTipAmountCents: tipAmount,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        return attempt;
      });
    } catch (e) {
      if (e?.httpStatus) return res.status(e.httpStatus).json(e.body);
      throw e;
    }

    const params = {
      amount: tipAmount,
      currency,
      customer: customerId,
      payment_method: resolvedPaymentMethodId,
      confirm: true,
      off_session: true,
      transfer_data: { destination: driverAccountId },
      metadata: {
        rideId,
        riderId: uid,
        driverId: ride.driverId || "",
        paymentType: "driver_tip",
        attempt: String(tipAttempt),
      },
    };

    try {
      const pi = await stripe.paymentIntents.create(params, {
        idempotencyKey: `tip_${rideId}_${tipAmount}_attempt${tipAttempt}`,
      });
      const succeeded = pi.status === "succeeded";
      await rideRef.set(
        {
          tipPaymentStatus: succeeded ? "succeeded" : "processing",
          tipRetryCount: tipAttempt,
          tipAmountCents: succeeded ? tipAmount : admin.firestore.FieldValue.delete(),
          pendingTipAmountCents: succeeded ? admin.firestore.FieldValue.delete() : tipAmount,
          stripeTipPaymentIntentId: pi.id,
          tippedAt: succeeded ? admin.firestore.FieldValue.serverTimestamp() : null,
          tipFailureReason: null,
          tipFailureCode: null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return res.json({ paymentIntentId: pi.id, status: pi.status, amountCents: tipAmount });
    } catch (e) {
      const code = e?.raw?.code || e?.code;
      const message = e?.raw?.message || e.message || "tip_payment_failed";
      await rideRef.set(
        {
          tipPaymentStatus: "failed",
          tipRetryCount: tipAttempt,
          tipFailureReason: message,
          tipFailureCode: code || null,
          stripeTipPaymentIntentId: e?.raw?.payment_intent?.id || null,
          pendingTipAmountCents: tipAmount,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return res.status(402).json({ error: code || "tip_payment_failed", message });
    }
  } catch (e) {
    console.error("❌ payments/tip:", e);
    res.status(500).json({ error: "tip_payment_failed" });
  }
});

// --- List saved card PaymentMethods (for wallet tiles) ---
// Auth required -> { paymentMethods: [{id,brand,last4,expMonth,expYear,isDefault}] }
// customerId is always the authenticated rider's own customer.
app.post("/list-payment-methods", async (req, res) => {
  try {
    const uid = await requireFirebaseUid(req, res);
    if (!uid) return;
    if (rejectIfSuppliedUidMismatch(req, res, uid)) return;
    if (await rejectIfSuppliedCustomerMismatch(req, res, uid)) return;

    const customerId = await ownedCustomerId(uid);
    if (!customerId) return res.json({ paymentMethods: [] });

    const [pms, customer] = await Promise.all([
      stripe.paymentMethods.list({ customer: customerId, type: "card" }),
      stripe.customers.retrieve(customerId),
    ]);

    const defaultPm = customer?.invoice_settings?.default_payment_method || null;

    res.json({
      paymentMethods: pms.data.map(pm => ({
        id: pm.id,
        brand: pm.card.brand,
        last4: pm.card.last4,
        expMonth: pm.card.exp_month,
        expYear: pm.card.exp_year,
        isDefault: pm.id === defaultPm,
      })),
    });
  } catch (e) {
    console.error("❌ list-payment-methods:", e);
    res.status(500).json({ error: "list_failed" });
  }
});

// --- Set default card ---
// Auth required. Body: { paymentMethodId } -> { ok: true }
// The paymentMethodId must belong to the authenticated rider's own customer.
app.post("/set-default-payment-method", async (req, res) => {
  try {
    const uid = await requireFirebaseUid(req, res);
    if (!uid) return;
    if (rejectIfSuppliedUidMismatch(req, res, uid)) return;
    if (await rejectIfSuppliedCustomerMismatch(req, res, uid)) return;

    const { paymentMethodId } = req.body || {};
    if (!paymentMethodId) return res.status(400).json({ error: "paymentMethodId_required" });

    const customerId = await ownedCustomerId(uid);
    if (!customerId) return res.status(404).json({ error: "no_stripe_customer_on_file" });

    const pm = await stripe.paymentMethods.retrieve(paymentMethodId);
    if (pm.customer !== customerId) {
      return res.status(403).json({ error: "payment_method_not_owned" });
    }

    await stripe.customers.update(
      customerId,
      {
        invoice_settings: { default_payment_method: paymentMethodId },
      },
      { idempotencyKey: `set_default_payment_method_${uid}_${paymentMethodId}` }
    );
    res.json({ ok: true });
  } catch (e) {
    console.error("❌ set-default-payment-method:", e);
    res.status(500).json({ error: "update_failed" });
  }
});

// --- Detach a card ---
// Auth required. Body: { paymentMethodId } -> { ok: true }
// The paymentMethodId must belong to the authenticated rider's own customer.
app.post("/detach-payment-method", async (req, res) => {
  try {
    const uid = await requireFirebaseUid(req, res);
    if (!uid) return;
    if (rejectIfSuppliedUidMismatch(req, res, uid)) return;
    if (await rejectIfSuppliedCustomerMismatch(req, res, uid)) return;

    const { paymentMethodId } = req.body || {};
    if (!paymentMethodId) return res.status(400).json({ error: "paymentMethodId_required" });

    const customerId = await ownedCustomerId(uid);
    if (!customerId) return res.status(404).json({ error: "no_stripe_customer_on_file" });

    const pm = await stripe.paymentMethods.retrieve(paymentMethodId);
    if (pm.customer !== customerId) {
      return res.status(403).json({ error: "payment_method_not_owned" });
    }

    await stripe.paymentMethods.detach(
      paymentMethodId,
      { idempotencyKey: `detach_payment_method_${uid}_${paymentMethodId}` }
    );
    res.json({ ok: true });
  } catch (e) {
    console.error("❌ detach-payment-method:", e);
    res.status(500).json({ error: "detach_failed" });
  }
});

// ============================================================================
// Driver: Stripe Connect — return pages for hosted onboarding (opened in an
// in-app Safari sheet; the user just taps Done to go back to the app, which
// polls /connect/status itself, so these only need to show a friendly message).
function returnPageHTML(message) {
  return `<!doctype html>
<html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Rydr</title></head>
<body style="font-family: -apple-system, sans-serif; text-align: center; padding: 48px 24px;">
<h2>${message}</h2>
<p>You can close this window and return to the Rydr Driver app.</p>
</body></html>`;
}

app.get("/return/complete", (_req, res) => {
  res.send(returnPageHTML("You're all set!"));
});

app.get("/return/refresh", (_req, res) => {
  res.send(returnPageHTML("Let's try that again."));
});

// ============================================================================
// Driver: Stripe Connect (Express) — Create account
// Body: { uid, email, firstName, lastName, phone, dob:{day,month,year}, address:{ line1, city, state, postal_code, line2? } }
app.post("/connect/accounts", async (req, res) => {
  try {
    const driverUid = await requireFirebaseUid(req, res);
    if (!driverUid) return;
    if (rejectIfSuppliedUidMismatch(req, res, driverUid)) return;

    const { uid, email, firstName, lastName, phone, dob, address } = req.body || {};

    if (!email || !firstName || !lastName || !phone || !dob || !address) {
      return res.status(400).json({ error: "missing_required_fields" });
    }

    const existingAccountId = (await driverData(driverUid))?.stripeAccountId;
    if (existingAccountId) {
      try {
        const existing = await stripe.accounts.retrieve(existingAccountId);
        if (!existing.deleted) {
          await updateDriver(driverUid, {
            stripeAccountId: existing.id,
            stripeConnectStatus: missionControlConnectStatus(existing),
            stripeChargesEnabled: !!existing.charges_enabled,
            stripePayoutsEnabled: !!existing.payouts_enabled,
            stripeRequirementsDue: existing.requirements?.currently_due || [],
          });
          await updatePublicDriverConnectStatus(driverUid, {
            stripeAccountId: existing.id,
            stripeChargesEnabled: existing.charges_enabled,
          });
          return res.json({ accountId: existing.id, reused: true });
        }
      } catch (err) {
        console.warn("⚠️ Stored Stripe account could not be reused", {
          uid: driverUid,
          accountId: existingAccountId,
          message: err.message,
        });
      }
    }

    const account = await stripe.accounts.create(
      {
        type: "express",
        country: "US",
        email,
        business_type: "individual",
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true },
        },
        individual: {
          first_name: firstName,
          last_name: lastName,
          email,
          phone,
          dob, // { day, month, year }
          address, // { line1, city, state, postal_code, line2? }
        },
        metadata: { uid: driverUid },
      },
      { idempotencyKey: `connect_account_create_${driverUid}` }
    );

    await updateDriver(driverUid, {
      stripeAccountId: account.id,
      stripeConnectStatus: missionControlConnectStatus(account),
      stripeChargesEnabled: !!account.charges_enabled,
      stripePayoutsEnabled: !!account.payouts_enabled,
      stripeRequirementsDue: account.requirements?.currently_due || [],
    });
    await updatePublicDriverConnectStatus(driverUid, {
      stripeAccountId: account.id,
      stripeChargesEnabled: account.charges_enabled,
    });

    res.json({ accountId: account.id, reused: false });
  } catch (err) {
    console.error("❌ connect/accounts error", err);
    res.status(500).json({ error: "account_create_failed" });
  }
});

/**
 * Every driver-side Connect route below takes no accountId from the client.
 * The accountId is always re-derived from `drivers/{uid}.stripeAccountId` —
 * a driver can only ever act on their own Connect account.
 */
async function requireOwnAccountId(req, res) {
  const uid = await requireFirebaseUid(req, res);
  if (!uid) return null;
  if (rejectIfSuppliedUidMismatch(req, res, uid)) return null;
  const driver = await driverData(uid);
  const accountId = driver?.stripeAccountId;
  if (!accountId) {
    res.status(404).json({ error: "no_connect_account_on_file" });
    return null;
  }
  if (rejectIfSuppliedAccountMismatch(req, res, accountId)) return null;
  return { uid, accountId };
}

// Driver: Stripe Connect — Create onboarding link
// Auth required.
app.post("/connect/account-link", async (req, res) => {
  try {
    const owned = await requireOwnAccountId(req, res);
    if (!owned) return;
    const { accountId } = owned;
    const requestId = requireRequestId(req, res, "connect_account_link");
    if (!requestId) return;

    const base = appBaseURL();
    const link = await stripe.accountLinks.create(
      {
        account: accountId,
        type: "account_onboarding",
        refresh_url: `${base}/return/refresh`,
        return_url: `${base}/return/complete`,
      },
      { idempotencyKey: `account_link_${accountId}_${requestId}` }
    );

    res.json({ url: link.url });
  } catch (err) {
    console.error("❌ connect/account-link error", err);
    res.status(500).json({ error: "account_link_failed" });
  }
});

// Driver: Stripe Connect — Status
// Auth required.
app.get("/connect/status", async (req, res) => {
  try {
    const owned = await requireOwnAccountId(req, res);
    if (!owned) return;

    const acct = await stripe.accounts.retrieve(owned.accountId);
    res.json({
      charges_enabled: acct.charges_enabled,
      payouts_enabled: acct.payouts_enabled,
      requirements_due: acct.requirements?.currently_due ?? [],
    });
  } catch (err) {
    console.error("❌ connect/status error", err);
    res.status(500).json({ error: "status_failed" });
  }
});

// Driver: Stripe Connect — Balance available for payouts
// Auth required.
app.get("/connect/balance", async (req, res) => {
  try {
    const owned = await requireOwnAccountId(req, res);
    if (!owned) return;
    const { accountId } = owned;

    const [acct, balance] = await Promise.all([
      stripe.accounts.retrieve(accountId),
      stripe.balance.retrieve({ stripeAccount: accountId }),
    ]);

    const available = balance.available.filter((entry) => entry.currency === "usd");
    const pending = balance.pending.filter((entry) => entry.currency === "usd");
    const instantAvailableAmount = available.reduce((sum, entry) => sum + entry.amount, 0);
    const pendingAmount = pending.reduce((sum, entry) => sum + entry.amount, 0);

    res.json({
      instantAvailableAmount,
      pendingAmount,
      currency: "usd",
      payoutsEnabled: acct.payouts_enabled,
    });
  } catch (err) {
    console.error("❌ connect/balance error", err);
    res.status(500).json({ error: "balance_failed" });
  }
});

// Driver: Stripe Connect — Linked payout methods
// Auth required.
app.get("/connect/external-accounts", async (req, res) => {
  try {
    const owned = await requireOwnAccountId(req, res);
    if (!owned) return;
    const { accountId } = owned;

    const [bankAccounts, cards] = await Promise.all([
      stripe.accounts.listExternalAccounts(accountId, { object: "bank_account", limit: 10 }),
      stripe.accounts.listExternalAccounts(accountId, { object: "card", limit: 10 }),
    ]);

    res.json({
      bankAccounts: bankAccounts.data.map((bank) => ({
        id: bank.id,
        bankName: bank.bank_name || "Bank account",
        last4: bank.last4 || "",
        isDefault: bank.default_for_currency === true,
      })),
      cards: cards.data.map((card) => ({
        id: card.id,
        brand: card.brand || "Debit card",
        last4: card.last4 || "",
        isDefault: card.default_for_currency === true,
      })),
    });
  } catch (err) {
    console.error("❌ connect/external-accounts error", err);
    res.status(500).json({ error: "external_accounts_failed" });
  }
});

// Driver: Stripe Connect — Recent payouts
// Auth required.
app.get("/connect/payouts", async (req, res) => {
  try {
    const owned = await requireOwnAccountId(req, res);
    if (!owned) return;
    const { accountId } = owned;
    const rawLimit = Number.parseInt(String(req.query.limit || "10"), 10);
    const limit = Math.max(1, Math.min(25, Number.isFinite(rawLimit) ? rawLimit : 10));

    const payouts = await stripe.payouts.list(
      { limit },
      { stripeAccount: accountId }
    );

    res.json({
      payouts: payouts.data.map((payout) => ({
        id: payout.id,
        amount: payout.amount,
        currency: payout.currency,
        status: payout.status,
        method: payout.method,
        arrivalDate: payout.arrival_date || null,
        created: payout.created,
      })),
    });
  } catch (err) {
    console.error("❌ connect/payouts error", err);
    res.status(500).json({ error: "payouts_failed" });
  }
});

// Driver: Stripe Connect — Express dashboard login link
// Auth required.
app.get("/connect/login-link", async (req, res) => {
  try {
    const owned = await requireOwnAccountId(req, res);
    if (!owned) return;

    const link = await stripe.accounts.createLoginLink(owned.accountId);
    res.json({ url: link.url });
  } catch (err) {
    console.error("❌ connect/login-link error", err);
    res.status(500).json({ error: "login_link_failed" });
  }
});

// Driver: Stripe Connect — Instant payout from ride-earnings balance
// Auth required. Body: { amount, currency?, requestId }
// requestId (a client-generated UUID per tap) is required and becomes part of
// the idempotency key so a double-tap or retried request cannot trigger two payouts.
app.post("/connect/instant-payout", async (req, res) => {
  try {
    const owned = await requireOwnAccountId(req, res);
    if (!owned) return;
    const { uid, accountId } = owned;

    const { amount, currency = "usd" } = req.body || {};
    const payoutRequestId = requireRequestId(req, res, "connect_instant_payout");
    if (!payoutRequestId) return;
    if (!Number.isInteger(amount) || amount <= 0) {
      return res.status(400).json({ error: "invalid_amount" });
    }

    const acct = await stripe.accounts.retrieve(accountId);
    if (!acct.payouts_enabled) {
      return res.status(400).json({ error: "payouts_not_enabled" });
    }

    const payout = await stripe.payouts.create(
      {
        amount,
        currency,
        method: "instant",
        metadata: {
          uid,
          source: "driver_wallet_instant_pay",
        },
      },
      { stripeAccount: accountId, idempotencyKey: `instant_payout_${accountId}_${payoutRequestId}` }
    );

    res.json({
      payoutId: payout.id,
      amount: payout.amount,
      currency: payout.currency,
      status: payout.status,
    });
  } catch (err) {
    console.error("❌ connect/instant-payout error", err);
    res.status(500).json({ error: "instant_payout_failed", detail: err.message });
  }
});

// Admin: Account deletion cleanup (Part 12 — called from Mission Control's
// /api/account-deletions/[id]/process route after a human reviews the
// request). Detaches/removes the rider's saved payment methods and Stripe
// customer record, and rejects/deactivates the driver's Connect account so
// no further payouts or charges can occur. Idempotent: missing Stripe
// records are treated as already-cleaned-up rather than errors, since this
// can be safely re-run if a previous attempt partially failed.
app.post("/admin/cleanup-account", async (req, res) => {
  try {
    const adminUid = await requireAdminUid(req, res);
    if (!adminUid) return;

    const { role, stripeCustomerId, stripeAccountId, uid } = req.body || {};
    const requestId = requireRequestId(req, res, "admin_cleanup_account");
    if (!requestId) return;
    const cleanupKey = `${uid || role || "account"}_${requestId}`;
    const result = { role: role || null, customer: "skipped", connectAccount: "skipped" };

    if (stripeCustomerId) {
      try {
        await stripe.customers.del(
          stripeCustomerId,
          { idempotencyKey: `account_deletion_customer_${cleanupKey}` }
        );
        result.customer = "deleted";
      } catch (err) {
        if (err.code === "resource_missing") {
          result.customer = "already_deleted";
        } else {
          throw err;
        }
      }
    }

    if (stripeAccountId) {
      try {
        await stripe.accounts.update(
          stripeAccountId,
          {
            metadata: { deactivated_by: adminUid, deactivated_reason: "account_deletion" },
          },
          { idempotencyKey: `account_deletion_connect_metadata_${cleanupKey}` }
        );
        await stripe.accounts.reject(
          stripeAccountId,
          { reason: "fraud" },
          { idempotencyKey: `account_deletion_connect_reject_${cleanupKey}` }
        ).catch(async () => {
          // `accounts.reject` only succeeds for platform-initiated risk
          // rejections; if Stripe declines it (e.g. account already has
          // payout history), fall back to disabling payouts/charges
          // directly so the account can no longer move money.
          await stripe.accounts.update(
            stripeAccountId,
            {
              capabilities: { transfers: { requested: false } },
            },
            { idempotencyKey: `account_deletion_connect_disable_${cleanupKey}` }
          );
        });
        result.connectAccount = "deactivated";
      } catch (err) {
        if (err.code === "resource_missing") {
          result.connectAccount = "already_removed";
        } else {
          throw err;
        }
      }
    }

    res.json({ ok: true, ...result });
  } catch (err) {
    console.error("❌ admin/cleanup-account error", err);
    res.status(500).json({ error: "cleanup_failed", detail: err.message });
  }
});

// --- Listen ---
const PORT = process.env.PORT || 10000;
app.listen(PORT, () => console.log(`🚀 Server running on port ${PORT}`));
