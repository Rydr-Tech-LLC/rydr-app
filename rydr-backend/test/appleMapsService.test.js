const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {
  createDeveloperToken,
  getAccessToken,
  normalizeRoute,
  resetAccessTokenCache
} = require("../src/services/appleMapsService");

test("developer token contains the Apple Maps server scope and a valid ES256 signature", () => {
  const { privateKey, publicKey } = crypto.generateKeyPairSync("ec", { namedCurve: "P-256" });
  const token = createDeveloperToken({
    config: {
      teamId: "TEAM123456",
      keyId: "KEY1234567",
      privateKey: privateKey.export({ type: "pkcs8", format: "pem" })
    },
    nowSeconds: 1_700_000_000
  });
  const [encodedHeader, encodedPayload, encodedSignature] = token.split(".");
  const header = JSON.parse(Buffer.from(encodedHeader, "base64url").toString());
  const payload = JSON.parse(Buffer.from(encodedPayload, "base64url").toString());

  assert.deepEqual(header, { alg: "ES256", kid: "KEY1234567", typ: "JWT" });
  assert.equal(payload.iss, "TEAM123456");
  assert.equal(payload.scope, "server_api");
  assert.equal(payload.exp - payload.iat, 900);
  assert.equal(crypto.verify("sha256", Buffer.from(`${encodedHeader}.${encodedPayload}`), {
    key: publicKey,
    dsaEncoding: "ieee-p1363"
  }, Buffer.from(encodedSignature, "base64url")), true);
});

test("access token is cached until its refresh window", async () => {
  resetAccessTokenCache();
  const { privateKey } = crypto.generateKeyPairSync("ec", { namedCurve: "P-256" });
  const config = {
    teamId: "TEAM123456",
    keyId: "KEY1234567",
    privateKey: privateKey.export({ type: "pkcs8", format: "pem" })
  };
  let calls = 0;
  const fetchImpl = async () => {
    calls += 1;
    return new Response(JSON.stringify({ accessToken: "maps-access-token", expiresInSeconds: 1800 }), { status: 200 });
  };

  const first = await getAccessToken({ config, fetchImpl, nowMillis: 1_700_000_000_000 });
  const second = await getAccessToken({ config, fetchImpl, nowMillis: 1_700_000_010_000 });
  assert.equal(first, "maps-access-token");
  assert.equal(second, first);
  assert.equal(calls, 1);
});

test("directions response normalization follows route step indexes", () => {
  const normalized = normalizeRoute({
    steps: [
      { instructions: "Turn left", distanceMeters: 100, durationSeconds: 20, stepPathIndex: 0 },
      { instructions: "Arrive", distanceMeters: 200, durationSeconds: 40, stepPathIndex: 1 }
    ],
    stepPaths: [
      [{ latitude: 1, longitude: 2 }, { latitude: 2, longitude: 3 }],
      [{ latitude: 2, longitude: 3 }, { latitude: 3, longitude: 4 }]
    ]
  }, {
    name: "Test Route",
    distanceMeters: 300,
    durationSeconds: 60,
    stepIndexes: [0, 1]
  });

  assert.equal(normalized.distanceMeters, 300);
  assert.equal(normalized.durationMinutes, 1);
  assert.equal(normalized.steps.length, 2);
  assert.deepEqual(normalized.polyline, [
    { latitude: 1, longitude: 2 },
    { latitude: 2, longitude: 3 },
    { latitude: 3, longitude: 4 }
  ]);
});
