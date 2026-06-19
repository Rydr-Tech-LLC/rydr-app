const express = require("express");
const moderationService = require("../services/moderationService");

const router = express.Router();

router.post("/check-image", async (req, res, next) => {
  try {
    const { storagePath } = req.body || {};

    if (!storagePath || typeof storagePath !== "string") {
      return res.status(400).json({ error: "storagePath (string) is required" });
    }

    const result = await moderationService.checkImage(storagePath);

    return res.status(200).json({
      ok: true,
      verdict: result.verdict,
      flagged: result.flagged
    });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
