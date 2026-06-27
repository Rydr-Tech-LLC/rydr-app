export default function StatCard({
  label,
  value,
  tone = "default"
}: {
  label: string;
  value: string | number;
  tone?: "default" | "warning" | "danger" | "good";
}) {
  const toneClasses: Record<string, string> = {
    default: "text-ink",
    warning: "text-champagne",
    danger: "text-rydr-red",
    good: "text-emerald-600"
  };

  return (
    <div className="rounded-lg border border-line bg-white p-4 shadow-sm">
      <p className="text-xs font-medium text-muted">{label}</p>
      <p className={`mt-1.5 text-2xl font-semibold ${toneClasses[tone]}`}>{value}</p>
    </div>
  );
}
