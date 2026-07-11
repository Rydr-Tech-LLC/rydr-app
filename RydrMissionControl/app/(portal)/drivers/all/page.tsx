import Link from "next/link";
import { adminDb } from "@/lib/firebaseAdmin";
import type { DriverRecord } from "@/lib/types";
import { fullName } from "@/lib/format";
import StatusPill from "@/components/StatusPill";
import { cashHubBillingDisplay, getCurrentCashHubBilling } from "@/lib/cashHubBilling";

export const dynamic = "force-dynamic";

export default async function AllDriversPage() {
  const [snap, configSnap] = await Promise.all([
    adminDb.collection("drivers").limit(500).get(),
    adminDb.collection("platformConfig").doc("cashRydrHub").get().catch(() => null)
  ]);
  const configData = configSnap?.data() ?? {};
  const cashHubGateConfig = {
    termsAcceptanceEnabled: configData.termsAcceptanceEnabled === true,
    cashHubTermsVersion: typeof configData.cashHubTermsVersion === "string" ? configData.cashHubTermsVersion : null
  };
  const drivers = snap.docs.map((doc) => ({ ...(doc.data() as DriverRecord), uid: doc.id }));
  const billingEntries = await Promise.all(
    drivers.map(async (driver) => [driver.uid, await getCurrentCashHubBilling(driver.uid)] as const)
  );
  const billingByUid = new Map(billingEntries);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Drivers</h1>
        <p className="mt-1 text-sm text-muted">{drivers.length} total drivers.</p>
      </div>

      <div className="overflow-hidden rounded-lg border border-line bg-white shadow-sm">
        <table className="w-full text-sm">
          <thead className="border-b border-line bg-grouped text-left text-xs font-medium text-muted">
            <tr>
              <th className="px-4 py-2.5">Name</th>
              <th className="px-4 py-2.5">Email</th>
              <th className="px-4 py-2.5">Vehicle</th>
              <th className="px-4 py-2.5">Status</th>
              <th className="px-4 py-2.5">Cash Hub</th>
              <th className="px-4 py-2.5" />
            </tr>
          </thead>
          <tbody className="divide-y divide-line">
            {drivers.map((driver) => {
              const cashHub = cashHubBillingDisplay(driver, billingByUid.get(driver.uid) ?? null, cashHubGateConfig);

              return (
                <tr key={driver.uid} className="hover:bg-grouped/60">
                  <td className="px-4 py-2.5 font-medium text-ink">{fullName(driver.firstName, driver.lastName)}</td>
                  <td className="px-4 py-2.5 text-muted">{driver.email ?? "—"}</td>
                  <td className="px-4 py-2.5 text-muted">
                    {[driver.vehicle?.year, driver.vehicle?.make, driver.vehicle?.model].filter(Boolean).join(" ") || "—"}
                  </td>
                  <td className="px-4 py-2.5">
                    <StatusPill status={driver.driverApprovalStatus ?? "pending"} />
                  </td>
                  <td className="px-4 py-2.5">
                    <div className="space-y-1">
                      <StatusPill status={cashHub.status} label={cashHub.label} />
                      <p className="max-w-52 text-[11px] leading-snug text-muted">{cashHub.detail}</p>
                    </div>
                  </td>
                  <td className="px-4 py-2.5 text-right">
                    <Link href={`/drivers/${driver.uid}`} className="text-xs font-semibold text-rydr-burgundy hover:underline">
                      Review
                    </Link>
                  </td>
                </tr>
              );
            })}
            {drivers.length === 0 && (
              <tr>
                <td colSpan={6} className="px-4 py-8 text-center text-muted">
                  No drivers yet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
