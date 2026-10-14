import Link from "next/link";
import { redirect } from "next/navigation";
import { adminDb } from "@/lib/firebaseAdmin";
import { getAdminSession } from "@/lib/session";
import { toDateSafe } from "@/lib/format";
import PayoutActions from "./PayoutActions";
export const dynamic="force-dynamic";
export default async function DriverPayoutsPage() {
  if(!(await getAdminSession()))redirect("/login");
  const [issues,pending]=await Promise.all([
    adminDb.collection("driverPayouts").where("needsReview","==",true).limit(200).get(),
    adminDb.collection("driverPayouts").where("status","==","pending").count().get()
  ]);
  const jobs=issues.docs.map(doc=>({id:doc.id,...doc.data()})).sort((a:any,b:any)=>(toDateSafe(b.updatedAt)?.getTime()??0)-(toDateSafe(a.updatedAt)?.getTime()??0)) as Array<Record<string,any>>;
  return <div className="space-y-6">
    <div><h1 className="text-xl font-semibold text-ink">Driver payouts</h1><p className="mt-1 text-sm text-muted">Weekly bank payouts are initiated Mondays at 9:00 a.m. Eastern from settled, available USD funds. Bank arrival dates vary. Instant cash-out remains available.</p>
      <p className="mt-2 text-sm">{pending.data().count} payouts pending or in transit · {issues.size} issues shown (up to 200)</p></div>
    {!jobs.length&&<div className="rounded-lg border border-dashed border-line bg-white p-8 text-center text-muted">No driver payout issues need review.</div>}
    {jobs.map(job=><section key={job.id} className="space-y-3 rounded-lg border border-line bg-white p-4">
      <div className="flex flex-wrap items-center justify-between gap-2"><h2 className="font-semibold">{job.kind==="weekly"?`Week of ${job.weekDate}`:job.kind==="instant"?"Instant cash-out":job.kind==="policy"?"Weekly payout setup":"Stripe payout"}</h2>
        <span className="text-sm">{typeof job.amount==="number"?new Intl.NumberFormat("en-US",{style:"currency",currency:String(job.currency??"usd").toUpperCase()}).format(job.amount/100):"Amount not determined"}</span></div>
      {job.driverId&&<Link href={`/drivers/${encodeURIComponent(job.driverId)}`} className="text-sm underline">Driver {job.driverId}</Link>}
      <p className="text-sm text-rydr-red">{job.reason??"Payout requires review"}</p>
      <p className="text-xs text-muted">{job.reasonCode} · {job.status}{job.bankLast4?` · bank ending ${job.bankLast4}`:""}</p>
      {job.blockedByJobId&&<p className="text-sm">Blocked by payout job <code>{job.blockedByJobId}</code>. Recheck the earlier job first.</p>}
      {(job.parts??[]).map((part:any,i:number)=><div key={i} className="text-xs text-muted">{part.payoutId??"No confirmed Stripe payout ID"} · {(part.amount/100).toFixed(2)} {String(part.currency??"usd").toUpperCase()} · {part.status}{part.failureCode?` · ${part.failureCode}`:""}{part.arrivalDate?` · estimated arrival ${new Date(part.arrivalDate*1000).toLocaleDateString("en-US",{timeZone:"America/New_York"})}`:""}</div>)}
      <PayoutActions jobId={job.id}/>
      <p className="text-xs text-muted">Rechecking refreshes Stripe records or repairs weekly payout timing and does not initiate a new payout. An uncertain submission stays blocked until its outcome can be established.</p>
    </section>)}
  </div>;
}
