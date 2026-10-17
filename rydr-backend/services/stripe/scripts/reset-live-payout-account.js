'use strict';
const {modeProfile,profilePatch}=require('../stripeMode');
async function run({stripe,db,auth,uid,accountId,apply=false,fieldValue}) {
 const ref=db.collection('drivers').doc(uid),audit=db.collection('stripeConnectResets').doc(uid+'_'+accountId);
 const user=await auth.getUser(uid); // Existing login must remain present.
 const raw=(await ref.get()).data();if(!raw)throw Error('driver_not_found');
 const profile=modeProfile(raw,'live'),prior=(await audit.get()).data();
 const attemptState=(await db.collection('stripeConnectSetupAttempts').doc(uid).get()).data();
 if(attemptState?.accountId&&attemptState.accountId!==accountId)throw Error('setup_attempt_account_mismatch');
 if(!Number.isSafeInteger(attemptState?.generation||0)||(attemptState?.generation||0)<0)throw Error('invalid_setup_generation');
 if(prior?.status==='complete'&&!profile.stripeAccountId)return {alreadyReset:true,loginPreserved:true};
 if(profile.stripeAccountId!==accountId)throw Error('account_reference_changed');
 const idle=p=>!p.isOnline&&!p.online&&!p.hasActiveRide&&!p.activeRideId&&Number(p.availableBalance||0)===0&&Number(p.pendingPayouts||0)===0;
 if(!idle(profile))throw Error('driver_must_be_offline_and_settled');
 let account;try{account=await stripe.accounts.retrieve(accountId);}catch(e){if(e.code!=='resource_missing'||!prior)throw e;}
 if(account&&!account.deleted){
  if(account.charges_enabled||account.payouts_enabled)throw Error('active_account_requires_separate_review');
  if(account.type!=='express'||account.metadata?.uid!==uid||account.metadata?.stripeMode!=='live')throw Error('account_owner_mode_or_type_mismatch');
  const balance=await stripe.balance.retrieve({},{stripeAccount:accountId});
  if(['available','pending','connect_reserved','instant_available'].some(k=>(balance[k]||[]).some(v=>v.amount!==0)))throw Error('stripe_balance_not_zero');
  let cursor;do{const page=await stripe.payouts.list({limit:100,...(cursor?{starting_after:cursor}:{})},{stripeAccount:accountId});if(page.data.some(p=>['pending','in_transit'].includes(p.status)))throw Error('payout_in_flight');cursor=page.has_more?page.data.at(-1)?.id:null;if(page.has_more&&!cursor)throw Error('invalid_payout_page');}while(cursor);
 }
 const jobs=await db.collection('driverPayouts').where('accountId','==',accountId).get();
 if(jobs.docs.some(d=>!['paid','failed','canceled'].includes(d.data().status)))throw Error('payout_job_requires_review');
 if(!apply)return {ready:true,dryRun:true,uid,accountId,balancesZero:true,pendingPayouts:0,loginPreserved:true,email:user.email};
 if(!prior)await audit.set({uid,oldAccountId:accountId,status:'prepared',workspace:'live-beta',stripeMode:'live',oldPayoutState:{stripeConnectStatus:profile.stripeConnectStatus,stripePayoutsEnabled:profile.stripePayoutsEnabled,payoutBankLast4:profile.payoutBankLast4||null},createdAt:fieldValue.serverTimestamp()});
 // Re-read before destructive action. No Auth deletion or customer deletion exists here.
 if(!idle(modeProfile((await ref.get()).data(),'live')))throw Error('driver_state_changed');
 if(account&&!account.deleted){const result=await stripe.accounts.del(accountId,{idempotencyKey:'payout_only_reset_'+uid+'_'+accountId});if(!result.deleted)throw Error('stripe_deletion_not_confirmed');}
 await audit.set({status:'stripe_deleted',deletedAt:fieldValue.serverTimestamp()},{merge:true});
 await db.runTransaction(async tx=>{const snap=await tx.get(ref),current=snap.data(),p=modeProfile(current,'live');if(p.stripeAccountId!==accountId)throw Error('account_changed_after_deletion');
  const attempt=db.collection('stripeConnectSetupAttempts').doc(uid);const a=(await tx.get(attempt)).data();
  if(a?.accountId&&a.accountId!==accountId)throw Error('setup_attempt_account_mismatch');
  tx.set(ref,profilePatch(current,{stripeAccountId:null,stripeConnectStatus:'not_started',stripeChargesEnabled:false,stripePayoutsEnabled:false,stripeRequirementsDue:[],payoutsStepCompleted:false,payoutsStepCompletedAt:null,payoutBankName:null,payoutBankLast4:null,payoutCardName:null,payoutCardLast4:null,updatedAt:fieldValue.serverTimestamp()},'live'),{merge:true});
  // Fresh creation must not recover the deleted account from the old idempotency record.
  tx.set(attempt,{accountId:null,status:'reset',generation:(a?.generation||0)+1,previousAccountId:accountId,updatedAt:fieldValue.serverTimestamp()},{merge:true});
  tx.set(audit,{status:'complete',completedAt:fieldValue.serverTimestamp(),loginPreserved:true},{merge:true});
 });
 await auth.getUser(uid);
 return {reset:true,deletedAccountId:accountId,loginPreserved:true,auditPreserved:true};
}
module.exports={run};
if(require.main===module)(async()=>{
 require('dotenv').config();const admin=require('firebase-admin');const {getFirestore,FieldValue}=require('firebase-admin/firestore');
 if(!/^sk_live_/.test(process.env.STRIPE_SECRET_KEY_LIVE||''))throw Error('live_key_required');
 const app=admin.initializeApp({projectId:'rydrapp-c7ec1',credential:admin.credential.cert({projectId:process.env.FIREBASE_ADMIN_PROJECT_ID,clientEmail:process.env.FIREBASE_ADMIN_CLIENT_EMAIL,privateKey:process.env.FIREBASE_ADMIN_PRIVATE_KEY.replace(/\\n/g,'\n')})});
 const [uid,accountId]=process.argv.slice(2);if(!uid||!/^acct_\w+$/.test(accountId||''))throw Error('uid_and_account_required');
 const db=getFirestore(app,'live-beta');console.log(JSON.stringify(await run({stripe:require('stripe')(process.env.STRIPE_SECRET_KEY_LIVE,{apiVersion:'2024-06-20'}),db,auth:admin.auth(app),uid,accountId,apply:process.argv.includes('--apply'),fieldValue:FieldValue})));await db.terminate();
})().catch(e=>{console.error(e.code||e.message);process.exitCode=1});
