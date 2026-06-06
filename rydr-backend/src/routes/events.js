const express = require("express");
const eventbriteService = require("../services/eventbriteService");

const router = express.Router();

router.get("/", async (req, res, next) => {
  try {
    const events = await eventbriteService.getEvents();
    res.json(events);
  } catch (err) {
    next(err);
  }
});

router.get("/:id", async (req, res, next) => {
  try {
    const event = await eventbriteService.getEventById(req.params.id);

    if (!event) {
      return res.status(404).json({
        error: "Event Not Found"
      });
    }

    return res.json(event);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
