"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
export default function PayoutActions({jobId}:{jobId:string}) {
  const [busy,setBusy]=useState(false),[error,setError]=useState("");
  const router=useRouter();
  async function recheck() {
    setBusy(true);setError("");
    try {
      const response=await fetch(`/api/payouts/${encodeURIComponent(jobId)}/reconcile`,{method:"POST"});
      const result=await response.json();
      if(!response.ok)throw new Error(result.error||"Reconciliation failed");
      router.refresh();
    } catch(e){setError(e instanceof Error?e.message:"Reconciliation failed");}
    finally{setBusy(false);}
  }
  return <div className="space-y-2"><button disabled={busy} onClick={recheck} className="rounded border border-line px-3 py-2 text-sm">{busy?"Checking Stripe…":"Recheck with Stripe"}</button>{error&&<p role="alert" className="text-sm text-rydr-red">{error}</p>}</div>;
}
