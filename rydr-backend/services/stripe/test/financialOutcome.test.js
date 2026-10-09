const test = require("node:test");
const assert = require("node:assert/strict");
const { normalizeFinancialOutcome, rideWithFinancialOutcome } = require("../financialOutcome");

test("maps finalized backend cents without changing the charge or payout", () => {
  const result = rideWithFinancialOutcome(
    { status: "completed", pickupPaidWaitStartedAt: { seconds: 1 } },
    {
      status: "finalized",
      outcomeType: "completed",
      currency: "usd",
      finalRiderChargeCents: 1425,
      driverPayoutCents: 875,
      platformShareCents: 550,
      waitChargeCents: 125,
    }
  );

  assert.equal(result.ok, true);
  assert.equal(result.value.finalRiderChargeCents, 1425);
  assert.equal(result.value.estimatedDriverPayoutCents, 875);
  assert.equal(result.value.estimatedPlatformShareCents, 550);
  assert.equal(result.value.backendWaitChargeCents, 125);
  assert.equal(result.value.backendFinancialOutcome, true);
});

test("rejects an outcome whose charge does not balance", () => {
  const result = normalizeFinancialOutcome({
    status: "finalized",
    currency: "usd",
    finalRiderChargeCents: 1000,
    driverPayoutCents: 700,
    platformShareCents: 250,
  });
  assert.deepEqual(result, { ok: false, error: "financial_outcome_unbalanced" });
});

test("rejects fractional and negative authoritative cents", () => {
  const result = normalizeFinancialOutcome({
    status: "finalized",
    finalRiderChargeCents: 999.5,
    driverPayoutCents: -1,
    platformShareCents: 1000,
  });
  assert.deepEqual(result, { ok: false, error: "financial_outcome_invalid_amounts" });
});

test("rejects a non-USD outcome", () => {
  const result = normalizeFinancialOutcome({
    status: "finalized",
    currency: "eur",
    finalRiderChargeCents: 1000,
    driverPayoutCents: 700,
    platformShareCents: 300,
  });
  assert.deepEqual(result, { ok: false, error: "financial_outcome_currency_unsupported" });
});

test("accepts a fully subsidized backend outcome while preserving driver economics", () => {
  const result = normalizeFinancialOutcome({
    status: "finalized",
    currency: "usd",
    grossChargeCents: 1000,
    promotionDiscountCents: 1000,
    finalRiderChargeCents: 0,
    driverPayoutCents: 700,
    platformShareCents: 300,
  });
  assert.equal(result.ok, true);
  assert.equal(result.value.finalRiderChargeCents, 0);
  assert.equal(result.value.driverPayoutCents, 700);
});
