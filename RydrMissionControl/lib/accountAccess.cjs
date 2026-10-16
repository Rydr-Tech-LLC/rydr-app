"use strict";
const roles = new Set(["rider", "driver"]);
function summary(user, profile, workspace) {
 const providers = [...new Set((user.providerData || []).map(p => p.providerId))];
 return {workspace, disabled: !!user.disabled, email: user.email || null,
  emailVerified: !!user.emailVerified, phoneLinked: !!user.phoneNumber, providers,
  lastSignIn: user.metadata?.lastSignInTime || null,
  accountStatus: profile.accountStatus || profile.driverApprovalStatus || "unknown",
  canRecover: !user.disabled && !!user.email && providers.includes("password"),
  smsBlockStatus: "not_exposed_by_firebase", smsUnblockAvailable: false};
}
function createAccountAccess(deps) {
 async function context(role, uid) {
  const session = await deps.session();
  if (!session) return {response:{status:401,body:{error:"Not authenticated"}}};
  if (!roles.has(role) || typeof uid !== "string" || !uid || uid.length > 128 || uid.includes("/"))
   return {response:{status:400,body:{error:"Invalid account"}}};
  const workspace = await deps.workspace();
  if (!["test", "live-beta"].includes(workspace)) return {response:{status:400,body:{error:"Workspace is required"}}};
  const account = await deps.account(role, uid);
  if (!account) return {response:{status:404,body:{error:"Account not found in this workspace"}}};
  return {session,workspace,...account};
 }
 return {
  async get(role,uid) {
   const c = await context(role,uid); if(c.response) return c.response;
   return {status:200,body:summary(c.user,c.profile,c.workspace)};
  },
  async post(role,uid,body) {
   const c = await context(role,uid); if(c.response) return c.response;
   if(body?.action !== "send_recovery") return {status:400,body:{error:"Unsupported recovery action"}};
   const state = summary(c.user,c.profile,c.workspace);
   if(!state.canRecover) return {status:409,body:{error:state.disabled ? "This Firebase account is disabled. Review its access restrictions first; a password reset cannot enable it." : "Email/password sign-in is not linked. Use the linked sign-in provider or contact support."}};
   if(!await deps.reserve(role,uid)) return {status:429,body:{error:"A recovery request was made recently. Wait five minutes before sending another."}};
   // Test never creates a reset credential or sends a real email.
   if(c.workspace === "live-beta") await deps.send(c.user.email,role);
   await deps.audit({session:c.session,role,uid,workspace:c.workspace,simulated:c.workspace === "test"});
   return {status:200,body:{ok:true,simulated:c.workspace === "test",message:c.workspace === "test" ? "Test recovery simulated. No email was sent." : "Recovery email sent. This does not clear Firebase SMS restrictions or account holds."}};
  }
 };
}
module.exports = {createAccountAccess,summary};
