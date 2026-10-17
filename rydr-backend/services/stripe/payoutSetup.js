'use strict';
const {assertManaged,isManagedAccount}=require('./connectConfiguration');
const {PayoutError}=require('./driverPayouts');
const {allExternalAccounts,payoutMethodSummary}=require('./driverWallet');
const BUSINESS={mcc:'4121',product_description:'Independent driver providing prearranged passenger rides through the Rydr ridesharing platform.'};
function missingBusinessDetails(account){
 if(!isManagedAccount(account))return {};
 const p=account.business_profile||{},patch={};
 if(!p.mcc)patch.mcc=BUSINESS.mcc;
 if(!p.product_description&&!p.url)patch.product_description=BUSINESS.product_description;
 return patch;
}
async function prefillBusiness(stripe,account){const business_profile=missingBusinessDetails(account);return Object.keys(business_profile).length?stripe.accounts.update(account.id,{business_profile}):account;}
async function addMethod({stripe,account,tokenId,kind,mode,requestId}){
 assertManaged(account);
 if(!['bank','card'].includes(kind)||!/^(tok_|btok_)[A-Za-z0-9]+$/.test(tokenId||''))throw new PayoutError('invalid_payout_method',400);
 const token=await stripe.tokens.retrieve(tokenId,{},{stripeAccount:account.id});
 if(token.livemode!==(mode==='live'))throw new PayoutError('stripe_mode_mismatch',400);
 const value=kind==='bank'?token.bank_account:token.card;
 if(!value||token.type!==(kind==='bank'?'bank_account':'card'))throw new PayoutError('payout_method_type_mismatch',400);
 if(kind==='card'&&value.funding!=='debit')throw new PayoutError('debit_card_required',400);
 const existing=(await allExternalAccounts(stripe,account.id)).find(a=>a.object===(kind==='bank'?'bank_account':'card')&&value.fingerprint&&a.fingerprint===value.fingerprint&&a.currency==='usd'&&(kind==='bank'||a.exp_month===value.exp_month&&a.exp_year===value.exp_year));
 if(existing)return {method:payoutMethodSummary(existing),reused:true};
 const saved=await stripe.accounts.createExternalAccount(account.id,{external_account:tokenId},{idempotencyKey:`rydr_payout_method_${account.id}_${requestId}`});
 return {method:payoutMethodSummary(saved),reused:false};
}
async function editMethod({stripe,account,id,action,requestId}){
 assertManaged(account);
 if(!/^(ba_|card_)[A-Za-z0-9]+$/.test(id||'')||!['default','remove'].includes(action))throw new PayoutError('invalid_payout_method_action',400);
 const methods=await allExternalAccounts(stripe,account.id),method=methods.find(m=>m.id===id);
 if(!method)throw new PayoutError('payout_method_not_found',404);
 if(action==='remove'){
  if(method.default_for_currency)throw new PayoutError('choose_another_default_before_removing',409);
  const payouts=await stripe.payouts.list({limit:100},{stripeAccount:account.id});
  if(payouts.has_more||payouts.data.some(p=>['pending','in_transit'].includes(p.status)&&(!p.destination||p.destination===id||p.destination.id===id)))throw new PayoutError('payout_in_flight',409);
  await stripe.accounts.deleteExternalAccount(account.id,id,{},{idempotencyKey:`rydr_remove_method_${account.id}_${requestId}`});return {removed:true};
 }
 const saved=await stripe.accounts.updateExternalAccount(account.id,id,{default_for_currency:true},{idempotencyKey:`rydr_default_method_${account.id}_${requestId}`});return {method:payoutMethodSummary(saved)};
}
module.exports={BUSINESS,missingBusinessDetails,prefillBusiness,addMethod,editMethod};
