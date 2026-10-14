const {test}=require('node:test');
const assert=require('node:assert/strict');
const {mondayDate,modeAccountId}=require('../lib/triggers/weeklyDriverPayouts');
test('weekly payouts select only the active mode account',()=>{
 assert.equal(modeAccountId({stripeAccountId:'acct_test'},'test'),'acct_test');
 assert.equal(modeAccountId({stripeAccountId:'acct_test'},'live'),null);
 assert.equal(modeAccountId({stripeMode:'live',stripeAccountId:'acct_live'},'test'),null);
 assert.equal(modeAccountId({stripeAccountId:'acct_test',stripeProfiles:{live:{stripeAccountId:'acct_live'}}},'live'),'acct_live');
});
test('weekly keys follow Eastern calendar time across DST and retries',()=>{
 assert.equal(mondayDate(new Date('2026-10-19T13:00:00Z')),'2026-10-19');
 assert.equal(mondayDate(new Date('2026-11-02T14:00:00Z')),'2026-11-02');
 assert.equal(mondayDate(new Date('2026-10-19T03:59:00Z')),'2026-10-12');
 assert.equal(mondayDate(new Date('2026-10-21T16:00:00Z')),'2026-10-19');
});
