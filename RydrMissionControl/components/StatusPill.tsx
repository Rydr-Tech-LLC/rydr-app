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
  inactive: "bg-grouped text-muted border-line",
  researching: "bg-blue-50 text-blue-700 border-blue-200",
  draft: "bg-grouped text-muted border-line",
  new: "bg-blue-50 text-blue-700 border-blue-200",
  qualified: "bg-emerald-50 text-emerald-700 border-emerald-200",
  queued: "bg-amber-50 text-amber-700 border-amber-200",
  contacted: "bg-blue-50 text-blue-700 border-blue-200",
  replied: "bg-emerald-50 text-emerald-700 border-emerald-200",
  denied: "bg-red-50 text-red-700 border-red-200",
  sent: "bg-emerald-50 text-emerald-700 border-emerald-200",
  prospect: "bg-blue-50 text-blue-700 border-blue-200",
  interview: "bg-amber-50 text-amber-700 border-amber-200",
  accepted: "bg-emerald-50 text-emerald-700 border-emerald-200",
  pending_review: "bg-amber-50 text-amber-700 border-amber-200",
  low: "bg-grouped text-muted border-line",
  medium: "bg-amber-50 text-amber-700 border-amber-200",
  high: "bg-red-50 text-red-700 border-red-200",
  cold: "bg-grouped text-muted border-line",
  warm: "bg-amber-50 text-amber-700 border-amber-200",
  partner: "bg-emerald-50 text-emerald-700 border-emerald-200",
  organization: "bg-blue-50 text-blue-700 border-blue-200",
  club: "bg-blue-50 text-blue-700 border-blue-200",
  chapter: "bg-blue-50 text-blue-700 border-blue-200",
  incubator: "bg-purple-50 text-purple-700 border-purple-200",
  event: "bg-amber-50 text-amber-700 border-amber-200",
  department: "bg-emerald-50 text-emerald-700 border-emerald-200",
  student_government: "bg-emerald-50 text-emerald-700 border-emerald-200",
  student_media: "bg-purple-50 text-purple-700 border-purple-200",
  scheduled: "bg-blue-50 text-blue-700 border-blue-200",
  paused: "bg-amber-50 text-amber-700 border-amber-200",
  ended: "bg-grouped text-muted border-line",
  archived: "bg-grouped text-muted border-line",
  feePending: "bg-amber-50 text-amber-700 border-amber-200",
  fee_pending: "bg-amber-50 text-amber-700 border-amber-200",
  partiallyCollected: "bg-blue-50 text-blue-700 border-blue-200",
  partially_collected: "bg-blue-50 text-blue-700 border-blue-200",
  collected: "bg-emerald-50 text-emerald-700 border-emerald-200",
  unknown: "bg-grouped text-muted border-line",
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
