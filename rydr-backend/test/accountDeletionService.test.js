const test = require("node:test");
const assert = require("node:assert/strict");
const {
  createAccountDeletionRequest,
  normalizeReason,
  rolesForProfiles
} = require("../src/services/accountDeletionService");

class FakeSnapshot {
  constructor(ref, value) {
    this.ref = ref;
    this.exists = value != null;
    this.value = value;
  }
  data() { return this.value; }
}

class FakeRef {
  constructor(db, path) { this.db = db; this.path = path; }
  async get() { return new FakeSnapshot(this, this.db.values.get(this.path)); }
}

class FakeCollection {
  constructor(db, path) { this.db = db; this.path = path; }
  doc(id) { return new FakeRef(this.db, `${this.path}/${id}`); }
}

class FakeDb {
  constructor(values) { this.values = new Map(Object.entries(values)); }
  collection(name) { return new FakeCollection(this, name); }
  async runTransaction(callback) {
    const tx = {
      get: (ref) => ref.get(),
      set: (ref, value, options) => {
        const existing = options?.merge ? (this.values.get(ref.path) || {}) : {};
        this.values.set(ref.path, { ...existing, ...value });
      }
    };
    return callback(tx);
  }
}

test("account roles are derived from canonical profiles", () => {
  assert.deepEqual(rolesForProfiles(true, false), ["rider"]);
  assert.deepEqual(rolesForProfiles(false, true), ["driver"]);
  assert.deepEqual(rolesForProfiles(true, true), ["rider", "driver"]);
});

test("deletion reasons are trimmed and bounded", () => {
  assert.equal(normalizeReason("  leaving  "), "leaving");
  assert.equal(normalizeReason("   "), null);
  assert.throws(() => normalizeReason("x".repeat(1001)), /1000 characters/);
});

test("deletion request is backend-authored and disables driver dispatch", async () => {
  const db = new FakeDb({
    "riders/user-1": { email: "profile@example.com", accountStatus: "active" },
    "drivers/user-1": { email: "driver@example.com", accountStatus: "active", isOnline: true },
    "driver_status/user-1": { isOnline: true, availabilityStatus: "available" },
    "publicDriverProfiles/user-1": { uid: "user-1", isOnline: true }
  });

  const result = await createAccountDeletionRequest({
    uid: "user-1",
    reason: "Done",
    tokenEmail: "verified@example.com",
    db
  });

  assert.deepEqual(result.roles, ["rider", "driver"]);
  assert.equal(result.duplicate, false);
  const request = db.values.get("accountDeletionRequests/user-1");
  assert.equal(request.email, "verified@example.com");
  assert.equal(request.role, "driver");
  assert.deepEqual(request.roles, ["rider", "driver"]);
  assert.equal(request.status, "requested");
  assert.equal(db.values.get("riders/user-1").accountStatus, "deletion_requested");
  assert.equal(db.values.get("drivers/user-1").isOnline, false);
  assert.equal(db.values.get("driver_status/user-1").availabilityStatus, "offline");
  assert.equal(db.values.get("publicDriverProfiles/user-1").isOnline, false);
});

test("an active request is idempotent", async () => {
  const db = new FakeDb({
    "riders/user-2": { email: "rider@example.com" },
    "accountDeletionRequests/user-2": { status: "requested", roles: ["rider"] }
  });
  const result = await createAccountDeletionRequest({ uid: "user-2", reason: "again", db });
  assert.equal(result.duplicate, true);
  assert.equal(result.status, "requested");
});
