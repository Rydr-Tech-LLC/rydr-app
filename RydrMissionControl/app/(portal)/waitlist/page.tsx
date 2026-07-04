import { adminDb } from "@/lib/firebaseAdmin";
import { timeAgo, toDateSafe } from "@/lib/format";
import StatusPill from "@/components/StatusPill";
import WaitlistActions from "./WaitlistActions";

export const dynamic = "force-dynamic";

type WaitlistRole = "rider" | "driver";
type WaitlistStatus = "pending" | "approved" | "rejected";

interface WaitlistRecord {
  id: string;
  firstName?: string;
  lastName?: string;
  email?: string;
  phoneNumber?: string;
  role?: WaitlistRole;
  source?: string;
  status?: WaitlistStatus;
  confirmationEmailStatus?: string;
  approvalEmailStatus?: string;
  rejectionReason?: string;
  createdAt?: { toDate?: () => Date } | null;
  reviewedAt?: { toDate?: () => Date } | null;
}

export default async function WaitlistPage() {
  const snap = await adminDb.collection("betaWaitlist").limit(500).get();
  const entries = snap.docs
    .map((doc) => ({ ...(doc.data() as Omit<WaitlistRecord, "id">), id: doc.id }))
    .sort((a, b) => {
      const statusScore = scoreStatus(a.status) - scoreStatus(b.status);
      if (statusScore !== 0) return statusScore;
      return (toDateSafe(b.createdAt)?.getTime() ?? 0) - (toDateSafe(a.createdAt)?.getTime() ?? 0);
    });

  const pending = entries.filter((entry) => (entry.status ?? "pending") === "pending");
  const approved = entries.filter((entry) => entry.status === "approved");
  const rejected = entries.filter((entry) => entry.status === "rejected");
  const riders = entries.filter((entry) => entry.role === "rider");
  const drivers = entries.filter((entry) => entry.role === "driver");

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Beta Waitlist</h1>
        <p className="mt-1 text-sm text-muted">
          Review public beta signups, approve TestFlight invites, and keep cohort size controlled.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
        <Tile label="Pending" value={pending.length} />
        <Tile label="Approved" value={approved.length} />
        <Tile label="Rejected" value={rejected.length} />
        <Tile label="Riders" value={riders.length} />
        <Tile label="Drivers" value={drivers.length} />
      </div>

      <div className="overflow-hidden rounded-lg border border-line bg-white shadow-sm">
        <div className="border-b border-line px-5 py-3">
          <h2 className="text-sm font-semibold text-ink">Requests</h2>
        </div>
        {entries.length === 0 ? (
          <p className="px-5 py-8 text-center text-sm text-muted">No waitlist requests yet.</p>
        ) : (
          <div className="divide-y divide-line">
            {entries.map((entry) => {
              const status = entry.status ?? "pending";
              const createdAt = toDateSafe(entry.createdAt);
              const reviewedAt = toDateSafe(entry.reviewedAt);
              return (
                <div key={entry.id} className="grid gap-4 px-5 py-4 lg:grid-cols-[1fr_auto]">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="font-medium text-ink">{displayName(entry)}</p>
                      <StatusPill status={status} />
                      <StatusPill status={entry.role ?? "pending"} label={entry.role === "driver" ? "Driver" : "Rider"} />
                    </div>
                    <div className="mt-2 grid gap-1 text-xs text-muted sm:grid-cols-2 lg:grid-cols-4">
                      <span className="truncate">Email: {entry.email ?? "-"}</span>
                      <span>Phone: {entry.phoneNumber ?? "-"}</span>
                      <span>Source: {entry.source ?? "-"}</span>
                      <span>Submitted: {timeAgo(createdAt)}</span>
                    </div>
                    <div className="mt-2 flex flex-wrap gap-2 text-[11px] text-muted">
                      <span>Confirmation email: {entry.confirmationEmailStatus ?? "unknown"}</span>
                      {entry.approvalEmailStatus && <span>Approval email: {entry.approvalEmailStatus}</span>}
                      {reviewedAt && <span>Reviewed: {timeAgo(reviewedAt)}</span>}
                    </div>
                    {entry.rejectionReason && (
                      <p className="mt-2 rounded-md bg-red-50 px-3 py-2 text-xs text-red-700">
                        Rejection reason: {entry.rejectionReason}
                      </p>
                    )}
                  </div>
                  <WaitlistActions id={entry.id} status={status} />
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

function Tile({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-lg border border-line bg-white p-4 shadow-sm">
      <p className="text-xs font-medium text-muted">{label}</p>
      <p className="mt-1.5 text-2xl font-semibold text-ink">{value}</p>
    </div>
  );
}

function displayName(entry: WaitlistRecord): string {
  const name = [entry.firstName, entry.lastName].filter(Boolean).join(" ");
  return name || "Unnamed applicant";
}

function scoreStatus(status?: string): number {
  if (!status || status === "pending") return 0;
  if (status === "approved") return 1;
  return 2;
}
