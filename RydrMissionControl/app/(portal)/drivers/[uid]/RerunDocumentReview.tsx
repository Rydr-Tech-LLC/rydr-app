"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useWorkspace } from "@/components/WorkspaceContext";

export default function RerunDocumentReview({ uid, kind, reviewId }: {
  uid: string;
  kind: string;
  reviewId: string;
}) {
  const router = useRouter();
  const workspace = useWorkspace();
  const [working, setWorking] = useState(false);
  const [error, setError] = useState("");

  async function rerun() {
    setWorking(true);
    setError("");
    try {
      const response = await fetch(`/api/drivers/${encodeURIComponent(uid)}/document-ocr`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-rydr-workspace": workspace },
        body: JSON.stringify({ kind, reviewId })
      });
      if (!response.ok) {
        const result = await response.json();
        throw new Error(result.error ?? "Automated review could not be completed.");
      }
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Automated review could not be completed.");
    } finally {
      setWorking(false);
    }
  }

  return <div className="mt-3">
    <button type="button" onClick={rerun} disabled={working} className="rounded-lg border border-line px-3 py-1.5 text-xs font-medium disabled:opacity-50">
      {working ? "Reading document…" : "Re-run automated review"}
    </button>
    {error && <p role="alert" className="mt-1 text-xs text-red-700">{error}</p>}
  </div>;
}
