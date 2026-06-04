// server.js
// RydrBank service — Express + Firebase Admin + Firestore
// - Fixes Firestore transaction order (all READS before any WRITES)
// - Adds notifications (SendGrid email + Twilio SMS)
// - Supports transfers to existing users (in‑app) and non‑users (web code)
// - Adds web booking endpoints for non‑users

import express from "express";
import cors from "cors";
import admin from "firebase-admin";

// ---------- Firebase Admin ----------
if (!admin.apps.length) {
  admin.initializeApp({
    // On Render, mount your service account JSON as a Secret File
    // Path should be /etc/secrets/firebase.json and exposed via env if desired
    credential: admin.credential.cert(
      process.env.GOOGLE_APPLICATION_CREDENTIALS || "/etc/secrets/firebase.json"
    ),
  });
}
const db = admin.firestore();

// ---------- Express ----------
const app = express();
app.use(express.json());
app.use(cors({ origin: true })); // tighten later

// ---------- Auth middleware ----------
async function requireAuth(req, res, next) {
  try {
    const authz = req.headers.authorization || "";
    const [, token] = authz.split(" ");
    if (!token) return res.status(401).json({ error: "Missing token" });
    const decoded = await admin.auth().verifyIdToken(token);
    req.uid = decoded.uid;
    next();
  } catch (e) {
    res.status(401).json({ error: "Invalid token" });
  }
}

// ===== Notifications (email + SMS) =====
import sgMail from "@sendgrid/mail";
sgMail.setApiKey(process.env.SENDGRID_API_KEY || ""); // set in Render

import twilio from "twilio";
const twilioClient =
  process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN
    ? twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN)
    : null;

const FROM_EMAIL = process.env.EMAIL_FROM || "support@rydr-go.com";
const FROM_NAME = process.env.EMAIL_FROM_NAME || "Rydr Support";
const SMS_FROM = process.env.TWILIO_FROM || ""; // +1555...

function giftEmailContent(friendName, code) {
  const safeName =
    friendName && friendName.trim().length > 0 ? friendName.trim() : "there";
  const siteUrl = "https://www.rydr-go.com";
  const subject = "You’ve been gifted a free Rydr ride";

  const text = `Hi ${safeName},

Congratulations! You have just been gifted a free ride from your friend. If you have a Rydr account the promo code for the free ride will be added to your RydrBank. The free ride is good for up to a 15 mile ride. Keep in mind, this promo code is only good for one ride even if the ride is less than 15 miles.

If you do not have a Rydr account, but would still like to take advantage of the promo code, please go to ${siteUrl} and use the web to book your ride using the promo code.

Promo Code: ${code}

Happy Rydying!

Rydr Support`;

  const html = `
  <p>Hi ${safeName},</p>
  <p>Congratulations! You have just been gifted a free ride from your friend. If you have a Rydr account the promo code for the free ride will be added to your RydrBank. The free ride is good for up to a 15 mile ride. Keep in mind, this promo code is only good for one ride even if the ride is less than 15 miles.</p>
  <p>If you do not have a Rydr account, but would still like to take advantage of the promo code, please go to <a href="${siteUrl}" target="_blank">${siteUrl}</a> and use the web to book your ride using the promo code.</p>
  <p><strong>Promo Code:</strong> ${code}</p>
  <p>Happy Rydying!</p>
  <p>Rydr Support</p>`;

  return { subject, text, html };
}

async function sendGiftEmail({ toEmail, friendName, code }) {
  if (!process.env.SENDGRID_API_KEY) return;
  const { subject, text, html } = giftEmailContent(friendName, code);
  await sgMail.send({
    to: toEmail,
    from: { email: FROM_EMAIL, name: FROM_NAME },
    subject,
    text,
    html,
  });
}

async function sendGiftSms({ toPhone, code }) {
  if (!twilioClient || !SMS_FROM || !toPhone) return;
  const msg = `You’ve been gifted a free Rydr ride. Promo code: ${code}. Book at https://www.rydr-go.com`;
  await twilioClient.messages.create({ to: toPhone, from: SMS_FROM, body: msg });
}

// ---------- Helpers ----------
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no I,O,1,0
function randomCode(len = 8) {
  let s = "";
  for (let i = 0; i < len; i++) s += ALPHABET[Math.floor(Math.random() * ALPHABET.length)];
  return `RB-${s.slice(0, 4)}-${s.slice(4, 8)}`;
}

function rewardGroupForRideType(rideType = "") {
  const key = String(rideType).toLowerCase();
  if (key.includes("xl")) return "xl";
  if (key.includes("prestine") || key.includes("pristine")) return "prestine";
  if (key.includes("executive")) return "executive";
  return "go_eco";
}

function rewardLabelForGroup(group = "go_eco") {
  if (group === "xl") return "Rydr XL";
  if (group === "prestine") return "Rydr Prestine";
  if (group === "executive") return "Rydr Executive";
  return "Rydr Go / Rydr Eco";
}

function emptyRewardProgress() {
  return { eligibleCount: 0, totalEligible: 0, codesEarned: 0 };
}

function nextRewardProgress(bank, rewardGroup) {
  const current = bank?.progressByRideType?.[rewardGroup] || emptyRewardProgress();
  return {
    eligibleCount: (current.eligibleCount || 0) + 1,
    totalEligible: (current.totalEligible || 0) + 1,
    codesEarned: current.codesEarned || 0,
  };
}

function assertCodeMatchesRide(data, rideType, distanceMi) {
  if (typeof distanceMi === "number" && distanceMi > (data.maxMiles || 15)) {
    throw new Error("ride_too_long");
  }

  const codeGroup = data.rewardGroup || "go_eco";
  const requestedGroup = rewardGroupForRideType(rideType);
  if (codeGroup !== requestedGroup) {
    throw new Error("wrong_ride_type");
  }
}

// Only READS a free code in the transaction; returns chosen code + indexRef to write later
async function reserveUniqueCodeReadsOnly(t) {
  while (true) {
    const code = randomCode(8);
    const indexRef = db.collection("codes_index").doc(code);
    const idxSnap = await t.get(indexRef); // READ
    if (!idxSnap.exists) return { code, indexRef };
  }
}

// Combined accrual + (optional) mint inside ONE transaction with proper ordering.
async function accrueAndMaybeMintInOneTxn(uid, rideId, distanceMi, rideType) {
  if (typeof distanceMi !== "number" || distanceMi < 5) {
    return { eligible: false, minted: null };
  }

  const userRef = db.collection("users").doc(uid);
  const contribRef = userRef.collection("rydrContrib").doc(rideId);
  const rewardGroup = rewardGroupForRideType(rideType);
  const rewardLabel = rewardLabelForGroup(rewardGroup);

  const result = await db.runTransaction(async (t) => {
    // === READS FIRST ===
    const [contribSnap, userSnap] = await Promise.all([t.get(contribRef), t.get(userRef)]);

    if (contribSnap.exists) {
      const bank = (userSnap.exists ? userSnap.get("rydrBank") : null) || {};
      const current = bank?.progressByRideType?.[rewardGroup]?.eligibleCount ?? bank.eligibleCount ?? 0;
      return { eligible: true, minted: null, currentEligible: current };
    }

    const bank = (userSnap.exists ? userSnap.get("rydrBank") : null) || {};
    const currentEligible = bank?.progressByRideType?.[rewardGroup]?.eligibleCount ?? 0;
    const nextEligible = currentEligible + 1;
    const updatedProgress = nextRewardProgress(bank, rewardGroup);

    let mintPlan = null;
    if (nextEligible % 10 === 0) {
      const { code, indexRef } = await reserveUniqueCodeReadsOnly(t); // READS ONLY
      const newCodeRef = userRef.collection("rydrBankCodes").doc();
      mintPlan = { code, indexRef, newCodeRef };
    }

    // === WRITES AFTER ALL READS ===
    t.set(contribRef, {
      contributedAt: admin.firestore.FieldValue.serverTimestamp(),
      distanceMi,
      rideType: rideType || null,
      rewardGroup,
    });

    t.set(
      userRef,
      {
        rydrBank: {
          eligibleCount: admin.firestore.FieldValue.increment(1),
          totalEligible: admin.firestore.FieldValue.increment(1),
          progressByRideType: {
            [rewardGroup]: updatedProgress,
          },
        },
      },
      { merge: true }
    );

    if (mintPlan) {
      const { code, indexRef, newCodeRef } = mintPlan;

      t.set(indexRef, {
        code,
        currentOwnerUid: uid,
        codeDocPath: newCodeRef.path,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      t.set(newCodeRef, {
        code,
        status: "active", // active | reserved | used | void
        maxMiles: 15,
        rewardGroup,
        rewardLabel,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        reservedRideId: null,
        usedRideId: null,
        originalOwnerUid: uid,
        transferCount: 0,
        transferable: true,
      });

      t.set(
        userRef,
        {
          rydrBank: {
            codesAvailable: admin.firestore.FieldValue.increment(1),
            codesEarned: admin.firestore.FieldValue.increment(1),
            progressByRideType: {
              [rewardGroup]: {
                ...updatedProgress,
                codesEarned: (updatedProgress.codesEarned || 0) + 1,
              },
            },
          },
        },
        { merge: true }
      );

      return { eligible: true, minted: code, currentEligible: nextEligible, rewardGroup };
    }

    return { eligible: true, minted: null, currentEligible: nextEligible, rewardGroup };
  });

  return { eligible: true, minted: result.minted || null, rewardGroup: result.rewardGroup || rewardGroup };
}

// ---------- Routes ----------

// Health
app.get("/", (_, res) => res.send("RydrBank service up"));

// Earn (simulate ride completion). distanceMi >= 5 required to be eligible.
app.post("/rides/complete", requireAuth, async (req, res) => {
  try {
    const { rideId, distanceMi, rideType } = req.body || {};
    if (!rideId || typeof distanceMi !== "number") {
      return res.status(400).json({ error: "rideId and distanceMi required" });
    }
    const out = await accrueAndMaybeMintInOneTxn(req.uid, rideId, distanceMi, rideType);
    return res.json(out);
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: "server_error" });
  }
});

// Reserve a code for a booking (mobile preview/apply)
app.post("/promo/preview", requireAuth, async (req, res) => {
  const { code, bookingId, rideType, distanceMi } = req.body || {};
  if (!code) return res.status(400).json({ error: "code required" });

  try {
    let rewardLabel = "Rydr Go / Rydr Eco";
    await db.runTransaction(async (t) => {
      const idxRef = db.collection("codes_index").doc(code);
      const idxSnap = await t.get(idxRef);
      if (!idxSnap.exists) throw new Error("not_found");

      const ownerUid = idxSnap.get("currentOwnerUid");
      if (ownerUid !== req.uid) throw new Error("not_owner");

      const codeRef = db.doc(idxSnap.get("codeDocPath"));
      const codeSnap = await t.get(codeRef);
      const data = codeSnap.data();
      if (!data) throw new Error("not_found");
      if (data.status === "reserved" && data.reservedRideId === bookingId) {
        assertCodeMatchesRide(data, rideType, distanceMi);
        rewardLabel = data.rewardLabel || rewardLabelForGroup(data.rewardGroup || "go_eco");
        return;
      }
      if (data.status !== "active") throw new Error("not_active");
      assertCodeMatchesRide(data, rideType, distanceMi);
      rewardLabel = data.rewardLabel || rewardLabelForGroup(data.rewardGroup || "go_eco");

      t.update(codeRef, {
        status: "reserved",
        reservedRideId: bookingId || "preview-" + Date.now(),
      });
    });

    res.json({
      ok: true,
      rewardLabel,
      message: "RydrBank applied: this eligible ride is covered.",
    });
  } catch (e) {
    console.error(e);
    res.status(400).json({ error: e.message || "cannot_preview" });
  }
});

// Release a reserved code
app.post("/promo/release", requireAuth, async (req, res) => {
  const { code } = req.body || {};
  if (!code) return res.status(400).json({ error: "code required" });

  try {
    await db.runTransaction(async (t) => {
      const idxRef = db.collection("codes_index").doc(code);
      const idxSnap = await t.get(idxRef);
      if (!idxSnap.exists) throw new Error("not_found");
      const ownerUid = idxSnap.get("currentOwnerUid");
      if (ownerUid !== req.uid) throw new Error("not_owner");

      const codeRef = db.doc(idxSnap.get("codeDocPath"));
      const codeSnap = await t.get(codeRef);
      const data = codeSnap.data();
      if (!data) throw new Error("not_found");
      if (data.status !== "reserved") return;

      t.update(codeRef, { status: "active", reservedRideId: null });
    });

    res.json({ ok: true });
  } catch (e) {
    console.error(e);
    res.status(400).json({ error: e.message || "cannot_release" });
  }
});

// Consume a code after the ride is completed (mobile)
app.post("/promo/consume", requireAuth, async (req, res) => {
  const { code, rideId, rideType, distanceMi } = req.body || {};
  if (!code || !rideId) return res.status(400).json({ error: "code and rideId required" });

  try {
    await db.runTransaction(async (t) => {
      const idxRef = db.collection("codes_index").doc(code);
      const idxSnap = await t.get(idxRef);
      if (!idxSnap.exists) throw new Error("not_found");
      const ownerUid = idxSnap.get("currentOwnerUid");
      if (ownerUid !== req.uid) throw new Error("not_owner");

      const codeRef = db.doc(idxSnap.get("codeDocPath"));
      const codeSnap = await t.get(codeRef);
      const data = codeSnap.data();
      if (!data) throw new Error("not_found");
      if (data.status !== "reserved" && data.status !== "active")
        throw new Error("bad_status");
      assertCodeMatchesRide(data, rideType, distanceMi);

      t.update(codeRef, {
        status: "used",
        usedRideId: rideId,
        reservedRideId: null,
        usedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      t.set(
        db.collection("users").doc(ownerUid),
        { rydrBank: { codesAvailable: admin.firestore.FieldValue.increment(-1) } },
        { merge: true }
      );
    });

    res.json({ ok: true });
  } catch (e) {
    console.error(e);
    res.status(400).json({ error: e.message || "cannot_consume" });
  }
});

// One-time transfer to a friend (user or non-user) + notifications
app.post("/promo/transfer", requireAuth, async (req, res) => {
  const { code, recipientEmail, recipientName, recipientPhone } = req.body || {};
  if (!code || !recipientEmail)
    return res.status(400).json({ error: "code and recipientEmail required" });

  try {
    const recipient = await admin.auth().getUserByEmail(recipientEmail).catch(() => null);
    const friendIsUser = !!recipient;

    if (friendIsUser) {
      // ----- EXISTING USER -----
      await db.runTransaction(async (t) => {
        const idxRef = db.collection("codes_index").doc(code);
        const idxSnap = await t.get(idxRef);
        if (!idxSnap.exists) throw new Error("not_found");

        const ownerUid = idxSnap.get("currentOwnerUid");
        if (ownerUid !== req.uid) throw new Error("not_owner");

        const codeRef = db.doc(idxSnap.get("codeDocPath"));
        const codeSnap = await t.get(codeRef);
        const data = codeSnap.data();
        if (!data) throw new Error("not_found");
        if (data.status !== "active") throw new Error("not_active");
        if (data.transferCount !== 0 || data.transferable !== true)
          throw new Error("not_transferable");
        if (data.originalOwnerUid !== req.uid)
          throw new Error("only_original_owner_can_transfer");

        const recipRef = db
          .collection("users")
          .doc(recipient.uid)
          .collection("rydrBankCodes")
          .doc();

        t.set(recipRef, {
          code: data.code,
          status: "active",
          maxMiles: data.maxMiles,
          rewardGroup: data.rewardGroup || "go_eco",
          rewardLabel: data.rewardLabel || rewardLabelForGroup(data.rewardGroup || "go_eco"),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          reservedRideId: null,
          usedRideId: null,
          originalOwnerUid: data.originalOwnerUid,
          transferCount: 1,
          transferable: false,
        });

        t.update(codeRef, { status: "void", transferCount: 1, transferable: false });

        t.update(idxRef, {
          currentOwnerUid: recipient.uid,
          codeDocPath: recipRef.path,
          rewardGroup: data.rewardGroup || "go_eco",
          rewardLabel: data.rewardLabel || rewardLabelForGroup(data.rewardGroup || "go_eco"),
          transferredAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        t.set(
          db.collection("users").doc(req.uid),
          { rydrBank: { codesAvailable: admin.firestore.FieldValue.increment(-1) } },
          { merge: true }
        );
        t.set(
          db.collection("users").doc(recipient.uid),
          { rydrBank: { codesAvailable: admin.firestore.FieldValue.increment(1) } },
          { merge: true }
        );
      });

      await Promise.all([
        sendGiftEmail({ toEmail: recipientEmail, friendName: recipientName, code }),
        sendGiftSms({ toPhone: recipientPhone, code }),
      ]);

      return res.json({ ok: true, friendIsUser: true });
    } else {
      // ----- NON-USER -----
      await db.runTransaction(async (t) => {
        const idxRef = db.collection("codes_index").doc(code);
        const idxSnap = await t.get(idxRef);
        if (!idxSnap.exists) throw new Error("not_found");

        const ownerUid = idxSnap.get("currentOwnerUid");
        if (ownerUid !== req.uid) throw new Error("not_owner");

        const codeDocPath = idxSnap.get("codeDocPath");
        const codeRef = db.doc(codeDocPath);
        const codeSnap = await t.get(codeRef);
        const data = codeSnap.data();
        if (!data) throw new Error("not_found");
        if (data.status !== "active") throw new Error("not_active");
        if (data.transferCount !== 0 || data.transferable !== true)
          throw new Error("not_transferable");
        if (data.originalOwnerUid !== req.uid)
          throw new Error("only_original_owner_can_transfer");

        // Void sender copy
        t.update(codeRef, { status: "void", transferCount: 1, transferable: false });

        // Mark index as owned by external email
        t.update(idxRef, {
          currentOwnerUid: `external:${recipientEmail.toLowerCase()}`,
          codeDocPath: null,
          rewardGroup: data.rewardGroup || "go_eco",
          rewardLabel: data.rewardLabel || rewardLabelForGroup(data.rewardGroup || "go_eco"),
          maxMiles: data.maxMiles || 15,
          transferredAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // decrement sender balance
        t.set(
          db.collection("users").doc(req.uid),
          { rydrBank: { codesAvailable: admin.firestore.FieldValue.increment(-1) } },
          { merge: true }
        );
      });

      await Promise.all([
        sendGiftEmail({ toEmail: recipientEmail, friendName: recipientName, code }),
        sendGiftSms({ toPhone: recipientPhone, code }),
      ]);

      return res.json({ ok: true, friendIsUser: false });
    }
  } catch (e) {
    console.error(e);
    return res.status(400).json({ error: e.message || "cannot_transfer" });
  }
});

// ===== Web booking (no auth) for non-user recipients =====

// Preview/apply (no auth) -> check external email owns the code
app.post("/web/promo/preview", async (req, res) => {
  const { code, email, bookingId, rideType, distanceMi } = req.body || {};
  if (!code || !email) return res.status(400).json({ error: "code and email required" });

  try {
    let rewardLabel = "Rydr Go / Rydr Eco";
    await db.runTransaction(async (t) => {
      const idxRef = db.collection("codes_index").doc(code);
      const idxSnap = await t.get(idxRef);
      if (!idxSnap.exists) throw new Error("not_found");

      const owner = idxSnap.get("currentOwnerUid");
      if (owner !== `external:${email.toLowerCase()}`) throw new Error("not_owner_external");
      assertCodeMatchesRide(
        {
          rewardGroup: idxSnap.get("rewardGroup") || "go_eco",
          maxMiles: idxSnap.get("maxMiles") || 15,
        },
        rideType,
        distanceMi
      );
      rewardLabel = idxSnap.get("rewardLabel") || rewardLabelForGroup(idxSnap.get("rewardGroup") || "go_eco");

      // Optional: write a soft reservation doc if you want
      // (skipped here; preview just returns ok)
    });

    return res.json({
      ok: true,
      rewardLabel,
      message: "RydrBank applied: this eligible ride is covered.",
    });
  } catch (e) {
    console.error(e);
    return res.status(400).json({ error: e.message || "cannot_preview" });
  }
});

// Consume (no auth) -> mark external code as used
app.post("/web/promo/consume", async (req, res) => {
  const { code, email, rideId, rideType, distanceMi } = req.body || {};
  if (!code || !email || !rideId)
    return res.status(400).json({ error: "code, email, rideId required" });

  try {
    await db.runTransaction(async (t) => {
      const idxRef = db.collection("codes_index").doc(code);
      const idxSnap = await t.get(idxRef);
      if (!idxSnap.exists) throw new Error("not_found");

      const owner = idxSnap.get("currentOwnerUid");
      if (owner !== `external:${email.toLowerCase()}`) throw new Error("not_owner_external");
      assertCodeMatchesRide(
        {
          rewardGroup: idxSnap.get("rewardGroup") || "go_eco",
          maxMiles: idxSnap.get("maxMiles") || 15,
        },
        rideType,
        distanceMi
      );

      t.update(idxRef, {
        usedByExternal: email.toLowerCase(),
        usedRideId: rideId,
        usedAt: admin.firestore.FieldValue.serverTimestamp(),
        status: "used", // informational
      });

      // Optional: audit record
      const auditRef = db.collection("audits").doc();
      t.set(auditRef, {
        type: "external_consume",
        code,
        email: email.toLowerCase(),
        rideId,
        at: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return res.json({ ok: true });
  } catch (e) {
    console.error(e);
    return res.status(400).json({ error: e.message || "cannot_consume" });
  }
});

// ---------- Start ----------
const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log("Listening on", PORT));
