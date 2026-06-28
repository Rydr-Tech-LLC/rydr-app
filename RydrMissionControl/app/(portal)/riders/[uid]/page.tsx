import { notFound } from "next/navigation";
import { adminDb } from "@/lib/firebaseAdmin";
import type { RiderRecord } from "@/lib/types";
import { toDateSafe, fullName } from "@/lib/format";
import StatusPill from "@/components/StatusPill";
import RiderActions from "./RiderActions";

export const dynamic = "force-dynamic";

export default async function RiderReviewPage({ params }: { params: { uid: string } }) {
  const snap = await adminDb.collection("riders").doc(params.uid).get();
  if (!snap.exists) notFound();

  const rider = { ...(snap.data() as RiderRecord), uid: snap.id };
  const createdAt = toDateSafe(rider.createdAt);
  const accountStatus = rider.accountStatus ?? "active";

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-xl font-semibold text-ink">{fullName(rider.firstName, rider.lastName)}</h1>
            <StatusPill status={accountStatus} />
          </div>
          <p className="mt-1 text-sm text-muted">
            {rider.email ?? "no email"} · {rider.phoneNumber ?? rider.phoneE164 ?? "no phone"} · Joined{" "}
            {createdAt ? createdAt.toLocaleDateString() : "—"}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-2">
          <Section title="Rider Profile">
            <Grid>
              <Field label="Full name" value={fullName(rider.firstName, rider.lastName)} />
              <Field label="Email" value={rider.email} />
              <Field label="Phone" value={rider.phoneNumber ?? rider.phoneE164} />
              <Field label="Rides taken" value={rider.rideCount ?? 0} />
              <Field label="Verified" value={rider.verifiedRider ? "Verified" : "Unverified"} />
            </Grid>
          </Section>
        </div>

        <div className="space-y-6">
          <Section title="Account Status">
            <Grid cols={1}>
              <Field label="Status" value={accountStatus} />
              <Field label="Verified rider" value={rider.verifiedRider ? "Yes" : "No"} />
            </Grid>
          </Section>

          <RiderActions uid={rider.uid} accountStatus={accountStatus} />
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
