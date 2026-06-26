const express = require("express");
const { admin, initializeFirebase } = require("../config/firebase");
const moderationService = require("../services/moderationService");

const router = express.Router();

async function requireFirebaseUser(req, res) {
  const authorization = req.header("authorization") || "";
  const match = authorization.match(/^Bearer (.+)$/);

  if (!match) {
    res.status(401).json({ error: "Firebase ID token is required" });
    return null;
  }

  try {
    initializeFirebase();
    return await admin.auth().verifyIdToken(match[1]);
  } catch {
    res.status(401).json({ error: "Invalid Firebase ID token" });
    return null;
  }
}

function storagePathBelongsToUser(storagePath, uid) {
  const safeSegment = "[A-Za-z0-9._-]+";
  const riderPattern = new RegExp(`^pendingProfilePhotos/${uid}/${safeSegment}\\.jpg$`);
  const driverPattern = new RegExp(`^driverProfilePhotos/${uid}/${safeSegment}\\.jpg$`);
  return riderPattern.test(storagePath) || driverPattern.test(storagePath);
}

router.post("/check-image", async (req, res, next) => {
  try {
    const decodedToken = await requireFirebaseUser(req, res);
    if (!decodedToken) return;

    const { storagePath } = req.body || {};

    if (!storagePath || typeof storagePath !== "string") {
      return res.status(400).json({ error: "storagePath (string) is required" });
    }

    if (!storagePathBelongsToUser(storagePath, decodedToken.uid)) {
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
