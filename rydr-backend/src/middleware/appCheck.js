const { admin, initializeFirebase } = require("../config/firebase");

async function requireFirebaseAppCheck(req, res, next) {
  const enforce = process.env.REQUIRE_FIREBASE_APP_CHECK === "true"
    || (process.env.NODE_ENV === "production" && process.env.REQUIRE_FIREBASE_APP_CHECK !== "false");
  if (!enforce) return next();
  const token = req.header("x-firebase-appcheck") || "";
  if (!token) return res.status(401).json({ error: "Firebase App Check token is required" });
  try {
    initializeFirebase();
    await admin.appCheck().verifyToken(token);
    return next();
  } catch (err) {
    console.warn("Firebase App Check verification failed", { uid: req.firebaseUid, message: err?.message });
    return res.status(401).json({ error: "Invalid Firebase App Check token" });
  }
}

module.exports = { requireFirebaseAppCheck };
