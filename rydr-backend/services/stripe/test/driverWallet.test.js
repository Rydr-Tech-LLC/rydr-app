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
