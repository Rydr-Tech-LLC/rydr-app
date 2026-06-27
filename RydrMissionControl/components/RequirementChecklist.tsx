import { DRIVER_APPROVAL_REQUIREMENTS } from "@/lib/types";

export default function RequirementChecklist({ checks }: { checks: Record<string, boolean> }) {
  return (
    <ul className="space-y-1.5">
      {DRIVER_APPROVAL_REQUIREMENTS.map((req) => {
        const met = checks[req.key];
        return (
          <li key={req.key} className="flex items-center gap-2 text-sm">
            <span
              className={`flex h-4 w-4 flex-shrink-0 items-center justify-center rounded-full text-[10px] text-white ${
                met ? "bg-emerald-500" : "bg-line text-muted"
              }`}
            >
              {met ? "✓" : ""}
            </span>
            <span className={met ? "text-ink" : "text-muted"}>{req.label}</span>
          </li>
        );
      })}
    </ul>
  );
}
