const {test}=require('node:test');
const assert=require('node:assert/strict');
const {mondayDate}=require('../lib/triggers/weeklyDriverPayouts');
test('weekly keys follow Eastern calendar time across DST and retries',()=>{
 assert.equal(mondayDate(new Date('2026-10-19T13:00:00Z')),'2026-10-19');
 assert.equal(mondayDate(new Date('2026-11-02T14:00:00Z')),'2026-11-02');
 assert.equal(mondayDate(new Date('2026-10-19T03:59:00Z')),'2026-10-12');
 assert.equal(mondayDate(new Date('2026-10-21T16:00:00Z')),'2026-10-19');
});
