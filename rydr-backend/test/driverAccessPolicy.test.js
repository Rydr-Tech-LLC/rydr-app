const test = require('node:test'), assert = require('node:assert/strict');
const { driverAccess } = require('../src/services/driverAccessPolicy');
const approved = {driverSignupCompleted:true,driverApprovalStatus:'approved',identityVerified:true};
test('completed signup permits dashboard but pending checks never grant driving',()=>{
 const pending={...approved,identityVerified:false,identityStatus:'processing',documentComplianceHold:true,backgroundCheckHold:true,safetyHold:true};
 const result=driverAccess(pending);
 assert.equal(result.allowed,false);
 assert.deepEqual(result.reasons.map(x=>x.code),['safety_review','identity','documents','background_check']);
 assert.ok(result.reasons.every(x=>x.title&&x.message));
 assert.equal(driverAccess(approved).allowed,true);
});
test('screening is only required when enabled and approved account cannot bypass identity or safety',()=>{
 assert.equal(driverAccess(approved).reasons.some(x=>x.code==='background_check'),false);
 assert.equal(driverAccess(approved,{backgroundChecksRequired:true}).reasons.some(x=>x.code==='background_check'),true);
 for(const patch of [{identityStatus:'processing',identityVerified:false},{accountStatus:'paused'},{safetyReviewStatus:'under_review'},{driverApprovalStatus:'needs_attention'},{driverSignupCompleted:false},{stripePayoutsEnabled:false}])assert.equal(driverAccess({...approved,...patch}).allowed,false);
});
