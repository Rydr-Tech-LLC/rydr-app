'use strict';
const {isManagedAccount}=require('./connectConfiguration');
async function migrationReadiness({stripe,profile}) {
 if(!profile.stripeAccountId)return {requiresMigration:false,blockers:[],action:'new_managed_account'};
 const account=await stripe.accounts.retrieve(profile.stripeAccountId);
 if(isManagedAccount(account))return {requiresMigration:false,blockers:[],action:'already_managed'};
 const balance=await stripe.balance.retrieve({}, {stripeAccount:account.id});
 const blockers=[];
 if([...(balance.available||[]),...(balance.pending||[]),...(balance.connect_reserved||[])].some(v=>v.amount!==0))blockers.push('unsettled_stripe_balance');
 let cursor;
 do {const page=await stripe.payouts.list({limit:100,...(cursor?{starting_after:cursor}:{})},{stripeAccount:account.id});
  if(page.data.some(p=>['pending','in_transit'].includes(p.status)))blockers.push('payout_in_flight');
  cursor=page.has_more?page.data.at(-1)?.id:null;
 }while(cursor);
 if(['availableBalance','pendingPayouts'].some(k=>Number(profile[k]||0)!==0))blockers.push('unsettled_driver_earnings');
 if(profile.hasActiveRide || profile.activeRideId || profile.isOnline || profile.online)blockers.push('driver_must_be_offline_without_active_ride');
 // This is deliberately not an authorization to swap IDs. Transfers, disputed
 // charges, payout jobs and historical ride links need an operator's review.
 return {requiresMigration:true,blockers:[...new Set(blockers)],action:'review_replacement_plan',automaticMigrationAllowed:false,
  steps:['reconcile_rides_transfers_and_payout_jobs','retain_old_account_and_financial_history','create_new_managed_account_after_approval','driver_reenters_bank_and_card_and_accepts_agreement','verify_new_account_payout_readiness','audited_switch_of_future_earnings_destination']};
}
module.exports={migrationReadiness};
