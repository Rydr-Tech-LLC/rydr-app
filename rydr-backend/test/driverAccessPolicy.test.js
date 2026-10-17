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
test('checklist highlights only blockers and marks inactive screening as not required',()=>{
 const result=driverAccess({...approved,documentComplianceHold:true});
 assert.equal(result.allowed,false);
 assert.deepEqual(result.checks.filter(x=>x.blocking).map(x=>x.code),['documents']);
 assert.equal(result.checks.find(x=>x.code==='identity').status,'cleared');
 assert.equal(result.checks.find(x=>x.code==='background_check').status,'not_required');
 assert.equal(result.checks.find(x=>x.code==='safety_review').statusLabel,'No hold');
 const cleared=driverAccess(approved);
 assert.equal(cleared.allowed,true);assert.equal(cleared.checks.some(x=>x.blocking),false);assert.deepEqual(cleared.reasons,[]);
});
test('manual decline blocks even without strict OCR policy and sheet does not expose detailed decline reason',()=>{
 const d={...approved,documents:{insurance:{status:'rejected',driverFacingReason:'The photo is blurry.',reviewReason:'The photo is blurry.'}}};
 const result=driverAccess(d);assert.equal(result.allowed,false);assert.equal(result.checks.find(x=>x.code==='documents').blocking,true);assert.doesNotMatch(JSON.stringify(result),/blurry/);
 d.documents.insurance.approvedRecord={status:'approved',expirationDate:'2099-01-01'};
 assert.equal(driverAccess(d).allowed,true);
});
