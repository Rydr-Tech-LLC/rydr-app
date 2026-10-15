export default function StatCard({
  label,
  value,
  tone = "default",
}: {
  label: string;
  value: string | number;
  tone?: "default" | "warning" | "danger" | "good";
}) {
  const toneClasses: Record<string, string> = {
    default: "text-ink",
    warning: "text-amber-700",
    danger: "text-rydr-red",
    good: "text-emerald-600",
  };

  return (
    <div className="relative overflow-hidden rounded-lg border border-line bg-white p-5 shadow-sm before:absolute before:inset-x-5 before:top-0 before:h-0.5 before:bg-gradient-to-r before:from-red-400 before:via-pink-400 before:to-violet-400">
      <p className="text-xs font-medium text-muted">{label}</p>
      <p
        className={`mt-1.5 text-3xl font-semibold tracking-tight ${toneClasses[tone]}`}
      >
        {value}
      </p>
    </div>
  );
}
