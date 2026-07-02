"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

const rewardGroups = [
  { value: "go_eco", label: "Rydr Go / Rydr Eco" },
  { value: "xl", label: "Rydr XL" },
  { value: "prestine", label: "Rydr Prestine" },
  { value: "executive", label: "Rydr Executive" }
] as const;

type RewardGroup = (typeof rewardGroups)[number]["value"];

export default function RydrBankMintPanel({ uid }: { uid: string }) {
  const router = useRouter();
  const [rewardGroup, setRewardGroup] = useState<RewardGroup>("go_eco");
  const [maxMiles, setMaxMiles] = useState(15);
  const [reason, setReason] = useState("Student Ambassador first ride free");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [mintedCode, setMintedCode] = useState<string | null>(null);

  async function mintCode() {
    setLoading(true);
    setError(null);
    setMintedCode(null);

    try {
      const response = await fetch(`/api/riders/${uid}/rydrbank/mint`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ rewardGroup, maxMiles, reason: reason || undefined })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) {
        setError(body.error ?? "Could not mint code.");
        return;
      }

      setMintedCode(body.code);
      router.refresh();
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <h2 className="mb-3 text-sm font-semibold text-ink">Mint RydrBank Code</h2>

      <div className="space-y-3">
        <label className="block">
          <span className="mb-1 block text-[11px] font-medium text-muted">Reward group</span>
          <select
            value={rewardGroup}
            onChange={(event) => setRewardGroup(event.target.value as RewardGroup)}
            className="w-full rounded-md border border-line bg-grouped px-3 py-2 text-xs outline-none focus:border-ink"
          >
            {rewardGroups.map((group) => (
              <option key={group.value} value={group.value}>
                {group.label}
              </option>
            ))}
          </select>
        </label>

        <label className="block">
          <span className="mb-1 block text-[11px] font-medium text-muted">Max miles</span>
          <input
            type="number"
            min={1}
            max={100}
            value={maxMiles}
            onChange={(event) => setMaxMiles(Number(event.target.value))}
            className="w-full rounded-md border border-line bg-grouped px-3 py-2 text-xs outline-none focus:border-ink"
          />
        </label>

        <label className="block">
          <span className="mb-1 block text-[11px] font-medium text-muted">Reason</span>
          <textarea
            value={reason}
            onChange={(event) => setReason(event.target.value)}
            className="w-full rounded-md border border-line bg-grouped px-3 py-2 text-xs outline-none focus:border-ink"
            rows={2}
          />
        </label>

        {mintedCode && (
          <div className="rounded-md border border-emerald-200 bg-emerald-50 px-3 py-2">
            <p className="text-[11px] font-medium text-emerald-700">Minted code</p>
            <p className="font-mono text-sm font-semibold text-emerald-900">{mintedCode}</p>
          </div>
        )}

        {error && <p className="text-xs text-rydr-red">{error}</p>}

        <button
          disabled={loading}
          onClick={mintCode}
          className="w-full rounded-md bg-ink py-2 text-xs font-semibold text-white transition disabled:opacity-40"
        >
          {loading ? "Minting..." : "Mint Code"}
        </button>
      </div>
    </div>
  );
}
