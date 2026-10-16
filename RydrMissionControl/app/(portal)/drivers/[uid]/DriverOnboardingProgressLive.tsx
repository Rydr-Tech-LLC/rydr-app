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
  const [target, setTarget] = useState<{ key: string; label: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [failed, setFailed] = useState(false);
  async function resume() {
    if (!target || !window.confirm(`Return this driver to ${target.label}? Saved documents and Stripe setup will be preserved. Driving will be disabled until onboarding is complete.`)) return;
    setBusy(true); setNotice(""); setFailed(false);
    try {
      const response = await fetch(`/api/drivers/${uid}/onboarding`, { method: "POST" });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? "Unable to resume onboarding.");
      setNotice(`Onboarding resumed at ${body.resumeTarget.label}. The updated driver app will reopen this step.`);
    } catch (error) { setFailed(true); setNotice(error instanceof Error ? error.message : "Unable to resume onboarding."); }
    finally { setBusy(false); }
  }

  useEffect(() => {
    let cancelled = false;
    async function refresh() {
      const response = await fetch(`/api/drivers/${uid}/onboarding`, { cache: "no-store" }).catch(() => null);
      if (!response?.ok) return;
      const body = (await response.json()) as { progress?: DriverOnboardingProgressView; resumeTarget?: { key: string; label: string } };
      if (!cancelled && body.progress) { setProgress(body.progress); setTarget(body.resumeTarget ?? null); }
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
      <div className="rounded-xl border border-rydr-red/20 bg-gradient-to-br from-rydr-red/5 via-white to-purple-50 p-4">
        <p className="text-sm font-semibold text-ink">Resume onboarding</p>
        <p className="mt-2 text-xs text-muted">Reopen the next unfinished step after their saved progress. Documents, vehicle details, and Stripe setup are preserved.</p>
        <p className="mt-2 text-xs font-semibold text-ink">Resume at: {target?.label ?? "Checking saved progress…"}</p>
        <button onClick={resume} disabled={busy || !target} className="mt-3 w-full rounded-lg bg-gradient-to-r from-rydr-red to-purple-600 px-4 py-2 text-xs font-semibold text-white disabled:opacity-40">{busy ? "Resuming…" : "Send back to onboarding"}</button>
        <p className="mt-2 text-[11px] text-muted">Requires the updated driver build. Driving is disabled immediately. Active rides must be resolved first. Every action is audited.</p>
        {notice && <p role="status" className={`mt-3 text-xs ${failed ? "text-rydr-red" : "text-emerald-700"}`}>{notice}</p>}
      </div>
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
