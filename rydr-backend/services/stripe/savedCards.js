'use strict';
const {createHash}=require('node:crypto');
const {PayoutError}=require('./driverPayouts');
function cardKey(pm) {
 const c=pm?.card;
 if(pm?.type!=='card'||!c?.fingerprint||!c.exp_month||!c.exp_year)return null;
 // Wallet/network tokens can represent different credentials for the same physical card.
 return createHash('sha256').update(JSON.stringify([c.fingerprint,c.exp_month,c.exp_year,c.funding||'',c.wallet?.type||'',c.wallet?.dynamic_last4||''])).digest('hex');
}
async function listCards(stripe,customerId) {
 const cards=[];let cursor;
 do {const p=await stripe.paymentMethods.list({customer:customerId,type:'card',limit:100,...(cursor?{starting_after:cursor}:{})});cards.push(...p.data);cursor=p.has_more?p.data.at(-1)?.id:null;}while(cursor);
 return cards;
}
async function finishCardSetup({stripe,db,customerId,uid,setupIntentId}) {
 if(!/^seti_[A-Za-z0-9]+$/.test(setupIntentId||''))throw new PayoutError('invalid_setup_intent',400);
 const si=await stripe.setupIntents.retrieve(setupIntentId,{expand:['payment_method']});
 if(si.customer!==customerId || si.metadata?.firebase_uid!==uid)throw new PayoutError('setup_intent_not_owned',403);
 if(si.status!=='succeeded')throw new PayoutError('card_setup_not_complete',409);
 const pm=typeof si.payment_method==='string'?await stripe.paymentMethods.retrieve(si.payment_method):si.payment_method;
 if(!pm || pm.customer && pm.customer!==customerId)throw new PayoutError('payment_method_not_owned',403);
 const key=cardKey(pm);
 if(!key) {if(pm.customer!==customerId)throw new PayoutError('saved_card_unavailable',409);return {paymentMethodId:pm.id};}
 const cards=(await listCards(stripe,customerId)).filter(c=>cardKey(c)===key);
 if(!cards.length)throw new PayoutError('saved_card_unavailable',409);
 const ref=db.collection('savedCardCanonical').doc(createHash('sha256').update(customerId+':'+key).digest('hex'));
 const customer=await stripe.customers.retrieve(customerId);
 const defaultId=typeof customer.invoice_settings?.default_payment_method==='string'?customer.invoice_settings.default_payment_method:customer.invoice_settings?.default_payment_method?.id;
 const ordered=[...cards].sort((a,b)=>(a.created||0)-(b.created||0)||a.id.localeCompare(b.id));
 // Persist the first chosen destination so simultaneous confirmations cannot delete
 // each other's canonical card, including cards created in the same second.
 const canonical=await db.runTransaction(async tx=>{
  const existing=(await tx.get(ref)).data()?.paymentMethodId;
  const chosen=cards.find(c=>c.id===existing)||cards.find(c=>c.id===defaultId)||ordered[0];
  tx.set(ref,{paymentMethodId:chosen.id,customerId},{merge:true});return chosen;
 });
 // Only detach the duplicate introduced by this successful setup. Do not
 // sweep unrelated historical methods or methods referenced by other flows.
 const duplicates=cards.filter(c=>c.id===pm.id && c.id!==canonical.id);
 if(duplicates.some(c=>c.id===defaultId))await stripe.customers.update(customerId,{invoice_settings:{default_payment_method:canonical.id}},{idempotencyKey:`saved_card_default_${customerId}_${defaultId}_${canonical.id}`});
 for(const duplicate of duplicates) {
  // Recheck ownership before any detach; this operates only on an authenticated
  // successful setup's exact fingerprint + expiration + wallet credential group.
  const current=await stripe.paymentMethods.retrieve(duplicate.id);
  if(current.customer===customerId)await stripe.paymentMethods.detach(duplicate.id,{}, {idempotencyKey:`saved_card_duplicate_${customerId}_${duplicate.id}`});
 }
 return {paymentMethodId:canonical.id};
}
module.exports={cardKey,listCards,finishCardSetup};
