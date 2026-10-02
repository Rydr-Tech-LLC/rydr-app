const express = require("express");
const driverService = require("../services/driverService");
const { createAccountDeletionRequest } = require("../services/accountDeletionService");
const { updateDriverPresence } = require("../services/driverPresenceService");
const { getDriverDemandSnapshot } = require("../services/driverDemandService");
const { promoteNextQueuedRide } = require("../services/driverQueueService");
const { recordBackgroundCheckIntent } = require("../services/driverScreeningService");
const { updateDriverRateCard } = require("../services/driverRateCardService");
const { driverEarningsSummary } = require("../services/driverInsightsService");
const { requireFirebaseAuth, assertOwnsUid } = require("../middleware/firebaseAuth");

const router = express.Router();

// Every route in this file is state-changing and driver-account-scoped, so
// every route requires a verified Firebase ID token first (Part 8 backend
// security audit). Ownership of the specific uid/driverId in the body is
// then checked per-route below — the body is never trusted on its own.
router.use(requireFirebaseAuth);

router.post("/presence", async (req, res, next) => {
  try {
    const result = await updateDriverPresence({
      uid: req.firebaseUid,
      online: req.body?.online,
      selectedRideTypes: req.body?.selectedRideTypes,
      location: req.body?.location
    });
    return res.json({ ok: true, ...result });
  } catch (err) {
    return next(err);
  }
});

router.post("/demand", async (req, res, next) => {
  try {
    const demand = await getDriverDemandSnapshot({
      uid: req.firebaseUid,
      rideTypes: req.body?.rideTypes
    });
    return res.json({ ok: true, ...demand });
  } catch (err) {
    return next(err);
  }
});

router.post("/queue/promote-next", async (req, res, next) => {
  try {
    const result = await promoteNextQueuedRide({
      driverId: req.firebaseUid,
      requestId: req.body?.requestId
    });
    return res.json({ ok: true, ...result });
  } catch (err) {
    return next(err);
  }
});

router.post("/background-check/:action", async (req, res, next) => {
  try {
    const action = req.params.action;
    if (!["redirect", "acknowledge"].includes(action)) return res.status(404).json({ error: "Unknown background-check action" });
    const result = await recordBackgroundCheckIntent({
      uid: req.firebaseUid,
      payload: req.body,
      redirected: action === "redirect"
    });
    return res.json({ ok: true, ...result });
  } catch (err) {
    return next(err);
  }
});

router.put("/rate-card", async (req, res, next) => {
  try {
    const result = await updateDriverRateCard({ uid: req.firebaseUid, payload: req.body });
    return res.json({ ok: true, ...result });
  } catch (err) {
    return next(err);
  }
});

router.get("/earnings-summary", async (req, res, next) => {
  try { return res.json({ ok: true, ...(await driverEarningsSummary({ uid: req.firebaseUid })) }); }
  catch (err) { return next(err); }
});

router.post("/wait-time-events", async (req, res, next) => {
  try {
    const driverId = (req.body && req.body.driverId) || "";
    if (!assertOwnsUid(req, res, driverId)) return;

    const eventId = await driverService.recordWaitTimeEvent(req.body || {});
    return res.status(201).json({
      ok: true,
      eventId
    });
  } catch (err) {
    return next(err);
  }
});

router.post("/account-deletion-requests", async (req, res, next) => {
  try {
    const result = await createAccountDeletionRequest({
      uid: req.firebaseUid,
      reason: req.body?.reason,
      tokenEmail: req.firebaseToken?.email
    });
    return res.status(result.duplicate ? 200 : 201).json({
      ok: true,
      ...result
    });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
