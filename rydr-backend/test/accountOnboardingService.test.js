const test=require('node:test'),assert=require('node:assert/strict');
const {onboardingState,resumeProfile,recordOnboardingCheckpoint}=require('../src/services/accountOnboardingService');
const token={phone_number:'+16783220004',email:'test@example.com'};
const basic={betaWaiverAccepted:true,betaWaiverVersion:'2026-07-04',firstName:'Test',lastName:'Driver',dob:'1990-01-01',address:{street:'1 Main',city:'Atlanta',state:'GA',zip:'30303'}};
test('server completion gates both dashboards, regardless of cached approvals or viewed steps',()=>{
 for(const role of ['driver','rider']) {
  assert.equal(onboardingState(role,{driverApprovalStatus:'approved',hasRydrRiderAccess:true,driverOnboardingCurrentStep:'complete'},token).completed,false);
  assert.equal(onboardingState(role,{[role==='driver'?'driverSignupCompleted':'riderSignupCompleted']:true},token).completed,true);
 }
});
test('driver resumes earliest incomplete verified checkpoint and permits pending identity without completing signup',()=>{
 assert.equal(onboardingState('driver',{},token).nextStep,'betaWaiver');
 assert.equal(onboardingState('driver',basic,token).nextStep,'license');
 const vehicle={...basic,licenseStepCompleted:true,vehicleStepCompleted:true};
 assert.equal(onboardingState('driver',vehicle,token).nextStep,'identity');
 const pending={...vehicle,identityStatus:'processing',stripeIdentityVerificationId:'vs_test123'};
 assert.equal(onboardingState('driver',pending,token).nextStep,'backgroundCheck');
 assert.equal(onboardingState('driver',{...pending,backgroundCheckStepCompleted:true},token).nextStep,'payouts');
 assert.equal(onboardingState('driver',{...pending,identityStatus:'requires_input'},token).nextStep,'identity');
 assert.equal(onboardingState('driver',{...pending,stripeIdentityVerificationId:null},token).nextStep,'identity');
});
test('rider payment skip is a checkpoint; final terms remain required',()=>{
 assert.equal(onboardingState('rider',basic,token).nextStep,'paymentMethod');
 assert.equal(onboardingState('rider',{...basic,riderPaymentStepCompleted:true},token).nextStep,'termsAndVerification');
 assert.equal(onboardingState('rider',{...basic,riderPaymentStepCompleted:true,address:{}},token).nextStep,'addressEntry');
 assert.equal(onboardingState('rider',{...basic,betaWaiverAccepted:false},token).nextStep,'betaWaiver');
});
test('explicit Cash Hub accounts retain access until they start a rider upgrade',()=>{
 const cash={...basic,cashHubRole:'rider',hasRydrRiderAccess:false};
 assert.equal(onboardingState('rider',cash,token).cashHubOnly,true);
 assert.equal(onboardingState('rider',{...cash,riderOnboardingStarted:true},token).completed,false);
});
test('resume payload contains no Stripe secrets or document image paths',()=>{
 const p=resumeProfile({...basic,stripeCustomerId:'private',documents:{driverLicense:{storagePath:'private'}},vehicle:{year:2024}},token);
 assert.equal(p.vehicle.year,'2024');assert.equal(p.phoneNumber,token.phone_number);assert.doesNotMatch(JSON.stringify(p),/private/);
});
test('checkpoint cannot set completion, approval, identity or another role',async()=>{
 await assert.rejects(recordOnboardingCheckpoint({uid:'test',role:'driver',step:'done',db:{}}),/Unsupported/);
 await assert.rejects(recordOnboardingCheckpoint({uid:'test',role:'rider',step:'done',db:{}}),/Unsupported/);
});

test('onboarding restores only explicit driver sex disclosures',()=>{
 assert.equal(resumeProfile({...basic,driverSex:'female'},token).driverSex,'female');
 assert.equal(resumeProfile({...basic,driverSex:'male'},token).driverSex,'male');
 assert.equal(resumeProfile({...basic,gender:'Female'},token).driverSex,'undisclosed');
 assert.equal(resumeProfile({...basic,driverSex:'invalid'},token).driverSex,'undisclosed');
});
