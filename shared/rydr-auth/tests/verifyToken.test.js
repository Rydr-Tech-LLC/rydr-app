"use strict";

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");

const { createVerifyToken } = require("../src/verifyToken");
const {
  MOCK_TOKENS,
  EXPIRED_TOKEN,
  createMockAdmin,
  createMockReq,
  runMiddleware,
  captureLogs,
} = require("./helpers");

const { requireAuth } = createVerifyToken({ admin: createMockAdmin() });

describe("requireAuth", () => {
  it("returns 401 and logs token_missing when there is no Authorization header", async (t) => {
    const logs = captureLogs(t);

    const { res, nextCalled } = await runMiddleware(requireAuth, createMockReq());

    assert.equal(nextCalled, false);
    assert.equal(res.statusCode, 401);
    assert.deepEqual(res.body, {
      error: "unauthorized",
      message: "Authorization header is missing or malformed",
    });
    assert.equal(logs.entries.length, 1);
    assert.equal(logs.entries[0].event, "token_missing");
    assert.equal(logs.entries[0].route, "/test-route");
  });

  it("returns 401 when the header is not in the form 'Bearer <token>'", async (t) => {
    captureLogs(t);

    for (const authorization of ["rider-token", "Basic abc123", "Bearer", "bearer rider-token"]) {
      const req = createMockReq({ headers: { authorization } });
      const { res, nextCalled } = await runMiddleware(requireAuth, req);

      assert.equal(nextCalled, false, `expected rejection for "${authorization}"`);
      assert.equal(res.statusCode, 401);
    }
  });

  it("returns 401 and logs token_invalid with only the error code when verification fails", async (t) => {
    const logs = captureLogs(t);
    const req = createMockReq({ headers: { authorization: `Bearer ${EXPIRED_TOKEN}` } });

    const { res, nextCalled } = await runMiddleware(requireAuth, req);

    assert.equal(nextCalled, false);
    assert.equal(res.statusCode, 401);
    assert.deepEqual(res.body, { error: "unauthorized", message: "Invalid Firebase ID token" });
    assert.equal(logs.entries.length, 1);
    assert.equal(logs.entries[0].event, "token_invalid");
    assert.equal(logs.entries[0].code, "auth/id-token-expired");
    assert.equal(logs.entries[0].message, undefined, "the Firebase error message must not be logged");
  });

  it("never writes the raw token to the logs", async (t) => {
    const logs = captureLogs(t);
    const req = createMockReq({ headers: { authorization: `Bearer ${EXPIRED_TOKEN}` } });

    await runMiddleware(requireAuth, req);

    for (const line of logs.raw) {
      assert.ok(!line.includes(EXPIRED_TOKEN), `token leaked into log: ${line}`);
    }
  });

  it("calls next() and sets req.user plus the migration aliases for a valid token", async (t) => {
    const logs = captureLogs(t);
    const req = createMockReq({ headers: { authorization: "Bearer rider-token" } });

    const { res, nextCalled } = await runMiddleware(requireAuth, req);

    assert.equal(nextCalled, true);
    assert.equal(res.statusCode, undefined, "no response should be sent on success");
    assert.deepEqual(req.user, { uid: "rider-123", claims: MOCK_TOKENS["rider-token"] });
    assert.equal(req.firebaseUid, "rider-123");
    assert.equal(req.uid, "rider-123");
    assert.equal(logs.entries.length, 0, "successful requests are not logged");
  });
});
