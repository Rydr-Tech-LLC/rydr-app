const test = require("node:test");
const assert = require("node:assert/strict");
const { normalizeRating, cleanCompliments, nextReputation } = require("../src/services/rideRatingService");

test("rating inputs and compliments are bounded", () => {
  assert.equal(normalizeRating(5), 5);
  assert.throws(() => normalizeRating(5.5), /integer/);
  assert.deepEqual(cleanCompliments([" Clean car ", "Clean car", "Great route"]), ["Clean car", "Great route"]);
});

test("reputation adjusts an edited rating without increasing its count", () => {
  const profile = { reputation: { ratingCount: 2, ratingSum: 8, complimentCounts: {} } };
  const result = nextReputation(profile, 3, 5, []);
  assert.equal(result.ratingCount, 2);
  assert.equal(result.ratingSum, 10);
  assert.equal(result.rating, 5);
});
