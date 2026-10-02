const express = require("express");
const { requireFirebaseAuth } = require("../middleware/firebaseAuth");
const { transitionRide } = require("../services/rideLifecycleService");
const { calculateAndStoreRideRouteEstimate } = require("../services/rideRouteService");
const { initializeRideDispatch, refreshRideDispatch } = require("../services/rideDispatchService");
const { recordRideTelemetry } = require("../services/rideTelemetryService");
const { submitRideRating } = require("../services/rideRatingService");

const router = express.Router();
router.use(requireFirebaseAuth);
router.post("/:rideId/telemetry", async (req, res, next) => {
  try {
    const result = await recordRideTelemetry({
      rideId: req.params.rideId,
      driverId: req.firebaseUid,
      eventId: req.body?.eventId,
      payload: req.body
    });
    res.status(result.duplicate ? 200 : 201).json({ ok: true, ...result });
  } catch (err) {
    next(err);
  }
});
router.post("/:rideId/rating", async (req, res, next) => {
  try {
    const result = await submitRideRating({
      rideId: req.params.rideId,
      actorUid: req.firebaseUid,
      payload: req.body
    });
    res.json({ ok: true, ...result });
  } catch (err) {
    next(err);
  }
});
router.post("/:rideId/route-estimate", async (req, res, next) => {
  try {
    const result = await calculateAndStoreRideRouteEstimate({
      rideId: req.params.rideId,
      uid: req.firebaseUid,
      departureDate: req.body?.departureDate
    });
    res.json({ ok: true, ...result });
  } catch (err) {
    next(err);
  }
});
router.post("/:rideId/dispatch/initialize", async (req, res, next) => {
  try {
    const result = await initializeRideDispatch({
      rideId: req.params.rideId,
      uid: req.firebaseUid,
      candidateIds: req.body?.candidateIds,
      requestId: req.body?.requestId
    });
    res.json({ ok: true, ...result });
  } catch (err) {
    next(err);
  }
});
router.post("/:rideId/dispatch/refresh", async (req, res, next) => {
  try {
    const result = await refreshRideDispatch({
      rideId: req.params.rideId,
      uid: req.firebaseUid,
      requestId: req.body?.requestId
    });
    res.json({ ok: true, ...result });
  } catch (err) {
    next(err);
  }
});
router.post("/:rideId/transition", async (req, res, next) => {
  try {
    const result = await transitionRide({ rideId: req.params.rideId, action: req.body?.action, uid: req.firebaseUid, reason: req.body?.reason, requestId: req.body?.requestId, queued: req.body?.queued === true });
    res.json({ ok: true, ...result });
  } catch (err) { next(err); }
});
module.exports = router;
