"use strict";

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");

const { unauthorized, forbidden } = require("../src/responses");
const { createMockRes } = require("./helpers");

describe("responses", () => {
  it("unauthorized() sends 401 { error: 'unauthorized', message }", () => {
    const res = createMockRes();

    const returned = unauthorized(res, "Invalid Firebase ID token");

    assert.equal(returned, res, "returns the response so callers can `return unauthorized(...)`");
    assert.equal(res.statusCode, 401);
    assert.deepEqual(res.body, { error: "unauthorized", message: "Invalid Firebase ID token" });
  });

  it("forbidden() sends 403 { error: 'forbidden', message }", () => {
    const res = createMockRes();

    const returned = forbidden(res, "admin_required");

    assert.equal(returned, res);
    assert.equal(res.statusCode, 403);
    assert.deepEqual(res.body, { error: "forbidden", message: "admin_required" });
  });
});
