import { notFound } from "next/navigation";
import StatusPill from "@/components/StatusPill";
import { getPromotion, type PromotionRecord } from "@/lib/promotions";
import PromotionActions from "../PromotionActions";
import PromotionForm, { type PromotionFormInitial } from "../PromotionForm";

export const dynamic = "force-dynamic";

export default async function PromotionDetailPage({ params }: { params: { promotionId: string } }) {
  const promotion = await getPromotion(params.promotionId);
  if (!promotion) notFound();

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="text-xl font-semibold text-ink">{promotion.title}</h1>
            <StatusPill status={promotion.status} />
          </div>
          <p className="mt-1 text-sm text-muted">
            {promotion.type} · {promotion.id}
          </p>
        </div>
        <PromotionActions id={promotion.id} status={promotion.status} />
      </div>

      {promotion.status === "archived" ? (
        <div className="rounded-lg border border-line bg-white p-5 text-sm text-muted">
          This promotion is deleted from active views. Use Reuse to create a new editable draft from it.
        </div>
      ) : (
        <PromotionForm initial={serializePromotion(promotion)} />
      )}
    </div>
  );
}

function serializePromotion(promotion: PromotionRecord): PromotionFormInitial {
  return {
    id: promotion.id,
    title: promotion.title,
    description: promotion.description,
    status: promotion.status,
    type: promotion.type,
    appliesTo: promotion.appliesTo,
    startsAt: promotion.startsAt.toDate().toISOString(),
    endsAt: promotion.endsAt.toDate().toISOString(),
    timezone: promotion.timezone,
    markets: promotion.markets,
    rideTypes: promotion.rideTypes,
    discountKind: promotion.discountKind,
    discountPercent: promotion.discountPercent,
    discountCents: promotion.discountCents,
    maxDiscountCents: promotion.maxDiscountCents,
    bonusCents: promotion.bonusCents,
    milestoneRideCount: promotion.milestoneRideCount,
    rewardKind: promotion.rewardKind,
    rewardQuantity: promotion.rewardQuantity,
    rewardCents: promotion.rewardCents,
    maxRedemptions: promotion.maxRedemptions,
    perUserLimit: promotion.perUserLimit,
    betaOnly: promotion.betaOnly
  };
}
