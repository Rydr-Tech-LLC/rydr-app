"use client";
import { useCallback, useEffect, useState } from "react";
import { KeyRound, RefreshCw, ShieldCheck, Mail } from "lucide-react";
import { useWorkspace } from "@/components/WorkspaceContext";
type Access={workspace:string;disabled:boolean;email:string|null;emailVerified:boolean;phoneLinked:boolean;providers:string[];lastSignIn:string|null;accountStatus:string;canRecover:boolean};
export default function AccountAccessSupport({uid,role}:{uid:string;role:"rider"|"driver"}){
 const workspace=useWorkspace(),[data,setData]=useState<Access|null>(null),[loading,setLoading]=useState(false),[sending,setSending]=useState(false),[error,setError]=useState(""),[message,setMessage]=useState("");
 const url=`/api/account-access/${role}/${encodeURIComponent(uid)}`;
 const refresh=useCallback(async()=>{
  setLoading(true);setError("");
  try{const res=await fetch(url,{cache:"no-store",headers:{"x-rydr-workspace":workspace}}),body=await res.json();if(!res.ok)throw new Error(body.error);setData(body);}
  catch(e){setError(e instanceof Error?e.message:"Unable to check account access.");}
  finally{setLoading(false);}
 },[url,workspace]);
 useEffect(()=>{setData(null);setMessage("");void refresh();},[refresh]);
 async function recover(){
  if(sending || !data?.canRecover)return;
  if(!window.confirm(workspace === "test" ? "Simulate recovery in Test? No email will be sent." : `Send a password reset to ${data.email} for this Live Beta ${role}? This will not clear Firebase SMS restrictions.`))return;
  setSending(true);setError("");setMessage("");
  try{const res=await fetch(url,{method:"POST",headers:{"Content-Type":"application/json","x-rydr-workspace":workspace},body:JSON.stringify({action:"send_recovery"})}),body=await res.json();if(!res.ok)throw new Error(body.error);setMessage(body.message);}
  catch(e){setError(e instanceof Error?e.message:"Unable to send recovery email.");}
  finally{setSending(false);}
 }
 return <section className="overflow-hidden rounded-2xl border border-line bg-white shadow-sm" aria-label="Account access and recovery">
  <div className="flex items-center justify-between gap-3 bg-gradient-to-r from-red-50 via-white to-purple-50 p-5"><div className="flex items-center gap-3"><KeyRound className="h-5 w-5 text-rydr-red"/><div><h2 className="font-semibold text-ink">Account access & recovery</h2><p className="text-xs text-muted">{workspace === "test"?"Test":"Live Beta"} · {role} sign-in support</p></div></div><button onClick={()=>void refresh()} disabled={loading || sending} aria-label="Refresh account access" className="rounded-lg border border-line bg-white p-2 disabled:opacity-40"><RefreshCw className={`h-4 w-4 ${loading?"animate-spin":""}`}/></button></div>
  <div className="space-y-4 p-5">
   {data && <><div className="grid gap-3 text-sm sm:grid-cols-2"><div className="rounded-xl bg-grouped p-3"><p className="text-xs text-muted">Firebase account</p><p className={`mt-1 flex items-center gap-2 font-semibold ${data.disabled?"text-rydr-red":"text-emerald-700"}`}><ShieldCheck className="h-4 w-4"/>{data.disabled?"Disabled":"Enabled"}</p></div><div className="rounded-xl bg-grouped p-3"><p className="text-xs text-muted">Linked sign-in methods</p><p className="mt-1 font-medium">{data.providers.map(p=>p === "password"?"Email & password":p === "phone"?"Phone SMS":p).join(", ") || "None linked"}</p></div></div><p className="text-xs text-muted">Last successful sign-in: {data.lastSignIn?new Date(data.lastSignIn).toLocaleString():"Not recorded"}. Account status: {data.accountStatus}.</p></>}
   <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-xs leading-relaxed text-amber-950"><p className="font-semibold">SMS restrictions are managed by Firebase</p><p className="mt-1">Firebase does not expose the current device/number block status or an admin SMS-unblock action. An enabled account and verified identity can still be blocked from requesting codes. Stop SMS retries and use a linked email or social sign-in method. Resetting a password does not remove SMS restrictions or account holds.</p></div>
   {data?.disabled && <p className="text-xs text-rydr-red">Review the account’s access restrictions before recovery. This panel cannot override a disabled account.</p>}
   {error && <p role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-rydr-red">{error}</p>}{message && <p role="status" className="rounded-xl bg-emerald-50 p-3 text-sm text-emerald-800">{message}</p>}
   <button onClick={()=>void recover()} disabled={!data?.canRecover || loading || sending} className="flex items-center gap-2 rounded-xl bg-gradient-to-r from-rydr-red to-purple-600 px-4 py-3 text-sm font-semibold text-white disabled:opacity-40"><Mail className="h-4 w-4"/>{sending?"Processing…":workspace === "test"?"Simulate recovery email":"Send recovery email"}</button>
   {data && !data.canRecover && !data.disabled && <p className="text-xs text-muted">Recovery requires a linked email/password method. Use the account’s existing sign-in provider.</p>}
  </div>
 </section>;
}
