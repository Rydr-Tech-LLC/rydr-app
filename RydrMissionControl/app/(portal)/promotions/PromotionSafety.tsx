"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
export default function PromotionSafety({
  signals,
  holds,
}: {
  signals: {
    id: string;
    userId: string;
    relatedUserId: string;
    reason: string;
    promotionId: string;
  }[];
  holds: { userId: string; reason: string }[];
}) {
  const router = useRouter();
  const [userId, setUserId] = useState("");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  async function act(action: string, uid = userId, signalId?: string) {
    setBusy(true);
    setMessage("");
    try {
      const r = await fetch("/api/promotions/safety", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, userId: uid, reason, signalId }),
      });
      const b = await r.json();
      if (!r.ok) throw Error(b.error);
      setMessage(
        "Saved. Existing payment reservations keep their committed amount; new rides use the updated controls.",
      );
      router.refresh();
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Could not save.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="rounded-2xl border border-line bg-white p-5 space-y-4">
      <div>
        <h2 className="text-lg font-semibold">Promotion safeguards</h2>
        <p className="text-sm text-muted">
          Hold future promotion use for an account, or review shared verified
          phones and payment cards on new-user offers. A shared card may belong
          to a family; review before treating it as abuse.
        </p>
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <input
          aria-label="Account ID"
          placeholder="Account ID"
          value={userId}
          onChange={(e) => setUserId(e.target.value)}
          className="rounded-xl border border-line p-3"
        />
        <input
          aria-label="Review reason"
          placeholder="Review reason (required for every action)"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          className="rounded-xl border border-line p-3"
        />
      </div>
      <div className="flex gap-3">
        <button
          disabled={busy || reason.trim().length < 5 || !userId}
          onClick={() => act("hold")}
          className="rounded-xl bg-ink text-white px-4 py-2 disabled:opacity-40"
        >
          Hold promotions
        </button>
        <button
          disabled={busy || reason.trim().length < 5 || !userId}
          onClick={() => act("release")}
          className="rounded-xl border border-line px-4 py-2 disabled:opacity-40"
        >
          Release account hold
        </button>
      </div>
      {message && (
        <p role="status" className="text-sm">
          {message}
        </p>
      )}
      <p className="text-xs text-muted">
        Up to 50 pending review signals and 50 held accounts. Releasing an
        account hold does not clear a shared-identity review. Review exceptions
        apply only to the selected campaign.
      </p>
      {holds.map((h) => (
        <div key={h.userId} className="rounded-xl bg-amber-50 p-3 text-sm">
          Held:{" "}
          <button onClick={() => setUserId(h.userId)} className="underline">
            {h.userId}
          </button>{" "}
          · {h.reason}
        </div>
      ))}
      {signals.map((s) => (
        <div
          key={s.id}
          className="rounded-xl border border-amber-200 p-3 text-sm flex flex-wrap justify-between gap-3"
        >
          <div>
            <p className="font-semibold">{s.reason.replaceAll("_", " ")}</p>
            <p>
              Account {s.userId} · related account {s.relatedUserId}
            </p>
            <p className="text-xs text-muted">Campaign {s.promotionId}</p>
          </div>
          <div className="flex gap-2">
            <button onClick={() => setUserId(s.userId)} className="underline">
              Select account
            </button>
            <button
              disabled={busy || reason.trim().length < 5}
              onClick={() => act("allow_shared_identity", s.userId, s.id)}
              className="rounded-xl border border-line px-3 py-2 disabled:opacity-40"
            >
              Allow this campaign after review
            </button>
          </div>
        </div>
      ))}
      {!signals.length && (
        <p className="text-sm text-muted">
          No shared-identity reviews pending. Detection uses available verified
          phone and Stripe default-card evidence; it cannot identify every
          duplicate account.
        </p>
      )}
    </section>
  );
}
