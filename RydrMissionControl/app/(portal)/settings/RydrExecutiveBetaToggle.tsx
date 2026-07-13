"use client";

import { useState, useTransition } from "react";

type Props = {
  initialEnabled: boolean;
};

export default function RydrExecutiveBetaToggle({ initialEnabled }: Props) {
  const [enabled, setEnabled] = useState(initialEnabled);
  const [message, setMessage] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function update(nextEnabled: boolean) {
    setMessage(null);
    startTransition(async () => {
      const previous = enabled;
      setEnabled(nextEnabled);

      const res = await fetch("/api/platform-config/rydr-executive", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          enabled: nextEnabled,
          reason: nextEnabled ? "Rydr Executive beta offering enabled" : "Rydr Executive paused during Phase 0 beta"
        })
      });

      if (!res.ok) {
        setEnabled(previous);
        const data = (await res.json().catch(() => null)) as { error?: string } | null;
        setMessage(data?.error ?? "Could not update Rydr Executive availability.");
        return;
      }

      setMessage(nextEnabled ? "Rydr Executive is available to riders." : "Rydr Executive is hidden from rider booking during beta.");
    });
  }

  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <div className="flex items-start justify-between gap-5">
        <div>
          <h2 className="text-sm font-semibold text-ink">Rydr Executive Beta Gate</h2>
          <p className="mt-2 max-w-2xl text-sm text-muted">
            Controls whether Rydr Executive can be offered in rider booking during Phase 0 beta. Keep this off until the
            Executive operating model, vehicle qualifications, and driver readiness are approved.
          </p>
        </div>

        <button
          type="button"
          role="switch"
          aria-checked={enabled}
          disabled={isPending}
          onClick={() => update(!enabled)}
          className={`relative h-8 w-14 flex-shrink-0 rounded-full transition ${
            enabled ? "bg-rydr-red" : "bg-gray-300"
          } ${isPending ? "cursor-wait opacity-70" : "cursor-pointer"}`}
        >
          <span
            className={`absolute top-1 h-6 w-6 rounded-full bg-white shadow-sm transition ${
              enabled ? "left-7" : "left-1"
            }`}
          />
        </button>
      </div>

      <div className="mt-4 flex items-center gap-2">
        <span className={`h-2.5 w-2.5 rounded-full ${enabled ? "bg-rydr-red" : "bg-gray-400"}`} />
        <p className="text-sm font-medium text-ink">
          {enabled ? "Executive available" : "Executive paused for live beta"}
        </p>
      </div>

      {message ? <p className="mt-3 text-sm text-muted">{message}</p> : null}
    </div>
  );
}
