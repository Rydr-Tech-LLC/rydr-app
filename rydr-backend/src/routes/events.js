const express = require("express");
const ticketmasterService = require("../services/ticketmasterService");

const router = express.Router();

router.get("/", async (req, res, next) => {
  try {
    const payload = await ticketmasterService.getEvents({
      category: req.query.category,
      keyword: req.query.keyword,
      city: req.query.city,
      stateCode: req.query.stateCode,
      countryCode: req.query.countryCode,
      size: req.query.size
    });

    res.json(payload);
  } catch (err) {
    next(err);
  }
});

router.get("/:id", async (req, res, next) => {
  try {
    const event = await ticketmasterService.getEventById(req.params.id);

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
