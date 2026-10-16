import { notFound } from "next/navigation";
import { getWorkspaceDb } from "@/lib/firebaseAdmin";
import { WorkspaceLink as Link } from "@/components/WorkspaceContext";
import StatusPill from "@/components/StatusPill";
const money = (v: unknown) =>
  typeof v === "number"
    ? (v / 100).toLocaleString("en-US", { style: "currency", currency: "USD" })
    : "Not recorded";
export const dynamic = "force-dynamic";
export default async function RidePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const db = await getWorkspaceDb(),
    ref = db.collection("rides").doc(id);
  const [snap, outcome] = await Promise.all([
    ref.get(),
    ref.collection("financial").doc("outcome").get(),
  ]);
  if (!snap.exists) notFound();
  const r = snap.data()!,
    f = outcome.data() ?? {};
  return (
    <div className="space-y-6">
      <div>
        <Link href="/rides" className="text-sm text-rydr-burgundy">
          ← All rides
        </Link>
        <h1 className="mt-3 break-all text-2xl font-semibold">Ride {id}</h1>
        <div className="mt-3">
          <StatusPill status={r.status ?? "unknown"} />
        </div>
      </div>
      <section className="mc-panel">
        <h2 className="text-lg font-semibold">Trip details</h2>
        <dl className="mt-5 grid gap-5 sm:grid-cols-2">
          {[
            ["Ride type", r.rideType ?? "—"],
            ["Pickup", r.pickup ?? "Not recorded"],
            ["Drop-off", r.dropoff ?? "Not recorded"],
            ["Payment status", r.paymentStatus ?? "Not recorded"],
          ].map(([label, value]) => (
            <div key={label}>
              <dt className="mc-eyebrow">{label}</dt>
              <dd className="mt-2 text-sm">
                {typeof value === "string" ? value : "Location recorded"}
              </dd>
            </div>
          ))}
        </dl>
        <div className="mt-6 flex flex-wrap gap-4 text-sm text-rydr-burgundy">
          {r.riderId && (
            <Link href={`/riders/${r.riderId}`}>Open rider profile ↗</Link>
          )}
          {r.driverId && (
            <Link href={`/drivers/${r.driverId}`}>Open driver profile ↗</Link>
          )}
        </div>
      </section>
      <section className="mc-panel">
        <h2 className="text-lg font-semibold">Fare & settlement</h2>
        <p className="mt-2 text-sm text-muted">
          Rider promotions do not reduce the driver’s pre-promotion earnings.
        </p>
        <dl className="mt-5 grid gap-5 sm:grid-cols-3">
          {[
            [
              "Rider charge",
              r.finalRiderChargeCents ?? f.finalRiderChargeCents,
            ],
            [
              "Promotion discount",
              r.backendPromotionDiscountCents ?? r.promoDiscountCents,
            ],
            [
              "Driver earnings before withholding",
              r.driverPayoutCents ?? f.driverPayoutCents,
            ],
          ].map(([label, value]) => (
            <div key={String(label)}>
              <dt className="mc-eyebrow">{label}</dt>
              <dd className="mt-2 text-xl font-semibold">{money(value)}</dd>
            </div>
          ))}
        </dl>
      </section>
    </div>
  );
}
