"use strict";
const API_VERSION = "2024-06-20";
const PROFILE_DEFAULTS = {
  stripeCustomerId: null,
  stripeAccountId: null,
  stripeConnectStatus: "not_started",
  stripeChargesEnabled: false,
  stripePayoutsEnabled: false,
  stripeRequirementsDue: [],
  payoutsStepCompleted: false,
  payoutsStepCompletedAt: null,
  stripeIdentityVerificationId: null,
  stripeIdentityFlow: null,
  stripeIdentityStatus: "not_started",
  stripeIdentityLastEventAt: null,
  identityStatus: "not_started",
  identityVerified: false,
  identityVerifiedAt: null,
  identityLastError: null,
  identityVerificationStepCompleted: false,
  identityVerificationStepCompletedAt: null,
  verifiedRider: false,
  verifiedBadge: false,
  payoutBankName: null,
  payoutBankLast4: null,
  payoutCardName: null,
  payoutCardLast4: null,
  availableBalance: 0,
  pendingPayouts: 0,
};
function modeError(code) {
  const e = new Error(code);
  e.code = code;
  return e;
}
function runtimeConfig(env) {
  const mode = String(env.STRIPE_SECRET_KEY || "").match(
    /^(?:sk|rk)_(test|live)_/,
  )?.[1];
  if (!mode) throw modeError("invalid_stripe_secret_key_mode");
  const publishableKey = String(env.STRIPE_PUBLISHABLE_KEY || "").trim();
  if (!publishableKey.startsWith(`pk_${mode}_`))
    throw modeError("stripe_key_mode_mismatch");
  const suffix = mode.toUpperCase();
  const scoped = (name) =>
    String(
      env[`${name}_${suffix}`] || (mode === "test" ? env[name] : "") || "",
    ).trim();
  const platformSecrets = [
    env.STRIPE_WEBHOOK_SECRET_TEST || env.STRIPE_WEBHOOK_SECRET,
    env.STRIPE_WEBHOOK_SECRET_LIVE,
  ].filter(Boolean);
  const connectSecrets = [
    env.STRIPE_CONNECT_WEBHOOK_SECRET_TEST || env.STRIPE_CONNECT_WEBHOOK_SECRET,
    env.STRIPE_CONNECT_WEBHOOK_SECRET_LIVE,
  ].filter(Boolean);
  if (
    mode === "live" &&
    (!scoped("STRIPE_WEBHOOK_SECRET") ||
      !scoped("STRIPE_CONNECT_WEBHOOK_SECRET") ||
      !scoped("STRIPE_DRIVER_VERIFICATION_FLOW_ID") ||
      !scoped("STRIPE_RIDER_VERIFICATION_FLOW_ID"))
  )
    throw modeError("live_stripe_configuration_incomplete");
  const liveMissing = [
    "STRIPE_WEBHOOK_SECRET_LIVE",
    "STRIPE_CONNECT_WEBHOOK_SECRET_LIVE",
    "STRIPE_DRIVER_VERIFICATION_FLOW_ID_LIVE",
    "STRIPE_RIDER_VERIFICATION_FLOW_ID_LIVE",
  ].filter((name) => !String(env[name] || "").trim());
  return {
    mode,
    publishableKey,
    apiVersion: API_VERSION,
    platformSecrets,
    connectSecrets,
    livePreparation: {
      configured: liveMissing.length === 0,
      missing: liveMissing,
    },
    platformWebhookSecret: scoped("STRIPE_WEBHOOK_SECRET"),
    connectWebhookSecret: scoped("STRIPE_CONNECT_WEBHOOK_SECRET"),
    identityFlows: {
      driver: scoped("STRIPE_DRIVER_VERIFICATION_FLOW_ID"),
      verified_rider: scoped("STRIPE_RIDER_VERIFICATION_FLOW_ID"),
    },
  };
}
function profileState(raw, mode) {
  const source =
    raw?.stripeProfiles?.[mode] ||
    (raw?.stripeMode === mode || (!raw?.stripeMode && mode === "test")
      ? raw
      : {});
  const values = { ...PROFILE_DEFAULTS };
  for (const field of Object.keys(PROFILE_DEFAULTS))
    if (source[field] !== undefined) values[field] = source[field];
  return values;
}
function modeProfile(raw, mode) {
  return raw ? { ...raw, ...profileState(raw, mode), stripeMode: mode } : null;
}
function profilePatch(raw, payload, mode) {
  const priorMode = raw?.stripeMode || "test";
  const prior = profileState(raw, priorMode);
  const active = { ...profileState(raw, mode) };
  for (const field of Object.keys(PROFILE_DEFAULTS))
    if (payload[field] !== undefined) active[field] = payload[field];
  return {
    ...payload,
    ...active,
    stripeMode: mode,
    stripeProfiles: {
      ...raw?.stripeProfiles,
      [priorMode]: prior,
      [mode]: active,
    },
  };
}
function jobMode(job) {
  return job?.stripeMode || "test";
}
function canChargeRide(ride, mode, activatedAt) {
  if (ride.stripeMode) return ride.stripeMode === mode;
  if (mode === "test") return true;
  const created =
    ride.createdAt?.toMillis?.() || ride.requestedAt?.toMillis?.() || 0;
  return created > 0 && created >= activatedAt;
}
function verifyWebhook(stripe, body, signature, secret, scope, mode) {
  const secrets = (Array.isArray(secret) ? secret : [secret]).filter(Boolean);
  if (!secrets.length) throw modeError("stripe_webhook_not_configured");
  let event;
  for (const candidate of secrets) {
    try {
      event = stripe.webhooks.constructEvent(body, signature, candidate);
      break;
    } catch {}
  }
  if (!event) throw modeError("stripe_webhook_signature_invalid");
  if (
    event.api_version &&
    !["2024-06-20", "2025-05-28.basil"].includes(event.api_version)
  )
    throw modeError("stripe_webhook_version_unsupported");
  if (scope === "connect" ? !event.account : !!event.account)
    throw modeError("stripe_webhook_scope_mismatch");
  return { event, active: event.livemode === (mode === "live") };
}
class StripeModeState {
  constructor({ getDb, mode, fieldValue }) {
    this.getDb = getDb;
    this.mode = mode;
    this.fieldValue = fieldValue;
    this.pending = null;
    this.initialized = false;
  }
  async ensure() {
    if (this.pending) return this.pending;
    this.pending = this.activate();
    try {
      return await this.pending;
    } finally {
      this.pending = null;
    }
  }
  async activate() {
    const db = this.getDb(),
      ref = db.collection("platformConfig").doc("stripeRuntime");
    let state = (await ref.get()).data();
    // A draining process must never switch the shared database back after a new
    // deployment activates the other mode. Only a fresh deployment can activate.
    if (this.initialized && state?.mode !== this.mode)
      throw modeError("stripe_mode_inactive");
    if (
      state?.mode === this.mode &&
      state.status === "ready" &&
      state.version === 1
    ) {
      this.initialized = true;
      return state;
    }
    await ref.set(
      {
        mode: this.mode,
        status: "preparing",
        version: 1,
        updatedAt: this.fieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    for (const collection of ["riders", "drivers"]) {
      let cursor;
      do {
        let query = db.collection(collection).orderBy("__name__").limit(100);
        if (cursor) query = query.startAfter(cursor);
        const page = await query.get();
        // Each transaction preserves both modes even if a profile changes concurrently.
        for (const doc of page.docs) {
          const result = await db.runTransaction(async (tx) => {
            const raw = (await tx.get(doc.ref)).data() || {};
            const patch = profilePatch(raw, {}, this.mode);
            tx.set(doc.ref, patch, { merge: true });
            return patch;
          });
          if (collection === "drivers")
            await db
              .collection("publicDriverProfiles")
              .doc(doc.id)
              .set(
                {
                  stripeMode: this.mode,
                  stripeAccountId: result.stripeAccountId,
                  stripeChargesEnabled: result.stripeChargesEnabled,
                  identityVerified: result.identityVerified,
                  updatedAt: this.fieldValue.serverTimestamp(),
                },
                { merge: true },
              );
        }
        cursor = page.size === 100 ? page.docs.at(-1).id : undefined;
      } while (cursor);
    }
    await ref.set(
      {
        mode: this.mode,
        status: "ready",
        version: 1,
        activatedAt: this.fieldValue.serverTimestamp(),
        updatedAt: this.fieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    state = (await ref.get()).data();
    this.initialized = true;
    return state;
  }
  async updateProfile(collection, uid, payload) {
    const db = this.getDb(),
      ref = db.collection(collection).doc(uid);
    await db.runTransaction(async (tx) => {
      const runtime = (
        await tx.get(db.collection("platformConfig").doc("stripeRuntime"))
      ).data();
      if (runtime?.mode !== this.mode || runtime.status !== "ready")
        throw modeError("stripe_mode_inactive");
      const raw = (await tx.get(ref)).data() || {};
      tx.set(ref, profilePatch(raw, payload, this.mode), { merge: true });
    });
  }
}
module.exports = {
  API_VERSION,
  runtimeConfig,
  profileState,
  modeProfile,
  profilePatch,
  jobMode,
  canChargeRide,
  verifyWebhook,
  StripeModeState,
};
