const {test}=require('node:test');
const assert=require('node:assert/strict');
const {DriverPayoutService,payoutJobId,availableUsdParts}=require('../driverPayouts');
function fixture({amount=10000,sources={card:10000},bank=true,enabled=true}={}){
 const records=new Map(),payouts=new Map(),calls=[];let mutex=Promise.resolve(),failure=null,hook=null,balanceHook=null;
 const snap=path=>({exists:records.has(path),data:()=>records.get(path)});
 const ref=path=>({path,id:path.split('/').at(-1),get:async()=>snap(path),set:async(d,o)=>records.set(path,o?.merge?{...records.get(path),...d}:d)});
 const db={collection:path=>({doc:id=>ref(`${path}/${id}`),where:()=>({limit:()=>({get:async()=>({docs:[{id:'driver'}]})})})}),runTransaction:fn=>{const task=mutex.then(async()=>{const writes=[];let writing=false;const result=await fn({get:async r=>{assert.equal(writing,false);return snap(r.path);},set:(r,d,o)=>{writing=true;writes.push(()=>records.set(r.path,o?.merge?{...records.get(r.path),...d}:d));},update:(r,d)=>{writing=true;writes.push(()=>records.set(r.path,{...records.get(r.path),...d}));},delete:r=>{writing=true;writes.push(()=>records.delete(r.path));}});writes.forEach(w=>w());return result;});mutex=task.catch(()=>{});return task;}};
 const account={id:'acct_driver',type:'express',country:'US',payouts_enabled:enabled,settings:{payouts:{schedule:{interval:'daily'}}}};
 const stripe={accounts:{retrieve:async()=>account,update:async(id,params)=>{calls.push({kind:'schedule',params});account.settings.payouts.schedule.interval=params.settings.payouts.schedule.interval;},listExternalAccounts:async()=>({data:bank?[{id:'ba_default',object:'bank_account',country:'US',currency:'usd',status:'validated',default_for_currency:true,available_payout_methods:['standard'],last4:'1234'}]:[],has_more:false})},balance:{retrieve:async()=>{if(balanceHook)await balanceHook();return{available:[{currency:'usd',amount,source_types:sources}],pending:[{currency:'usd',amount:90000}]};}},payouts:{create:async(params,options)=>{calls.push({kind:'payout',params,options});if(failure)throw failure;const prior=[...payouts.values()].find(p=>p.key===options.idempotencyKey);if(prior)return prior;const p={...params,id:`po_${payouts.size+1}`,status:'pending',arrival_date:1900000000,key:options.idempotencyKey};payouts.set(p.id,p);if(hook)await hook(p);return p;},retrieve:async id=>payouts.get(id),list:async()=>({data:[...payouts.values()],has_more:false})}};
 records.set('drivers/driver',{stripeAccountId:'acct_driver'});
 const service=new DriverPayoutService({stripe,getDb:()=>db,now:()=>new Date("2026-10-19T13:00:00Z").getTime()}),id=payoutJobId('acct_driver','weekly','2026-10-19');
 records.set(`driverPayouts/${id}`,{kind:'weekly',driverId:'driver',accountId:'acct_driver',weekDate:'2026-10-19',status:'queued'});
 return{records,payouts,calls,stripe,service,id,account,fail:e=>failure=e,hook:h=>hook=h,balanceHook:h=>balanceHook=h,job:()=>records.get(`driverPayouts/${id}`),creates:()=>calls.filter(c=>c.kind==='payout')};
}
test('weekly pays available USD to a bank once, excluding pending funds',async()=>{
 const f=fixture();assert.equal(await f.service.processWeekly(f.id),'pending');const c=f.creates()[0];assert.equal(c.params.amount,10000);assert.equal(c.params.method,'standard');assert.equal(c.params.destination,'ba_default');assert.equal(c.params.source_type,'card');assert.equal(c.options.stripeAccount,'acct_driver');assert.equal(f.account.settings.payouts.schedule.interval,'manual');assert.equal(f.records.has('driverPayoutLocks/acct_driver'),false);await f.service.processWeekly(f.id);assert.equal(f.creates().length,1);
});
test('zero available funds skip payouts',async()=>{const f=fixture({amount:0,sources:{card:0}});assert.equal(await f.service.processWeekly(f.id),'skipped');assert.equal(f.creates().length,0);});
test('missing bank and disabled payouts flag issues without money movement',async()=>{for(const opts of [{bank:false},{enabled:false}]){const f=fixture(opts);await f.service.processWeekly(f.id);assert.equal(f.job().needsReview,true);assert.equal(f.creates().length,0);assert.equal(f.records.has('driverPayoutLocks/acct_driver'),false);}});
test('separate payment sources have separate fixed payout keys',async()=>{const f=fixture({amount:12000,sources:{card:10000,bank_account:2000}});await f.service.processWeekly(f.id);assert.deepEqual(f.creates().map(c=>[c.params.source_type,c.params.amount]),[['card',10000],['bank_account',2000]]);assert.notEqual(f.creates()[0].options.idempotencyKey,f.creates()[1].options.idempotencyKey);});
test('instant cash-out cannot overlap an active weekly payout',async()=>{const f=fixture();let open,entered;const gate=new Promise(r=>open=r),started=new Promise(r=>entered=r);f.balanceHook(async()=>{entered();await gate;});const weekly=f.service.processWeekly(f.id);await started;await assert.rejects(f.service.instant({driverId:'driver',accountId:'acct_driver',amount:100,currency:'usd',requestId:'tap'}),e=>e.code==='payout_in_progress');open();await weekly;assert.equal(f.creates().length,1);});
test('uncertain submissions keep the lock and never blindly resubmit',async()=>{const f=fixture();f.fail({type:'StripeConnectionError'});await f.service.processWeekly(f.id);assert.equal(f.job().parts[0].status,'submitting');await f.service.processWeekly(f.id);await f.service.reconcile(f.id);assert.equal(f.creates().length,1);assert.equal(f.records.has('driverPayoutLocks/acct_driver'),true);});
test('definite Stripe rejection releases the lock and flags the part',async()=>{const f=fixture();f.fail({type:'StripeInvalidRequestError',statusCode:400,code:'balance_insufficient'});await f.service.processWeekly(f.id);assert.equal(f.job().parts[0].status,'failed');assert.equal(f.job().needsReview,true);assert.equal(f.records.has('driverPayoutLocks/acct_driver'),false);});
test('read-only reconciliation discovers a lost-response payout',async()=>{const f=fixture();f.fail({type:'StripeConnectionError'});await f.service.processWeekly(f.id);f.payouts.set('po_lost',{...f.creates()[0].params,id:'po_lost',status:'pending'});await f.service.reconcile(f.id);assert.equal(f.job().parts[0].payoutId,'po_lost');assert.equal(f.job().status,'pending');assert.equal(f.records.has('driverPayoutLocks/acct_driver'),false);assert.equal(f.creates().length,1);});
test('webhooks use current Stripe status and flag later bank failures',async()=>{const f=fixture();await f.service.processWeekly(f.id);const p=f.payouts.get('po_1');p.status='paid';await f.service.webhook({account:'acct_driver',data:{object:{id:'po_1',status:'pending'}}});assert.equal(f.job().status,'paid');p.status='failed';p.failure_code='bank_account_closed';await f.service.webhook({account:'acct_driver',data:{object:{id:'po_1'}}});assert.equal(f.job().needsReview,true);assert.equal(f.job().parts[0].failureCode,'bank_account_closed');});
test('a first-part webhook cannot unlock a multi-part payout',async()=>{const f=fixture({amount:12000,sources:{card:10000,bank_account:2000}});f.hook(async p=>{await f.service.webhook({account:'acct_driver',data:{object:{id:p.id}}});if(p.id==='po_1')assert.equal(f.records.has('driverPayoutLocks/acct_driver'),true);});await f.service.processWeekly(f.id);assert.equal(f.records.has('driverPayoutLocks/acct_driver'),false);});
test('instant retries preserve the shipped parameters and return one payout',async()=>{const f=fixture(),input={driverId:'driver',accountId:'acct_driver',amount:123,currency:'usd',requestId:'tap'};const a=await f.service.instant(input),b=await f.service.instant(input);assert.equal(a.id,b.id);assert.equal(f.creates().length,1);assert.deepEqual(f.creates()[0].params.metadata,{uid:'driver',source:'driver_wallet_instant_pay'});assert.equal(f.creates()[0].options.idempotencyKey,'instant_payout_acct_driver_tap');await assert.rejects(f.service.instant({...input,amount:999}),e=>e.code==='payout_request_parameters_changed');});
test('Connect ownership changes block a queued job',async()=>{const f=fixture();f.records.set('drivers/driver',{stripeAccountId:'acct_other'});await f.service.processWeekly(f.id);assert.equal(f.job().needsReview,true);assert.equal(f.creates().length,0);});
test('other currencies and inconsistent source amounts never inflate payouts',()=>{assert.deepEqual(availableUsdParts({available:[{currency:'eur',amount:99999},{currency:'usd',amount:50,source_types:{card:50}}]}),[{amount:50,sourceType:'card'}]);assert.throws(()=>availableUsdParts({available:[{currency:'usd',amount:50,source_types:{card:100}}]}),/inconsistent_available_balance/);});

test('interrupted prepared work retires the owner before releasing the account lock',async()=>{
 const f=fixture(),old={toMillis:()=>Date.now()-20*60*1000};
 f.records.set(`driverPayouts/${f.id}`,{...f.job(),status:'processing',owner:'old-owner',startedAt:old,parts:[{amount:10000,currency:'usd',sourceType:'card',status:'prepared'}]});
 f.records.set('driverPayoutLocks/acct_driver',{jobId:f.id,owner:'old-owner',createdAt:old});
 await f.service.reconcile(f.id);
 assert.equal(f.job().needsReview,true);assert.equal(f.job().parts[0].status,'not_attempted');assert.equal(f.records.has('driverPayoutLocks/acct_driver'),false);
 await assert.rejects(f.service.setPart(f.id,0,{status:'submitting'},'old-owner'),e=>e.code==='payout_worker_claim_lost');assert.equal(f.creates().length,0);
});
test('an old unresolved lock blocks a new payout and records the earlier job',async()=>{
 const f=fixture();f.records.set('driverPayoutLocks/acct_driver',{jobId:'earlier-job',owner:'old-owner',createdAt:{toMillis:()=>Date.now()-20*60*1000}});
 await f.service.processWeekly(f.id);assert.equal(f.job().needsReview,true);assert.equal(f.job().blockedByJobId,'earlier-job');assert.equal(f.creates().length,0);
});
test('Stripe account ownership mismatch is flagged',async()=>{
 const f=fixture();f.account.metadata={uid:'another-driver'};await f.service.processWeekly(f.id);assert.equal(f.job().reasonCode,'payout_account_owner_mismatch');assert.equal(f.creates().length,0);
});

test('preparing existing accounts changes timing without paying any funds',async()=>{
 const f=fixture();assert.equal((await f.service.preparePolicy('driver')).status,'configured');
 assert.equal(f.account.settings.payouts.schedule.interval,'manual');assert.equal(f.creates().length,0);
});

test('old weekly jobs cannot withdraw a later week balance',async()=>{
 const f=fixture();f.records.set(`driverPayouts/${f.id}`,{...f.job(),weekDate:'2026-10-12'});
 await f.service.processWeekly(f.id);assert.equal(f.job().reasonCode,'weekly_payout_job_outside_current_week');assert.equal(f.creates().length,0);
});

test('a debit card is never accepted as the weekly ACH destination',async()=>{
 const f=fixture();f.stripe.accounts.listExternalAccounts=async()=>({data:[{id:'card_default',object:'card',country:'US',currency:'usd',default_for_currency:true,available_payout_methods:['standard','instant']}],has_more:false});
 await f.service.processWeekly(f.id);assert.equal(f.job().reasonCode,'valid_default_bank_account_required');assert.equal(f.creates().length,0);
});
test('a lost response in one source does not leave never-submitted parts locked forever',async()=>{
 const f=fixture({amount:12000,sources:{card:10000,bank_account:2000}});f.fail({type:'StripeConnectionError'});await f.service.processWeekly(f.id);
 assert.equal(f.job().parts[1].status,'not_attempted');f.payouts.set('po_lost',{...f.creates()[0].params,id:'po_lost',status:'pending'});await f.service.reconcile(f.id);
 assert.equal(f.records.has('driverPayoutLocks/acct_driver'),false);assert.equal(f.job().needsReview,true);assert.equal(f.creates().length,1);
});
