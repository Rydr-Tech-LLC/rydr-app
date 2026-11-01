"use strict";

const { forbidden, unauthorized } = require("./responses");
const { logAuthEvent } = require("./logger");

/**
 * Builds the role-check middlewares for one service's already-initialized
 * `admin` (firebase-admin) instance.
 *
 * @param {object} deps
 * @param {import("firebase-admin")} deps.admin
 */
function createRoles({ admin }) {
  /**
   * 403 unless `drivers/{uid}` exists in Firestore for the authenticated
   * caller. Assumes `req.user` is already set by `requireAuth`.
   */
  function requireDriver(req, res, next) {
    const uid = req.user && req.user.uid;
    if (!uid) {
      return unauthorized(res, "Authentication required before role check");
    }

    admin
      .firestore()
      .collection("drivers")
      .doc(uid)
      .get()
      .then((snap) => {
        if (!snap.exists) {
          logAuthEvent({
            event: "role_denied",
            uid,
            route: req.originalUrl,
            reason: "driver account required",
          });
          return forbidden(res, "driver account required");
        }
        next();
      })
      .catch((err) => {
        logAuthEvent({
          event: "role_check_error",
          uid,
          route: req.originalUrl,
          reason: "driver lookup failed",
          code: err.code,
        });
        forbidden(res, "driver account required");
      });
  }

  /**
   * 403 unless the caller is an admin. Two paths, mirroring
   * stripe-backend's existing requireAdminUid:
   *   1. allowInternalSecret: Mission Control's server-to-server call,
   *      which presents x-internal-admin-secret + x-admin-uid instead of
   *      a Firebase token (its own auth is a session cookie).
   *   2. A Firebase ID token whose claims carry admin === true or
   *      role === "admin".
   *
   * Verifies the token itself rather than assuming req.user is already
   * set, so this works standalone -- the way stripe-backend's admin
   * route uses it today, with no requireAuth in front of it.
   */
  function requireAdmin({ allowInternalSecret = false } = {}) {
    return async function (req, res, next) {
      if (allowInternalSecret) {
        const suppliedSecret = req.header("x-internal-admin-secret");
        const expectedSecret = process.env.RYDR_INTERNAL_ADMIN_SECRET;

        if (suppliedSecret && expectedSecret && suppliedSecret === expectedSecret) {
          const onBehalfOf = req.header("x-admin-uid") || "mission-control";
          req.user = { uid: onBehalfOf, claims: { admin: true, via: "internal-secret" } };
          return next();
        }
      }

      const authorization = req.header("authorization") || "";
      const match = authorization.match(/^Bearer (.+)$/);
      if (!match) {
        return unauthorized(res, "Authorization header is missing or malformed");
      }

      try {
        const decoded = await admin.auth().verifyIdToken(match[1]);
        const isAdminClaim = decoded.admin === true || decoded.role === "admin";
        if (!isAdminClaim) {
          logAuthEvent({
            event: "role_denied",
            uid: decoded.uid,
            route: req.originalUrl,
            reason: "admin_required",
          });
          return forbidden(res, "admin_required");
        }
        req.user = { uid: decoded.uid, claims: decoded };
        next();
      } catch (err) {
        logAuthEvent({
          event: "token_invalid",
          route: req.originalUrl,
          reason: "admin token verification failed",
          code: err.code,
        });
        unauthorized(res, "Invalid Firebase ID token");
      }
    };
  }

  return { requireDriver, requireAdmin };
}

module.exports = { createRoles };
