"use strict";
const { createHash } = require("node:crypto");
function accessError(code, status = 403) {
  const e = new Error(code);
  e.code = code;
  e.statusCode = status;
  e.status = status;
  return e;
}
function phoneHash(phone) {
  return typeof phone === "string" && /^\+[1-9]\d{6,14}$/.test(phone.trim())
    ? createHash("sha256").update(phone.trim()).digest("hex")
    : null;
}
function isBlockedTestAccount(policy, uid, phone) {
  const hash = policy.authSeparationEnabled === true ? null : phoneHash(phone);
  return (
    policy.blockedAuthUids.includes(uid) ||
    (hash !== null && policy.blockedPhoneHashes.includes(hash))
  );
}
async function liveBetaContext(db, mode) {
  const liveWorkspace = db.databaseId === "live-beta";
  if (liveWorkspace) {
    if (mode === "test") throw accessError("workspace_stripe_mode_mismatch", 503);
    const state = (await db.collection("platformConfig").doc("workspace").get()).data();
    if (state?.enabled !== true || state.livePaymentsEnabled !== true)
      throw accessError("live_beta_not_enabled", 503);
  }
  if (mode === "test") return { mode: "test" };
  if (mode === undefined) {
    const runtime = (
      await db.collection("platformConfig").doc("stripeRuntime").get()
    ).data();
    if (
      !runtime ||
      runtime.status !== "ready" ||
      !["test", "live"].includes(runtime.mode)
    )
      throw accessError("payment_environment_unavailable", 503);
    mode = runtime.mode;
    if (mode === "test") {
      if (liveWorkspace) throw accessError("workspace_stripe_mode_mismatch", 503);
      return { mode: "test" };
    }
  }
  if (mode !== "live")
    throw accessError("payment_environment_unavailable", 503);
  const policy = (
    await db.collection("operationalSecurity").doc("liveBetaAccess").get()
  ).data();
  if (
    !policy ||
    ![1,2].includes(policy.version) ||
    policy.configured !== true ||
    !Array.isArray(policy.blockedAuthUids) ||
    !Array.isArray(policy.blockedPhoneHashes) ||
    (!policy.authSeparationEnabled && !policy.blockedPhoneHashes.length)
  )
    throw accessError("live_beta_protection_unavailable", 503);
  return { mode: "live", policy };
}
async function assertLiveBetaAccess({
  db,
  uid,
  mode,
  phone,
  getUser,
  context,
}) {
  const state = context || (await liveBetaContext(db, mode));
  if (state.mode === "test") return;
  if (!uid) throw accessError("account_required");
  if (isBlockedTestAccount(state.policy, uid, phone))
    throw accessError("firebase_test_account_live_access_blocked");
  if (getUser) {
    let user;
    try {
      user = await getUser(uid);
    } catch {
      throw accessError("live_account_verification_unavailable", 503);
    }
    if (
      user.disabled ||
      isBlockedTestAccount(state.policy, uid, user.phoneNumber)
    )
      throw accessError("firebase_test_account_live_access_blocked");
  } else if (phone === undefined)
    throw accessError("live_account_verification_unavailable", 503);
}
async function filterLiveBetaCandidates(db, candidates) {
  const state = await liveBetaContext(db);
  if (state.mode === "test") return candidates;
  return candidates.filter(
    (c) =>
      !isBlockedTestAccount(
        state.policy,
        c.id,
        c.profile?.phoneE164 || c.profile?.phoneNumber,
      ),
  );
}
module.exports = {
  phoneHash,
  isBlockedTestAccount,
  liveBetaContext,
  assertLiveBetaAccess,
  filterLiveBetaCandidates,
};
