"use client";

import { useState, useTransition } from "react";

type Props = {
  initialEnabled: boolean;
  initialTermsVersion: string | null;
};

export default function CashHubBetaToggle({ initialEnabled, initialTermsVersion }: Props) {
  const [enabled, setEnabled] = useState(initialEnabled);
  const [termsVersion, setTermsVersion] = useState(initialTermsVersion);
  const [message, setMessage] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function update(nextEnabled: boolean) {
    setMessage(null);
    startTransition(async () => {
      const previous = enabled;
      setEnabled(nextEnabled);

      const res = await fetch("/api/platform-config/cash-rydr-hub", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          termsAcceptanceEnabled: nextEnabled,
          reason: nextEnabled ? "Live beta Cash Hub terms gate opened" : "Live beta Cash Hub terms gate closed"
        })
      });

      if (!res.ok) {
        setEnabled(previous);
        const data = (await res.json().catch(() => null)) as { error?: string } | null;
        setMessage(data?.error ?? "Could not update Cash Rydr Hub gate.");
        return;
      }

      const data = (await res.json().catch(() => null)) as { cashHubTermsVersion?: string } | null;
      setTermsVersion(data?.cashHubTermsVersion ?? null);
      setMessage(nextEnabled ? "Terms acceptance is enabled." : "Terms acceptance is disabled and prior acceptances were reset.");
    });
  }

  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <div className="flex items-start justify-between gap-5">
        <div>
          <h2 className="text-sm font-semibold text-ink">Cash Rydr Hub Live Beta Gate</h2>
          <p className="mt-2 max-w-2xl text-sm text-muted">
            Controls whether riders and drivers can accept Cash Rydr Hub terms. When off, both apps show the terms
            screen but block acceptance and prevent Cash Rydr Hub access, even for users who accepted earlier.
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
          {enabled ? "Acceptance enabled" : "Acceptance disabled for live beta"}
        </p>
      </div>
      <p className="mt-2 text-xs text-muted">Current terms version: {termsVersion ?? "Not set"}</p>

      {message ? <p className="mt-3 text-sm text-muted">{message}</p> : null}
    </div>
  );
}
