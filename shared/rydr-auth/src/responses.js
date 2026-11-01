// Two Helper Functions that would handle the responses
// These functions would be later used in the rest of the authorization layer



/**
 * Sends a 401 Unauthorized response.
 *
 * Use when the request has no valid credentials (missing, malformed, or
 * expired token), so the caller's identity could not be established.
 *
 * @param {import("express").Response} res - The Express response object.
 * @param {string} [message] - Optional human-readable detail for the client.
 * @returns {import("express").Response} The response, after sending
 *   `{ error: "unauthorized", message }` as JSON.
 */
function unauthorized(res, message) {
    return res.status(401).json({ error: "unauthorized", message});
}

/**
 * Sends a 403 Forbidden response.
 *
 * Use when the caller is authenticated but lacks the role or permission
 * required for the requested resource or action.
 *
 * @param {import("express").Response} res - The Express response object.
 * @param {string} [message] - Optional human-readable detail for the client.
 * @returns {import("express").Response} The response, after sending
 *   `{ error: "forbidden", message }` as JSON.
 */
function forbidden(res, message) {
    return res.status(403).json({error: "forbidden", message});
}

module.exports = { unauthorized, forbidden };
