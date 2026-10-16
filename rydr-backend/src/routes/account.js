const express = require("express");
const { requireFirebaseAuth } = require("../middleware/firebaseAuth");
const { createAccountDeletionRequest } = require("../services/accountDeletionService");
const { syncAccountIdentity, finalizeAccountProfile } = require("../services/accountIdentityService");

const { getOnboardingStatus, recordOnboardingCheckpoint } = require("../services/accountOnboardingService");

const router = express.Router();
router.use(requireFirebaseAuth);

router.get("/onboarding", async (req, res, next) => {
  try { res.set("Cache-Control", "no-store").json(await getOnboardingStatus({ uid: req.firebaseUid, role: req.query.role, token: req.firebaseToken })); }
  catch (err) { next(err); }
});
router.post("/onboarding/checkpoint", async (req, res, next) => {
  try { res.json(await recordOnboardingCheckpoint({ uid: req.firebaseUid, role: req.body?.role, step: req.body?.step })); }
  catch (err) { next(err); }
});

router.post("/deletion-requests", async (req, res, next) => {
  try {
    const result = await createAccountDeletionRequest({
      uid: req.firebaseUid,
      reason: req.body?.reason,
      tokenEmail: req.firebaseToken?.email
    });
    return res.status(result.duplicate ? 200 : 201).json({ ok: true, ...result });
  } catch (err) {
    return next(err);
  }
});

router.post("/identity/sync", async (req, res, next) => {
  try {
    const result = await syncAccountIdentity({
      uid: req.firebaseUid,
      role: req.body?.role,
      token: req.firebaseToken,
      acceptBetaWaiver: req.body?.betaWaiverAccepted === true,
      beginOnboarding: req.body?.beginOnboarding === true
    });
    return res.json({ ok: true, ...result });
  } catch (err) {
    return next(err);
  }
});

router.post("/profile/finalize", async (req, res, next) => {
  try {
    const result = await finalizeAccountProfile({
      uid: req.firebaseUid,
      role: req.body?.role,
      token: req.firebaseToken,
      payload: req.body?.profile
    });
    return res.json({ ok: true, ...result });
  } catch (err) {
    return next(err);
  }
});

router.post("/cash-hub-rider-profile", async (req, res, next) => {
  try {
    const result = await syncAccountIdentity({
      uid: req.firebaseUid,
      role: "rider",
      token: req.firebaseToken,
      profileData: req.body
    });
    return res.status(201).json({ ok: true, ...result });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
