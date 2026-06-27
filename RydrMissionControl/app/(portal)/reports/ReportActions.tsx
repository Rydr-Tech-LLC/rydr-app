"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function ReportActions({ id, hasDriver, hasRider }: { id: string; hasDriver: boolean; hasRider: boolean }) {
  const router = useRouter();
  const [loading, setLoading] = useState<string | null>(null);

  async function run(action: string) {
    setLoading(action);
    try {
      await fetch(`/api/reports/${id}/action`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action })
      });
      router.refresh();
    } finally {
      setLoading(null);
    }
  }

  return (
    <div className="flex flex-wrap gap-1.5">
      <ActionButton label="Open" onClick={() => run("escalate")} loading={loading === "escalate"} variant="muted" />
      <ActionButton label="Dismiss" onClick={() => run("dismiss")} loading={loading === "dismiss"} variant="muted" />
      <ActionButton label="Escalate" onClick={() => run("escalate")} loading={loading === "escalate"} variant="warning" />
      {hasDriver && (
        <ActionButton label="Suspend Driver" onClick={() => run("suspend_driver")} loading={loading === "suspend_driver"} variant="danger" />
      )}
      {hasRider && (
        <ActionButton label="Suspend Rider" onClick={() => run("suspend_rider")} loading={loading === "suspend_rider"} variant="danger" />
      )}
    </div>
  );
}

function ActionButton({
  label,
  onClick,
  loading,
  variant
}: {
  label: string;
  onClick: () => void;
  loading: boolean;
  variant: "muted" | "warning" | "danger";
}) {
  const styles = {
    muted: "bg-grouped text-ink hover:bg-line",
    warning: "bg-amber-500 text-white hover:bg-amber-600",
    danger: "bg-rydr-red text-white hover:bg-rydr-red/90"
  }[variant];

  return (
    <button
      onClick={onClick}
      disabled={loading}
      className={`rounded-md px-2.5 py-1 text-[11px] font-medium transition disabled:opacity-50 ${styles}`}
    >
      {loading ? "…" : label}
    </button>
  );
}
