const {test}=require('node:test');const assert=require('node:assert/strict');
const {newAccountConfiguration,isManagedAccount,setupConfiguration}=require('../connectConfiguration');
const {accountSessionComponents}=require('../driverWallet');
const managed={controller:{requirement_collection:'application',stripe_dashboard:{type:'none'}}};
test('new Test accounts use managed setup without switching Live accounts',()=>{
 assert.equal(newAccountConfiguration({},'test').controller.requirement_collection,'application');
 assert.deepEqual(newAccountConfiguration({},'live-beta'),{type:'express'});
 assert.deepEqual(newAccountConfiguration({STRIPE_CONNECT_MANAGED_SETUP_TEST:'false'},'test'),{type:'express'});
 assert.equal(newAccountConfiguration({STRIPE_CONNECT_MANAGED_SETUP_LIVE:'true'},'live-beta').controller.stripe_dashboard.type,'none');
});
test('only platform-managed accounts may skip Stripe user authentication',()=>{
 for(const purpose of ['onboarding','payout_methods']){
  const component=purpose==='onboarding'?'account_onboarding':'payouts';
  assert.equal(accountSessionComponents(purpose,managed)[component].features.disable_stripe_user_authentication,true);
  for(const account of [{type:'express'},{controller:{requirement_collection:'stripe',stripe_dashboard:{type:'none'}}},{controller:{requirement_collection:'application',stripe_dashboard:{type:'express'}}},undefined]){
   assert.equal(accountSessionComponents(purpose,account)[component].features.disable_stripe_user_authentication,false);
   assert.equal(isManagedAccount(account),false);
  }
 }
 assert.equal(setupConfiguration(managed).requiresMigration,false);
 assert.equal(setupConfiguration({type:'express'}).requiresMigration,true);
});
