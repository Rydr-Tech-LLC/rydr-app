"use strict";

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");

const { assertOwnsUid } = require("../src/ownership");
const { createMockReq, createMockRes, captureLogs } = require("./helpers");

describe("assertOwnsUid", () => {
  it("returns true and sends nothing when the uid matches", (t) => {
    const logs = captureLogs(t);
    const req = createMockReq({ user: { uid: "rider-123", claims: {} } });
    const res = createMockRes();

    assert.equal(assertOwnsUid(req, res, "rider-123"), true);
    assert.equal(res.statusCode, undefined);
    assert.equal(logs.entries.length, 0);
  });

  it("returns false, sends 403 and logs ownership_mismatch when the uid differs", (t) => {
    const logs = captureLogs(t);
    const req = createMockReq({ user: { uid: "rider-123", claims: {} } });
    const res = createMockRes();

    assert.equal(assertOwnsUid(req, res, "someone-else"), false);
    assert.equal(res.statusCode, 403);
    assert.deepEqual(res.body, {
      error: "forbidden",
      message: "uid does not match the authenticated user",
    });
    assert.equal(logs.entries.length, 1);
    assert.equal(logs.entries[0].event, "ownership_mismatch");
    assert.equal(logs.entries[0].uid, "rider-123");
  });

  it("returns false and sends 403 when there is no req.user", (t) => {
    captureLogs(t);
    const res = createMockRes();

    assert.equal(assertOwnsUid(createMockReq(), res, "rider-123"), false);
    assert.equal(res.statusCode, 403);
  });

  it("returns false when both uids are missing (undefined must not match undefined)", (t) => {
    captureLogs(t);
    const res = createMockRes();

    assert.equal(assertOwnsUid(createMockReq(), res, undefined), false);
    assert.equal(res.statusCode, 403);
  });

  it("includes the route in the log entry", (t) => {
    const logs = captureLogs(t);
    const req = createMockReq({ user: { uid: "rider-123", claims: {} }, url: "/driver/profile" });

    assertOwnsUid(req, createMockRes(), "someone-else");

    assert.equal(logs.entries[0].route, "/driver/profile");
  });
});
