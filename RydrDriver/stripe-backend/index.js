// index.js
"use strict";

/**
 * Rydr Stripe Backend (Rider + Driver)
 * - Rider payments (PaymentSheet): /customers, /ephemeral-keys, /payment-intents
 * - Driver payouts (Stripe Connect Express): /connect/*
 * - Driver identity (Stripe Identity): /identity/*
 * - Webhooks: /webhook
 */

const express = require("express");
const cors = require("cors");
const dotenv = require("dotenv");
const Stripe = require("stripe");
const admin = require("firebase-admin");

dotenv.config();

if (!process.env.STRIPE_SECRET_KEY) {
  console.error("❌ Missing STRIPE_SECRET_KEY");
  process.exit(1);
}

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY, {
  apiVersion: "2024-06-20", // use a stable version
});

const app = express();
const identityFlows = {
  driver: "vf_1TmzHIBOkTOLtDHQffuNJGj8",
  verified_rider: "vf_1TmyroBOkTOLtDHQ6iv0Ojxc",
};
let firestore = null;

try {
  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    admin.initializeApp({
      credential: admin.credential.cert(
        JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)
      ),
    });
  } else {
    admin.initializeApp();
  }
  firestore = admin.firestore();
  console.log("Firestore ledger persistence enabled.");
} catch (err) {
  console.warn(
    "Firestore ledger persistence disabled:",
    err.message
  );
}

function appBaseURL() {
  const base = process.env.APP_BASE_URL;
  if (!base) {
    throw new Error("APP_BASE_URL is required for hosted Stripe return URLs");
  }
  return base.replace(/\/+$/, "");
}

async function persistStripeLedger(id, payload) {
  if (!firestore) return;
  await firestore.collection("stripeLedger").doc(id).set(
    {
      ...payload,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function updateDriver(uid, payload) {
  if (!firestore || !uid) return;
  await firestore.collection("drivers").doc(uid).set(
    {
      ...payload,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function updateRider(uid, payload) {
  if (!firestore || !uid) return;
  await firestore.collection("riders").doc(uid).set(
    {
      ...payload,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

async function driverData(uid) {
  if (!firestore || !uid) return null;
  const snapshot = await firestore.collection("drivers").doc(uid).get();
  return snapshot.exists ? snapshot.data() : null;
}

async function verifiedFirebaseUid(req) {
  const authorization = req.header("authorization") || "";
  const match = authorization.match(/^Bearer (.+)$/);
  if (!match) return null;
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
    console.warn("Firebase auth failed", err.message);
    res.status(401).json({ error: "unauthorized" });
    return null;
  }
}

async function identityProfile(uid, role) {
  if (!firestore) return {};
  const collection = role === "driver" ? "drivers" : "riders";
  const snapshot = await firestore.collection(collection).doc(uid).get();
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
    stripeIdentityVerificationId: session.id,
    stripeIdentityFlow: role,
    stripeIdentityLastEventAt: timestamp,
  };
  const lastError = session.last_error?.reason || session.last_error?.code || null;

  if (role === "driver") {
    await updateDriver(uid, status === "verified" ? {
      ...base,
      identityVerified: true,
      identityVerifiedAt: timestamp,
    } : {
      ...base,
      identityVerified: false,
      identityLastError: lastError,
    });
    return;
  }

  if (role === "verified_rider") {
    await updateRider(uid, status === "verified" ? {
      ...base,
      verifiedRider: true,
      identityVerified: true,
      verifiedBadge: true,
      identityVerifiedAt: timestamp,
    } : {
      ...base,
      verifiedRider: false,
      identityVerified: false,
      verifiedBadge: false,
      identityLastError: lastError,
    });
  }
}

// --- CORS (adjust origin if you want to lock it down) ---
app.use(cors());

// --- Raw body ONLY for webhooks ---
app.post(
  "/webhook",
  express.raw({ type: "application/json" }),
  async (req, res) => {
    const sig = req.headers["stripe-signature"];
    const endpointSecret = process.env.STRIPE_WEBHOOK_SECRET;

    try {
      let event;
      if (endpointSecret) {
        event = stripe.webhooks.constructEvent(
          req.body,
          sig,
          endpointSecret
        );
      } else {
        // Not recommended for prod, but allows local testing without secret
        event = JSON.parse(req.body);
      }

      switch (event.type) {
        case "payment_intent.succeeded": {
          const pi = event.data.object;
          console.log("✅ payment_intent.succeeded", pi.id);
          await persistStripeLedger(pi.id, {
            type: event.type,
            paymentIntentId: pi.id,
            rideId: pi.metadata?.rideId || null,
            driverId: pi.metadata?.driverId || null,
            riderId: pi.metadata?.riderId || null,
            amount: pi.amount,
            currency: pi.currency,
            status: pi.status,
            livemode: pi.livemode,
            created: pi.created,
          });
          break;
        }
        case "account.updated": {
          const acct = event.data.object;
          console.log("ℹ️ account.updated", acct.id, {
            charges_enabled: acct.charges_enabled,
            payouts_enabled: acct.payouts_enabled,
          });
          await persistStripeLedger(`account_${acct.id}`, {
            type: event.type,
            accountId: acct.id,
            uid: acct.metadata?.uid || null,
            charges_enabled: acct.charges_enabled,
            payouts_enabled: acct.payouts_enabled,
            requirements_due: acct.requirements?.currently_due || [],
          });
          await updateDriver(acct.metadata?.uid, {
            stripeAccountId: acct.id,
            stripeChargesEnabled: acct.charges_enabled,
            stripePayoutsEnabled: acct.payouts_enabled,
            stripeRequirementsDue: acct.requirements?.currently_due || [],
          });
          break;
        }
        case "identity.verification_session.verified":
        case "identity.verification_session.processing":
        case "identity.verification_session.requires_input":
        case "identity.verification_session.canceled": {
          const session = event.data.object;
          const status = event.type.replace("identity.verification_session.", "");
          console.log("ℹ️ identity status", session.id, status);
          await persistStripeLedger(`identity_${session.id}`, {
            type: event.type,
            verificationSessionId: session.id,
            uid: session.metadata?.uid || null,
            role: session.metadata?.role || null,
            status,
          });
          await updateIdentityStatus(session, status);
          break;
        }
        default:
          console.log("ℹ️ Unhandled event:", event.type);
      }

      res.sendStatus(200);
    } catch (err) {
      console.error("❌ Webhook verify failed:", err.message);
      res.status(400).send(`Webhook Error: ${err.message}`);
    }
  }
);

// --- JSON parser for all OTHER routes ---
app.use(express.json());

// ===== Misc =====
app.get("/", (_req, res) => {
  res.json({ ok: true, service: "Rydr Stripe backend", version: "1.0.0" });
});

// ============================================================================
// Rider: Customers (idempotent create-or-get)
// Body: { email?: string, name?: string, uid?: string } -> { customerId }
app.post("/customers", async (req, res) => {
  try {
    const { email, name, uid } = req.body || {};
    if (!email && !uid) {
      return res.status(400).json({ error: "email_or_uid_required" });
    }

    // Try to find by metadata.uid or email
    let customer;
    if (uid) {
      const search = await stripe.customers.search({
        query: `metadata['uid']:'${uid}'`,
      });
      if (search.data.length > 0) customer = search.data[0];
    }
    if (!customer && email) {
      const list = await stripe.customers.list({ email, limit: 1 });
      if (list.data.length > 0) customer = list.data[0];
    }
    if (!customer) {
      customer = await stripe.customers.create({
        email: email || undefined,
        name: name || undefined,
        metadata: uid ? { uid } : undefined,
      });
    }
    res.json({ customerId: customer.id });
  } catch (err) {
    console.error("customers error", err);
    res.status(500).json({ error: "customer_failed" });
  }
});

// Rider: Ephemeral key for PaymentSheet
// Query: ?customerId=cus_xxx&apiVersion=2024-06-20
app.post("/ephemeral-keys", async (req, res) => {
  try {
    const { customerId, apiVersion } = req.query;
    if (!customerId || !apiVersion) {
      return res.status(400).json({ error: "missing_params" });
    }
    const key = await stripe.ephemeralKeys.create(
      { customer: customerId },
      { apiVersion }
    );
    res.status(200).json(key);
  } catch (err) {
    console.error("ephemeral-keys error", err);
    res.status(500).json({ error: "ephemeral_key_failed" });
  }
});

// Rider: Create PaymentIntent (platform-only OR destination charge)
// Body: {
//   amount, currency, customerId,
//   driverAccountId?,            // if present -> destination charge
//   applicationFeeAmount?,       // in cents (your platform fee)
//   rideId?, driverId?, riderId?, source?
// }
app.post("/payment-intents", async (req, res) => {
  try {
    const {
      amount,
      currency = "usd",
      customerId,
      driverAccountId,
      applicationFeeAmount,
      rideId,
      driverId,
      riderId,
      source,
    } = req.body || {};

    if (!amount || !customerId) {
      return res.status(400).json({ error: "missing_amount_or_customer" });
    }

    const base = {
      amount,
      currency,
      customer: customerId,
      automatic_payment_methods: { enabled: true },
    };

    const metadata = {};
    if (rideId) metadata.rideId = String(rideId);
    if (driverId) metadata.driverId = String(driverId);
    if (riderId) metadata.riderId = String(riderId);
    if (source) metadata.source = String(source);
    if (Object.keys(metadata).length > 0) {
      base.metadata = metadata;
    }

    // Destination charge to driver (Connect)
    if (driverAccountId) {
      base.transfer_data = { destination: driverAccountId };
      if (typeof applicationFeeAmount === "number") {
        base.application_fee_amount = applicationFeeAmount;
      }
    }

    const intent = await stripe.paymentIntents.create(base);
    res.json({ clientSecret: intent.client_secret });
  } catch (err) {
    console.error("payment-intents error", err);
    res.status(500).json({ error: "create_intent_failed" });
  }
});

// ============================================================================
// Driver: Stripe Connect (Express) — Create account
// Body expects: { uid, email, firstName, lastName, phone, dob:{day,month,year}, address:{ line1, city, state, postal_code, line2? } }
app.post("/connect/accounts", async (req, res) => {
  try {
    const { uid, email, firstName, lastName, phone, dob, address } =
      req.body || {};

    if (!uid || !email || !firstName || !lastName || !phone || !dob || !address) {
      return res.status(400).json({ error: "missing_required_fields" });
    }

    const existingAccountId = (await driverData(uid))?.stripeAccountId;
    if (existingAccountId) {
      try {
        const existing = await stripe.accounts.retrieve(existingAccountId);
        if (!existing.deleted) {
          await updateDriver(uid, {
            stripeAccountId: existing.id,
            stripeChargesEnabled: !!existing.charges_enabled,
            stripePayoutsEnabled: !!existing.payouts_enabled,
            stripeRequirementsDue: existing.requirements?.currently_due || [],
          });
          return res.json({ accountId: existing.id, reused: true });
        }
      } catch (err) {
        console.warn("Stored Stripe account could not be reused", {
          uid,
          accountId: existingAccountId,
          message: err.message,
        });
      }
    }

    const account = await stripe.accounts.create({
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
      metadata: { uid },
    });

    await updateDriver(uid, { stripeAccountId: account.id });

    res.json({ accountId: account.id, reused: false });
  } catch (err) {
    console.error("connect/accounts error", err);
    res.status(500).json({ error: "account_create_failed" });
  }
});

// Driver: Stripe Connect — Create onboarding link
// Body: { accountId }
app.post("/connect/account-link", async (req, res) => {
  try {
    const { accountId } = req.body || {};
    if (!accountId) return res.status(400).json({ error: "missing_accountId" });

    const base = appBaseURL();
    const link = await stripe.accountLinks.create({
      account: accountId,
      type: "account_onboarding",
      refresh_url: `${base}/return/refresh`,
      return_url: `${base}/return/complete`,
    });

    res.json({ url: link.url });
  } catch (err) {
    console.error("connect/account-link error", err);
    res.status(500).json({ error: "account_link_failed" });
  }
});

// Driver: Stripe Connect — Status
// Query: ?accountId=acct_xxx
app.get("/connect/status", async (req, res) => {
  try {
    const { accountId } = req.query;
    if (!accountId) return res.status(400).json({ error: "missing_accountId" });

    const acct = await stripe.accounts.retrieve(accountId);
    res.json({
      charges_enabled: acct.charges_enabled,
      payouts_enabled: acct.payouts_enabled,
      requirements_due: acct.requirements?.currently_due ?? [],
    });
  } catch (err) {
    console.error("connect/status error", err);
    res.status(500).json({ error: "status_failed" });
  }
});

// Driver: Stripe Connect — Balance available for payouts
// Query: ?accountId=acct_xxx
app.get("/connect/balance", async (req, res) => {
  try {
    const { accountId } = req.query;
    if (!accountId) return res.status(400).json({ error: "missing_accountId" });

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
    console.error("connect/balance error", err);
    res.status(500).json({ error: "balance_failed" });
  }
});

// Driver: Stripe Connect — Instant payout from ride-earnings balance
// Body: { accountId, amount, currency?, uid? }
app.post("/connect/instant-payout", async (req, res) => {
  try {
    const { accountId, amount, currency = "usd", uid } = req.body || {};
    if (!accountId) return res.status(400).json({ error: "missing_accountId" });
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
          uid: uid || acct.metadata?.uid || "",
          source: "driver_wallet_instant_pay",
        },
      },
      { stripeAccount: accountId }
    );

    await persistStripeLedger(`payout_${payout.id}`, {
      type: "instant_payout.created",
      payoutId: payout.id,
      accountId,
      uid: uid || acct.metadata?.uid || null,
      amount: payout.amount,
      currency: payout.currency,
      status: payout.status,
      method: payout.method,
    });

    res.json({
      payoutId: payout.id,
      amount: payout.amount,
      currency: payout.currency,
      status: payout.status,
    });
  } catch (err) {
    console.error("connect/instant-payout error", err);
    res.status(500).json({ error: "instant_payout_failed", detail: err.message });
  }
});

// Driver: Stripe Connect — Real payout history (replaces any client-side mock data)
// Query: ?accountId=acct_xxx&limit=10
app.get("/connect/payouts", async (req, res) => {
  try {
    const { accountId } = req.query;
    const limit = Math.min(parseInt(req.query.limit, 10) || 10, 50);
    if (!accountId) return res.status(400).json({ error: "missing_accountId" });

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
        arrivalDate: payout.arrival_date,
        created: payout.created,
      })),
    });
  } catch (err) {
    console.error("connect/payouts error", err);
    res.status(500).json({ error: "payouts_failed" });
  }
});

// Driver: Stripe Connect — Real linked bank account / debit card on file
// (replaces any client-side mock "Chase Checking •••• 4242" placeholder data)
// Query: ?accountId=acct_xxx
app.get("/connect/external-accounts", async (req, res) => {
  try {
    const { accountId } = req.query;
    if (!accountId) return res.status(400).json({ error: "missing_accountId" });

    const [banks, cards] = await Promise.all([
      stripe.accounts.listExternalAccounts(accountId, { object: "bank_account", limit: 5 }),
      stripe.accounts.listExternalAccounts(accountId, { object: "card", limit: 5 }),
    ]);

    res.json({
      bankAccounts: banks.data.map((account) => ({
        id: account.id,
        bankName: account.bank_name || "Bank account",
        last4: account.last4,
        isDefault: !!account.default_for_currency,
      })),
      cards: cards.data.map((card) => ({
        id: card.id,
        brand: card.brand || "Card",
        last4: card.last4,
        isDefault: !!card.default_for_currency,
      })),
    });
  } catch (err) {
    console.error("connect/external-accounts error", err);
    res.status(500).json({ error: "external_accounts_failed" });
  }
});

// Driver: Stripe Connect — Express dashboard login link, used to add/manage
// payout methods (bank accounts, debit cards) after onboarding. Stripe
// Express accounts manage external accounts in the Express dashboard rather
// than through another account-onboarding link.
// Query: ?accountId=acct_xxx
app.get("/connect/login-link", async (req, res) => {
  try {
    const { accountId } = req.query;
    if (!accountId) return res.status(400).json({ error: "missing_accountId" });

    const link = await stripe.accounts.createLoginLink(accountId);
    res.json({ url: link.url });
  } catch (err) {
    console.error("connect/login-link error", err);
    res.status(500).json({ error: "login_link_failed" });
  }
});

// ============================================================================
// Stripe Identity — Create verification session from configured Verification Flow
// Body: { role: "driver" | "verified_rider" }
app.post("/identity/create-session", async (req, res) => {
  try {
    const uid = await requireFirebaseUid(req, res);
    if (!uid) return;

    const { role } = req.body || {};
    const verificationFlow = identityFlows[role];
    if (!verificationFlow) {
      return res.status(400).json({ error: "invalid_identity_role" });
    }

    const profile = await identityProfile(uid, role);

    const session = await stripe.identity.verificationSessions.create({
      verification_flow: verificationFlow,
      provided_details: {
        email: profile.email,
      },
      metadata: {
        uid,
        role,
        verification_flow: verificationFlow,
      },
    });

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
    console.error("identity/create-session error", err);
    res.status(500).json({ error: "identity_session_failed" });
  }
});

// Stripe Identity — Poll backend-confirmed status
app.get("/identity/status", async (req, res) => {
  try {
    const uid = await requireFirebaseUid(req, res);
    if (!uid) return;

    const role = String(req.query.role || "");
    if (!identityFlows[role]) {
      return res.status(400).json({ error: "invalid_identity_role" });
    }

    const collection = role === "driver" ? "drivers" : "riders";
    const snapshot = firestore ? await firestore.collection(collection).doc(uid).get() : null;
    const data = snapshot?.exists ? snapshot.data() : {};
    res.json({
      identityVerified: !!data.identityVerified,
      verifiedRider: !!data.verifiedRider,
      verifiedBadge: !!data.verifiedBadge,
      identityStatus: data.identityStatus || "not_started",
      stripeIdentityVerificationId: data.stripeIdentityVerificationId || null,
    });
  } catch (err) {
    console.error("identity/status error", err);
    res.status(500).json({ error: "identity_status_failed" });
  }
});

// ============================================================================
// (Optional) PaymentMethod detach (handy for testing)
// Body: { paymentMethodId }
app.post("/payment-methods/detach", async (req, res) => {
  try {
    const { paymentMethodId } = req.body || {};
    if (!paymentMethodId)
      return res.status(400).json({ error: "missing_paymentMethodId" });

    const pm = await stripe.paymentMethods.detach(paymentMethodId);
    res.json({ ok: true, detached: pm.id });
  } catch (err) {
    console.error("detach error", err);
    res.status(500).json({ error: "detach_failed" });
  }
});

// --- Listen ---
const PORT = process.env.PORT || 10000;
app.listen(PORT, () => console.log(`🚀 Server running on port ${PORT}`));
