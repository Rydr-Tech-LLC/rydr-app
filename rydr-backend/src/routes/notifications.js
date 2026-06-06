const express = require("express");
const notificationService = require("../services/notificationService");

const router = express.Router();

router.get("/", async (req, res, next) => {
  try {
    const notifications = await notificationService.getNotifications();
    res.json(notifications);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
