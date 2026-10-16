"use strict";
const { PayoutError } = require('./driverPayouts');
async function allExternalAccounts(stripe, accountId) {
  const accounts=[];let starting_after;
  do {
    const page=await stripe.accounts.listExternalAccounts(accountId,{limit:100,...(starting_after?{starting_after}:{})});
    accounts.push(...page.data);starting_after=page.has_more?page.data.at(-1)?.id:undefined;
  }while(starting_after);
  return accounts;
}
function destinationSummary(destination) {
  if(!destination || typeof destination==='string')return {id:typeof destination==='string'?destination:null,type:'unknown',name:'Payout account',last4:null};
  return {id:destination.id,type:destination.object==='card'?'card':'bank_account',name:destination.bank_name||destination.brand||'Payout account',last4:destination.last4||null};
}
function payoutMethodSummary(account) {
  return {id:account.id,...(account.object==='bank_account'?{bankName:account.bank_name||'Bank account'}:{brand:account.brand||'Debit card'}),
    last4:account.last4||'',isDefault:account.default_for_currency===true,
    status:account.status||null,instantEligible:account.currency==='usd' && account.available_payout_methods?.includes('instant')===true && !['errored','verification_failed'].includes(account.status)};
}
function payoutSummary(payout) {
  return {id:payout.id,amount:payout.amount,currency:payout.currency,status:payout.status,method:payout.method,arrivalDate:payout.arrival_date||null,created:payout.created,destination:destinationSummary(payout.destination),feeAmount:typeof payout.balance_transaction==='object' && payout.balance_transaction?.currency===payout.currency?payout.balance_transaction.fee:null,failureCode:payout.failure_code||null,failureMessage:payout.failure_message||null};
}
function instantEligibility(account,balance,externalAccounts) {
  const entry=(balance.instant_available||[]).find(b=>b.currency==='usd');
  const eligible=externalAccounts.filter(a=>a.currency==='usd' && a.available_payout_methods?.includes('instant') && !['errored','verification_failed'].includes(a.status));
  eligible.sort((a,b)=>Number(b.default_for_currency===true)-Number(a.default_for_currency===true)||Number(b.object==='card')-Number(a.object==='card')||a.id.localeCompare(b.id));
  const destination=eligible[0];
  let amount=Number.isSafeInteger(entry?.amount)?Math.max(0,entry.amount):0;
  if(entry?.net_available?.length) amount=Math.max(0,entry.net_available.find(v=>v.destination===destination?.id)?.amount??0);
  if(!account.payouts_enabled || !destination)amount=0;
  return {amount,destination:destination?destinationSummary(destination):null};
}
function accountSessionComponents(purpose) {
  if(purpose==='onboarding')return {account_onboarding:{enabled:true,features:{external_account_collection:true,disable_stripe_user_authentication:false}}};
  if(purpose==='payout_methods')return {payouts:{enabled:true,features:{external_account_collection:true,disable_stripe_user_authentication:false,instant_payouts:false,standard_payouts:false,edit_payout_schedule:false}}};
  throw new PayoutError('invalid_account_session_purpose',400);
}
// A session grants financial-account access: never return it across Stripe modes.
async function createDriverAccountSession({stripe,accountId,purpose,mode,workspace,publishableKey}) {
  const components=accountSessionComponents(purpose);
  const live=mode==='live';
  if(!['test','live'].includes(mode) || workspace!==(live?'live-beta':'test') ||
      !String(publishableKey||'').startsWith(live?'pk_live_':'pk_test_')) {
    throw new PayoutError('stripe_mode_mismatch',503);
  }
  const session=await stripe.accountSessions.create({account:accountId,components});
  if(session.livemode!==live || !session.client_secret || session.account!==accountId) {
    throw new PayoutError('stripe_mode_mismatch',503);
  }
  return {clientSecret:session.client_secret,mode,workspace};
}
async function walletSnapshot(stripe,accountId,startingAfter) {
  const [account,balance,externalAccounts]=await Promise.all([stripe.accounts.retrieve(accountId),stripe.balance.retrieve({stripeAccount:accountId}),allExternalAccounts(stripe,accountId)]);
  const instant=instantEligibility(account,balance,externalAccounts);
  const page=await stripe.payouts.list({limit:25,expand:['data.destination','data.balance_transaction'],...(startingAfter?{starting_after:startingAfter}:{})},{stripeAccount:accountId});
  // Settlement pending and bank payouts in transit are different balances.
  let inTransitAmount=0,cursor;do {
    const p=await stripe.payouts.list({limit:100,...(cursor?{starting_after:cursor}:{})},{stripeAccount:accountId});
    inTransitAmount+=p.data.filter(v=>v.currency==='usd'&&['pending','in_transit'].includes(v.status)).reduce((sum,v)=>sum+v.amount,0);
    cursor=p.has_more?p.data.at(-1)?.id:undefined;
  }while(cursor);
  const sum=entries=>(entries||[]).filter(e=>e.currency==='usd').reduce((s,e)=>s+e.amount,0);
  const due=account.requirements?.currently_due||[];
  return {accountId,currency:'usd',availableAmount:sum(balance.available),pendingSettlementAmount:sum(balance.pending),inTransitAmount,instantAvailableAmount:instant.amount,instantDestination:instant.destination,payoutsEnabled:!!account.payouts_enabled,setupRequired:due.length>0||!account.details_submitted,verificationPending:(account.requirements?.pending_verification||[]).length>0,disabledReason:account.requirements?.disabled_reason||null,payoutSchedule:{day:'monday',hour:9,timeZone:'America/New_York'},updatedAt:new Date().toISOString(),bankAccounts:externalAccounts.filter(a=>a.object==='bank_account').map(a=>({...destinationSummary(a),isDefault:a.default_for_currency===true})),cards:externalAccounts.filter(a=>a.object==='card').map(a=>({...destinationSummary(a),isDefault:a.default_for_currency===true})),payouts:page.data.map(payoutSummary),nextCursor:page.has_more?page.data.at(-1)?.id:null};
}
module.exports={allExternalAccounts,destinationSummary,payoutSummary,instantEligibility,accountSessionComponents,createDriverAccountSession,payoutMethodSummary,walletSnapshot};
