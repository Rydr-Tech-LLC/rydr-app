import { notFound } from "next/navigation";
import { adminDb } from "@/lib/firebaseAdmin";
import { evaluateDriverRequirements, type DriverRecord } from "@/lib/types";
import { toDateSafe, fullName } from "@/lib/format";
import StatusPill from "@/components/StatusPill";
import ImageViewer from "@/components/ImageViewer";
import RequirementChecklist from "@/components/RequirementChecklist";
import DriverActions from "./DriverActions";

export const dynamic = "force-dynamic";

export default async function DriverReviewPage({ params }: { params: { uid: string } }) {
  const snap = await adminDb.collection("drivers").doc(params.uid).get();
  if (!snap.exists) notFound();

  const driver = { uid: snap.id, ...(snap.data() as DriverRecord) };
  const { checks, missing, canApprove } = evaluateDriverRequirements(driver);
  const createdAt = toDateSafe(driver.createdAt);
  const dob = toDateSafe(driver.dob);

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-xl font-semibold text-ink">{fullName(driver.firstName, driver.lastName)}</h1>
            <StatusPill status={driver.driverApprovalStatus ?? "pending"} />
          </div>
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
              <Field label="Full name" value={fullName(driver.firstName, driver.lastName)} />
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
              <ImageViewer label="License image" url={driver.license?.imageUrl} />
            </div>
          </Section>

          <Section title="Vehicle Information">
            <Grid>
              <Field label="Make" value={driver.vehicle?.make} />
              <Field label="Model" value={driver.vehicle?.model} />
              <Field label="Year" value={driver.vehicle?.year} />
              <Field label="VIN" value={driver.vehicle?.vin} />
              <Field label="Plate" value={driver.vehicle?.plate} />
              <Field label="Vehicle class" value={driver.vehicle?.class} />
            </Grid>
          </Section>

          <Section title="Insurance Information">
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              <ImageViewer label="Insurance card" url={driver.vehicle?.insuranceImageUrl} />
            </div>
          </Section>

          <Section title="Registration Information">
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              <ImageViewer label="Registration" url={driver.vehicle?.registrationImageUrl} />
            </div>
          </Section>

          <Section title="Background Check">
            <Grid>
              <Field
                label="Status"
                value={driver.backgroundCheckStatus === "beta_deferred" ? "Beta Deferred" : driver.backgroundCheckStatus ?? "Not started"}
              />
              <Field
                label="Beta agreement"
                value={driver.betaAgreementAccepted ? "Accepted" : "Not accepted"}
              />
              <Field
                label="Acknowledged at"
                value={toDateSafe(driver.backgroundCheckAcknowledgedAt)?.toLocaleString() ?? "—"}
              />
            </Grid>
            <p className="mt-2 text-[11px] text-muted">
              Beta-deferred satisfies onboarding for now; will be replaced with real Checkr integration.
            </p>
          </Section>
        </div>

        <div className="space-y-6">
          <Section title="Verification Status">
            <Grid cols={1}>
              <Field label="Stripe Identity" value={driver.stripeIdentityStatus ?? "Not started"} />
              <Field label="Stripe Connect" value={driver.stripeConnectStatus ?? (driver.stripeAccountId ? "Connected" : "Not started")} />
              <Field label="Beta Agreement" value={driver.betaAgreementAccepted ? "Accepted" : "Not accepted"} />
            </Grid>
          </Section>

          <Section title="Approval Requirements">
            <RequirementChecklist checks={checks} />
          </Section>

          <DriverActions uid={driver.uid} canApprove={canApprove} missing={missing} />
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
