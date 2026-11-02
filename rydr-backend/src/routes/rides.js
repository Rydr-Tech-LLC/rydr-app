const { requireLiveBetaAccess } = require("../middleware/liveBetaAccess");
const { admin, getFirestore } = require("../config/firebase");
const { authorizeRideEstimate } = require("../services/rideAuthorizationClient");
const express = require("express");
const { timingSafeEqual } = require("node:crypto");
const { requireFirebaseAuth } = require("../middleware/firebaseAuth");
const { requireFirebaseAppCheck } = require("../middleware/appCheck");
const { transitionRide } = require("../services/rideLifecycleService");
const { calculateAndStoreRideRouteEstimate } = require("../services/rideRouteService");
const { initializeRideDispatch, refreshRideDispatch } = require("../services/rideDispatchService");
const { recordRideTelemetry } = require("../services/rideTelemetryService");
const { submitRideRating } = require("../services/rideRatingService");
const { createRideRequest, dispatchAuthorizedRequest } = require("../services/rideRequestService");
const { createRideMatchSession } = require("../services/rideMatchService");
const { resolvePaymentFailure } = require("../services/adminFinancialService");

const router = express.Router();

function requireInternalService(req, res) {
  const expected = process.env.RYDR_INTERNAL_SERVICE_TOKEN;
  const supplied = req.header("x-rydr-internal-token");
  const expectedBuffer = expected ? Buffer.from(expected) : null;
  const suppliedBuffer = supplied ? Buffer.from(supplied) : null;
  const valid = expectedBuffer && suppliedBuffer && expectedBuffer.length === suppliedBuffer.length
    && timingSafeEqual(expectedBuffer, suppliedBuffer);
  if (!valid) {
    res.status(401).json({ error: "Internal service authentication is required" });
    return false;
  }
  return true;
}

router.post("/internal/maintenance", async (req, res, next) => {
  if (!requireInternalService(req, res)) return;
  try { res.json({ ok: true, ...(await require("../services/rideMaintenanceService").maintainRideRequests()) }); }
  catch (err) { next(err); }
});

router.post("/internal/:rideId/admin-cancel", async (req, res, next) => {
  if (!requireInternalService(req, res)) return;
  try {
    const result = await transitionRide({
      rideId: req.params.rideId,
      action: "admin_cancel",
      uid: String(req.body?.adminUid || "").slice(0, 128),
      actorRole: "admin",
      reason: req.body?.reason,
      requestId: req.body?.requestId
    });
    return res.json({ ok: true, ...result });
  } catch (err) { return next(err); }
});

router.post("/internal/:rideId/payment-resolution", async (req, res, next) => {
  if (!requireInternalService(req, res)) return;
  try {
    const result = await resolvePaymentFailure({
      rideId: req.params.rideId,
      action: req.body?.action,
      adminUid: String(req.body?.adminUid || "").slice(0, 128),
      reason: req.body?.reason,
      requestId: req.body?.requestId
    });
    return res.json({ ok: true, ...result });
  } catch (err) { return next(err); }
});

router.use(requireFirebaseAuth);
router.use(requireFirebaseAppCheck);
router.use(requireLiveBetaAccess);
router.post("/match-session", async (req, res, next) => {
  try {
    res.status(201).json({ ok: true, ...(await createRideMatchSession({ riderId: req.firebaseUid, payload: req.body })) });
  } catch (err) { next(err); }
});
router.post("/request", async (req, res, next) => {
  try {
    const result = await createRideRequest({
      riderId: req.firebaseUid,
      authorization: req.header("authorization"),
      payload: req.body
    });
    res.status(result.duplicate ? 200 : 201).json({ ok: true, ...result });
  } catch (err) {
    next(err);
  }
});
router.post("/:rideId/authorization/resume", async (req, res, next) => {
  try {
    const db = getFirestore();
    const ref = db.collection("rideRequests").doc(req.params.rideId);
    const snap = await ref.get();
    if (!snap.exists || snap.data().riderId !== req.firebaseUid) return res.status(404).json({ error: "Ride request not found" });
    if (!["authorizing", "authorizationFailed", "pending", "accepted"].includes(snap.data().status)) return res.status(409).json({ error: "This ride request is no longer active" });
    await dispatchAuthorizedRequest({ db, rideId: req.params.rideId, authorizationProvider: authorizeRideEstimate, now: admin.firestore.Timestamp.now() });
    res.json({ ok: true, status: (await ref.get()).data().status });
  } catch (err) { next(err); }
});
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
