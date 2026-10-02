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
  isCashHubConnectedStatus,
  cashHubRemovalUpdate,
  cashHubReleaseVisibilityUpdate,
  cashHubRiderCancellationUpdate,
  cashHubActionRequiresActiveAccess,
  normalizeCashHubOffer,
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

test("connected lifecycle accepts current and legacy accepted status values", () => {
  assert.equal(isCashHubConnectedStatus("connected"), true);
  assert.equal(isCashHubConnectedStatus("accepted"), true);
  assert.equal(isCashHubConnectedStatus("open"), false);
});

test("removing an open Cash Hub post cancels and hides it", () => {
  const now = { marker: "now" };
  assert.deepEqual(cashHubRemovalUpdate({ status: "open" }, now), {
    riderHiddenFromMyPosts: true,
    riderRemovedAt: now,
    status: "removed",
    removedAt: now
  });
});

test("removing an accepted or completed Cash Hub post preserves its lifecycle", () => {
  const now = { marker: "now" };
  assert.deepEqual(cashHubRemovalUpdate({ status: "connected", connectedDriverUid: "driver-1" }, now), {
    riderHiddenFromMyPosts: true,
    riderRemovedAt: now
  });
  assert.deepEqual(cashHubRemovalUpdate({ status: "completed", agreedPrice: 25 }, now), {
    riderHiddenFromMyPosts: true,
    riderRemovedAt: now
  });
});

test("a driver release restores a hidden post when the listing can reopen", () => {
  const now = { marker: "now" };
  assert.deepEqual(cashHubReleaseVisibilityUpdate(true, now), {
    riderHiddenFromMyPosts: false,
    riderRestoredToMyPostsAt: now
  });
  assert.deepEqual(cashHubReleaseVisibilityUpdate(false, now), {});
});

test("release is never blocked by a later Cash Hub access-state change", () => {
  assert.equal(cashHubActionRequiresActiveAccess("driver_connect"), true);
  assert.equal(cashHubActionRequiresActiveAccess("release"), false);
  assert.equal(cashHubActionRequiresActiveAccess("driver_status"), false);
});

test("a rider can cancel an active listing without deleting its card", () => {
  const now = { marker: "now" };
  const update = cashHubRiderCancellationUpdate({ status: "connected" }, now);
  assert.equal(update.status, "cancelled");
  assert.equal(update.riderCancelledAt, now);
  assert.equal(update.riderHiddenFromMyPosts, false);
  assert.throws(() => cashHubRiderCancellationUpdate({ status: "completed" }, now), /active Cash Hub listing/);
});

test("Cash Hub offers negotiate price without client-entered vehicle or availability", () => {
  assert.deepEqual(normalizeCashHubOffer({ offerAmount: "24.50", message: "Would this work?" }), {
    offerAmount: 24.5,
    message: "Would this work?"
  });
  assert.deepEqual(normalizeCashHubOffer({ offerAmount: 25 }), {
    offerAmount: 25,
    message: ""
  });
  assert.throws(() => normalizeCashHubOffer({ availability: "Any time", vehicleInfo: "Blue car" }), /valid offer amount/);
});

test("Cash Hub driver access rejects opt-outs, billing suspension, and safety holds", () => {
  assert.equal(cashHubAccessAllowed(approvedDriver, enabledConfig, "driver"), true);
  assert.equal(cashHubAccessAllowed({ ...approvedDriver, cashHubOptedOut: true }, enabledConfig, "driver"), false);
  assert.equal(cashHubAccessAllowed({ ...approvedDriver, cashHubAccessStatus: "past_due" }, enabledConfig, "driver"), false);
  assert.equal(cashHubAccessAllowed({ ...approvedDriver, safetyHold: true }, enabledConfig, "driver"), false);
});
