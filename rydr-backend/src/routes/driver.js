const express = require("express");
const driverService = require("../services/driverService");
const { requireFirebaseAuth, assertOwnsUid } = require("../middleware/firebaseAuth");

const router = express.Router();

// Every route in this file is state-changing and driver-account-scoped, so
// every route requires a verified Firebase ID token first (Part 8 backend
// security audit). Ownership of the specific uid/driverId in the body is
// then checked per-route below — the body is never trusted on its own.
router.use(requireFirebaseAuth);

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
    const uid = (req.body && req.body.uid) || "";
    if (!assertOwnsUid(req, res, uid)) return;

    const requestId = await driverService.createAccountDeletionRequest({
      ...req.body,
      uid: req.firebaseUid
    });
    return res.status(201).json({
      ok: true,
      requestId
    });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
