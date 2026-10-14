import PromotionForm from "../PromotionForm";

export const dynamic = "force-dynamic";

export default function NewPromotionPage() {
  const start = new Date();
  start.setHours(start.getHours() + 1, 0, 0, 0);
  const end = new Date(start.getTime() + 30 * 24 * 60 * 60 * 1000);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-ink">Create a promotion</h1>
        <p className="mt-1 text-sm text-muted">Set the offer, choose who can use it, and review before publishing.</p>
      </div>
      <PromotionForm initial={{ startsAt: start.toISOString(), endsAt: end.toISOString() }} />
    </div>
  );
}
