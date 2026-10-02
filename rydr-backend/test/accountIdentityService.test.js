const test = require("node:test");
const assert = require("node:assert/strict");
const { normalizePhone, linkedProviders } = require("../src/services/accountIdentityService");

test("account identity accepts only normalized verified phone numbers", () => {
  assert.equal(normalizePhone("+16783220004"), "+16783220004");
  assert.equal(normalizePhone("6783220004"), null);
});

test("account identity derives linked providers from the verified token", () => {
  assert.deepEqual(linkedProviders({ firebase: { identities: { phone: ["+1"], password: ["a@b.com"] }, sign_in_provider: "phone" } }), ["password", "phone"]);
});
