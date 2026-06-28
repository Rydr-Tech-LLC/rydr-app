// Shared Firebase ID token verification middleware for rydr-backend.
//
// Before this existed, individual route files (driver.js) had no auth at
// all, and moderation.js carried its own copy-pasted inline verifier. Every
// state-changing route in this service should use `requireFirebaseAuth`
// so there is exactly one place that decides what counts as an
// authenticated request, per the Part 8 backend security audit
// requirement: "Every state-changing endpoint must require Firebase
// Authentication, verify the token, and verify ownership."
//
// This middleware ONLY authenticates — it does not check ownership of any
// particular resource, because ownership rules differ per route (e.g. "the
// body's driverId must equal the caller's uid"). Routes are responsible
// for that check themselves using `req.firebaseUid`, generally via the
// `assertOwnsUid` helper below.

const { admin, initializeFirebase } = require("../config/firebase");

async function requireFirebaseAuth(req, res, next) {
  const authorization = req.header("authorization") || "";
  const match = authorization.match(/^Bearer (.+)$/);

  if (!match) {
    return res.status(401).json({ error: "Firebase ID token is required" });
  }

  try {
    initializeFirebase();
    const decoded = await admin.auth().verifyIdToken(match[1]);
    req.firebaseUid = decoded.uid;
    req.firebaseToken = decoded;
    return next();
  } catch {
    return res.status(401).json({ error: "Invalid Firebase ID token" });
  }
}

/** Rejects the request unless `candidateUid` (typically a body field the
 * client claims is "theirs") matches the authenticated caller. This is the
 * server-side ownership check that replaces ever trusting a client-supplied
 * uid on its own. */
function assertOwnsUid(req, res, candidateUid) {
  if (!candidateUid || candidateUid !== req.firebaseUid) {
    res.status(403).json({ error: "uid does not match the authenticated user" });
    return false;
  }
  return true;
}

module.exports = {
  requireFirebaseAuth,
  assertOwnsUid
};
