"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function PromotionActions({ id, status }: { id: string; status: string }) {
  const router = useRouter();
  const [loading, setLoading] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function run(action: string) {
    setLoading(action);
    setError(null);
    try {
      const res = await fetch(`/api/promotions/${id}/action`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action })
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(body.error ?? "Action failed.");
        return;
      }
      if (body.newPromotionId) {
        router.push(`/promotions/${body.newPromotionId}`);
      } else {
        router.refresh();
      }
    } finally {
      setLoading(null);
    }
  }

  async function archive() {
    if (!window.confirm("Delete this promotion from active Mission Control views? Its audit history and redemptions remain available.")) return;
    await run("archive");
  }

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-2">
        {status !== "active" && <Button label="Activate" loading={loading === "activate"} onClick={() => run("activate")} />}
        {status === "active" && <Button label="Pause" loading={loading === "pause"} onClick={() => run("pause")} />}
        {status !== "scheduled" && status !== "active" && <Button label="Schedule" loading={loading === "schedule"} onClick={() => run("schedule")} />}
        {status !== "ended" && <Button label="End" loading={loading === "end"} onClick={() => run("end")} muted />}
        <Button label="Reuse" loading={loading === "reuse"} onClick={() => run("reuse")} muted />
        <Button label="Delete" loading={loading === "archive"} onClick={archive} danger />
      </div>
      {error && <p className="text-xs text-rydr-red">{error}</p>}
    </div>
  );
}

function Button({
  label,
  loading,
  onClick,
  muted,
  danger
}: {
  label: string;
  loading: boolean;
  onClick: () => void;
  muted?: boolean;
  danger?: boolean;
}) {
  const className = danger
    ? "rounded-md border border-red-200 bg-red-50 px-3 py-1.5 text-xs font-semibold text-red-700 disabled:opacity-50"
    : muted
      ? "rounded-md border border-line bg-white px-3 py-1.5 text-xs font-semibold text-ink disabled:opacity-50"
      : "rounded-md bg-ink px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-50";
  return (
    <button onClick={onClick} disabled={loading} className={className}>
      {loading ? "Working" : label}
    </button>
  );
}
