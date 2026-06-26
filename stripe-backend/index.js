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

function firebaseCredential() {
  const { FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY } = process.env;

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

async function verifiedFirebaseUid(req) {
  const authorization = req.header("authorization") || "";
  const match = authorization.match(/^Bearer (.+)$/);
  if (!match) return null;

  initializeFirebase();
  const decoded = await admin.auth().verifyIdToken(match[1]);
  return decoded.uid;
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
      case "payment_intent.succeeded":
        console.log("💰 payment_intent.succeeded:", event.data.object.id);
        break;
      case "payment_intent.payment_failed":
        console.log("⚠️ payment_intent.payment_failed:", event.data.object.id);
        break;
      case "account.updated": {
        const acct = event.data.object;
        console.log("ℹ️ account.updated", acct.id, {
          charges_enabled: acct.charges_enabled,
          payouts_enabled: acct.payouts_enabled,
        });
        await updateDriver(acct.metadata?.uid, {
          stripeAccountId: acct.id,
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

// --- Create-or-get Customer (idempotent) ---
// Body: { email?: string, name?: string, uid?: string } -> { customerId }
app.post("/create-customer", async (req, res) => {
  try {
    const { email, name, uid } = req.body || {};
    const verifiedUid = await verifiedFirebaseUid(req);
    const stripeMetadataUid = verifiedUid || uid;

    // 1) Prefer lookup by metadata.firebase_uid (if provided)
    if (stripeMetadataUid) {
      const byUid = await stripe.customers.search({
        query: `metadata['firebase_uid']:'${stripeMetadataUid}'`,
      });
      if (byUid.data.length) {
        if (verifiedUid) {
          await persistStripeCustomerId(verifiedUid, byUid.data[0].id);
        }
        return res.json({ customerId: byUid.data[0].id });
      }
    }

    // 2) Fallback by email (if present)
    if (email) {
      const byEmail = await stripe.customers.search({ query: `email:'${email}'` });
      if (byEmail.data.length) {
        // Backfill UID so future lookups use metadata
        if (stripeMetadataUid && byEmail.data[0].metadata?.firebase_uid !== stripeMetadataUid) {
          await stripe.customers.update(byEmail.data[0].id, {
            metadata: { ...byEmail.data[0].metadata, firebase_uid: stripeMetadataUid },
          });
        }
        if (verifiedUid) {
          await persistStripeCustomerId(verifiedUid, byEmail.data[0].id);
        }
        return res.json({ customerId: byEmail.data[0].id });
      }
    }

    // 3) Create new customer (email optional)
    const customer = await stripe.customers.create({
      email: email || undefined,
      name: name || undefined,
      metadata: stripeMetadataUid ? { firebase_uid: stripeMetadataUid } : undefined,
    });
    if (verifiedUid) {
      await persistStripeCustomerId(verifiedUid, customer.id);
    }
    return res.json({ customerId: customer.id });
  } catch (e) {
    console.error("❌ create-customer:", e);
    res.status(500).json({ error: "create_customer_failed" });
  }
});

// --- Ephemeral Key ---
// Headers: "Stripe-Version" required; Body: { customerId }
app.post("/ephemeral-key", async (req, res) => {
  try {
    const { customerId } = req.body || {};
    const apiVer = req.headers["stripe-version"];
    if (!customerId) return res.status(400).json({ error: "customerId_required" });
    if (!apiVer)    return res.status(400).json({ error: "stripe_version_required" });

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
// Body: { customerId } -> { clientSecret }
app.post("/create-setup-intent", async (req, res) => {
  try {
    const { customerId } = req.body || {};
    if (!customerId) return res.status(400).json({ error: "customerId_required" });

    const si = await stripe.setupIntents.create({
      customer: customerId,
      payment_method_types: ["card"],
      usage: "off_session",
    });
    res.json({ clientSecret: si.client_secret });
  } catch (e) {
    console.error("❌ create-setup-intent:", e);
    res.status(500).json({ error: "setup_intent_failed" });
  }
});

// --- PaymentIntent (charge) ---
// Body: { amount: <int cents>, currency: "usd", customerId?: "cus_...",
//         driverAccountId?: "acct_...", applicationFeeAmount?: <int cents>,
//         paymentMethodId?: "pm_...", confirm?: boolean }
//
// If driverAccountId is provided, this becomes a Stripe Connect "destination
// charge": the rider's card is charged the full `amount` on the platform
// account, Stripe automatically transfers (amount - applicationFeeAmount) to
// the driver's connected account, and the platform keeps applicationFeeAmount
// (the driver's 70/30-split platform cut + the full booking fee).
//
// If paymentMethodId + confirm are provided, the PaymentIntent is confirmed
// immediately off-session (used at ride completion, when the rider isn't
// actively present in a payment UI to authenticate a new charge). Otherwise
// this falls back to the original behavior of returning a clientSecret for
// the client to confirm itself.
app.post("/create-payment-intent", async (req, res) => {
  try {
    const {
      amount,
      currency = "usd",
      customerId,
      driverAccountId,
      applicationFeeAmount,
      paymentMethodId,
      confirm,
    } = req.body || {};

    if (!Number.isInteger(amount) || amount <= 0) {
      return res.status(400).json({ error: "invalid_amount" });
    }

    const params = {
      amount,
      currency,
      customer: customerId,
    };

    if (driverAccountId) {
      if (!Number.isInteger(applicationFeeAmount) || applicationFeeAmount < 0 || applicationFeeAmount > amount) {
        return res.status(400).json({ error: "invalid_application_fee_amount" });
      }
      params.application_fee_amount = applicationFeeAmount;
      params.transfer_data = { destination: driverAccountId };
    }

    if (paymentMethodId && confirm) {
      params.payment_method = paymentMethodId;
      params.confirm = true;
      params.off_session = true;
    } else {
      params.automatic_payment_methods = { enabled: true };
    }

    const pi = await stripe.paymentIntents.create(params);
    res.json({ clientSecret: pi.client_secret, paymentIntentId: pi.id, status: pi.status });
  } catch (e) {
    console.error("❌ create-payment-intent:", e);
    const code = e?.raw?.code || e?.code;
    if (code === "authentication_required") {
      return res.status(402).json({
        error: "authentication_required",
        paymentIntentId: e?.raw?.payment_intent?.id || null,
      });
    }
    res.status(402).json({ error: e.message || "payment_intent_failed" });
  }
});

// --- List saved card PaymentMethods (for wallet tiles) ---
// Body: { customerId } -> { paymentMethods: [{id,brand,last4,expMonth,expYear,isDefault}] }
app.post("/list-payment-methods", async (req, res) => {
  try {
    const { customerId } = req.body || {};
    if (!customerId) return res.status(400).json({ error: "customerId_required" });

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
// Body: { customerId, paymentMethodId } -> { ok: true }
app.post("/set-default-payment-method", async (req, res) => {
  try {
    const { customerId, paymentMethodId } = req.body || {};
    if (!customerId || !paymentMethodId)
      return res.status(400).json({ error: "required_params" });

    await stripe.customers.update(customerId, {
      invoice_settings: { default_payment_method: paymentMethodId },
    });
    res.json({ ok: true });
  } catch (e) {
    console.error("❌ set-default-payment-method:", e);
    res.status(500).json({ error: "update_failed" });
  }
});

// --- Detach a card ---
// Body: { paymentMethodId } -> { ok: true }
app.post("/detach-payment-method", async (req, res) => {
  try {
    const { paymentMethodId } = req.body || {};
    if (!paymentMethodId)
      return res.status(400).json({ error: "paymentMethodId_required" });

    await stripe.paymentMethods.detach(paymentMethodId);
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

    await updateDriver(uid, { stripeAccountId: account.id });
    await updatePublicDriverConnectStatus(uid, {
      stripeAccountId: account.id,
      stripeChargesEnabled: account.charges_enabled,
    });

    res.json({ accountId: account.id });
  } catch (err) {
    console.error("❌ connect/accounts error", err);
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
    console.error("❌ connect/account-link error", err);
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
    console.error("❌ connect/status error", err);
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
    console.error("❌ connect/balance error", err);
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

// --- Listen ---
const PORT = process.env.PORT || 10000;
app.listen(PORT, () => console.log(`🚀 Server running on port ${PORT}`));





