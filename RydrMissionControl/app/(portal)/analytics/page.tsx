import { getWorkspaceDb } from "@/lib/firebaseAdmin";
import { toDateSafe } from "@/lib/format";
import AnalyticsWorkspace, {
  type AnalyticsRide,
} from "@/components/AnalyticsWorkspace";
export const dynamic = "force-dynamic";
export default async function AnalyticsPage() {
  const [rides, online] = await Promise.allSettled([
    (await getWorkspaceDb()).collection("rides").orderBy("updatedAt", "desc").limit(500).get(),
    (await getWorkspaceDb())
      .collection("driver_status")
      .where("isOnline", "==", true)
      .count()
      .get(),
  ]);
  const records: AnalyticsRide[] =
    rides.status === "fulfilled"
      ? rides.value.docs.map((doc) => {
          const r = doc.data();
          const cents = (v: unknown) =>
            typeof v === "number" && Number.isFinite(v)
              ? Math.max(0, Math.round(v))
              : 0;
          return {
            id: doc.id,
            at:
              (
                toDateSafe(r.completedAt) ??
                toDateSafe(r.updatedAt) ??
                toDateSafe(r.createdAt)
              )?.getTime() ?? 0,
            status: String(r.status ?? "unknown"),
            paymentStatus: String(r.paymentStatus ?? "unknown"),
            rideType: String(r.rideType ?? "Unknown"),
            charge:
              typeof r.finalRiderChargeCents === "number"
                ? cents(r.finalRiderChargeCents)
                : typeof r.estimatedRiderTotalCents === "number"
                  ? cents(r.estimatedRiderTotalCents)
                  : cents((r.fare ?? r.estimatedFare ?? 0) * 100),
            platform: cents(r.estimatedPlatformShareCents),
            tips: cents(r.tipAmountCents),
          };
        })
      : [];
  return (
    <AnalyticsWorkspace
      rides={records}
      onlineDrivers={
        online.status === "fulfilled" ? online.value.data().count : null
      }
      loadedAt={Date.now()}
      capped={records.length === 500}
      failed={rides.status === "rejected" || online.status === "rejected"}
    />
  );
}
