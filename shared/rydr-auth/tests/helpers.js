"use strict";

// Mock data and fakes shared by every test file. Not a test file itself
// (no `.test.js` suffix), so `node --test` doesn't run it directly.
//
// Nothing here talks to Firebase: `createMockAdmin` stands in for the
// service's firebase-admin instance, and the tokens are plain strings that
// map to the decoded claims below.

/** Decoded ID-token claims, keyed by the mock token that "verifies" to them. */
const MOCK_TOKENS = {
  "rider-token": { uid: "rider-123", email: "rider@example.com" },
  "driver-token": { uid: "driver-456", email: "driver@example.com" },
  "admin-token": { uid: "admin-789", email: "admin@example.com", admin: true },
  "role-admin-token": { uid: "admin-321", email: "ops@example.com", role: "admin" },
};

/** uids that have a `drivers/{uid}` document in the mock Firestore. */
const MOCK_DRIVER_UIDS = ["driver-456"];

/** A token string that the mock admin rejects, like an expired real one. */
const EXPIRED_TOKEN = "expired-token";

/**
 * A fake firebase-admin instance with just the two calls the package uses:
 * `auth().verifyIdToken(token)` and
 * `firestore().collection(name).doc(id).get()`.
 *
 * @param {object} [options]
 * @param {boolean} [options.firestoreFails] - Make every Firestore read reject.
 */
function createMockAdmin({ firestoreFails = false } = {}) {
  return {
    auth() {
      return {
        async verifyIdToken(token) {
          const decoded = MOCK_TOKENS[token];
          if (!decoded) {
            const code = token === EXPIRED_TOKEN ? "auth/id-token-expired" : "auth/argument-error";
            throw Object.assign(new Error("Firebase ID token rejected"), { code });
          }
          return { ...decoded };
        },
      };
    },
    firestore() {
      return {
        collection(name) {
          return {
            doc(id) {
              return {
                async get() {
                  if (firestoreFails) {
                    throw Object.assign(new Error("Firestore unavailable"), { code: "unavailable" });
                  }
                  return { exists: name === "drivers" && MOCK_DRIVER_UIDS.includes(id) };
                },
              };
            },
          };
        },
      };
    },
  };
}

/**
 * A fake Express request. Header lookup is case-insensitive, like Express.
 *
 * @param {object} [options]
 * @param {object} [options.headers]
 * @param {object} [options.user] - Pre-set `req.user`, as if requireAuth already ran.
 * @param {string} [options.url]
 */
function createMockReq({ headers = {}, user, url = "/test-route" } = {}) {
  const lower = Object.fromEntries(
    Object.entries(headers).map(([key, value]) => [key.toLowerCase(), value])
  );
  const req = {
    originalUrl: url,
    header(name) {
      return lower[name.toLowerCase()];
    },
  };
  if (user) req.user = user;
  return req;
}

/** A fake Express response that records the status and JSON body sent. */
function createMockRes() {
  return {
    statusCode: undefined,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

/**
 * Runs one middleware and waits until it either calls `next()` or sends a
 * response. Needed because `requireDriver` doesn't return its promise.
 *
 * @returns {Promise<{ req, res, nextCalled: boolean }>}
 */
function runMiddleware(middleware, req) {
  return new Promise((resolve, reject) => {
    const res = createMockRes();
    const json = res.json.bind(res);
    res.json = (body) => {
      json(body);
      resolve({ req, res, nextCalled: false });
      return res;
    };
    const next = () => resolve({ req, res, nextCalled: true });

    Promise.resolve()
      .then(() => middleware(req, res, next))
      .catch(reject);
  });
}

/**
 * Replaces console.error for the current test and returns the log entries
 * logAuthEvent writes, plus the raw text of everything logged.
 *
 * @param {import("node:test").TestContext} t
 */
function captureLogs(t) {
  const entries = [];
  const raw = [];
  t.mock.method(console, "error", (...args) => {
    raw.push(args.map((arg) => (typeof arg === "string" ? arg : JSON.stringify(arg))).join(" "));
    if (args[0] === "[rydr-auth]") entries.push(args[1]);
  });
  return { entries, raw };
}

module.exports = {
  MOCK_TOKENS,
  MOCK_DRIVER_UIDS,
  EXPIRED_TOKEN,
  createMockAdmin,
  createMockReq,
  createMockRes,
  runMiddleware,
  captureLogs,
};
