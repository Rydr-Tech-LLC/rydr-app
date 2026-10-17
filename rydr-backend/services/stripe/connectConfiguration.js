'use strict';
const {PayoutError}=require('./driverPayouts');
function newAccountConfiguration(env,workspace) {
 const setting=workspace==='test'?env.STRIPE_CONNECT_MANAGED_SETUP_TEST:env.STRIPE_CONNECT_MANAGED_SETUP_LIVE;
 // Activation is explicit and independent per workspace. Existing accounts are never replaced.
 return (setting==='true' || workspace==='test' && setting!=='false')?{controller:{fees:{payer:'application'},losses:{payments:'application'},requirement_collection:'application',stripe_dashboard:{type:'none'}}}:{type:'express'};
}
function isManagedAccount(account) {
 return account?.controller?.requirement_collection==='application' && account?.controller?.stripe_dashboard?.type==='none';
}
function setupConfiguration(account) {
 return {managed:isManagedAccount(account),requiresMigration:!isManagedAccount(account),stripeDashboard:account?.controller?.stripe_dashboard?.type||account?.type||'unknown'};
}
function assertManaged(account) {if(!isManagedAccount(account))throw new PayoutError('legacy_payout_account_requires_migration',409);}
module.exports={newAccountConfiguration,isManagedAccount,setupConfiguration,assertManaged};
