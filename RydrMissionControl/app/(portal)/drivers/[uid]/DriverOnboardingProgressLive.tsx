"use client";

import { useEffect, useState } from "react";
import type { DriverOnboardingProgressView } from "@/lib/driverOnboardingProgress";

export default function DriverOnboardingProgressLive({
  uid,
  initial
}: {
  uid: string;
  initial: DriverOnboardingProgressView;
}) {
  const [progress, setProgress] = useState(initial);

  useEffect(() => {
    let cancelled = false;
    async function refresh() {
      const response = await fetch(`/api/drivers/${uid}/onboarding`, { cache: "no-store" });
      if (!response.ok) return;
      const body = (await response.json()) as { progress?: DriverOnboardingProgressView };
      if (!cancelled && body.progress) setProgress(body.progress);
    }

    const id = window.setInterval(refresh, 5000);
    refresh();
    return () => {
      cancelled = true;
      window.clearInterval(id);
    };
  }, [uid]);

  const lastSeen = progress.lastSeen ? new Date(progress.lastSeen) : null;

  return (
    <div className="space-y-4">
      <div className="rounded-md bg-grouped p-3">
        <p className="text-[11px] font-medium text-muted">Current page</p>
        <p className="mt-1 text-sm font-semibold text-ink">{progress.currentStep}</p>
        <p className="mt-1 text-[11px] text-muted">
          {progress.currentIndex
            ? `Step ${Math.min(progress.currentIndex, progress.totalSteps)} of ${progress.totalSteps}`
            : `${progress.completedCount} of ${progress.steps.length} completed`}
          {lastSeen ? ` · last seen ${lastSeen.toLocaleString()}` : ""}
        </p>
      </div>

      <div className="space-y-2">
        {progress.steps.map((step) => (
          <div
            key={step.key}
            className={`flex items-start gap-2 rounded-md border px-3 py-2 ${
              step.active ? "border-rydr-red bg-rydr-red/5" : "border-line bg-white"
            }`}
          >
            <span
              className={`mt-0.5 flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-bold ${
                step.complete ? "bg-emerald-100 text-emerald-700" : step.active ? "bg-rydr-red text-white" : "bg-grouped text-muted"
              }`}
            >
              {step.complete ? "✓" : step.index}
            </span>
            <div className="min-w-0">
              <p className="text-xs font-semibold text-ink">{step.label}</p>
              <p className="text-[11px] text-muted">{step.complete ? "Completed" : step.active ? "Current page" : "Not completed"}</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
