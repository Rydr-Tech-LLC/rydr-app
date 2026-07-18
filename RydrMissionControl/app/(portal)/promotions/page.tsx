import Link from "next/link";
import StatusPill from "@/components/StatusPill";
import { listPromotions } from "@/lib/promotions";
import PromotionActions from "./PromotionActions";

export const dynamic = "force-dynamic";

export default async function PromotionsPage() {
  const promotions = await listPromotions();

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 className="text-xl font-semibold text-ink">Promotions</h1>
          <p className="mt-1 text-sm text-muted">
            Backend-owned rider discounts, driver bonuses, and beta milestone rewards.
          </p>
        </div>
        <Link href="/promotions/new" className="rounded-md bg-ink px-4 py-2 text-xs font-semibold text-white">
          New Promotion
        </Link>
      </div>

      {promotions.length === 0 ? (
        <div className="rounded-lg border border-dashed border-line bg-white p-10 text-center text-sm text-muted">
          No promotions yet.
        </div>
      ) : (
        <div className="space-y-2">
          {promotions.map((promotion) => (
            <div key={promotion.id} className="rounded-lg border border-line bg-white p-4 shadow-sm">
              <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <Link href={`/promotions/${promotion.id}`} className="font-medium text-ink hover:underline">
                      {promotion.title}
                    </Link>
                    <StatusPill status={promotion.status} />
                  </div>
                  <p className="mt-1 text-xs text-muted">
                    {labelForType(promotion.type)} · {promotion.appliesTo} · {dateLabel(promotion.startsAt)} to{" "}
                    {dateLabel(promotion.endsAt)}
                  </p>
                  <p className="mt-1 text-xs text-muted">
                    {promotion.markets.length ? promotion.markets.join(", ") : "All markets"} ·{" "}
                    {promotion.rideTypes.length ? promotion.rideTypes.join(", ") : "All ride types"}
                  </p>
                </div>
                <PromotionActions id={promotion.id} status={promotion.status} />
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function labelForType(type: string) {
  switch (type) {
    case "rider_fare_discount":
      return "Rider fare discount";
    case "driver_per_ride_bonus":
      return "Driver per-ride bonus";
    case "driver_milestone_reward":
      return "Driver milestone reward";
    default:
      return type;
  }
}

function dateLabel(value: { toDate?: () => Date } | null | undefined) {
  return value?.toDate ? value.toDate().toLocaleString() : "—";
}
