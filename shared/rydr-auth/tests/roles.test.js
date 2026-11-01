"use strict";

const { describe, it, beforeEach, afterEach } = require("node:test");
const assert = require("node:assert/strict");

const { createRoles } = require("../src/roles");
const {
  MOCK_TOKENS,
  EXPIRED_TOKEN,
  createMockAdmin,
  createMockReq,
  runMiddleware,
  captureLogs,
} = require("./helpers");

describe("requireDriver", () => {
  const { requireDriver } = createRoles({ admin: createMockAdmin() });

  it("calls next() when drivers/{uid} exists", async (t) => {
    const logs = captureLogs(t);
    const req = createMockReq({ user: { uid: "driver-456", claims: {} } });

    const { res, nextCalled } = await runMiddleware(requireDriver, req);

    assert.equal(nextCalled, true);
    assert.equal(res.statusCode, undefined);
    assert.equal(logs.entries.length, 0);
  });

  it("returns 403 and logs role_denied when drivers/{uid} is missing", async (t) => {
    const logs = captureLogs(t);
    const req = createMockReq({ user: { uid: "rider-123", claims: {} } });

    const { res, nextCalled } = await runMiddleware(requireDriver, req);

    assert.equal(nextCalled, false);
    assert.equal(res.statusCode, 403);
    assert.deepEqual(res.body, { error: "forbidden", message: "driver account required" });
    assert.equal(logs.entries.length, 1);
    assert.equal(logs.entries[0].event, "role_denied");
    assert.equal(logs.entries[0].uid, "rider-123");
  });

  it("fails closed with 403 and logs role_check_error when the Firestore lookup throws", async (t) => {
    const logs = captureLogs(t);
    const { requireDriver: failingRequireDriver } = createRoles({
      admin: createMockAdmin({ firestoreFails: true }),
    });
    const req = createMockReq({ user: { uid: "driver-456", claims: {} } });

    const { res, nextCalled } = await runMiddleware(failingRequireDriver, req);

    assert.equal(nextCalled, false);
    assert.equal(res.statusCode, 403);
    assert.equal(logs.entries.length, 1);
    assert.equal(logs.entries[0].event, "role_check_error");
    assert.equal(logs.entries[0].code, "unavailable");
  });

  it("returns 401 when requireAuth didn't run first (no req.user)", async (t) => {
    captureLogs(t);

    const { res, nextCalled } = await runMiddleware(requireDriver, createMockReq());

    assert.equal(nextCalled, false);
    assert.equal(res.statusCode, 401);
    assert.deepEqual(res.body, {
      error: "unauthorized",
      message: "Authentication required before role check",
    });
  });
});

describe("requireAdmin", () => {
  const { requireAdmin } = createRoles({ admin: createMockAdmin() });
  const SECRET = "test-internal-secret";
  let savedSecret;

  beforeEach(() => {
    savedSecret = process.env.RYDR_INTERNAL_ADMIN_SECRET;
    process.env.RYDR_INTERNAL_ADMIN_SECRET = SECRET;
  });

  afterEach(() => {
    if (savedSecret === undefined) delete process.env.RYDR_INTERNAL_ADMIN_SECRET;
    else process.env.RYDR_INTERNAL_ADMIN_SECRET = savedSecret;
  });

  describe("Firebase token path", () => {
    it("calls next() and sets req.user for a token with admin: true", async (t) => {
      const logs = captureLogs(t);
      const req = createMockReq({ headers: { authorization: "Bearer admin-token" } });

      const { nextCalled } = await runMiddleware(requireAdmin(), req);

      assert.equal(nextCalled, true);
      assert.deepEqual(req.user, { uid: "admin-789", claims: MOCK_TOKENS["admin-token"] });
      assert.equal(logs.entries.length, 0);
    });

    it("calls next() for a token with role: 'admin'", async (t) => {
      captureLogs(t);
      const req = createMockReq({ headers: { authorization: "Bearer role-admin-token" } });

      const { nextCalled } = await runMiddleware(requireAdmin(), req);

      assert.equal(nextCalled, true);
      assert.equal(req.user.uid, "admin-321");
    });

    it("returns 403 and logs role_denied for a valid token without an admin claim", async (t) => {
      const logs = captureLogs(t);
      const req = createMockReq({ headers: { authorization: "Bearer rider-token" } });

      const { res, nextCalled } = await runMiddleware(requireAdmin(), req);

      assert.equal(nextCalled, false);
      assert.equal(res.statusCode, 403);
      assert.deepEqual(res.body, { error: "forbidden", message: "admin_required" });
      assert.equal(req.user, undefined);
      assert.equal(logs.entries.length, 1);
      assert.equal(logs.entries[0].event, "role_denied");
      assert.equal(logs.entries[0].uid, "rider-123");
    });

    it("returns 401 when the Authorization header is missing or malformed", async (t) => {
      captureLogs(t);

      for (const headers of [{}, { authorization: "admin-token" }, { authorization: "Bearer" }]) {
        const { res, nextCalled } = await runMiddleware(requireAdmin(), createMockReq({ headers }));

        assert.equal(nextCalled, false);
        assert.equal(res.statusCode, 401);
        assert.deepEqual(res.body, {
          error: "unauthorized",
          message: "Authorization header is missing or malformed",
        });
      }
    });

    it("returns 401 and logs token_invalid when verification fails", async (t) => {
      const logs = captureLogs(t);
      const req = createMockReq({ headers: { authorization: `Bearer ${EXPIRED_TOKEN}` } });

      const { res, nextCalled } = await runMiddleware(requireAdmin(), req);

      assert.equal(nextCalled, false);
      assert.equal(res.statusCode, 401);
      assert.deepEqual(res.body, { error: "unauthorized", message: "Invalid Firebase ID token" });
      assert.equal(logs.entries.length, 1);
      assert.equal(logs.entries[0].event, "token_invalid");
      assert.equal(logs.entries[0].code, "auth/id-token-expired");
    });
  });

  describe("internal secret path", () => {
    it("calls next() with the x-admin-uid as req.user.uid when the secret matches", async (t) => {
      captureLogs(t);
      const req = createMockReq({
        headers: { "x-internal-admin-secret": SECRET, "x-admin-uid": "ops-user-1" },
      });

      const { nextCalled } = await runMiddleware(requireAdmin({ allowInternalSecret: true }), req);

      assert.equal(nextCalled, true);
      assert.deepEqual(req.user, {
        uid: "ops-user-1",
        claims: { admin: true, via: "internal-secret" },
      });
    });

    it("defaults req.user.uid to 'mission-control' when x-admin-uid is absent", async (t) => {
      captureLogs(t);
      const req = createMockReq({ headers: { "x-internal-admin-secret": SECRET } });

      const { nextCalled } = await runMiddleware(requireAdmin({ allowInternalSecret: true }), req);

      assert.equal(nextCalled, true);
      assert.equal(req.user.uid, "mission-control");
    });

    it("falls through to the token check when the secret is wrong", async (t) => {
      captureLogs(t);
      const middleware = requireAdmin({ allowInternalSecret: true });

      const noToken = await runMiddleware(
        middleware,
        createMockReq({ headers: { "x-internal-admin-secret": "wrong-secret" } })
      );
      assert.equal(noToken.nextCalled, false);
      assert.equal(noToken.res.statusCode, 401);

      const withAdminToken = await runMiddleware(
        middleware,
        createMockReq({
          headers: { "x-internal-admin-secret": "wrong-secret", authorization: "Bearer admin-token" },
        })
      );
      assert.equal(withAdminToken.nextCalled, true);
      assert.equal(withAdminToken.req.user.uid, "admin-789", "should be the token's uid, not the secret path");
    });

    it("never grants access through the secret when RYDR_INTERNAL_ADMIN_SECRET is unset", async (t) => {
      captureLogs(t);
      delete process.env.RYDR_INTERNAL_ADMIN_SECRET;
      const middleware = requireAdmin({ allowInternalSecret: true });

      for (const supplied of [SECRET, "", "undefined"]) {
        const req = createMockReq({ headers: { "x-internal-admin-secret": supplied } });
        const { res, nextCalled } = await runMiddleware(middleware, req);

        assert.equal(nextCalled, false, `secret "${supplied}" should not grant access`);
        assert.equal(res.statusCode, 401);
      }
    });

    it("doesn't treat a missing header and an unset secret as a match (undefined === undefined)", async (t) => {
      captureLogs(t);
      delete process.env.RYDR_INTERNAL_ADMIN_SECRET;

      const { res, nextCalled } = await runMiddleware(
        requireAdmin({ allowInternalSecret: true }),
        createMockReq()
      );

      assert.equal(nextCalled, false);
      assert.equal(res.statusCode, 401);
    });

    it("ignores the secret header when allowInternalSecret is false (the default)", async (t) => {
      captureLogs(t);
      const req = createMockReq({ headers: { "x-internal-admin-secret": SECRET } });

      const { res, nextCalled } = await runMiddleware(requireAdmin(), req);

      assert.equal(nextCalled, false);
      assert.equal(res.statusCode, 401);
    });
  });
});
