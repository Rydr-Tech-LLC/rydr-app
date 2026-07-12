"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export default function OutreachActions({ id, status }: { id: string; status: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function run(action: "approve" | "deny" | "mark_sent" | "mark_replied" | "reset") {
    const reason = action === "deny" ? window.prompt("Why is this outreach draft being denied?") : undefined;
    if (action === "deny" && !reason?.trim()) return;

    setBusy(action);
    setMessage(null);
    try {
      const response = await fetch(`/api/campus-growth/outreach/${id}/action`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, reason })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? "Unable to update draft.");
      setMessage("Updated.");
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to update draft.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="flex flex-col items-end gap-1.5">
      <div className="flex flex-wrap justify-end gap-1.5">
        <Button label="Approve" disabled={status === "approved"} busy={busy === "approve"} onClick={() => run("approve")} />
        <Button label="Deny" disabled={status === "denied"} busy={busy === "deny"} danger onClick={() => run("deny")} />
        <Button label="Sent" disabled={status === "sent"} busy={busy === "mark_sent"} muted onClick={() => run("mark_sent")} />
        <Button label="Replied" disabled={status === "replied"} busy={busy === "mark_replied"} muted onClick={() => run("mark_replied")} />
        <Button label="Reset" disabled={status === "draft"} busy={busy === "reset"} muted onClick={() => run("reset")} />
      </div>
      {message && <p className="max-w-xs text-right text-[11px] text-muted">{message}</p>}
    </div>
  );
}

function Button({
  label,
  busy,
  disabled,
  muted,
  danger,
  onClick
}: {
  label: string;
  busy: boolean;
  disabled: boolean;
  muted?: boolean;
  danger?: boolean;
  onClick: () => void;
}) {
  const className = danger
    ? "rounded-md bg-red-600 px-3 py-1.5 text-xs font-semibold text-white disabled:cursor-not-allowed disabled:opacity-40"
    : muted
      ? "rounded-md border border-line bg-white px-3 py-1.5 text-xs font-semibold text-ink disabled:cursor-not-allowed disabled:opacity-40"
      : "rounded-md bg-emerald-600 px-3 py-1.5 text-xs font-semibold text-white disabled:cursor-not-allowed disabled:opacity-40";

  return (
    <button type="button" disabled={busy || disabled} onClick={onClick} className={className}>
      {busy ? "Working..." : label}
    </button>
  );
}
