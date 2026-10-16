const {test}=require('node:test');const assert=require('node:assert/strict');
const {phoneHash,assertLiveBetaAccess,filterLiveBetaCandidates}=require('../firebase/functions/src/services/liveBetaAccessPolicy');
const policy={version:1,configured:true,blockedAuthUids:['test-uid'],blockedPhoneHashes:[phoneHash('+15555550101')]};
const db=(mode='live',protection=policy)=>({collection:()=>({doc:id=>({get:async()=>({data:()=>id==='stripeRuntime'?{mode,status:'ready'}:protection})})})});
test('test mode keeps simulated account operations working without an Auth lookup',async()=>{await assertLiveBetaAccess({db:db(),uid:'test-uid',mode:'test',getUser:()=>{throw Error('must not call')}})});
test('preserved test UID cannot initiate live operations even after phone changes',async()=>{await assert.rejects(assertLiveBetaAccess({db:db(),uid:'test-uid',mode:'live',phone:'+15555550999'}),e=>e.code==='firebase_test_account_live_access_blocked')});
test('a new UID using a configured Firebase test number is denied using Auth identity',async()=>{await assert.rejects(assertLiveBetaAccess({db:db(),uid:'new-uid',getUser:async()=>({phoneNumber:'+15555550101'})}),e=>e.statusCode===403)});
test('live operations fail closed when protection configuration or identity lookup is unavailable',async()=>{await assert.rejects(assertLiveBetaAccess({db:db('live',null),uid:'real',mode:'live'}),e=>e.statusCode===503);await assert.rejects(assertLiveBetaAccess({db:db(),uid:'real',getUser:async()=>{throw Error('offline')}}),e=>e.statusCode===503)});
test('real accounts are allowed and disabled Auth accounts are rejected',async()=>{await assertLiveBetaAccess({db:db(),uid:'real',getUser:async()=>({phoneNumber:'+15555550999'})});await assert.rejects(assertLiveBetaAccess({db:db(),uid:'real',getUser:async()=>({disabled:true})}),e=>e.statusCode===403)});
test('live matching excludes test UIDs and test-number profiles, test mode preserves them',async()=>{const candidates=[{id:'test-uid',profile:{}},{id:'recreated',profile:{phoneNumber:'+15555550101'}},{id:'real',profile:{}}];assert.deepEqual((await filterLiveBetaCandidates(db(),candidates)).map(c=>c.id),['real']);assert.equal((await filterLiveBetaCandidates(db('test'),candidates)).length,3)});
test('unknown runtime mode never silently enables live access',async()=>{await assert.rejects(assertLiveBetaAccess({db:db('unknown'),uid:'real'}),e=>e.statusCode===503)});

test('named Live Beta financial operations require an enabled workspace and reject Test mode',async()=>{
 const named=state=>({databaseId:'live-beta',collection:()=>({doc:id=>({get:async()=>({data:()=>id==='workspace'?state:id==='stripeRuntime'?{mode:'live',status:'ready'}:policy})})})});
 for(const state of [null,{enabled:true,livePaymentsEnabled:false}])await assert.rejects(assertLiveBetaAccess({db:named(state),uid:'real',mode:'live',phone:'+15555550999'}),e=>e.code==='live_beta_not_enabled');
 const ready=named({enabled:true,livePaymentsEnabled:true});await assertLiveBetaAccess({db:ready,uid:'real',mode:'live',phone:'+15555550999'});await assert.rejects(assertLiveBetaAccess({db:ready,uid:'real',mode:'test'}),e=>e.code==='workspace_stripe_mode_mismatch');
});
