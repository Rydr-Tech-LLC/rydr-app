const {test}=require('node:test');const assert=require('node:assert/strict');
const {cardKey,finishCardSetup}=require('../savedCards');
const card=(id,extra={})=>({id,type:'card',customer:'cus_owned',created:1,card:{fingerprint:'fp_same',last4:'4242',exp_month:12,exp_year:2030,funding:'credit',...extra}});
function fixture(cards=[card('pm_old'),card('pm_new'),card('pm_third')]) {
 const state=new Map(),detached=[];let defaultId='pm_old';let chain=Promise.resolve();
 const stripe={setupIntents:{retrieve:async()=>({id:'seti_owned',status:'succeeded',customer:'cus_owned',metadata:{firebase_uid:'uid'},payment_method:card('pm_new')})},
 paymentMethods:{list:async()=>({data:cards.filter(c=>!detached.includes(c.id)),has_more:false}),retrieve:async id=>({...cards.find(c=>c.id===id),customer:detached.includes(id)?null:'cus_owned'}),detach:async id=>{detached.push(id);}},
 customers:{retrieve:async()=>({invoice_settings:{default_payment_method:defaultId}}),update:async(_id,p)=>{defaultId=p.invoice_settings.default_payment_method;}}};
 const db={collection:()=>({doc:id=>({id})}),runTransaction:fn=>{const next=chain.then(()=>fn({get:async ref=>({data:()=>state.get(ref.id)}),set:(ref,data)=>state.set(ref.id,data)}));chain=next.catch(()=>{});return next;}};
 return {stripe,db,detached,defaultId:()=>defaultId};
}
const run=f=>finishCardSetup({...f,customerId:'cus_owned',uid:'uid',setupIntentId:'seti_owned'});
test('a duplicate confirmation reuses the existing default and removes only its own extra card',async()=>{
 const f=fixture();const result=await run(f);assert.equal(result.paymentMethodId,'pm_old');
 assert.deepEqual(f.detached,['pm_new']);assert.equal(f.defaultId(),result.paymentMethodId);assert.deepEqual(await run(f),result);
});
test('concurrent finalizations retain one canonical card',async()=>{
 const f=fixture();const results=await Promise.all([run(f),run(f),run(f)]);assert.equal(new Set(results.map(r=>r.paymentMethodId)).size,1);assert.ok(!f.detached.includes(results[0].paymentMethodId));
});
test('same last four digits never merge different fingerprints, expiry or wallet credentials',async()=>{
 assert.notEqual(cardKey(card('a')),cardKey(card('b',{fingerprint:'other'})));
 assert.notEqual(cardKey(card('a')),cardKey(card('b',{exp_year:2031})));
 assert.notEqual(cardKey(card('a')),cardKey(card('b',{wallet:{type:'apple_pay'}})));
 assert.equal(cardKey(card('a',{fingerprint:undefined})),null);
 const f=fixture([card('pm_new'),card('pm_other',{fingerprint:'different'}),card('pm_expiry',{exp_year:2031})]);await run(f);assert.equal(f.detached.length,0);
});
test('wrong customer, wrong UID and incomplete setup cannot mutate saved cards',async()=>{
 for(const override of [{customer:'cus_other'},{metadata:{firebase_uid:'other'}},{status:'requires_action'}]){
  const f=fixture();const retrieve=f.stripe.setupIntents.retrieve;f.stripe.setupIntents.retrieve=async()=>({...await retrieve(),...override});await assert.rejects(run(f));assert.equal(f.detached.length,0);
 }
});

test('three separate successful setup callbacks leave one saved card',async()=>{
 const f=fixture();
 for(const id of ['pm_old','pm_new','pm_third']) {
  f.stripe.setupIntents.retrieve=async()=>({status:'succeeded',customer:'cus_owned',metadata:{firebase_uid:'uid'},payment_method:card(id)});
  assert.equal((await run(f)).paymentMethodId,'pm_old');
 }
 assert.deepEqual(new Set(f.detached),new Set(['pm_new','pm_third']));
 assert.equal(f.defaultId(),'pm_old');
});
