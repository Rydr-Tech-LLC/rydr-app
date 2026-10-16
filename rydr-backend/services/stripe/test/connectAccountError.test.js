const test = require('node:test'), assert = require('node:assert/strict');
const { connectAccountError } = require('../connectAccountError');
test('platform restriction is a service issue, with no driver Stripe sign-in instruction', () => {
 const result = connectAccountError({message:"We've temporarily restricted your ability to create this type of connected account due to suspicious activity. Please log in to the Stripe Dashboard."});
 assert.equal(result.status,503);assert.equal(result.body.error,'connect_account_creation_restricted');assert.match(result.body.message,/Rydr support/);assert.doesNotMatch(result.body.message,/log in|suspicious activity/);
});
test('unclassified errors do not leak personal input or Stripe internals to drivers', () => {
 const result=connectAccountError({message:'private customer input'});assert.equal(result.status,500);assert.doesNotMatch(JSON.stringify(result.body),/private customer input/);
});
