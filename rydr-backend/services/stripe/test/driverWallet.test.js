const {test}=require('node:test');const assert=require('node:assert/strict');
const {instantEligibility,accountSessionComponents,walletSnapshot,payoutSummary}=require('../driverWallet');
const bank={id:'ba_bank',object:'bank_account',currency:'usd',bank_name:'Bank',last4:'1234',default_for_currency:true,available_payout_methods:['standard']};
const card={id:'card_debit',object:'card',currency:'usd',brand:'Visa',last4:'4321',available_payout_methods:['instant']};
test('settled funds do not imply instant eligibility',()=>{assert.equal(instantEligibility({payouts_enabled:true},{available:[{currency:'usd',amount:20000}]},[card]).amount,0);});
test('instant uses an eligible destination and its net balance, not the ACH bank',()=>{
 const result=instantEligibility({payouts_enabled:true},{instant_available:[{currency:'usd',amount:20000,net_available:[{destination:'card_debit',amount:19500}]}]},[bank,card]);assert.equal(result.amount,19500);assert.equal(result.destination.id,card.id);
 assert.equal(instantEligibility({payouts_enabled:false},{instant_available:[{currency:'usd',amount:20000}]},[card]).amount,0);
});
test('embedded method sessions cannot pay out or change the Monday schedule',()=>{
 const f=accountSessionComponents('payout_methods').payouts.features;assert.equal(f.instant_payouts,false);assert.equal(f.standard_payouts,false);assert.equal(f.edit_payout_schedule,false);assert.equal(f.external_account_collection,true);assert.equal(f.disable_stripe_user_authentication,false);assert.throws(()=>accountSessionComponents('admin'));
});
test('snapshot separates four money states and preserves actual payout destinations',async()=>{
 const payouts=[{id:'po_one',amount:3000,currency:'usd',status:'in_transit',method:'instant',created:10,destination:card},{id:'po_two',amount:4000,currency:'usd',status:'failed',method:'standard',created:9,destination:bank,failure_message:'Bank closed'},{id:'po_three',amount:5000,currency:'usd',status:'pending',method:'standard',created:8,destination:bank}];
 const calls=[];const stripe={accounts:{retrieve:async()=>({payouts_enabled:true,details_submitted:true,requirements:{}}),listExternalAccounts:async(id,p)=>({data:p.starting_after?[card]:[bank],has_more:!p.starting_after})},balance:{retrieve:async()=>({available:[{currency:'usd',amount:10000}],pending:[{currency:'usd',amount:20000}],instant_available:[{currency:'usd',amount:9000}]})},payouts:{list:async(p,o)=>{calls.push({p,o});return p.limit===25?{data:payouts.slice(0,2),has_more:true}:{data:p.starting_after?[payouts[2]]:payouts.slice(0,2),has_more:!p.starting_after};}}};
 const s=await walletSnapshot(stripe,'acct_owned','po_before');assert.equal(s.availableAmount,10000);assert.equal(s.pendingSettlementAmount,20000);assert.equal(s.instantAvailableAmount,9000);assert.equal(s.inTransitAmount,8000);assert.equal(s.payouts[0].destination.type,'card');assert.equal(s.payouts[1].failureMessage,'Bank closed');assert.equal(s.nextCursor,'po_two');assert.equal(calls[0].p.starting_after,'po_before');assert.ok(calls.every(c=>c.o.stripeAccount==='acct_owned'));
});
test('unknown historical destinations are never labeled as the current bank',()=>{assert.equal(payoutSummary({id:'po_old',destination:'ba_old'}).destination.name,'Payout account');});

test('receipt fees come from a confirmed balance transaction and stay unknown otherwise',()=>{
 assert.equal(payoutSummary({currency:'usd',balance_transaction:'txn_pending'}).feeAmount,null);
 assert.equal(payoutSummary({currency:'usd',balance_transaction:{currency:'usd',fee:123}}).feeAmount,123);
});

const {createDriverAccountSession}=require('../driverWallet');
test('embedded payout sessions are scoped to the owned account and workspace mode',async()=>{
 for(const mode of ['test','live']) {
  let params; const workspace=mode==='test'?'test':'live-beta';
  const stripe={accountSessions:{create:async p=>{params=p;return {account:p.account,livemode:mode==='live',client_secret:'secret_fixture'};}}};
  const result=await createDriverAccountSession({stripe,accountId:'acct_owned',purpose:'payout_methods',mode,workspace,publishableKey:`pk_${mode}_fixture`});
  assert.deepEqual(result,{clientSecret:'secret_fixture',mode,workspace});assert.equal(params.account,'acct_owned');
  assert.equal(params.components.payouts.features.external_account_collection,true);
  assert.equal(params.components.payouts.features.disable_stripe_user_authentication,false);
 }
});
test('cross-mode keys, workspaces, sessions and account IDs fail closed',async()=>{
 let calls=0;const valid={account:'acct_owned',livemode:false,client_secret:'private'};let response=valid;
 const stripe={accountSessions:{create:async()=>{calls++;return response;}}};
 const base={stripe,accountId:'acct_owned',purpose:'payout_methods',mode:'test',workspace:'test',publishableKey:'pk_test_fixture'};
 for(const override of [{publishableKey:'pk_live_fixture'},{workspace:'live-beta'},{mode:'invalid'},{purpose:'admin'}]) {
  await assert.rejects(createDriverAccountSession({...base,...override}));
 }
 assert.equal(calls,0);
 for(const bad of [{...valid,livemode:true},{...valid,account:'acct_other'},{...valid,client_secret:null}]) {
  response=bad;await assert.rejects(createDriverAccountSession(base),/stripe_mode_mismatch/);
 }
});

test('payout method summaries expose only masked details and confirmed instant eligibility',()=>{
 const {payoutMethodSummary}=require('../driverWallet');
 const summary=payoutMethodSummary({...card,number:'4000000000000000',routing_number:'private',account_holder_name:'Private Driver'});
 assert.deepEqual(summary,{id:'card_debit',brand:'Visa',last4:'4321',isDefault:false,status:null,instantEligible:true});
 assert.equal(payoutMethodSummary({...card,status:'errored'}).instantEligible,false);
 assert.equal(payoutMethodSummary({...card,currency:'eur'}).instantEligible,false);
 assert.equal(payoutMethodSummary({...card,available_payout_methods:undefined}).instantEligible,false);
 assert.equal(payoutMethodSummary(bank).instantEligible,false);
});
