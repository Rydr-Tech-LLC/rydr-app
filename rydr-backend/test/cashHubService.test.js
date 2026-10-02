const test = require("node:test");
const assert = require("node:assert/strict");

const {
  normalizeVisibility,
  normalizeTripFormat,
  driverCanAccessRequest,
  driverVehicleSummary,
  validateScheduledTime,
  hasCurrentTerms,
  canTransitionDriverQueue,
  cashHubAccessAllowed,
  PUBLIC_VISIBILITY,
  FAVORITES_VISIBILITY
} = require("../src/services/cashHubService");

const enabledConfig = { termsAcceptanceEnabled: true, cashHubTermsVersion: "2026-09" };
const approvedDriver = {
  cashHubTermsAccepted: true,
  cashHubTermsVersion: "2026-09",
  cashHubAccessStatus: "active",
  driverApprovalStatus: "approved"
};

test("Cash Hub accepts only supported visibility values", () => {
  assert.equal(normalizeVisibility(PUBLIC_VISIBILITY), PUBLIC_VISIBILITY);
  assert.equal(normalizeVisibility(FAVORITES_VISIBILITY), FAVORITES_VISIBILITY);
  assert.throws(() => normalizeVisibility("Everyone on the internet"), /Invalid Cash Rydr Hub visibility/);
});

test("Cash Hub uses arrangement formats rather than Rydr Dispatch tiers", () => {
  for (const value of ["One-way", "Round trip", "Scheduled", "Flexible"]) {
    assert.equal(normalizeTripFormat(value), value);
  }
  assert.throws(() => normalizeTripFormat("Rydr Go"), /trip format/);
});

test("favorite-only Cash Hub requests reject drivers outside the backend-owned audience", () => {
  assert.equal(driverCanAccessRequest({ status: "open", visibility: PUBLIC_VISIBILITY }, "driver-a"), true);
  assert.equal(driverCanAccessRequest({ status: "open", visibility: FAVORITES_VISIBILITY, allowedDriverUids: ["driver-a"] }, "driver-a"), true);
  assert.equal(driverCanAccessRequest({ status: "open", visibility: FAVORITES_VISIBILITY, allowedDriverUids: ["driver-a"] }, "driver-b"), false);
  assert.equal(driverCanAccessRequest({ status: "connected", visibility: PUBLIC_VISIBILITY }, "driver-a"), false);
});

test("Cash Hub derives the offered car from the driver's canonical vehicle", () => {
  assert.equal(driverVehicleSummary({ vehicle: { color: "Black", year: 2024, make: "Tesla", model: "Model Y" } }), "Black 2024 Tesla Model Y");
  assert.equal(driverVehicleSummary({ vehicle: {} }), "");
});

test("Cash Hub requests require two hours of lead time", () => {
  const now = Date.parse("2026-09-29T12:00:00Z");
  assert.throws(() => validateScheduledTime("2026-09-29T13:59:59Z", now), /at least 2 hours ahead/);
  assert.equal(validateScheduledTime("2026-09-29T14:00:00Z", now).toMillis(), now + 2 * 60 * 60 * 1000);
});

test("Cash Hub requires the enabled current terms version", () => {
  assert.equal(hasCurrentTerms(approvedDriver, enabledConfig), true);
  assert.equal(hasCurrentTerms({ ...approvedDriver, cashHubTermsVersion: "old" }, enabledConfig), false);
  assert.equal(hasCurrentTerms(approvedDriver, { ...enabledConfig, termsAcceptanceEnabled: false }), false);
});

test("Cash Hub driver lifecycle cannot skip forward or regress", () => {
  assert.equal(canTransitionDriverQueue("scheduled", "arrived"), true);
  assert.equal(canTransitionDriverQueue("arrived", "started"), true);
  assert.equal(canTransitionDriverQueue("started", "completed"), true);
  assert.equal(canTransitionDriverQueue("scheduled", "completed"), false);
  assert.equal(canTransitionDriverQueue("started", "arrived"), false);
});

test("Cash Hub driver access rejects opt-outs, billing suspension, and safety holds", () => {
  assert.equal(cashHubAccessAllowed(approvedDriver, enabledConfig, "driver"), true);
  assert.equal(cashHubAccessAllowed({ ...approvedDriver, cashHubOptedOut: true }, enabledConfig, "driver"), false);
  assert.equal(cashHubAccessAllowed({ ...approvedDriver, cashHubAccessStatus: "past_due" }, enabledConfig, "driver"), false);
  assert.equal(cashHubAccessAllowed({ ...approvedDriver, safetyHold: true }, enabledConfig, "driver"), false);
});
