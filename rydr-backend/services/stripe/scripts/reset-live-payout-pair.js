'use strict';
// Explicit operator action only. Never called by an app route or scheduler.
const {run}=require('./reset-live-payout-account');
async function orphanPreflight({stripe,databases,accountId}) {
 const account=await stripe.accounts.retrieve(accountId);
 if(account.deleted||account.charges_enabled||account.payouts_enabled||account.controller?.is_controller!==true||account.controller?.losses?.payments!=='application'||Object.keys(account.metadata||{}).length)throw Error('orphan_account_requires_review');
 for(const db of databases)for(const collection of ['drivers','riders','publicDriverProfiles','stripeConnectSetupAttempts','driverPayouts']) {
  const snap=await db.collection(collection).get();
  if(snap.docs.some(d=>JSON.stringify(d.data()).includes(accountId)))throw Error('orphan_has_rydr_reference');
 }
 const balance=await stripe.balance.retrieve({},{stripeAccount:accountId});
 const nonzero=v=>Array.isArray(v)?v.some(nonzero):v&&typeof v==='object'?Object.entries(v).some(([k,x])=>k==='amount'?x!==0:nonzero(x)):false;
 if(balance.livemode!==true||nonzero(balance))throw Error('orphan_balance_requires_review');
 // This unowned account must be completely unused, not merely settled.
 for(const resource of ['payouts','charges','transfers']) {
  const page=await stripe[resource].list({limit:1},{stripeAccount:accountId});
  if(page.data.length||page.has_more)throw Error('orphan_financial_history_requires_review');
 }
 return {accountId,ready:true,balancesZero:true,pendingPayouts:0,unreferenced:true};
}
async function resetPair({stripe,db,databases,auth,uid,accountId,orphanId,fieldValue,apply=false}) {
 if(accountId===orphanId)throw Error('distinct_accounts_required');
 const orphanAudit=db.collection('stripeConnectResets').doc('unlinked_'+orphanId);
 const previous=(await orphanAudit.get()).data();
 const linked=await run({stripe,db,auth,uid,accountId,fieldValue});
 const orphan=previous?.status==='complete'?{accountId:orphanId,alreadyDeleted:true}:await orphanPreflight({stripe,databases,accountId:orphanId});
 if(!apply)return {dryRun:true,linked,orphan};
 // Both preflights must pass before either account is deleted.
 const result=await run({stripe,db,auth,uid,accountId,fieldValue,apply:true});
 if(previous?.status!=='complete') {
  await orphanPreflight({stripe,databases,accountId:orphanId});
  await orphanAudit.set({oldAccountId:orphanId,status:'prepared',workspace:'live-beta',stripeMode:'live',reason:'operator_requested_unused_account_cleanup',createdAt:fieldValue.serverTimestamp()},{merge:true});
  const deleted=await stripe.accounts.del(orphanId,{idempotencyKey:'unused_live_reset_'+orphanId});
  if(!deleted.deleted)throw Error('orphan_deletion_not_confirmed');
  await orphanAudit.set({status:'complete',deletedAt:fieldValue.serverTimestamp(),auditPreserved:true},{merge:true});
 }
 return {linked:result,orphan:{deletedAccountId:orphanId,deleted:true,auditPreserved:true}};
}
module.exports={orphanPreflight,resetPair};
if(require.main===module)(async()=>{
 require('dotenv').config();
 if(!/^sk_live_/.test(process.env.STRIPE_SECRET_KEY_LIVE||''))throw Error('live_key_required');
 const {initializeApp,cert}=require('firebase-admin/app'),{getFirestore,FieldValue}=require('firebase-admin/firestore');
 const app=initializeApp({projectId:'rydrapp-c7ec1',credential:cert({projectId:process.env.FIREBASE_ADMIN_PROJECT_ID,clientEmail:process.env.FIREBASE_ADMIN_CLIENT_EMAIL,privateKey:process.env.FIREBASE_ADMIN_PRIVATE_KEY.replace(/\\n/g,'\n')})});
 const [uid,accountId,orphanId]=process.argv.slice(2);
 if(!uid||![accountId,orphanId].every(x=>/^acct_\w+$/.test(x||'')))throw Error('uid_and_two_account_ids_required');
 const db=getFirestore(app,'live-beta'),legacy=getFirestore(app);
 console.log(JSON.stringify(await resetPair({stripe:require('stripe')(process.env.STRIPE_SECRET_KEY_LIVE,{apiVersion:'2024-06-20'}),db,databases:[db,legacy],auth:require('firebase-admin/auth').getAuth(app),uid,accountId,orphanId,fieldValue:FieldValue,apply:process.argv.includes('--apply')})));
 await Promise.all([db.terminate(),legacy.terminate()]);
})().catch(e=>{console.error(e.code||e.message);process.exitCode=1});
