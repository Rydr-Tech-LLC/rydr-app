import { redirect } from "next/navigation";
import { getMissionControlSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import { isMissionControlRole } from "@/lib/missionControlAccess";
import AdminUsersPanel from "./AdminUsersPanel";
import CashHubBetaToggle from "./CashHubBetaToggle";
import PasswordChangeForm from "./PasswordChangeForm";
import RydrExecutiveBetaToggle from "./RydrExecutiveBetaToggle";

export default async function SettingsPage() {
  const session = await getMissionControlSession();
  if (!session) redirect("/login");

  if (session.role === "marketing") {
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-xl font-semibold text-ink">Settings</h1>
          <p className="mt-1 text-sm text-muted">Account and password settings.</p>
        </div>
        <AccountSummary email={session.email} role={session.role} />
        <PasswordChangeForm />
      </div>
    );
  }

  const [cashHubConfigSnap, executiveConfigSnap, adminUsersSnap] = await Promise.all([
    adminDb.collection("platformConfig").doc("cashRydrHub").get().catch(() => null),
    adminDb.collection("platformConfig").doc("rydrExecutive").get().catch(() => null),
    adminDb.collection("missionControlAdmins").orderBy("email", "asc").limit(250).get().catch(() => null)
  ]);
  const cashHubConfig = cashHubConfigSnap?.data() ?? {};
  const executiveConfig = executiveConfigSnap?.data() ?? {};
  const adminUsers =
    adminUsersSnap?.docs.map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        uid: typeof data.uid === "string" ? data.uid : doc.id,
        email: typeof data.email === "string" ? data.email : "",
        displayName: typeof data.displayName === "string" ? data.displayName : "",
        role: isMissionControlRole(data.role) ? data.role : "admin",
        status: typeof data.status === "string" ? data.status : "active",
        passwordStatus: typeof data.passwordStatus === "string" ? data.passwordStatus : "",
        createdLogin: data.createdLogin === true,
        grantedByEmail: typeof data.grantedByEmail === "string" ? data.grantedByEmail : null,
        revokedByEmail: typeof data.revokedByEmail === "string" ? data.revokedByEmail : null
      };
    }) ?? [];
  const cashHubTermsAcceptanceEnabled = cashHubConfig.termsAcceptanceEnabled === true;
  const cashHubTermsVersion = typeof cashHubConfig.cashHubTermsVersion === "string" ? cashHubConfig.cashHubTermsVersion : null;
  const rydrExecutiveEnabled = executiveConfig.enabled === true;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Settings</h1>
        <p className="mt-1 text-sm text-muted">Account and access information.</p>
      </div>

      <AccountSummary email={session.email} role={session.role} />

      <PasswordChangeForm />

      <CashHubBetaToggle initialEnabled={cashHubTermsAcceptanceEnabled} initialTermsVersion={cashHubTermsVersion} />

      <RydrExecutiveBetaToggle initialEnabled={rydrExecutiveEnabled} />

      <AdminUsersPanel admins={adminUsers} />

      <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
        <h2 className="mb-2 text-sm font-semibold text-ink">Future modules</h2>
        <p className="text-sm text-muted">
          Checkr Review Queue, Stripe Connect Monitoring, Ride Disputes, Refund Requests, Driver Appeals, Analytics,
          Promo Codes, Marketing, Community Moderation, Customer Support — add each as its own folder under
          <code className="ml-1 rounded bg-grouped px-1">app/(portal)/</code> plus a nav entry in{" "}
          <code className="rounded bg-grouped px-1">components/Sidebar.tsx</code>.
        </p>
      </div>
    </div>
  );
}

function AccountSummary({ email, role }: { email: string | null; role: string }) {
  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <h2 className="mb-3 text-sm font-semibold text-ink">Signed in as</h2>
      <p className="text-sm text-ink">{email}</p>
      <p className="mt-1 text-xs capitalize text-muted">Role: {role}</p>
    </div>
  );
}
