const { admin, getFirestore } = require("../config/firebase");
const {
  assertLiveBetaAccess,
} = require("../../firebase/functions/src/services/liveBetaAccessPolicy");
async function requireLiveBetaAccess(req, res, next) {
  try {
    await assertLiveBetaAccess({
      db: getFirestore(),
      uid: req.firebaseUid,
      getUser: (uid) => admin.auth().getUser(uid),
    });
    next();
  } catch (error) {
    res
      .status(error.statusCode || 503)
      .json({
        error: error.code || "live_beta_protection_unavailable",
        message:
          error.statusCode === 403
            ? "Firebase test accounts cannot participate in Live Beta rides or payments."
            : "Account access could not be verified. Please try again.",
      });
  }
}
module.exports = { requireLiveBetaAccess };
