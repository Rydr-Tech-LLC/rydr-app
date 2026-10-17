'use strict';
// Operator tool for an unused Live Beta Express account only. Dry-run by default.
// Never closes the old account or copies bank details/accepted agreements.
const {isManagedAccount,newAccountConfiguration}=require('../connectConfiguration');
const {modeProfile,profilePatch}=require('../stripeMode');
async function inspect({stripe,db,uid,expectedAccountId}) {
 const raw=(await db.collection('drivers').doc(uid).get()).data();
 if(!raw)throw Error('driver_not_found');
 const p=modeProfile(raw,'live');
 if(p.stripeAccountId!==expectedAccountId)throw Error('account_changed');
 if(p.isOnline||p.online||p.hasActiveRide||p.activeRideId||Number(p.availableBalance)||Number(p.pendingPayouts))throw Error('driver_not_idle_and_settled');
 const account=await stripe.accounts.retrieve(expectedAccountId);
 if(account.deleted||isManagedAccount(account)||account.type!=='express'||account.charges_enabled||account.payouts_enabled||account.tos_acceptance?.date)throw Error('only_unused_incomplete_express_supported');
 if(account.metadata?.uid!==uid||account.metadata?.stripeMode!=='live')throw Error('account_owner_or_mode_mismatch');
 const options={stripeAccount:expectedAccountId};
 const balance=await stripe.balance.retrieve({},options);
 if(['available','pending','connect_reserved','instant_available'].some(k=>(balance[k]||[]).some(v=>v.amount!==0)))throw Error('stripe_balance_not_zero');
 for(const resource of ['balanceTransactions','payouts','charges']) {
  if((await stripe[resource].list({limit:1},options)).data.length)throw Error('financial_history_requires_manual_reconciliation');
 }
 if((await stripe.transfers.list({destination:expectedAccountId,limit:1})).data.length)throw Error('transfer_history_requires_manual_reconciliation');
 for(const [collection,field,value] of [['driverPayouts','driverId',uid],['driverPayouts','accountId',expectedAccountId],['rides','driverId',uid],['rides','driverUid',uid]]) {
  if(!(await db.collection(collection).where(field,'==',value).limit(1).get()).empty)throw Error('ride_or_payout_history_requires_manual_reconciliation');
 }
 return {raw,profile:p,account};
}
async function run({stripe,db,uid,expectedAccountId,apply=false,operator,env,fieldValue}) {
 if(!env.STRIPE_SECRET_KEY_LIVE?.startsWith('sk_live_')||env.STRIPE_CONNECT_MANAGED_SETUP_LIVE!=='true')throw Error('live_managed_configuration_required');
 const {profile,account}=await inspect({stripe,db,uid,expectedAccountId});
 if(!apply)return {ready:true,dryRun:true,uid,oldAccountId:account.id,oldAccountRetained:true,bankDetailsMustBeReentered:true};
 if(!operator)throw Error('operator_required');
 const migrationRef=db.collection('stripeConnectMigrations').doc(uid+'_'+account.id);
 const prior=(await migrationRef.get()).data();
 if(prior?.status==='complete')return {alreadyCompleted:true,newAccountId:prior.newAccountId};
 // Stripe idempotency plus a durable candidate record prevents duplicate replacements.
 let candidate;
 if(prior?.newAccountId)candidate=await stripe.accounts.retrieve(prior.newAccountId);
 else {
  candidate=await stripe.accounts.create({...newAccountConfiguration(env,'live-beta'),country:'US',business_type:'individual',email:account.email,
   capabilities:{card_payments:{requested:true},transfers:{requested:true}},settings:{payouts:{schedule:{interval:'manual'}}},
   metadata:{uid,stripeMode:'live',replacesAccountId:account.id}}, {idempotencyKey:'rydr_managed_migrate_'+uid+'_'+account.id});
  await migrationRef.set({uid,oldAccountId:account.id,newAccountId:candidate.id,status:'candidate_created',operator,createdAt:fieldValue.serverTimestamp()},{merge:true});
 }
 if(!isManagedAccount(candidate)||candidate.metadata?.uid!==uid||candidate.metadata?.stripeMode!=='live'||candidate.deleted)throw Error('invalid_candidate');
 // Recheck external state after creation; an abort leaves an audited candidate, not a switched driver.
 await inspect({stripe,db,uid,expectedAccountId});
 await db.runTransaction(async tx=>{
  const ref=db.collection('drivers').doc(uid),snap=await tx.get(ref),raw=snap.data(),p=modeProfile(raw,'live');
  if(p.stripeAccountId!==account.id||p.isOnline||p.online||p.hasActiveRide||p.activeRideId||Number(p.availableBalance)||Number(p.pendingPayouts))throw Error('driver_changed_during_migration');
  tx.set(ref,profilePatch(raw,{stripeAccountId:candidate.id,stripeConnectStatus:'pending',stripeChargesEnabled:false,stripePayoutsEnabled:false,payoutsStepCompleted:false,payoutsStepCompletedAt:null,
   stripeRequirementsDue:candidate.requirements?.currently_due||[],payoutBankName:null,payoutBankLast4:null,payoutCardName:null,payoutCardLast4:null,updatedAt:fieldValue.serverTimestamp()},'live'),{merge:true});
  tx.set(migrationRef,{status:'complete',completedAt:fieldValue.serverTimestamp(),oldAccountRetained:true,operator},{merge:true});
 });
 return {migrated:true,uid,oldAccountId:account.id,newAccountId:candidate.id,oldAccountRetained:true,requiresDriverOnboarding:true};
}
module.exports={inspect,run};
if(require.main===module)(async()=>{
 require('dotenv').config();const admin=require('firebase-admin');const {getFirestore,FieldValue}=require('firebase-admin/firestore');
 const credential=admin.credential.cert({projectId:process.env.FIREBASE_ADMIN_PROJECT_ID,clientEmail:process.env.FIREBASE_ADMIN_CLIENT_EMAIL,privateKey:process.env.FIREBASE_ADMIN_PRIVATE_KEY.replace(/\\n/g,'\n')});
 const app=admin.initializeApp({projectId:'rydrapp-c7ec1',credential});const db=getFirestore(app,'live-beta');
 const stripe=require('stripe')(process.env.STRIPE_SECRET_KEY_LIVE,{apiVersion:'2024-06-20'});
 const [uid,expectedAccountId]=process.argv.slice(2);
 if(!uid||!/^acct_\w+$/.test(expectedAccountId||''))throw Error('usage: node scripts/migrate-unused-live-connect.js UID OLD_ACCOUNT_ID [--apply]');
 console.log(JSON.stringify(await run({stripe,db,uid,expectedAccountId,apply:process.argv.includes('--apply'),operator:process.env.MIGRATION_OPERATOR,env:process.env,fieldValue:FieldValue})));
 await db.terminate();
})().catch(e=>{console.error(e.code||e.message);process.exitCode=1});
