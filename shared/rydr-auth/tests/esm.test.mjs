// Loads the package the way rydr-bank-service ("type": "module") will:
// through Node's ESM-to-CommonJS interop, with both import forms (ADR-005).

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import rydrAuthCore, { createAuth } from "../index.js";
import helpers from "./helpers.js";

const EXPECTED_KEYS = ["assertOwnsUid", "requireAdmin", "requireAuth", "requireDriver"];

describe("createAuth (ESM)", () => {
  it("works as a named import", () => {
    const auth = createAuth({ admin: helpers.createMockAdmin() });

    assert.deepEqual(Object.keys(auth).sort(), EXPECTED_KEYS);
  });

  it("works as a default import", () => {
    const auth = rydrAuthCore.createAuth({ admin: helpers.createMockAdmin() });

    assert.deepEqual(Object.keys(auth).sort(), EXPECTED_KEYS);
  });

  it("named and default imports are the same function", () => {
    assert.equal(createAuth, rydrAuthCore.createAuth);
  });
});
