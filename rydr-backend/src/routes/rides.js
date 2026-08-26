const express = require("express");
const { requireFirebaseAuth } = require("../middleware/firebaseAuth");
const { transitionRide } = require("../services/rideLifecycleService");
const { calculateAndStoreRideRouteEstimate } = require("../services/rideRouteService");

const router = express.Router();
router.use(requireFirebaseAuth);
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
router.post("/:rideId/transition", async (req, res, next) => {
  try {
    const result = await transitionRide({ rideId: req.params.rideId, action: req.body?.action, uid: req.firebaseUid, reason: req.body?.reason, requestId: req.body?.requestId, queued: req.body?.queued === true });
    res.json({ ok: true, ...result });
  } catch (err) { next(err); }
});
module.exports = router;
