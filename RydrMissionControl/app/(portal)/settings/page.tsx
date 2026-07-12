import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import AdminUsersPanel from "./AdminUsersPanel";
import CashHubBetaToggle from "./CashHubBetaToggle";

export default async function SettingsPage() {
  const session = await getAdminSession();
  const [cashHubConfigSnap, adminUsersSnap] = await Promise.all([
    adminDb.collection("platformConfig").doc("cashRydrHub").get().catch(() => null),
    adminDb.collection("missionControlAdmins").orderBy("email", "asc").limit(250).get().catch(() => null)
  ]);
  const cashHubConfig = cashHubConfigSnap?.data() ?? {};
  const adminUsers =
    adminUsersSnap?.docs.map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        uid: typeof data.uid === "string" ? data.uid : doc.id,
        email: typeof data.email === "string" ? data.email : "",
        status: typeof data.status === "string" ? data.status : "active",
        grantedByEmail: typeof data.grantedByEmail === "string" ? data.grantedByEmail : null,
        revokedByEmail: typeof data.revokedByEmail === "string" ? data.revokedByEmail : null
      };
    }) ?? [];
  const cashHubTermsAcceptanceEnabled = cashHubConfig.termsAcceptanceEnabled === true;
  const cashHubTermsVersion = typeof cashHubConfig.cashHubTermsVersion === "string" ? cashHubConfig.cashHubTermsVersion : null;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Settings</h1>
        <p className="mt-1 text-sm text-muted">Account and access information.</p>
      </div>

      <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
        <h2 className="mb-3 text-sm font-semibold text-ink">Signed in as</h2>
        <p className="text-sm text-ink">{session?.email}</p>
        <p className="mt-1 text-xs text-muted">Role: {session?.role}</p>
      </div>

      <CashHubBetaToggle initialEnabled={cashHubTermsAcceptanceEnabled} initialTermsVersion={cashHubTermsVersion} />

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
