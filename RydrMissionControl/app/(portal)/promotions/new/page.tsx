import PromotionForm from "../PromotionForm";

export const dynamic = "force-dynamic";

export default function NewPromotionPage() {
  const start = new Date();
  start.setHours(start.getHours() + 1, 0, 0, 0);
  const end = new Date(start.getTime() + 4 * 60 * 60 * 1000);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">New Promotion</h1>
        <p className="mt-1 text-sm text-muted">Create a reusable backend-owned promo definition.</p>
      </div>
      <PromotionForm initial={{ startsAt: start.toISOString(), endsAt: end.toISOString() }} />
    </div>
  );
}
