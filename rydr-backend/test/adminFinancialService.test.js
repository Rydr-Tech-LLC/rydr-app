const test = require("node:test");
const assert = require("node:assert/strict");
const { ACTIONS } = require("../src/services/adminFinancialService");

test("manual payment outcomes do not masquerade as Stripe refunds", () => {
  assert.equal(ACTIONS.resolve.paymentStatus, "paid_externally");
  assert.equal(ACTIONS.write_off.paymentStatus, "written_off");
  assert.notEqual(ACTIONS.resolve.paymentStatus, "refunded");
  assert.notEqual(ACTIONS.write_off.paymentStatus, "refunded");
});
