import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { currentWorkspace } from "@/lib/workspace";
import { getWorkspaceAuth, getWorkspaceDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";
import { notificationService } from "@/src/services/notifications/NotificationService";
import { createAccountAccess } from "@/lib/accountAccess.cjs";
export const dynamic = "force-dynamic";
const access = createAccountAccess({
 session:getAdminSession, workspace:currentWorkspace,
 account:async(role:string,uid:string)=>{
  const profile = await (await getWorkspaceDb()).collection(role === "driver" ? "drivers" : "riders").doc(uid).get();
  if(!profile.exists)return null;
  try{return {profile:profile.data() || {},user:await (await getWorkspaceAuth()).getUser(uid)};}
  catch(error){if((error as {code?:string}).code === "auth/user-not-found")return null;throw error;}
 },
 reserve:async(role:string,uid:string)=>{
  const db=await getWorkspaceDb(),ref=db.collection("authSupport").doc(`${role}_${uid}`),now=Date.now();
  return db.runTransaction(async tx=>{
   const current=await tx.get(ref);
   if(Number(current.data()?.recoveryRetryAfter || 0)>now)return false;
   tx.set(ref,{recoveryRetryAfter:now+300_000,recoveryRequestedAt:FieldValue.serverTimestamp()},{merge:true});return true;
  });
 },
 send:async(email:string,role:string)=>{
  const link=await (await getWorkspaceAuth()).generatePasswordResetLink(email);
  const result=await notificationService.sendGenericEmail({to:email,
   subject:`Recover your Rydr ${role} account`,title:"Sign in with email",eyebrow:"Rydr Live Beta · Account support",
   body:`Mission Control requested a password reset for your Live Beta ${role} account. Use this link to set your password, then choose email login in the app.\n\n${link}\n\nYour Test account is separate. This does not change your verification, account holds, or Firebase SMS restrictions. If you did not request help, ignore this email.`});
  if(!result.ok)throw new Error("Recovery email could not be sent. Try later or contact support.");
 },
 audit:async(input:{session:{uid:string;email?:string|null};role:string;uid:string;workspace:string;simulated:boolean})=>{
  await writeAuditLog({adminUid:input.session.uid,adminEmail:input.session.email || undefined,
   action:input.simulated ? "Account recovery simulated" : "Account recovery email sent",targetType:input.role as "rider"|"driver",targetId:input.uid,
   metadata:{workspace:input.workspace,simulated:input.simulated,smsBlockCleared:false}});
 }
});
type Params={params:Promise<{role:string;uid:string}>};
export async function GET(_request:NextRequest,props:Params){
 const {role,uid}=await props.params;
 try {const result=await access.get(role,uid);return NextResponse.json(result.body,{status:result.status,headers:{"Cache-Control":"no-store"}});}
 catch {return NextResponse.json({error:"Unable to check authentication. Try again later."},{status:503});}
}
export async function POST(request:NextRequest,props:Params){
 if(request.headers.get("origin") !== request.nextUrl.origin)return NextResponse.json({error:"Same-origin request required"},{status:403});
 const {role,uid}=await props.params;
 try {const result=await access.post(role,uid,await request.json().catch(()=>null));return NextResponse.json(result.body,{status:result.status});}
 catch(error) {
  const failure=error as {code?:string;message?:string};
  console.error("[accountAccess] recovery_failed",{code:failure.code || "unknown",message:(failure.message || "Unknown failure").replace(/https?:\/\/[^\s]+/g,"[redacted URL]")});
  return NextResponse.json({error:"Recovery could not be completed. Try later or contact support."},{status:503});
 }
}
