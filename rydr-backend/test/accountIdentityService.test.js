const test = require("node:test");
const assert = require("node:assert/strict");
const { normalizePhone, linkedProviders, canonicalRiderProfile, validateDriverFinalization, driverFinalizationFields } = require("../src/services/accountIdentityService");

test("account identity accepts only normalized verified phone numbers", () => {
  assert.equal(normalizePhone("+16783220004"), "+16783220004");
  assert.equal(normalizePhone("6783220004"), null);
});

test("account identity derives linked providers from the verified token", () => {
  assert.deepEqual(linkedProviders({ firebase: { identities: { phone: ["+1"], password: ["a@b.com"] }, sign_in_provider: "phone" } }), ["password", "phone"]);
});

test("rider account finalization validates and normalizes canonical profile input", () => {
  const profile = canonicalRiderProfile({
    firstName: "  Khris ", lastName: " Nunnally ", preferredName: " Khris ", email: " KHRIS@EXAMPLE.COM ",
    address: { street: "1 Main St", city: "Atlanta", state: "GA", zip: "30303" },
    agreedToTerms: true, betaWaiverAccepted: true, verificationRequested: true
  });
  assert.equal(profile.email, "khris@example.com");
  assert.equal(profile.firstName, "Khris");
  assert.equal(profile.address.line2, "");
  assert.equal(profile.verificationRequested, true);
});

test("rider account finalization rejects missing consent", () => {
  assert.throws(() => canonicalRiderProfile({
    firstName: "Khris", lastName: "Nunnally", email: "k@example.com",
    address: { street: "1 Main St", city: "Atlanta", state: "GA", zip: "30303" },
    agreedToTerms: true, betaWaiverAccepted: false
  }), /terms and beta waiver/i);
});

test("driver account finalization requires every server-confirmed onboarding gate", () => {
  const complete = {
    firstName: "Khris",
    lastName: "Nunnally",
    email: "khris@example.com",
    license: { number: "D12345", state: "GA" },
    licenseStepCompleted: true,
    vehicle: { make: "Toyota", model: "Camry", year: 2025, plate: "SAFE1" },
    vehicleStepCompleted: true,
    betaWaiverAccepted: true,
    betaWaiverVersion: "2026-07-04",
    identityVerified: true,
    identityVerificationStepCompleted: true,
    backgroundCheckStepCompleted: true,
    stripePayoutsEnabled: true,
    payoutsStepCompleted: true
  };
  assert.doesNotThrow(() => validateDriverFinalization(complete));
  const pending = { ...complete, identityVerified: false, identityVerificationStepCompleted: false, identityStatus: "processing", stripeIdentityVerificationId: "vs_confirmed123", isApproved: true, driverApprovalStatus: "approved" };
  assert.doesNotThrow(() => validateDriverFinalization(pending));
  const patch = driverFinalizationFields(pending, "now");
  assert.equal(patch.driverSignupCompleted, true);
  assert.equal(patch.driverApprovalStatus, "pending");
  assert.equal(patch.isApproved, false);
  assert.equal(patch.canGoOnline, false);
  assert.equal(patch.isOnline, false);
  assert.equal(patch.online, false);
  assert.equal(patch.identityVerified, undefined);
  const { isApprovedDriver } = require("../src/services/driverPresenceService");
  assert.equal(isApprovedDriver({ ...pending, ...patch }), false);
  assert.equal(driverFinalizationFields({ ...pending, driverApprovalStatus: "rejected" }, "now").driverApprovalStatus, "rejected");
  assert.throws(() => validateDriverFinalization({ ...pending, stripeIdentityVerificationId: null }), /identity verification/i);
  for (const identityStatus of ["requires_input", "canceled", "not_started", "unknown"]) {
    assert.throws(() => validateDriverFinalization({ ...pending, identityStatus }), /identity verification/i);
  }
  assert.throws(() => validateDriverFinalization({ ...complete, identityVerified: false }), /identity verification/i);
  assert.throws(() => validateDriverFinalization({ ...complete, stripePayoutsEnabled: false }), /payout onboarding/i);
  assert.throws(() => validateDriverFinalization({ ...complete, betaWaiverVersion: "old" }), /beta waiver/i);
});
