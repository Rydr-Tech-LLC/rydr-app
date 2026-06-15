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
        case "identity.verification_session.verified": {
          const vs = event.data.object;
          console.log("✅ identity verified", vs.id);
          await persistStripeLedger(`identity_${vs.id}`, {
            type: event.type,
            verificationSessionId: vs.id,
            uid: vs.metadata?.uid || null,
            email: vs.metadata?.email || null,
            status: vs.status,
          });
          await updateDriver(vs.metadata?.uid, {
            identityStatus: "verified",
            identityVerificationSessionId: vs.id,
            identityVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
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

    res.json({ accountId: account.id });
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

// ============================================================================
// Driver: Identity (Stripe Identity) — Create hosted session
// Body: { uid, email, name }
app.post("/identity/session", async (req, res) => {
  try {
    const { uid, email, name } = req.body || {};
    if (!uid || !email || !name) {
      return res.status(400).json({ error: "missing_params" });
    }

    const base = appBaseURL();

    const session = await stripe.identity.verificationSessions.create({
      type: "document",
      return_url: `${base}/identity/return`,
      metadata: { uid, email, name },
      options: {
        document: {
          require_id_number: true,
          require_live_capture: true,
        },
      },
    });

    res.json({ sessionId: session.id, url: session.url });
  } catch (err) {
    console.error("identity/session error", err);
    res.status(500).json({ error: "identity_session_failed" });
  }
});

// Driver: Identity — Poll session status
app.get("/identity/session/:id", async (req, res) => {
  try {
    const session = await stripe.identity.verificationSessions.retrieve(
      req.params.id
    );
    res.json({
      status: session.status,
      verified_outputs: session.verified_outputs || null,
      last_error: session.last_error || null,
    });
  } catch (err) {
    console.error("identity/session retrieve error", err);
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





