const { forbidden } = require("./responses");
const { logAuthEvent } = require("./logger");



/**
 * Rejects the request with 403 unless `candidateUid` matches the
 * authenticated caller's uid (`req.user.uid`, set by `requireAuth`).
 *
 * Pure uid-equality check only — no Firestore access, no knowledge of
 * rides, payments, or promo codes. Resource-specific ownership (does this
 * caller own *this ride*, is *this ride* in a state that earns a reward,
 * etc.) stays in the service that owns that data model.
 *
 * Not Express middleware — call it inline inside a route handler and
 * check the boolean it returns:
 *
 *   if (!auth.assertOwnsUid(req, res, req.body.uid)) return;
 *
 * @param {import("express").Request} req - Must already have `req.user` set (requireAuth ran first).
 * @param {import("express").Response} res
 * @param {string} candidateUid - The uid to check against the authenticated caller.
 * @returns {boolean} true if the uids match (request may proceed); false if
 *   a 403 was already sent (caller must stop handling the request).
 */
function assertOwnsUid(req, res, candidateUid) {
    const authenticatedUid = req.user && req.user.uid;

    if(!authenticatedUid || candidateUid !== authenticatedUid) {
        logAuthEvent({
            event: "ownership_mismatch",
            uid: authenticatedUid,
            route: req.originalUrl,
            reason: "Uid does not match the authenticated user",
        });

        forbidden(res, "uid does not match the authenticated user");
        return false
    }

    return true;
}

module.exports = { assertOwnsUid };