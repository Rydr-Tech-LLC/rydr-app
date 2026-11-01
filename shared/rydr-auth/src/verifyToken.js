"use strict";

const { unauthorized } = require("./responses");
const { logAuthEvent } = require("./logger");

/**
 * Builds `requireAuth` for one service's already-initialized `admin`
 * (firebase-admin) instance.
 *
 * @param {object} deps
 * @param {import("firebase-admin")} deps.admin
 */
function createVerifyToken({ admin }) {
  /**
   * 401 unless the request carries a valid Firebase ID token.
   *
   * On success, sets `req.user = { uid, claims }` -- the one spelling the
   * rest of the package (and eventually all three services) standardizes
   * on. Also sets `req.firebaseUid` / `req.uid` as aliases so existing
   * route code written against the old spellings keeps working during
   * migration (Part 3 of the proposal).
   */
  async function requireAuth(req, res, next) {
    const authorization = req.header("authorization") || "";
    const match = authorization.match(/^Bearer (.+)$/);

    if (!match) {
      logAuthEvent({
        event: "token_missing",
        route: req.originalUrl,
        reason: "Authorization header is missing or malformed",
      });
      return unauthorized(res, "Authorization header is missing or malformed");
    }

    try {
      const decoded = await admin.auth().verifyIdToken(match[1]);

      req.user = { uid: decoded.uid, claims: decoded };
      req.firebaseUid = decoded.uid; // alias -- remove once all callers use req.user.uid
      req.uid = decoded.uid; // alias -- remove once all callers use req.user.uid

      next();
    } catch (err) {
      logAuthEvent({
        event: "token_invalid",
        route: req.originalUrl,
        reason: "Firebase ID token verification failed",
        code: err.code,
      });
      unauthorized(res, "Invalid Firebase ID token");
    }
  }

  return { requireAuth };
}

module.exports = { createVerifyToken };
