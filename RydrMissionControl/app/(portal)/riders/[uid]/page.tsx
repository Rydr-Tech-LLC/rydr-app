import { notFound } from "next/navigation";
import { adminDb } from "@/lib/firebaseAdmin";
import type { RiderRecord } from "@/lib/types";
import { toDateSafe, fullName } from "@/lib/format";
import StatusPill from "@/components/StatusPill";
import RiderActions from "./RiderActions";
import RydrBankMintPanel from "./RydrBankMintPanel";

export const dynamic = "force-dynamic";

interface RydrBankCodeRecord {
  id: string;
  code?: string;
  status?: string;
  rewardLabel?: string;
  maxMiles?: number;
  createdAt?: { toDate?: () => Date } | null;
  usedAt?: { toDate?: () => Date } | null;
}

export default async function RiderReviewPage({ params }: { params: { uid: string } }) {
  const [snap, userSnap, codesSnap] = await Promise.all([
    adminDb.collection("riders").doc(params.uid).get(),
    adminDb.collection("users").doc(params.uid).get(),
    adminDb.collection("users").doc(params.uid).collection("rydrBankCodes").orderBy("createdAt", "desc").limit(20).get()
  ]);
  if (!snap.exists) notFound();

  const rider = { ...(snap.data() as RiderRecord), uid: snap.id };
  const createdAt = toDateSafe(rider.createdAt);
  const accountStatus = rider.accountStatus ?? "active";
  const studentAmbassadorBadge = rider.badges?.studentAmbassador;
  const hasStudentAmbassadorBadge = studentAmbassadorBadge?.active === true;
  const rydrBank = (userSnap.data()?.rydrBank ?? {}) as {
    codesAvailable?: number;
    codesEarned?: number;
    totalEligible?: number;
  };
  const codes = codesSnap.docs.map((doc) => ({ id: doc.id, ...doc.data() })) as RydrBankCodeRecord[];

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

          <Section title="RydrBank">
            <Grid>
              <Field label="Available codes" value={rydrBank.codesAvailable ?? 0} />
              <Field label="Codes earned" value={rydrBank.codesEarned ?? 0} />
              <Field label="Eligible rides" value={rydrBank.totalEligible ?? 0} />
            </Grid>

            <div className="mt-4 overflow-hidden rounded-md border border-line">
              <table className="w-full text-sm">
                <thead className="border-b border-line bg-grouped text-left text-xs font-medium text-muted">
                  <tr>
                    <th className="px-3 py-2">Code</th>
                    <th className="px-3 py-2">Reward</th>
                    <th className="px-3 py-2">Status</th>
                    <th className="px-3 py-2">Created</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-line">
                  {codes.map((code) => {
                    const codeCreatedAt = toDateSafe(code.createdAt);
                    return (
                      <tr key={code.id}>
                        <td className="px-3 py-2 font-mono text-xs font-semibold text-ink">{code.code ?? "—"}</td>
                        <td className="px-3 py-2 text-muted">{code.rewardLabel ?? "Rydr Go / Rydr Eco"}</td>
                        <td className="px-3 py-2">
                          <StatusPill status={code.status ?? "active"} />
                        </td>
                        <td className="px-3 py-2 text-muted">
                          {codeCreatedAt ? codeCreatedAt.toLocaleDateString() : "—"}
                        </td>
                      </tr>
                    );
                  })}
                  {codes.length === 0 && (
                    <tr>
                      <td colSpan={4} className="px-3 py-6 text-center text-muted">
                        No RydrBank codes yet.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </Section>
        </div>

        <div className="space-y-6">
          <Section title="Account Status">
            <Grid cols={1}>
              <Field label="Status" value={accountStatus} />
              <Field label="Verified rider" value={rider.verifiedRider ? "Yes" : "No"} />
            </Grid>
          </Section>

          <Section title="Beta Badges">
            {hasStudentAmbassadorBadge ? (
              <div className="space-y-3">
                <img
                  src="/badges/student-ambassador-badge.svg"
                  alt="Student Ambassador badge"
                  className="mx-auto h-auto w-40"
                />
                <div>
                  <p className="text-sm font-semibold text-ink">
                    {studentAmbassadorBadge?.label ?? "Student Ambassador"}
                  </p>
                  <p className="mt-1 text-xs text-muted">
                    {studentAmbassadorBadge?.description ??
                      "Campus liaison helping Rydr build a student beta testing community."}
                  </p>
                </div>
              </div>
            ) : (
              <p className="text-sm text-muted">No beta badges assigned.</p>
            )}
          </Section>

          <RydrBankMintPanel uid={rider.uid} />
          <RiderActions
            uid={rider.uid}
            accountStatus={accountStatus}
            hasStudentAmbassadorBadge={hasStudentAmbassadorBadge}
          />
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
