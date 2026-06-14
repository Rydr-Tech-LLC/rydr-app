const express = require("express");
const driverService = require("../services/driverService");

const router = express.Router();

router.post("/wait-time-events", async (req, res, next) => {
  try {
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
    const requestId = await driverService.createAccountDeletionRequest(req.body || {});
    return res.status(201).json({
      ok: true,
      requestId
    });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
