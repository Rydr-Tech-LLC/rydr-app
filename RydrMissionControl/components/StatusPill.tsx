const STYLES: Record<string, string> = {
  pending: "bg-amber-50 text-amber-700 border-amber-200",
  needs_attention: "bg-orange-50 text-orange-700 border-orange-200",
  approved: "bg-emerald-50 text-emerald-700 border-emerald-200",
  rejected: "bg-red-50 text-red-700 border-red-200",
  verified: "bg-emerald-50 text-emerald-700 border-emerald-200",
  not_started: "bg-grouped text-muted border-line",
  completed: "bg-emerald-50 text-emerald-700 border-emerald-200",
  open: "bg-amber-50 text-amber-700 border-amber-200",
  dismissed: "bg-grouped text-muted border-line",
  escalated: "bg-red-50 text-red-700 border-red-200",
  active: "bg-emerald-50 text-emerald-700 border-emerald-200",
  suspended: "bg-red-50 text-red-700 border-red-200",
  removed: "bg-grouped text-muted border-line",
  beta_deferred: "bg-champagne/20 text-amber-800 border-champagne/40",
  requested: "bg-amber-50 text-amber-700 border-amber-200",
  processing: "bg-blue-50 text-blue-700 border-blue-200",
  succeeded: "bg-emerald-50 text-emerald-700 border-emerald-200",
  failed: "bg-red-50 text-red-700 border-red-200",
  refunded: "bg-grouped text-muted border-line"
};

function defaultLabel(status: string) {
  return status
    .split("_")
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}

export default function StatusPill({ status, label }: { status: string; label?: string }) {
  const classes = STYLES[status] ?? "bg-grouped text-muted border-line";
  return (
    <span className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-[11px] font-medium ${classes}`}>
      {label ?? defaultLabel(status)}
    </span>
  );
}
