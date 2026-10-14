import Link from "next/link";
import { adminDb } from "@/lib/firebaseAdmin";
import StatusPill from "@/components/StatusPill";
import { listPromotions } from "@/lib/promotions";
import PromotionActions from "./PromotionActions";

export const dynamic = "force-dynamic";

export default async function PromotionsPage({
  searchParams,
}: {
  searchParams: Promise<{ audience?: string }>;
}) {
  const audience = (await searchParams).audience;
  const all = await listPromotions();
  const promotions = all.filter((p) => !audience || p.audience === audience);
  const [issues, fundingIssues] = await Promise.all([
    adminDb
      .collection("promotionRedemptions")
      .where("status", "in", ["needs_review", "dispatching", "pending_payout"])
      .limit(50)
      .get(),
    adminDb
      .collection("rides")
      .where("promoSubsidyTransferStatus", "in", [
        "failed",
        "needs_review",
        "pending_driver_connect_account",
      ])
      .limit(50)
      .get(),
  ]);

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 rounded-3xl bg-gradient-to-br from-red-500 via-fuchsia-700 to-blue-700 p-7 text-white sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 className="text-3xl font-semibold">Promotions</h1>
          <p className="mt-2 text-sm text-white/85">
            Backend-owned rider discounts, driver bonuses, and beta milestone
            rewards.
          </p>
        </div>
        <Link
          href="/promotions/new"
          className="rounded-xl bg-white px-5 py-3 text-sm font-semibold text-fuchsia-800"
        >
          New Promotion
        </Link>
      </div>

      <div className="flex flex-wrap gap-2">
        {[
          ["", "All promotions"],
          ["riders", "Rider rewards"],
          ["drivers", "Driver bonuses"],
        ].map(([value, label]) => (
          <Link
            key={value}
            href={`/promotions${value ? `?audience=${value}` : ""}`}
            className={`rounded-full px-5 py-2 text-sm font-semibold ${audience === value || (!audience && !value) ? "bg-ink text-white" : "border border-line bg-white text-muted"}`}
          >
            {label}
          </Link>
        ))}
      </div>
      {!issues.empty && (
        <section className="rounded-2xl border border-amber-200 bg-amber-50 p-5">
          <h2 className="font-semibold text-amber-900">
            Driver bonus payment activity · {issues.size}
          </h2>
          <p className="mt-1 text-xs text-amber-800">
            Unresolved transfers stay here for review. Reconcile uncertain
            payments with Stripe before resubmitting.
          </p>
          <div className="mt-3 space-y-2">
            {issues.docs.map((doc) => {
              const issue = doc.data();
              return (
                <div
                  key={doc.id}
                  className="flex flex-wrap items-center justify-between gap-2 rounded-xl bg-white p-3 text-sm"
                >
                  <div>
                    <Link
                      className="font-semibold underline"
                      href={`/promotions/${issue.promotionId}`}
                    >
                      {issue.promotionTitle || "Promotion bonus"}
                    </Link>
                    <p className="text-xs text-muted">
                      {issue.status.replaceAll("_", " ")} ·{" "}
                      {issue.issue || "Awaiting payment confirmation"}
                    </p>
                  </div>
                  <div className="flex items-center gap-3">
                    <span>${((issue.rewardCents || 0) / 100).toFixed(2)}</span>
                    {issue.driverId && (
                      <Link
                        className="text-xs font-semibold text-fuchsia-700"
                        href={`/drivers/${issue.driverId}`}
                      >
                        Driver profile →
                      </Link>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}
      {!fundingIssues.empty && (
        <section className="rounded-2xl border border-red-200 bg-red-50 p-5">
          <h2 className="font-semibold text-red-900">
            Full-fare driver funding needs review · {fundingIssues.size}
          </h2>
          <p className="mt-1 text-xs text-red-800">
            These discounted rides have an unresolved driver funding transfer.
            The driver’s full fare remains owed. Reconcile the saved transfer
            before retrying.
          </p>
          <div className="mt-3 space-y-2">
            {fundingIssues.docs.map((doc) => {
              const ride = doc.data();
              return (
                <div
                  key={doc.id}
                  className="flex flex-wrap justify-between gap-2 rounded-xl bg-white p-3 text-sm"
                >
                  <span>
                    Ride {doc.id} ·{" "}
                    {ride.promoSubsidyTransferStatus.replaceAll("_", " ")}
                  </span>
                  {ride.driverId && (
                    <Link
                      className="font-semibold text-fuchsia-700"
                      href={`/drivers/${ride.driverId}`}
                    >
                      Driver profile →
                    </Link>
                  )}
                </div>
              );
            })}
          </div>
        </section>
      )}
      {promotions.length === 0 ? (
        <div className="rounded-lg border border-dashed border-line bg-white p-10 text-center text-sm text-muted">
          No promotions yet.
        </div>
      ) : (
        <div className="space-y-2">
          {promotions.map((promotion) => (
            <div
              key={promotion.id}
              className="rounded-2xl border border-line bg-white p-5 shadow-sm transition hover:border-fuchsia-200 hover:shadow-md"
            >
              <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <Link
                      href={`/promotions/${promotion.id}`}
                      className="font-medium text-ink hover:underline"
                    >
                      {promotion.title}
                    </Link>
                    <StatusPill status={promotion.status} />
                  </div>
                  <p className="mt-1 text-xs text-muted">
                    {labelForType(promotion.type)} · {promotion.appliesTo} ·{" "}
                    {dateLabel(promotion.startsAt)} to{" "}
                    {dateLabel(promotion.endsAt)}
                  </p>
                  <p className="mt-1 text-xs text-muted">
                    {promotion.applicationMode === "code"
                      ? `Code ${promotion.promoCode || "required"}`
                      : "Automatic"}{" "}
                    ·{" "}
                    {promotion.markets.length
                      ? promotion.markets.join(", ")
                      : "All markets"}{" "}
                    ·{" "}
                    {promotion.rideTypes.length
                      ? promotion.rideTypes.join(", ")
                      : "All ride types"}
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
    case "rider_milestone_reward":
      return "Rider ride milestone";
    case "driver_per_ride_bonus":
      return "Driver per-ride bonus";
    case "driver_milestone_reward":
      return "Driver milestone reward";
    default:
      return type;
  }
}

function dateLabel(value: { toDate?: () => Date } | null | undefined) {
  return value?.toDate
    ? value
        .toDate()
        .toLocaleString("en-US", {
          timeZone: "America/New_York",
          timeZoneName: "short",
        })
    : "—";
}
