"use strict";

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");

const { logAuthEvent } = require("../src/logger");
const { captureLogs } = require("./helpers");

describe("logAuthEvent", () => {
  it("writes only the allowed fields and drops everything else", (t) => {
    const logs = captureLogs(t);

    logAuthEvent({
      event: "token_invalid",
      uid: "rider-123",
      route: "/rides/complete",
      reason: "Firebase ID token verification failed",
      code: "auth/id-token-expired",
      token: "secret-bearer-token",
      email: "rider@example.com",
      body: { distanceMi: 999 },
    });

    assert.equal(logs.entries.length, 1);
    const { at, ...fields } = logs.entries[0];
    assert.deepEqual(fields, {
      event: "token_invalid",
      uid: "rider-123",
      route: "/rides/complete",
      reason: "Firebase ID token verification failed",
      code: "auth/id-token-expired",
    });
    assert.ok(!logs.raw[0].includes("secret-bearer-token"));
    assert.ok(!logs.raw[0].includes("rider@example.com"));
  });

  it("leaves out fields that are undefined", (t) => {
    const logs = captureLogs(t);

    logAuthEvent({ event: "token_missing", uid: undefined, route: "/x" });

    assert.deepEqual(Object.keys(logs.entries[0]).sort(), ["at", "event", "route"]);
  });

  it("stamps every entry with an ISO 'at' timestamp", (t) => {
    const logs = captureLogs(t);

    logAuthEvent({ event: "role_denied" });

    const { at } = logs.entries[0];
    assert.equal(new Date(at).toISOString(), at);
  });

  it("writes to console.error under the [rydr-auth] prefix", (t) => {
    const logs = captureLogs(t);

    logAuthEvent({ event: "role_denied" });

    assert.equal(console.error.mock.calls.length, 1);
    assert.equal(console.error.mock.calls[0].arguments[0], "[rydr-auth]");
    assert.equal(logs.entries.length, 1);
  });
});
