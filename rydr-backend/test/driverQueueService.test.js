const test = require("node:test");
const assert = require("node:assert/strict");
const { queuedCandidates } = require("../src/services/driverQueueService");

function doc(id, data) { return { id, data: () => data }; }

test("queue promotion selects the oldest accepted queued ride", () => {
  const result = queuedCandidates([
    doc("later", { status: "accepted", driverQueueStatus: "queued", queuedAt: { toMillis: () => 200 } }),
    doc("active", { status: "inProgress", driverQueueStatus: "active" }),
    doc("first", { status: "accepted", driverQueueStatus: "queued", queuedAt: { toMillis: () => 100 } })
  ]);
  assert.deepEqual(result.map((item) => item.id), ["first", "later"]);
});
