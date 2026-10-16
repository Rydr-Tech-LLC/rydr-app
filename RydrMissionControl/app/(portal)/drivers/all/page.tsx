import { evaluateDriverCompliance } from "../../../../../rydr-backend/firebase/functions/src/services/driverCompliancePolicy";
import DataTable from "@/components/DataTable";
import {WorkspaceLink as Link} from "@/components/WorkspaceContext";
import { getWorkspaceDb } from "@/lib/firebaseAdmin";
import type { DriverRecord } from "@/lib/types";
import { driverFullName, driverNameCollected } from "@/lib/format";
import StatusPill from "@/components/StatusPill";
import {
  cashHubBillingDisplay,
  getCurrentCashHubBilling,
} from "@/lib/cashHubBilling";

export const dynamic = "force-dynamic";

export default async function AllDriversPage() {
  const [snap, configSnap, complianceSnap] = await Promise.all([
    (await getWorkspaceDb()).collection("drivers").limit(500).get(),
    (await getWorkspaceDb())
      .collection("platformConfig")
      .doc("cashRydrHub")
      .get()
      .catch(() => null),
    (await getWorkspaceDb()).collection("platformConfig").doc("driverCompliance").get(),
  ]);
  const configData = configSnap?.data() ?? {};
  const cashHubGateConfig = {
    termsAcceptanceEnabled: configData.termsAcceptanceEnabled === true,
    cashHubTermsVersion:
      typeof configData.cashHubTermsVersion === "string"
        ? configData.cashHubTermsVersion
        : null,
  };
  const drivers = snap.docs.map((doc) => ({
    ...(doc.data() as DriverRecord),
    uid: doc.id,
  }));
  const billingEntries = await Promise.all(
    drivers.map(
      async (driver) =>
        [driver.uid, await getCurrentCashHubBilling(driver.uid)] as const,
    ),
  );
  const billingByUid = new Map(billingEntries);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Drivers</h1>
        <p className="mt-1 text-sm text-muted">
          {drivers.length} drivers loaded · Search, sort, and open a profile to
          review.
        </p>
      </div>

      <DataTable
        label="drivers"
        columns={[
          "Driver",
          "Email",
          "Vehicle",
          "Status",
          "Compliance",
          "Cash Hub",
          "Profile",
        ]}
        rows={drivers.map((driver) => {
          const cashHub = cashHubBillingDisplay(
            driver,
            billingByUid.get(driver.uid) ?? null,
            cashHubGateConfig,
          );
          const compliance = evaluateDriverCompliance(
            driver,
            complianceSnap.data() ?? {},
          );
          const vehicle = [
            driver.vehicle?.year,
            driver.vehicle?.make,
            driver.vehicle?.model,
          ]
            .filter(Boolean)
            .join(" ");
          const status = driver.driverApprovalStatus ?? "pending";
          const complianceLabel = !compliance.drivingAllowed
            ? "Driving hold"
            : compliance.needsReviewKinds.length
              ? "Dates need review"
              : compliance.expiringKinds.length
                ? "Expiring soon"
                : "Current";
          return {
            id: driver.uid,
            search: [
              driverFullName(driver),
              driver.email,
              vehicle,
              status,
              driver.vehicle?.vin,
              driver.vehicle?.plate,
            ].join(" "),
            values: [
              driverFullName(driver),
              driver.email ?? "",
              vehicle,
              status,
              complianceLabel,
              cashHub.label,
              "",
            ],
            cells: [
              <Link
                key="name"
                href={`/drivers/${driver.uid}`}
                className="font-semibold text-ink hover:text-rydr-red"
              >
                {driverFullName(driver)}
                {!driverNameCollected(driver) && (
                  <span className="block text-xs font-normal text-amber-700">
                    Name/DOB incomplete
                  </span>
                )}
              </Link>,
              driver.email ?? "—",
              vehicle || "—",
              <StatusPill key="status" status={status} />,
              <StatusPill
                key="compliance"
                status={
                  !compliance.drivingAllowed
                    ? "suspended"
                    : compliance.needsReviewKinds.length
                      ? "needs_attention"
                      : compliance.expiringKinds.length
                        ? "pending"
                        : "approved"
                }
                label={complianceLabel}
              />,
              <div key="billing">
                <StatusPill status={cashHub.status} label={cashHub.label} />
                <p className="mt-1 max-w-52 text-xs text-muted">
                  {cashHub.detail}
                </p>
              </div>,
              <Link
                key="link"
                href={`/drivers/${driver.uid}`}
                className="whitespace-nowrap text-xs font-semibold text-rydr-burgundy"
              >
                Open profile →
              </Link>,
            ],
          };
        })}
      />
    </div>
  );
}
