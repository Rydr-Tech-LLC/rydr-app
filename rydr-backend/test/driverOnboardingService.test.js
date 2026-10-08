const test = require("node:test");
const assert = require("node:assert/strict");
const { documentPath, requireStoredUploads } = require("../src/services/driverOnboardingService");

test("driver document paths must belong to the authenticated driver and expected kind", () => {
  assert.equal(
    documentPath("driver-1", "registration", "driverDocuments/driver-1/registration/single-1.jpg"),
    "driverDocuments/driver-1/registration/single-1.jpg"
  );
  assert.throws(
    () => documentPath("driver-1", "registration", "driverDocuments/driver-2/registration/single-1.jpg"),
    /owned by this driver/
  );
});

test("driver document finalization verifies that every upload exists", async () => {
  const bucket = { file: (path) => ({ exists: async () => [!path.includes("missing")] }) };
  await requireStoredUploads(["one.jpg", "two.jpg"], [bucket]);
  await assert.rejects(() => requireStoredUploads(["missing.jpg"], [bucket]), /could not be verified/);
});
