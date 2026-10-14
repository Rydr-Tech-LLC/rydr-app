import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
export async function POST(_request:NextRequest,context:{params:Promise<{jobId:string}>}) {
  const session=await getAdminSession();
  if(!session)return NextResponse.json({error:"Not authenticated"},{status:401});
  const {jobId}=await context.params;
  if(!/^(?:[a-f0-9]{64}|legacy_po_[A-Za-z0-9]+)$/.test(jobId))return NextResponse.json({error:"Invalid payout job"},{status:400});
  const base=process.env.STRIPE_BACKEND_BASE_URL||"https://rydr-stripe-backend.onrender.com",token=process.env.RYDR_INTERNAL_SERVICE_TOKEN;
  if(!base||!token)return NextResponse.json({error:"Stripe payout integration is not configured"},{status:503});
  try {
    const response=await fetch(`${base.replace(/\/+$/,"")}/internal/payout-jobs/${jobId}/reconcile`,{method:"POST",headers:{"Content-Type":"application/json","x-rydr-internal-token":token},body:"{}",signal:AbortSignal.timeout(30000)});
    const result=await response.json();
    if(!response.ok)return NextResponse.json({error:result.error??"Stripe reconciliation failed"},{status:409});
    await writeAuditLog({adminUid:session.uid,adminEmail:session.email??undefined,action:"Driver payout reconciled",targetType:"driverPayout",targetId:jobId});
    return NextResponse.json(result);
  } catch{return NextResponse.json({error:"Could not recheck Stripe. No new payout was initiated."},{status:503});}
}
