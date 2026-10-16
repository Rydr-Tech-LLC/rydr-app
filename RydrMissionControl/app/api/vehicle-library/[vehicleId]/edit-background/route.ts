import {currentWorkspace} from "@/lib/workspace";
import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { getAdminSession, SESSION_COOKIE } from "@/lib/session";
export const maxDuration = 300;
export async function POST(request: NextRequest, props: {params:Promise<{vehicleId:string}>}) {
 const session=await getAdminSession();if(!session)return NextResponse.json({error:"Not authenticated"},{status:401});
 const {vehicleId}=await props.params;const body=await request.json().catch(()=>null);
 if(!body||typeof body.prompt!=="string"||body.prompt.length>1500)return NextResponse.json({error:"Enter a prompt under 1500 characters."},{status:400});
 const cookie=(await cookies()).get(SESSION_COOKIE)?.value;
 try {
  const response=await fetch(`https://us-central1-${await currentWorkspace() === "test" ? "rydr-test-c7ec1" : "rydrapp-c7ec1"}.cloudfunctions.net/${await currentWorkspace() === "test" ? "" : "liveBeta-"}editVehicleLibraryBackground`,{method:"POST",headers:{Authorization:`Bearer ${cookie}`,"Content-Type":"application/json"},body:JSON.stringify({vehicleId,color:body.color,prompt:body.prompt}),signal:AbortSignal.timeout(270000),cache:"no-store"});
  if(!response.ok){const error=await response.json().catch(()=>({error:"Image editing service unavailable."}));return NextResponse.json(error,{status:response.status});}
  return new NextResponse(await response.arrayBuffer(),{headers:{"Content-Type":"image/jpeg","Cache-Control":"no-store"}});
 }catch{return NextResponse.json({error:"Image editing timed out or is unavailable. Your library image has not changed."},{status:502});}
}
