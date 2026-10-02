const test = require("node:test");
const assert = require("node:assert/strict");

const {
  billingPeriod,
  billingStatus,
  reservationAmount,
  applyCashHubWithholding,
  accessWasActivatedForPeriod
} = require("../cashHubBilling");

test("Cash Hub billing periods use the New York calendar month", () => {
  assert.equal(billingPeriod(new Date("2026-10-01T03:30:00Z")), "2026-09");
  assert.equal(billingPeriod(new Date("2026-10-01T04:30:00Z")), "2026-10");
});

test("Cash Hub withholding preserves gross earnings and reduces only the transfer", () => {
  assert.deepEqual(applyCashHubWithholding({
    grossDriverPayoutCents: 720,
    chargeAmountCents: 1100,
    baseApplicationFeeCents: 380,
    reservedCents: 499
  }), {
    cashHubFeeWithheldCents: 499,
    netDriverTransferCents: 221,
    applicationFeeCents: 879
  });
});

test("Cash Hub fee collection can span multiple dispatch earnings", () => {
  assert.equal(reservationAmount({ driverPayoutCents: 200, remainingCents: 499 }), 200);
  assert.equal(reservationAmount({ driverPayoutCents: 5000, remainingCents: 299 }), 299);
  assert.equal(reservationAmount({ driverPayoutCents: 500, remainingCents: 499, reservedCents: 300 }), 199);
});

test("Cash Hub billing status distinguishes pending, partial, past due, and collected", () => {
  assert.equal(billingStatus({ collectedCents: 0, remainingCents: 499 }), "fee_pending");
  assert.equal(billingStatus({ collectedCents: 200, remainingCents: 299 }), "partially_collected");
  assert.equal(billingStatus({ collectedCents: 0, remainingCents: 499, pastDue: true }), "past_due");
  assert.equal(billingStatus({ collectedCents: 499, remainingCents: 0 }), "collected");
});

test("Cash Hub never withholds from drivers who did not activate access", () => {
  assert.equal(accessWasActivatedForPeriod({ cashHubTermsAccepted: true, cashHubOptedOut: false }), true);
  assert.equal(accessWasActivatedForPeriod({ cashHubTermsAccepted: false, cashHubOptedOut: false }), false);
  assert.equal(accessWasActivatedForPeriod({ cashHubTermsAccepted: true, cashHubOptedOut: true }), false);
});

test("an incurred monthly obligation remains payable after opt-out", () => {
  assert.equal(accessWasActivatedForPeriod({ cashHubTermsAccepted: false, cashHubOptedOut: true }), false);
  assert.equal(reservationAmount({ driverPayoutCents: 720, remainingCents: 499 }), 499);
});
