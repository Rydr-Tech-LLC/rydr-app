const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const ts = require("typescript");
function fixture() {
  const docs = new Map();
  let session = { uid: "staff" };
  let seq = 0;
  const db = {
    collection: (name) => ({
      doc: (id) => ({ path: `${name}/${id ?? ++seq}` }),
    }),
    runTransaction: async (fn) => {
      const writes = [];
      let written = false;
      const result = await fn({
        get: async (r) => {
          assert.equal(written, false);
          return { data: () => docs.get(r.path) };
        },
        set: (r, d, o) => {
          written = true;
          writes.push(() =>
            docs.set(r.path, o?.merge ? { ...docs.get(r.path), ...d } : d),
          );
        },
        create: (r, d) => {
          written = true;
          writes.push(() => docs.set(r.path, d));
        },
        update: (r, d) => {
          written = true;
          writes.push(() => docs.set(r.path, { ...docs.get(r.path), ...d }));
        },
      });
      writes.forEach((f) => f());
      return result;
    },
  };
  const filename = path.join(
    __dirname,
    "../app/api/promotions/safety/route.ts",
  );
  const mod = { exports: {} };
  const req = (id) => {
    if (id === "next/server")
      return {
        NextResponse: {
          json: (body, opts) => ({ body, status: opts?.status ?? 200 }),
        },
      };
    if (id === "@/lib/session") return { getAdminSession: async () => session };
    if (id === "@/lib/firebaseAdmin") return { getWorkspaceDb: async () => db };
    if (id === "firebase-admin/firestore")
      return { FieldValue: { serverTimestamp: () => new Date() } };
    return require(id);
  };
  vm.runInNewContext(
    ts.transpileModule(fs.readFileSync(filename, "utf8"), {
      compilerOptions: {
        module: ts.ModuleKind.CommonJS,
        target: ts.ScriptTarget.ES2020,
      },
    }).outputText,
    { module: mod, exports: mod.exports, require: req },
  );
  return {
    docs,
    setSession: (s) => (session = s),
    post: (body) => mod.exports.POST({ json: async () => body }),
  };
}
test("promotion safety actions require an authenticated admin session", async () => {
  const f = fixture();
  f.setSession(null);
  assert.equal(
    (
      await f.post({
        userId: "rider",
        action: "hold",
        reason: "review account",
      })
    ).status,
    401,
  );
  assert.equal(f.docs.size, 0);
});
test("hold and release are audited atomically and require a valid reason", async () => {
  const f = fixture();
  assert.equal(
    (await f.post({ userId: "rider", action: "hold", reason: "" })).status,
    400,
  );
  assert.equal(f.docs.size, 0);
  assert.equal(
    (await f.post({ userId: "rider", action: "hold", reason: "manual review" }))
      .status,
    200,
  );
  assert.equal(f.docs.get("promotionAccountControls/rider").blocked, true);
  await f.post({
    userId: "rider",
    action: "release",
    reason: "review complete",
  });
  assert.equal(f.docs.get("promotionAccountControls/rider").blocked, false);
  assert.equal(
    [...f.docs.keys()].filter((k) => k.startsWith("audits/")).length,
    2,
  );
});
test("review exception cannot be granted for another account or a missing signal", async () => {
  const f = fixture();
  const id = "a".repeat(64);
  f.docs.set(`promotionAbuseSignals/${id}`, {
    userId: "other",
    promotionId: "promo",
  });
  assert.equal(
    (
      await f.post({
        userId: "rider",
        action: "allow_shared_identity",
        reason: "verified family",
        signalId: id,
      })
    ).status,
    400,
  );
  assert.equal(
    [...f.docs.keys()].some((k) => k.startsWith("promotionIdentityOverrides/")),
    false,
  );
  assert.equal(
    (
      await f.post({
        userId: "other",
        action: "allow_shared_identity",
        reason: "verified family",
        signalId: id,
      })
    ).status,
    200,
  );
  const override = [...f.docs.entries()].find(([k]) =>
    k.startsWith("promotionIdentityOverrides/"),
  )[1];
  assert.equal(override.promotionId, "promo");
  assert.equal(override.userId, "other");
  assert.equal(f.docs.get(`promotionAbuseSignals/${id}`).status, "allowed");
});
