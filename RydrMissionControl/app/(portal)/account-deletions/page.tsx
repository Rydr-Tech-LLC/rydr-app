import { adminDb } from "@/lib/firebaseAdmin";
import type { AccountDeletionRequestRecord } from "@/lib/types";
import { toDateSafe } from "@/lib/format";
import StatusPill from "@/components/StatusPill";
import AccountDeletionActions from "./AccountDeletionActions";

export const dynamic = "force-dynamic";

export default async function AccountDeletionsPage() {
  const snap = await adminDb
    .collection("accountDeletionRequests")
    .orderBy("requestedAt", "desc")
    .limit(200)
    .get()
    .catch(() => null);

  const requests = snap
    ? snap.docs.map((doc) => ({ ...(doc.data() as AccountDeletionRequestRecord), id: doc.id }))
    : [];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Account Deletion Requests</h1>
        <p className="mt-1 text-sm text-muted">
          Riders and drivers request deletion from the apps. Every request needs human review before the
          Firebase Auth account, Firestore data, and Stripe records are actually removed — this queue is the
          only place that can do it.
        </p>
      </div>

      {requests.length === 0 ? (
        <div className="rounded-lg border border-dashed border-line bg-white p-10 text-center text-sm text-muted">
          No deletion requests right now.
        </div>
      ) : (
        <div className="space-y-2">
          {requests.map((req) => {
            const requested = toDateSafe(req.requestedAt) ?? toDateSafe(req.createdAt);
            return (
              <div key={req.id} className="rounded-lg border border-line bg-white p-4 shadow-sm">
                <div className="flex items-start justify-between">
                  <div>
                    <div className="flex items-center gap-2">
                      <p className="font-medium text-ink">{req.email ?? req.uid}</p>
                      <StatusPill status={req.status} />
                      <span className="rounded-full border border-line bg-grouped px-2 py-0.5 text-[11px] font-medium text-muted">
                        {req.role}
                      </span>
                    </div>
                    <p className="mt-0.5 text-xs text-muted">
                      uid {req.uid} · requested {requested ? requested.toLocaleString() : "—"}
                      {req.source ? ` · via ${req.source}` : ""}
                    </p>
                    {req.reason && <p className="mt-2 text-sm text-ink">"{req.reason}"</p>}
                    {req.status === "rejected" && req.rejectionReason && (
                      <p className="mt-1 text-xs text-rydr-red">Rejected: {req.rejectionReason}</p>
                    )}
                  </div>
                </div>
                {(req.status === "requested" || req.status === "processing") && (
                  <div className="mt-3">
                    <AccountDeletionActions id={req.id} />
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
