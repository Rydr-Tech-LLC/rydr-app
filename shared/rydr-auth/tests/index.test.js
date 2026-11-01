"use strict";

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");

const { createAuth } = require("../index");
const { createMockAdmin, createMockReq, runMiddleware, captureLogs } = require("./helpers");

const EXPECTED_KEYS = ["assertOwnsUid", "requireAdmin", "requireAuth", "requireDriver"];

describe("createAuth (CommonJS)", () => {
  it("returns exactly requireAuth, requireDriver, requireAdmin and assertOwnsUid", () => {
    const auth = createAuth({ admin: createMockAdmin() });

    assert.deepEqual(Object.keys(auth).sort(), EXPECTED_KEYS);
    for (const key of EXPECTED_KEYS) {
      assert.equal(typeof auth[key], "function", `${key} should be a function`);
    }
  });

  it("is the package's only export", () => {
    assert.deepEqual(Object.keys(require("../index")), ["createAuth"]);
  });

  it("wires the pieces to the admin it was given (requireAuth then requireDriver)", async (t) => {
    captureLogs(t);
    const auth = createAuth({ admin: createMockAdmin() });
    const req = createMockReq({ headers: { authorization: "Bearer driver-token" } });

    const afterAuth = await runMiddleware(auth.requireAuth, req);
    assert.equal(afterAuth.nextCalled, true);

    const afterDriver = await runMiddleware(auth.requireDriver, req);
    assert.equal(afterDriver.nextCalled, true);
  });
});
