const express = require("express");
const { requireFirebaseAuth } = require("../middleware/firebaseAuth");
const { requireFirebaseAppCheck } = require("../middleware/appCheck");
const {
  previewScheduledRide,
  createScheduledRide,
  respondToScheduledRide,
  selectScheduledDriver,
  checkInScheduledRide,
  cancelScheduledRide,
  sweepScheduledRides
} = require("../services/scheduledRideService");

const router = express.Router();

router.post("/internal/sweep", async (req, res, next) => {
  try {
    const expected = process.env.RYDR_INTERNAL_SERVICE_TOKEN;
    if (!expected || req.header("x-rydr-internal-token") !== expected) {
      return res.status(401).json({ error: "Internal service authentication is required" });
    }
    return res.json({ ok: true, ...(await sweepScheduledRides({})) });
  } catch (err) {
    return next(err);
  }
});

router.use(requireFirebaseAuth);
router.use(requireFirebaseAppCheck);

router.post("/preview", async (req, res, next) => {
  try {
    return res.json({ ok: true, ...(await previewScheduledRide({ riderId: req.firebaseUid, authorization: req.header("authorization"), payload: req.body })) });
  } catch (err) { return next(err); }
});

router.post("/", async (req, res, next) => {
  try {
    const result = await createScheduledRide({ riderId: req.firebaseUid, authorization: req.header("authorization"), payload: req.body });
    return res.status(result.duplicate ? 200 : 201).json({ ok: true, ...result });
  } catch (err) { return next(err); }
});

router.post("/:requestId/respond", async (req, res, next) => {
  try { return res.json({ ok: true, ...(await respondToScheduledRide({ driverId: req.firebaseUid, requestId: req.params.requestId, response: req.body?.response })) }); }
  catch (err) { return next(err); }
});

router.post("/:requestId/select", async (req, res, next) => {
  try { return res.json({ ok: true, ...(await selectScheduledDriver({ riderId: req.firebaseUid, requestId: req.params.requestId, driverId: req.body?.driverId })) }); }
  catch (err) { return next(err); }
});

router.post("/:requestId/check-in", async (req, res, next) => {
  try { return res.json({ ok: true, ...(await checkInScheduledRide({ driverId: req.firebaseUid, requestId: req.params.requestId, etaSeconds: req.body?.etaSeconds })) }); }
  catch (err) { return next(err); }
});

router.post("/:requestId/cancel", async (req, res, next) => {
  try { return res.json({ ok: true, ...(await cancelScheduledRide({ uid: req.firebaseUid, requestId: req.params.requestId, reason: req.body?.reason })) }); }
  catch (err) { return next(err); }
});

module.exports = router;
