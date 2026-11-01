// Safe, fixed-field security event logging.
//
// Deliberately takes a fixed set of named fields instead of a request,
// token, or Error object, so a future caller can never accidentally log a
// bearer token, a decoded ID token (which carries email/phone), or a
// request body through this function.

const ALLOWED_FIELDS = ["event", "uid", "route", "reason", "code"];

/**
 * Logs a security-relevant auth event — a failed token verification, or a
 * role/ownership denial (403). Successful requests are never logged here;
 * that's noise, not signal.
 *
 * @param {object} fields
 * @param {string} fields.event - Short event name, e.g. "token_invalid", "role_denied", "ownership_mismatch".
 * @param {string} [fields.uid] - The authenticated uid, if one was established.
 * @param {string} [fields.route] - The route the event happened on (e.g. req.originalUrl).
 * @param {string} [fields.reason] - Human-readable reason for the denial.
 * @param {string} [fields.code] - A machine error code, e.g. a Firebase Admin error code.
 */

function logAuthEvent(fields = {}) {
    const entry = { at: new Date().toISOString() };
    for(const key of ALLOWED_FIELDS) {
        if(fields[key] !== undefined) {
            entry[key] = fields[key];
        }
    }
    console.error("[rydr-auth]", entry);
}

module.exports = { logAuthEvent };