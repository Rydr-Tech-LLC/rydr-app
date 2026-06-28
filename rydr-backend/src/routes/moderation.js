const express = require("express");
const moderationService = require("../services/moderationService");
const { requireFirebaseAuth } = require("../middleware/firebaseAuth");

const router = express.Router();

router.use(requireFirebaseAuth);

function storagePathBelongsToUser(storagePath, uid) {
  const safeSegment = "[A-Za-z0-9._-]+";
  const riderPattern = new RegExp(`^pendingProfilePhotos/${uid}/${safeSegment}\\.jpg$`);
  const driverPattern = new RegExp(`^driverProfilePhotos/${uid}/${safeSegment}\\.jpg$`);
  return riderPattern.test(storagePath) || driverPattern.test(storagePath);
}

router.post("/check-image", async (req, res, next) => {
  try {
    const { storagePath } = req.body || {};

    if (!storagePath || typeof storagePath !== "string") {
      return res.status(400).json({ error: "storagePath (string) is required" });
    }

    if (!storagePathBelongsToUser(storagePath, req.firebaseUid)) {
      return res.status(403).json({ error: "storagePath is not allowed for this user" });
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
