"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";

export default function ReviewActions({ jobId }: { jobId: string }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const router = useRouter();
  async function act(action: string) {
    setBusy(true); setError("");
    try {
      const response = await fetch(`/api/vehicle-image-jobs/${jobId}`, { method: "POST",
        headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action }) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || "Action failed");
      router.refresh();
    } catch (e) { setError(e instanceof Error ? e.message : "Action failed"); }
    finally { setBusy(false); }
  }
  return <div className="space-y-2">
    <div className="flex flex-wrap gap-3">
      <button className="rounded border px-3 py-2 text-sm" disabled={busy} onClick={() => act("retry")}>Retry search</button>
      <button className="rounded border px-3 py-2 text-sm" disabled={busy} onClick={() => act("use_library")}>Use uploaded library image</button>
      <button className="rounded border px-3 py-2 text-sm" disabled={busy} onClick={() => act("dismiss")}>Dismiss</button>
    </div>
    {error && <p role="alert" className="text-sm text-red-600">{error}</p>}
  </div>;
}
