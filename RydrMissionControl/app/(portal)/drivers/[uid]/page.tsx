import { notFound } from "next/navigation";
import Link from "next/link";
import { adminDb } from "@/lib/firebaseAdmin";
import {
  driverConnectStatus,
  driverDocumentBackUrl,
  driverDocumentUrl,
  driverIdentityStatus,
  evaluateDriverRequirements,
  type DriverRecord
} from "@/lib/types";
import { driverFullName, driverNameCollected, toDateSafe } from "@/lib/format";
import StatusPill from "@/components/StatusPill";
import ImageViewer from "@/components/ImageViewer";
import RequirementChecklist from "@/components/RequirementChecklist";
import TripSafetyAnalytics from "@/components/TripSafetyAnalytics";
import { findActiveRideForDriver } from "@/lib/activeRides";
import { cashHubBillingDisplay, formatCents, getCurrentCashHubBilling } from "@/lib/cashHubBilling";
import { buildDriverOnboardingProgress } from "@/lib/driverOnboardingProgress";
import DriverActions from "./DriverActions";
import DriverOnboardingProgressLive from "./DriverOnboardingProgressLive";
import DriverProfileAdminTools, { type DriverProfileAdminInitial } from "./DriverProfileAdminTools";

export const dynamic = "force-dynamic";

export default async function DriverReviewPage({ params }: { params: { uid: string } }) {
  const [snap, activeRide, cashHubBilling, cashHubConfigSnap] = await Promise.all([
    adminDb.collection("drivers").doc(params.uid).get(),
    findActiveRideForDriver(params.uid),
    getCurrentCashHubBilling(params.uid),
    adminDb.collection("platformConfig").doc("cashRydrHub").get().catch(() => null)
  ]);
  if (!snap.exists) notFound();
  const cashHubConfigData = cashHubConfigSnap?.data() ?? {};
  const cashHubGateConfig = {
    termsAcceptanceEnabled: cashHubConfigData.termsAcceptanceEnabled === true,
    cashHubTermsVersion: typeof cashHubConfigData.cashHubTermsVersion === "string" ? cashHubConfigData.cashHubTermsVersion : null
  };

  const driver = { ...(snap.data() as DriverRecord), uid: snap.id };
  const { checks, missing } = evaluateDriverRequirements(driver);
  const createdAt = toDateSafe(driver.createdAt);
  const dob = toDateSafe(driver.dob);
  const licenseUrl = driverDocumentUrl(driver, "license");
  const licenseBackUrl = driverDocumentBackUrl(driver, "license");
  const insuranceUrl = driverDocumentUrl(driver, "insurance");
  const insuranceBackUrl = driverDocumentBackUrl(driver, "insurance");
  const registrationUrl = driverDocumentUrl(driver, "registration");
  const registrationBackUrl = driverDocumentBackUrl(driver, "registration");
  const identityStatus = driverIdentityStatus(driver);
  const connectStatus = driverConnectStatus(driver);
  const cashHubDisplay = cashHubBillingDisplay(driver, cashHubBilling, cashHubGateConfig);
  const onboardingProgress = buildDriverOnboardingProgress(driver);
  const adminProfileInitial: DriverProfileAdminInitial = {
    firstName: driver.firstName ?? driver.legalFirstName ?? "",
    lastName: driver.lastName ?? driver.legalLastName ?? "",
    email: driver.email ?? "",
    phoneNumber: driver.phoneE164 ?? driver.phoneNumber ?? "",
    dob: dateInputValue(dob),
    address: {
      street: driver.address?.street ?? "",
      line2: driver.address?.line2 ?? "",
      city: driver.address?.city ?? "",
      state: driver.address?.state ?? "",
      zip: driver.address?.zip ?? ""
    },
    license: {
      number: driver.license?.number ?? "",
      state: driver.license?.state ?? ""
    },
    vehicle: {
      year: driver.vehicle?.year ? String(driver.vehicle.year) : "",
      make: driver.vehicle?.make ?? "",
      model: driver.vehicle?.model ?? "",
      trim: driver.vehicle?.trim ?? "",
      color: driver.vehicle?.color ?? "",
      plate: driver.vehicle?.plate ?? "",
      vin: driver.vehicle?.vin ?? "",
      class: driver.vehicle?.class ?? ""
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-xl font-semibold text-ink">{driverFullName(driver)}</h1>
            <StatusPill status={driver.driverApprovalStatus ?? "pending"} />
          </div>
          {!driverNameCollected(driver) && (
            <p className="mt-1 text-sm font-medium text-amber-700">Name/DOB onboarding step has not been completed.</p>
          )}
          <p className="mt-1 text-sm text-muted">
            {driver.email ?? "no email"} · {driver.phoneNumber ?? "no phone"} · Applied{" "}
            {createdAt ? createdAt.toLocaleDateString() : "—"}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-2">
          <Section title="Driver Profile">
            <Grid>
              <Field label="Full name" value={driverFullName(driver)} />
              <Field label="Date of birth" value={dob ? dob.toLocaleDateString() : "—"} />
              <Field label="Email" value={driver.email} />
              <Field label="Phone" value={driver.phoneNumber ?? driver.phoneE164} />
              <Field
                label="Address"
                value={
                  [driver.address?.street, driver.address?.line2, driver.address?.city, driver.address?.state, driver.address?.zip]
                    .filter(Boolean)
                    .join(", ") || "—"
                }
              />
            </Grid>
          </Section>

          <Section title="Driver License">
            <Grid>
              <Field label="License number" value={driver.license?.number} />
              <Field label="License state" value={driver.license?.state} />
            </Grid>
            <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
              <ImageViewer label="License front" url={licenseUrl} />
              {licenseBackUrl && licenseBackUrl !== licenseUrl && <ImageViewer label="License back" url={licenseBackUrl} />}
            </div>
          </Section>

          <Section title="Vehicle Information">
            <Grid>
              <Field label="Decoded VIN" value={driver.vehicle?.vin} />
              <Field label="Year" value={driver.vehicle?.year} />
              <Field label="Make" value={driver.vehicle?.make} />
              <Field label="Model" value={driver.vehicle?.model} />
              <Field label="Trim" value={driver.vehicle?.trim} />
              <Field label="Selected color" value={driver.vehicle?.color} />
              <Field label="Plate" value={driver.vehicle?.plate} />
              <Field label="Vehicle class" value={driver.vehicle?.class} />
              <Field
                label="VIN decode status"
                value={
                  driver.vinDecodeStatus === "decoded"
                    ? "Decoded"
                    : driver.vinDecodeStatus === "failed"
                      ? "Failed"
                      : "Pending"
                }
              />
              <Field
                label="Vehicle image status"
                value={
                  driver.vehicleImageStatus === "matched"
                    ? "Matched"
                    : driver.vehicleImageStatus === "fallback"
                      ? "Fallback image"
                      : "Missing"
                }
              />
            </Grid>

            <div className="mt-3">
              <p className="mb-1.5 text-[11px] font-medium text-muted">Generic Vehicle Image</p>
              {driver.vehicle?.imageUrl ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={driver.vehicle.imageUrl}
                  alt={`${driver.vehicle?.color ?? ""} ${driver.vehicle?.make ?? ""} ${driver.vehicle?.model ?? ""}`}
                  className="h-32 w-48 rounded-md border border-line object-cover"
                />
              ) : (
                <div className="flex h-32 w-48 flex-col items-center justify-center gap-2 rounded-md border border-dashed border-line bg-grouped text-center">
                  <p className="text-xs font-medium text-muted">Vehicle image not yet available.</p>
                  {driver.vehicle?.make && driver.vehicle?.model && (
                    <Link
                      href={`/vehicle-library?make=${encodeURIComponent(driver.vehicle.make)}&model=${encodeURIComponent(driver.vehicle.model)}`}
                      className="text-[11px] font-semibold text-rydr-burgundy hover:underline"
                    >
                      Add Vehicle Image →
                    </Link>
                  )}
                </div>
              )}
            </div>
          </Section>

          <Section title="Insurance Information">
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              <ImageViewer label="Insurance card" url={insuranceUrl} />
              {insuranceBackUrl && insuranceBackUrl !== insuranceUrl && <ImageViewer label="Insurance back" url={insuranceBackUrl} />}
            </div>
          </Section>

          <Section title="Registration Information">
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              <ImageViewer label="Registration" url={registrationUrl} />
              {registrationBackUrl && registrationBackUrl !== registrationUrl && <ImageViewer label="Registration back" url={registrationBackUrl} />}
            </div>
          </Section>

          <Section title="Background Check">
            <Grid>
              <Field
                label="Status"
                value={driver.backgroundCheckStatus === "beta_deferred" ? "Beta Deferred" : driver.backgroundCheckStatus ?? "Not started"}
              />
              <Field
                label="Mission Control deferral"
                value={driver.betaBackgroundCheckBypassEnabled ? "Enabled" : "Not enabled"}
              />
              <Field
                label="Beta agreement"
                value={driver.betaAgreementAccepted ? "Accepted" : "Not accepted"}
              />
              <Field
                label="Acknowledged at"
                value={toDateSafe(driver.backgroundCheckAcknowledgedAt)?.toLocaleString() ?? "—"}
              />
              <Field
                label="Deferred at"
                value={toDateSafe(driver.betaBackgroundCheckBypassedAt)?.toLocaleString() ?? "—"}
              />
            </Grid>
            <p className="mt-2 text-[11px] text-muted">
              Mission Control may defer the background check for this 60-day beta. Final driver approval still requires
              the Approve Driver action.
            </p>
          </Section>

          <TripSafetyAnalytics uid={driver.uid} kind="driver" />
        </div>

        <div className="space-y-6">
          <Section title="Onboarding Progress">
            <DriverOnboardingProgressLive uid={driver.uid} initial={onboardingProgress} />
          </Section>

          <Section title="Verification Status">
            <Grid cols={1}>
              <Field label="Stripe Identity" value={formatStatus(identityStatus)} />
              <Field label="Stripe Connect" value={formatStatus(connectStatus)} />
              <Field label="Charges enabled" value={driver.stripeChargesEnabled ? "Yes" : "No"} />
              <Field label="Payouts enabled" value={driver.stripePayoutsEnabled ? "Yes" : "No"} />
              <Field label="Beta Agreement" value={driver.betaAgreementAccepted ? "Accepted" : "Not accepted"} />
            </Grid>
          </Section>

          <Section title="CashRydr Hub">
            <div className="space-y-3">
              <div className="flex items-center gap-2">
                <StatusPill status={cashHubDisplay.status} label={cashHubDisplay.label} />
              </div>
              <p className="text-xs text-muted">{cashHubDisplay.detail}</p>
              <Grid cols={1}>
                <Field
                  label="Access"
                  value={cashHubDisplay.label}
                />
                <Field label="Monthly fee" value={formatCents(cashHubBilling?.feeCents ?? driver.cashHubDriverAccessFeeCents ?? 499)} />
                <Field label="Collected" value={cashHubBilling ? formatCents(cashHubBilling.collectedCents) : "—"} />
                <Field label="Remaining" value={cashHubBilling ? formatCents(cashHubBilling.remainingCents) : "—"} />
                <Field label="Last collection ride" value={cashHubBilling?.lastCollectionRideId} />
                <Field label="Terms accepted" value={toDateSafe(driver.cashHubTermsAcceptedAt)?.toLocaleString() ?? "—"} />
                <Field label="Opted out" value={toDateSafe(driver.cashHubOptedOutAt)?.toLocaleString() ?? "—"} />
                <Field label="Accepted terms version" value={driver.cashHubTermsVersion} />
                <Field label="Fee terms version" value={driver.cashHubDriverAccessFeeVersion} />
              </Grid>
            </div>
          </Section>

          <Section title="Approval Requirements">
            <RequirementChecklist checks={checks} />
          </Section>

          <DriverProfileAdminTools uid={driver.uid} initial={adminProfileInitial} />

          <DriverActions uid={driver.uid} missing={missing} activeRide={activeRide} />
        </div>
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <h2 className="mb-3 text-sm font-semibold text-ink">{title}</h2>
      {children}
    </div>
  );
}

function Grid({ children, cols = 2 }: { children: React.ReactNode; cols?: number }) {
  return <div className={`grid gap-3 ${cols === 1 ? "grid-cols-1" : "grid-cols-1 sm:grid-cols-2"}`}>{children}</div>;
}

function Field({ label, value }: { label: string; value?: string | number | null }) {
  return (
    <div>
      <p className="text-[11px] font-medium text-muted">{label}</p>
      <p className="text-sm text-ink">{value || value === 0 ? value : "—"}</p>
    </div>
  );
}

function formatStatus(value: string) {
  return value
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function dateInputValue(date: Date | null): string {
  if (!date) return "";
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}
