"use strict";
const { createHash, randomUUID } = require("node:crypto");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const COLLECTION = "driverPayouts";
const LOCKS = "driverPayoutLocks";
const LOCK_WARNING_MS = 10 * 60 * 1000;

class PayoutError extends Error {
  constructor(code, status = 409) { super(code); this.code = code; this.status = status; }
}
function payoutJobId(accountId, kind, requestId) {
  return createHash("sha256").update(`${accountId}:${kind}:${requestId}`).digest("hex");
}
function easternWeekDate(instant) {
  const parts=new Intl.DateTimeFormat("en-US",{timeZone:"America/New_York",year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date(instant));
  const value=type=>parts.find(p=>p.type===type).value;
  const day=new Date(`${value("year")}-${value("month")}-${value("day")}T00:00:00Z`);
  day.setUTCDate(day.getUTCDate()-(day.getUTCDay()+6)%7);
  return day.toISOString().slice(0,10);
}
function availableUsdParts(balance) {
  const parts = [];
  for (const entry of balance.available ?? []) {
    if (entry.currency !== "usd" || !Number.isSafeInteger(entry.amount) || entry.amount <= 0) continue;
    const sources = Object.entries(entry.source_types ?? {}).filter(([, amount]) => Number.isSafeInteger(amount) && amount > 0);
    if (sources.length) {
      if (sources.some(([source]) => !["card", "bank_account", "fpx"].includes(source))) throw new PayoutError("unsupported_balance_source", 400);
      if (sources.reduce((sum, [, amount]) => sum + amount, 0) !== entry.amount) throw new PayoutError("inconsistent_available_balance", 400);
      for (const [sourceType, amount] of sources) parts.push({ amount, sourceType });
    } else parts.push({ amount: entry.amount, sourceType: "card" });
  }
  return parts;
}
function safeError(error) {
  return String(error?.code || error?.type || "payout_processing_failed").slice(0, 120);
}
function definiteRejection(error) {
  return error?.type === "StripeInvalidRequestError" || error?.type === "StripeCardError"
    || (error?.statusCode >= 400 && error?.statusCode < 500 && ![408,409,429].includes(error.statusCode));
}
function summary(parts) {
  if (parts.some(p => ["submitting", "prepared", "not_attempted"].includes(p.status))) return "needs_review";
  if (parts.some(p => ["failed", "canceled"].includes(p.status))) return "needs_review";
  if (parts.length && parts.every(p => p.status === "paid")) return "paid";
  return parts.length ? "pending" : "skipped";
}

class DriverPayoutService {
  constructor({ stripe, getDb, now = () => Date.now() }) { this.stripe = stripe; this.getDb = getDb; this.now = now; }
  jobs() { return this.getDb().collection(COLLECTION); }
  async preparePolicy(driverId) {
    const driver=(await this.getDb().collection("drivers").doc(driverId).get()).data();
    const accountId=driver?.stripeAccountId;
    if(!accountId)return {status:"skipped"};
    const id=payoutJobId(accountId,"policy","weekly-monday");
    const ref=this.jobs().doc(id);
    try {
      const account=await this.stripe.accounts.retrieve(accountId);
      if(account.country!=="US" || account.type!=="express")throw new PayoutError("unsupported_connect_account",400);
      if(account.metadata?.uid && account.metadata.uid!==driverId)throw new PayoutError("payout_account_owner_mismatch",400);
      if(account.settings?.payouts?.schedule?.interval!=="manual")await this.stripe.accounts.update(accountId,{settings:{payouts:{schedule:{interval:"manual"}}}});
      await ref.set({kind:"policy",driverId,accountId,status:"configured",needsReview:false,reason:null,reasonCode:null,updatedAt:FieldValue.serverTimestamp()},{merge:true});
      return {status:"configured"};
    } catch(error) {
      await ref.set({kind:"policy",driverId,accountId,status:"needs_review",needsReview:true,reasonCode:safeError(error),reason:`Weekly payout schedule setup failed: ${safeError(error)}`,updatedAt:FieldValue.serverTimestamp()},{merge:true});
      return {status:"needs_review"};
    }
  }
  async claim(jobId, initial) {
    const db = this.getDb(), ref = this.jobs().doc(jobId), owner = randomUUID();
    const result = await db.runTransaction(async tx => {
      const snap = await tx.get(ref); const existing = snap.data();
      if (existing && initial && (existing.amount !== initial.amount || existing.currency !== initial.currency || existing.accountId !== initial.accountId || existing.driverId !== initial.driverId || existing.destination !== initial.destination)) {
        throw new PayoutError("payout_request_parameters_changed");
      }
      const job = existing ?? initial;
      if (!job) throw new PayoutError("payout_job_not_found",404);
      if (existing && existing.status !== "queued") return { job, acquired: false };
      const driver = (await tx.get(db.collection("drivers").doc(job.driverId))).data();
      if (!job.accountId || driver?.stripeAccountId !== job.accountId) {
        tx.set(ref, { ...job, status: "needs_review", needsReview: true, reason: "Driver has no matching Stripe Connect account", reasonCode: "connect_account_missing", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
        return { job: { ...job, status: "needs_review" }, acquired: false };
      }
      const lockRef = db.collection(LOCKS).doc(job.accountId);
      const lock = (await tx.get(lockRef)).data();
      if (lock) {
        // Never expire a monetary operation's lock without reconciliation.
        if (this.now() - (lock.createdAt?.toMillis?.() ?? 0) > LOCK_WARNING_MS) {
          tx.set(ref, { ...job, status: "needs_review", needsReview: true, reason: "An earlier payout is unresolved. Recheck that payout with Stripe first.", reasonCode: "unresolved_payout_lock", blockedByJobId: lock.jobId, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
          return { job: { ...job, status: "needs_review" }, acquired: false };
        }
        throw new PayoutError("payout_in_progress");
      }
      tx.set(lockRef, { jobId, owner, createdAt: Timestamp.fromMillis(this.now()) });
      tx.set(ref, { ...job, status: "processing", needsReview: false, reason: null, reasonCode: null, owner, startedAt: Timestamp.fromMillis(this.now()), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      return { job: { ...job, owner, status: "processing" }, acquired: true };
    });
    return { ...result, ref, owner };
  }
  async release(jobId, accountId, owner) {
    const db = this.getDb(), lockRef = db.collection(LOCKS).doc(accountId);
    await db.runTransaction(async tx => {
      const lock = (await tx.get(lockRef)).data();
      if (lock?.jobId === jobId && (!owner || lock.owner === owner)) tx.delete(lockRef);
    });
  }
  async markIssue(ref, code, reason) {
    await ref.set({ status: "needs_review", needsReview: true, reasonCode: code, reason, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  }
  async processWeekly(jobId) {
    const claim = await this.claim(jobId);
    if (!claim.acquired) return claim.job.status;
    const { job, ref, owner } = claim;
    if (job.kind !== "weekly") {
      await this.markIssue(ref,"invalid_job_kind","Weekly dispatch received an invalid payout job");
      await this.release(jobId,job.accountId,owner); return "needs_review";
    }
    let submissionStarted = false;
    try {
      if (job.weekDate !== easternWeekDate(this.now())) throw new PayoutError("weekly_payout_job_outside_current_week",400);
      const account = await this.stripe.accounts.retrieve(job.accountId);
      if (account.metadata?.uid && account.metadata.uid !== job.driverId) throw new PayoutError("payout_account_owner_mismatch",400);
      if (account.country !== "US" || account.type !== "express") throw new PayoutError("unsupported_connect_account",400);
      if (account.settings?.payouts?.schedule?.interval !== "manual") {
        await this.stripe.accounts.update(job.accountId,{settings:{payouts:{schedule:{interval:"manual"}}}});
      }
      const balance = await this.stripe.balance.retrieve({}, {stripeAccount:job.accountId});
      const amounts = availableUsdParts(balance);
      if (!amounts.length) {
        await ref.set({status:"skipped",reason:"No settled USD balance available",amount:0,parts:[],updatedAt:FieldValue.serverTimestamp()},{merge:true});
        await this.release(jobId,job.accountId,owner); return "skipped";
      }
      if (!account.payouts_enabled) throw new PayoutError("payouts_not_enabled",400);
      // Paginate bank accounts; a debit card must never become the ACH destination.
      const banks=[];
      let startingAfter;
      do {
        const page = await this.stripe.accounts.listExternalAccounts(job.accountId,{object:"bank_account",limit:100,...(startingAfter?{starting_after:startingAfter}:{})});
        banks.push(...page.data);
        startingAfter=page.has_more?page.data.at(-1)?.id:undefined;
      } while (startingAfter);
      const eligible=banks.filter(bank=>bank.object==="bank_account" && typeof bank.id==="string" && bank.id.startsWith("ba_") && bank.currency==="usd" && bank.country==="US" && !["errored","verification_failed"].includes(bank.status) && (!bank.available_payout_methods || bank.available_payout_methods.includes("standard")));
      const bank=eligible.find(bank=>bank.default_for_currency) ?? (eligible.length===1?eligible[0]:null);
      if (!bank) throw new PayoutError("valid_default_bank_account_required",400);
      const parts=amounts.map((part,i)=>({...part,destination:bank.id,currency:"usd",status:"prepared",payoutId:null,idempotencyKey:`weekly_${jobId}_${i}`}));
      await ref.set({parts,amount:amounts.reduce((sum,part)=>sum+part.amount,0),bankLast4:bank.last4??null,updatedAt:FieldValue.serverTimestamp()},{merge:true});
      for (let i=0;i<parts.length;i++) {
        await this.setPart(jobId,i,{status:"submitting",submissionStartedAt:Timestamp.fromMillis(this.now())},owner);
        submissionStarted=true;
        try {
          const payout=await this.stripe.payouts.create({amount:parts[i].amount,currency:"usd",method:"standard",source_type:parts[i].sourceType,destination:bank.id,metadata:{uid:job.driverId,source:"driver_weekly_ach",payoutJobId:jobId,payoutPart:String(i),weekDate:job.weekDate}}, {stripeAccount:job.accountId,idempotencyKey:parts[i].idempotencyKey});
          await this.recordPayout(jobId,job.accountId,payout);
          submissionStarted=false;
        } catch(error) {
          if (definiteRejection(error)) {
            await this.setPart(jobId,i,{status:"failed",failureCode:safeError(error)});
            submissionStarted=false;
          }
          throw error;
        }
      }
      await this.release(jobId,job.accountId,owner);
      return (await ref.get()).data().status;
    } catch(error) {
      await this.markIssue(ref,safeError(error),submissionStarted?"Stripe's payout response is uncertain. Reconcile before any new payout.":`Weekly payout blocked: ${safeError(error)}`);
      const current=(await ref.get()).data();
      if(current.parts) await ref.set({parts:current.parts.map(p=>p.status==="prepared"?{...p,status:"not_attempted"}:p)},{merge:true});
      if (!submissionStarted) await this.release(jobId,job.accountId,owner);
      return "needs_review";
    }
  }
  async setPart(jobId,index,update,owner=null) {
    const db=this.getDb(),ref=this.jobs().doc(jobId);
    await db.runTransaction(async tx=>{
      const job=(await tx.get(ref)).data();
      if(owner) {
        const lock=(await tx.get(db.collection(LOCKS).doc(job.accountId))).data();
        if(job.owner!==owner || lock?.owner!==owner) throw new PayoutError("payout_worker_claim_lost");
      }
      const parts=job.parts.map((p,i)=>i===index?{...p,...update}:p);
      tx.update(ref,{parts,updatedAt:FieldValue.serverTimestamp()});
    });
  }
  async recordPayout(jobId,accountId,payout) {
    const db=this.getDb(),ref=this.jobs().doc(jobId);
    await db.runTransaction(async tx=>{
      const job=(await tx.get(ref)).data();
      if (!job || job.accountId!==accountId) return;
      const i=job.kind==="instant"?0:Number(payout.metadata?.payoutPart);
      const part=job.parts?.[i];
      if (!Number.isInteger(i) || !part || part.amount!==payout.amount || part.currency!==payout.currency || (payout.method && payout.method!==(job.kind==="instant"?"instant":"standard")) || (job.kind==="weekly" && payout.source_type && payout.source_type!==part.sourceType) || (part.destination && part.destination!==payout.destination) || (job.kind!=="instant" && payout.metadata?.payoutJobId!==jobId) || (job.kind==="instant" && payout.metadata?.uid!==job.driverId)) throw new PayoutError("payout_reconciliation_mismatch");
      const parts=job.parts.map((p,index)=>index===i?{...p,payoutId:payout.id,status:payout.status,arrivalDate:payout.arrival_date??null,failureCode:payout.failure_code??null}:p);
      let status=summary(parts);
      if(status==="needs_review" && job.status==="processing" && parts.some(p=>["prepared","submitting"].includes(p.status)) && !parts.some(p=>["failed","canceled"].includes(p.status))) status="processing";
      tx.set(db.collection("driverPayoutStripeLinks").doc(payout.id),{jobId,accountId});
      tx.update(ref,{parts,status,needsReview:status==="needs_review",...(status==="needs_review"?{reason:"Payout failed, was canceled, or still has an unresolved submission",reasonCode:"payout_needs_review"}:{reason:null,reasonCode:null}),updatedAt:FieldValue.serverTimestamp()});
    });
  }
  async instant({driverId,accountId,amount,currency,requestId,destination}) {
    const jobId=payoutJobId(accountId,"instant",requestId);
    const claim=await this.claim(jobId,{driverId,accountId,kind:"instant",amount,currency,requestId,...(destination?{destination}:{}),status:"queued",createdAt:Timestamp.fromMillis(this.now())});
    if (!claim.acquired) {
      const job=(await claim.ref.get()).data();
      if (job.parts?.[0]?.payoutId) {
        const payout=await this.stripe.payouts.retrieve(job.parts[0].payoutId,{stripeAccount:accountId});
        await this.recordPayout(jobId,accountId,payout);return payout;
      }
      throw new PayoutError(job.reasonCode??"payout_in_progress");
    }
    let submissionStarted=false;
    try {
      const account=await this.stripe.accounts.retrieve(accountId);
      if (account.metadata?.uid && account.metadata.uid !== driverId) throw new PayoutError("payout_account_owner_mismatch",400);
      if (!account.payouts_enabled) throw new PayoutError("payouts_not_enabled",400);
      if(destination){
        const {allExternalAccounts,instantEligibility}=require('./driverWallet');
        const [balance,external]=await Promise.all([this.stripe.balance.retrieve({stripeAccount:accountId}),allExternalAccounts(this.stripe,accountId)]);
        const eligibility=instantEligibility(account,balance,external.filter(a=>a.id===destination));
        if(currency!=="usd" || eligibility.amount<amount || !eligibility.destination)throw new PayoutError("instant_payout_not_eligible",400);
      }
      const key=destination?`instant_payout_v2_${accountId}_${requestId}`:`instant_payout_${accountId}_${requestId}`; // Preserve the shipped client's existing idempotency namespace.
      await claim.ref.set({parts:[{amount,currency,status:"prepared",payoutId:null,idempotencyKey:key,sourceType:"card",...(destination?{destination}:{})}],updatedAt:FieldValue.serverTimestamp()},{merge:true});
      await this.setPart(jobId,0,{status:"submitting",submissionStartedAt:Timestamp.fromMillis(this.now())},claim.owner);submissionStarted=true;
      const payout=await this.stripe.payouts.create({amount,currency,method:"instant",...(destination?{destination}:{}),metadata:{uid:driverId,source:"driver_wallet_instant_pay"}},{stripeAccount:accountId,idempotencyKey:key});
      await this.recordPayout(jobId,accountId,payout);submissionStarted=false;
      await this.release(jobId,accountId,claim.owner);return payout;
    } catch(error) {
      if (submissionStarted && definiteRejection(error)) {
        await this.setPart(jobId,0,{status:"failed",failureCode:safeError(error)});submissionStarted=false;
      }
      error.payoutSubmissionUncertain = submissionStarted;
      await this.markIssue(claim.ref,safeError(error),submissionStarted?"Instant payout response is uncertain. Reconcile with Stripe before another payout.":`Instant payout blocked: ${safeError(error)}`);
      if (!submissionStarted) await this.release(jobId,accountId,claim.owner);
      throw error;
    }
  }
  async reconcile(jobId) {
    const ref=this.jobs().doc(jobId),job=(await ref.get()).data();
    if (!job) throw new PayoutError("payout_job_not_found",404);
    if(job.kind==="policy")return (await this.preparePolicy(job.driverId)).status;
    if(job.kind==="legacy" && job.payoutId) {
      const payout=await this.stripe.payouts.retrieve(job.payoutId,{stripeAccount:job.accountId});
      const needsReview=["failed","canceled"].includes(payout.status);
      await ref.set({status:needsReview?"needs_review":payout.status,needsReview,updatedAt:FieldValue.serverTimestamp()},{merge:true});
      return needsReview?"needs_review":payout.status;
    }
    const interrupted=job.status==="processing" && this.now()-(job.startedAt?.toMillis?.()??this.now())>LOCK_WARNING_MS;
    if (!job.parts?.length) {
      if(interrupted || job.status==="needs_review") {
        await ref.set({status:"needs_review",needsReview:true,owner:null,...(interrupted?{reasonCode:"payout_worker_interrupted",reason:"Payout worker stopped before a submission was prepared; inspect this week's payout before retrying"}:{}),updatedAt:FieldValue.serverTimestamp()},{merge:true});
        await this.release(jobId,job.accountId);
        return "needs_review";
      }
      return job.status;
    }
    if(interrupted) {
      await ref.set({owner:null,parts:job.parts.map(p=>p.status==="prepared"?{...p,status:"not_attempted"}:p),status:"needs_review",needsReview:true,reason:"Payout worker was interrupted; reconcile submitted payouts before further withdrawals",reasonCode:"payout_worker_interrupted",updatedAt:FieldValue.serverTimestamp()},{merge:true});
    }
    for (let i=0;i<job.parts.length;i++) {
      const part=job.parts[i];
      if (part.payoutId) {
        const payout=await this.stripe.payouts.retrieve(part.payoutId,{stripeAccount:job.accountId});
        await this.recordPayout(jobId,job.accountId,payout);
      } else if (part.status==="submitting") {
        // Read-only discovery. A missing response is never permission to submit again,
        // especially after Stripe's idempotency retention window has elapsed.
        let startingAfter,found=null;
        do {
          const page=await this.stripe.payouts.list({limit:100,created:{gte:Math.floor((part.submissionStartedAt?.toMillis?.()??job.startedAt.toMillis())/1000)-60},...(startingAfter?{starting_after:startingAfter}:{})},{stripeAccount:job.accountId});
          found=page.data.find(p=>p.metadata?.payoutJobId===jobId && p.metadata?.payoutPart===String(i));
          startingAfter=!found&&page.has_more?page.data.at(-1)?.id:undefined;
        } while(startingAfter);
        if(found)await this.recordPayout(jobId,job.accountId,found);
      }
    }
    const current=(await ref.get()).data();
    if (!current.parts.some(p=>["submitting","prepared"].includes(p.status))) await this.release(jobId,job.accountId);
    return current.status;
  }
  async webhook(event) {
    const accountId=event.account,p=event.data.object;
    if (!accountId) return;
    const payout=await this.stripe.payouts.retrieve(p.id,{stripeAccount:accountId});
    const jobId=payout.metadata?.payoutJobId ?? (await this.getDb().collection("driverPayoutStripeLinks").doc(payout.id).get()).data()?.jobId;
    if(jobId) {
      await this.recordPayout(jobId,accountId,payout);
      const job=(await this.jobs().doc(jobId).get()).data();
      if(job && !job.parts?.some(part=>["submitting","prepared"].includes(part.status))) await this.release(jobId,accountId);
    } else if(["failed","canceled"].includes(payout.status)) {
      const drivers=await this.getDb().collection("drivers").where("stripeAccountId","==",accountId).limit(1).get();
      await this.jobs().doc(`legacy_${payout.id}`).set({kind:"legacy",driverId:drivers.docs[0]?.id??null,accountId,status:"needs_review",needsReview:true,amount:payout.amount,currency:payout.currency,reasonCode:payout.failure_code??"payout_canceled",reason:"Stripe reported a failed or canceled payout outside the new weekly job flow",payoutId:payout.id,updatedAt:FieldValue.serverTimestamp()},{merge:true});
    }
  }
}
module.exports={DriverPayoutService,PayoutError,payoutJobId,availableUsdParts,definiteRejection,summary,easternWeekDate};
