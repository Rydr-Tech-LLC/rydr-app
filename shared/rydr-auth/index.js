"use strict";

const { createVerifyToken } = require("./src/verifyToken");
const { createRoles } = require("./src/roles");
const { assertOwnsUid } = require("./src/ownership");

/**
 * Builds the full set of auth helpers for one service, bound to that
 * service's already-initialized `admin` (firebase-admin) instance.
 *
 * Usage:
 *   const { createAuth } = require("@rydr/auth-core");
 *   const auth = createAuth({ admin });
 *
 *   router.use(auth.requireAuth);
 *   router.post("/x", auth.requireDriver, (req, res) => { ... });
 *   router.post("/admin/y", auth.requireAdmin({ allowInternalSecret: true }), (req, res) => { ... });
 *
 *   if (!auth.assertOwnsUid(req, res, req.body.uid)) return;
 *
 * @param {object} deps
 * @param {import("firebase-admin")} deps.admin - The service's own
 *   already-initialized firebase-admin instance. Never imported here --
 *   the package never touches credentials.
 */
function createAuth({ admin }) {
  const { requireAuth } = createVerifyToken({ admin });
  const { requireDriver, requireAdmin } = createRoles({ admin });

  return {
    requireAuth,
    requireDriver,
    requireAdmin,
    assertOwnsUid,
  };
}

module.exports = { createAuth };
