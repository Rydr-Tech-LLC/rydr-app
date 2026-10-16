const {test}=require('node:test');const assert=require('node:assert/strict');const express=require('express');const Stripe=require('stripe');const {createHash}=require('node:crypto');
const {createWorkspaceServer,environmentFor,createStripeApp}=require('../index');
const {phoneHash}=require('../../../firebase/functions/src/services/liveBetaAccessPolicy');
const keys={STRIPE_SECRET_KEY:'sk_test_sample',STRIPE_PUBLISHABLE_KEY:'pk_test_sample',STRIPE_SECRET_KEY_LIVE:'sk_live_sample',STRIPE_PUBLISHABLE_KEY_LIVE:'pk_live_sample',STRIPE_WEBHOOK_SECRET_TEST:'whsec_test',STRIPE_CONNECT_WEBHOOK_SECRET_TEST:'whsec_connect_test',STRIPE_WEBHOOK_SECRET_LIVE:'whsec_live',STRIPE_CONNECT_WEBHOOK_SECRET_LIVE:'whsec_connect_live',STRIPE_DRIVER_VERIFICATION_FLOW_ID_LIVE:'vf_driver_live',STRIPE_RIDER_VERIFICATION_FLOW_ID_LIVE:'vf_rider_live'};
const policy={configured:true,blockedAuthUids:['test-uid'],blockedPhoneHashes:[phoneHash('+15555550101')]};
async function fixture(env={},overrides={}){
 const app=createWorkspaceServer({...keys,...env},{createApp:(config,workspace)=>{const child=express();child.use((req,res)=>res.json({workspace,key:config.STRIPE_PUBLISHABLE_KEY}));return child},control:()=>({getWorkspaceState:async()=>Object.hasOwn(overrides,'workspaceState')?overrides.workspaceState:{enabled:true,livePaymentsEnabled:true},auth:{verifyIdToken:async(token,revoked)=>{assert.equal(revoked,true);return {uid:token,...(overrides.audience?{aud:overrides.audience}:{})}},getUser:async uid=>({uid,phoneNumber:uid==='recreated'?'+15555550101':'+15555550999',...overrides.user})},db:{collection:()=>({doc:()=>({get:async()=>({data:()=>overrides.policy===null?null:(overrides.policy||policy)})})})}})});
 const server=app.listen(0,'127.0.0.1');await new Promise(resolve=>server.once('listening',resolve));return {url:`http://127.0.0.1:${server.address().port}`,close:()=>new Promise(resolve=>server.close(resolve))};
}
test('test key selection survives global live key changes and mismatches fail closed',()=>{
 assert.equal(environmentFor('test',{...keys,STRIPE_SECRET_KEY:'sk_live_other',STRIPE_PUBLISHABLE_KEY:'pk_live_other',STRIPE_SECRET_KEY_TEST:'sk_test_explicit',STRIPE_PUBLISHABLE_KEY_TEST:'pk_test_explicit'}).STRIPE_SECRET_KEY,'sk_test_explicit');
 assert.equal(environmentFor('test',{STRIPE_SECRET_KEY:'sk_live_other'}).STRIPE_SECRET_KEY,'');
 assert.throws(()=>createStripeApp({...keys,STRIPE_SECRET_KEY:'sk_live_bad'},'test'),/mismatch/);
});
test('account configuration is identity-derived; test-number recreation cannot opt into live',async()=>{
 const f=await fixture({LIVE_BETA_ENABLED:'true'});try{for(const uid of ['test-uid','recreated','real']){
 const r=await fetch(f.url+'/account-config',{headers:{authorization:'Bearer '+uid,'x-rydr-workspace':'live-beta'}});assert.equal(r.status,200);const b=await r.json();assert.equal(b.workspace,uid==='real'?'live-beta':'test');assert.equal(b.publishableKey,uid==='real'?'pk_live_sample':'pk_test_sample');
 }assert.equal((await fetch(f.url+'/account-config')).status,401)}finally{await f.close()}
});
test('disabled Live Beta never returns a live public key; Test remains available',async()=>{
 const f=await fixture();try{assert.equal((await fetch(f.url+'/workspaces/live-beta/config')).status,503);assert.equal((await (await fetch(f.url+'/workspaces/test/config')).json()).key,'pk_test_sample');const b=await (await fetch(f.url+'/account-config',{headers:{authorization:'Bearer real'}})).json();assert.equal(b.ready,false);assert.equal(b.publishableKey,null)}finally{await f.close()}
});
test('incomplete live configuration and missing policy fail closed',async()=>{
 const f=await fixture({LIVE_BETA_ENABLED:'true',STRIPE_DRIVER_VERIFICATION_FLOW_ID_LIVE:''});const g=await fixture({}, {policy:null});try{assert.equal((await fetch(f.url+'/workspaces/live-beta/config')).status,503);assert.equal((await fetch(g.url+'/workspace-bootstrap')).status,503);assert.equal((await fetch(g.url+'/account-config',{headers:{authorization:'Bearer test-uid'}})).status,503)}finally{await f.close();await g.close()}
});
test('public bootstrap contains hashes only, never phone numbers or UIDs',async()=>{
 const f=await fixture();try{const r=await fetch(f.url+'/workspace-bootstrap');const b=await r.json();assert.equal(r.headers.get('cache-control'),'no-store');assert.deepEqual(b.testUidHashes,[createHash('sha256').update('test-uid').digest('hex')]);assert.deepEqual(b.testPhoneHashes,policy.blockedPhoneHashes);assert.ok(!JSON.stringify(b).includes('test-uid'))}finally{await f.close()}
});
test('signed webhooks are routed to their environment; unsigned mode switching is rejected',async()=>{
 const f=await fixture({LIVE_BETA_ENABLED:'true'});try{const stripe=new Stripe('sk_test_sample');for(const mode of ['test','live']){for(const scope of ['platform','connect']){
 const body=JSON.stringify({id:'evt_'+mode,livemode:mode==='live',api_version:'2024-06-20',...(scope==='connect'?{account:'acct_test'}:{})});const secret=scope==='connect'?keys['STRIPE_CONNECT_WEBHOOK_SECRET_'+mode.toUpperCase()]:keys['STRIPE_WEBHOOK_SECRET_'+mode.toUpperCase()];const signature=stripe.webhooks.generateTestHeaderString({payload:body,secret});const r=await fetch(f.url+(scope==='connect'?'/webhook/connect':'/webhook'),{method:'POST',headers:{'content-type':'application/json','stripe-signature':signature},body});assert.equal(r.status,200);assert.equal((await r.json()).workspace,mode==='test'?'test':'live-beta');
 }}assert.equal((await fetch(f.url+'/webhook',{method:'POST',headers:{'content-type':'application/json'},body:'{"livemode":true}'})).status,400)}finally{await f.close()}
});

test('a live signing secret cannot authorize a Test event or vice versa',async()=>{
 const f=await fixture({LIVE_BETA_ENABLED:'true'});try{const stripe=new Stripe('sk_test_sample');for(const mode of ['test','live']){const body=JSON.stringify({id:'evt_mismatch',livemode:mode==='live',api_version:'2024-06-20'});const signature=stripe.webhooks.generateTestHeaderString({payload:body,secret:mode==='live'?keys.STRIPE_WEBHOOK_SECRET_TEST:keys.STRIPE_WEBHOOK_SECRET_LIVE});const response=await fetch(f.url+'/webhook',{method:'POST',headers:{'content-type':'application/json','stripe-signature':signature},body});assert.equal(response.status,400)}}finally{await f.close()}
});
test('direct prefixed webhook routes accept only their own signing secret',async()=>{
 const app=createWorkspaceServer({...keys,LIVE_BETA_ENABLED:'true'},{control:()=>({getWorkspaceState:async()=>({enabled:true,livePaymentsEnabled:true})})});const server=app.listen(0,'127.0.0.1');await new Promise(resolve=>server.once('listening',resolve));try{const stripe=new Stripe('sk_test_sample');for(const workspace of ['test','live-beta']){const body=JSON.stringify({id:'evt_direct_mismatch',livemode:workspace==='live-beta',api_version:'2024-06-20'});const signature=stripe.webhooks.generateTestHeaderString({payload:body,secret:workspace==='test'?keys.STRIPE_WEBHOOK_SECRET_LIVE:keys.STRIPE_WEBHOOK_SECRET_TEST});const response=await fetch(`http://127.0.0.1:${server.address().port}/workspaces/${workspace}/webhook`,{method:'POST',headers:{'content-type':'application/json','stripe-signature':signature},body});assert.equal(response.status,400)}}finally{await new Promise(resolve=>server.close(resolve))}
});

test('the Firestore Live Beta switch is enforced even with complete enabled live keys',async()=>{
 for(const workspaceState of [null,{enabled:true,livePaymentsEnabled:false}]){const f=await fixture({LIVE_BETA_ENABLED:'true'},{workspaceState});try{assert.equal((await fetch(f.url+'/workspaces/live-beta/config')).status,503);const response=await fetch(f.url+'/account-config',{headers:{authorization:'Bearer real'}});const config=await response.json();assert.equal(config.ready,false);assert.equal(config.publishableKey,null);assert.equal((await fetch(f.url+'/workspaces/test/config')).status,200)}finally{await f.close()}}
});

test('separate Auth projects route identical email and phone to their own Stripe keys',async()=>{
 const v2={...policy,version:2,authSeparationEnabled:true};
 for(const [audience,workspace,key] of [['rydr-test-c7ec1','test','pk_test_sample'],['rydrapp-c7ec1','live-beta','pk_live_sample']]){
  const f=await fixture({LIVE_BETA_ENABLED:'true'},{audience,policy:v2,user:{email:'same@example.com',phoneNumber:'+15555550101'}});
  try{const r=await fetch(f.url+'/account-config',{headers:{authorization:'Bearer same-new-uid','x-rydr-workspace':workspace==='test'?'live-beta':'test'}});assert.equal(r.status,200);const body=await r.json();assert.equal(body.workspace,workspace);assert.equal(body.publishableKey,key);}finally{await f.close()}
 }
});
