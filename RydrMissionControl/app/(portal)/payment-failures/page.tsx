import { adminDb } from "@/lib/firebaseAdmin";
import type { RideRecord } from "@/lib/types";
import { toDateSafe } from "@/lib/format";
import StatusPill from "@/components/StatusPill";
import PaymentFailureActions from "./PaymentFailureActions";

export const dynamic = "force-dynamic";

export default async function PaymentFailuresPage() {
  const snap = await adminDb
    .collection("rides")
    .where("paymentStatus", "==", "failed")
    .orderBy("lastPaymentAttempt", "desc")
    .limit(200)
    .get()
    .catch(() => null);

  const rides = snap ? snap.docs.map((doc) => ({ ...(doc.data() as RideRecord), id: doc.id })) : [];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Payment Failures</h1>
        <p className="mt-1 text-sm text-muted">
          Rides where the rider's charge failed. The rider already sees a Retry / Update Card prompt in-app —
          this queue is for cases that need a manual nudge, a refund, or a write-off.
        </p>
      </div>

      {rides.length === 0 ? (
        <div className="rounded-lg border border-dashed border-line bg-white p-10 text-center text-sm text-muted">
          No failed payments right now.
        </div>
      ) : (
        <div className="space-y-2">
          {rides.map((ride) => {
            const lastAttempt = toDateSafe(ride.lastPaymentAttempt);
            return (
              <div key={ride.id} className="rounded-lg border border-line bg-white p-4 shadow-sm">
                <div className="flex items-start justify-between">
                  <div>
                    <div className="flex items-center gap-2">
                      <p className="font-medium text-ink">{ride.riderName ?? ride.riderId ?? "Rider"}</p>
                      <StatusPill status="failed" />
                      {typeof ride.retryCount === "number" && ride.retryCount > 0 && (
                        <span className="rounded-full border border-line bg-grouped px-2 py-0.5 text-[11px] font-medium text-muted">
                          {ride.retryCount} retr{ride.retryCount === 1 ? "y" : "ies"}
                        </span>
                      )}
                    </div>
                    <p className="mt-0.5 text-xs text-muted">
                      ride {ride.id} · driver {ride.driverName ?? ride.driverId ?? "—"} · last attempt{" "}
                      {lastAttempt ? lastAttempt.toLocaleString() : "—"}
                    </p>
                    {ride.pickup && ride.dropoff && (
                      <p className="mt-1 text-xs text-muted">
                        {ride.pickup} → {ride.dropoff}
                      </p>
                    )}
                    {ride.failureReason && (
                      <p className="mt-2 text-sm text-rydr-red">
                        {ride.failureReason}
                        {ride.failureCode ? ` (${ride.failureCode})` : ""}
                      </p>
                    )}
                  </div>
                </div>
                <div className="mt-3">
                  <PaymentFailureActions id={ride.id} />
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
