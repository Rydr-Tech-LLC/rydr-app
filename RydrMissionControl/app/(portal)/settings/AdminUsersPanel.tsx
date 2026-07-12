"use client";

import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";
import StatusPill from "@/components/StatusPill";

interface AdminUserRecord {
  id: string;
  uid?: string;
  email?: string;
  status?: string;
  grantedByEmail?: string | null;
  revokedByEmail?: string | null;
}

export default function AdminUsersPanel({ admins }: { admins: AdminUserRecord[] }) {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState<"grant" | "revoke" | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await run("grant", email);
  }

  async function run(action: "grant" | "revoke", targetEmail: string) {
    setBusy(action);
    setMessage(null);
    try {
      const response = await fetch("/api/admin-users", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, email: targetEmail })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? "Unable to update admin access.");
      setMessage(
        action === "grant"
          ? `Granted Mission Control access to ${body.email}. They must sign out and back in.`
          : `Revoked Mission Control access for ${body.email}.`
      );
      if (action === "grant") setEmail("");
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to update admin access.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 className="text-sm font-semibold text-ink">Mission Control Admins</h2>
          <p className="mt-1 text-sm text-muted">
            Grant admin access to existing Firebase Auth users with a <code className="rounded bg-grouped px-1">@rydr-go.com</code> email.
          </p>
        </div>
      </div>

      <form onSubmit={submit} className="mt-4 grid gap-2 sm:grid-cols-[1fr_auto]">
        <input
          type="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          placeholder="name@rydr-go.com"
          className="w-full rounded-md border border-line bg-white px-3 py-2 text-sm text-ink outline-none focus:border-ink"
          required
        />
        <button type="submit" disabled={busy !== null} className="rounded-md bg-ink px-4 py-2 text-xs font-semibold text-white disabled:opacity-50">
          {busy === "grant" ? "Granting..." : "Grant Admin"}
        </button>
      </form>

      {message && <p className="mt-3 text-xs text-muted">{message}</p>}

      <div className="mt-5 overflow-hidden rounded-md border border-line">
        {admins.length === 0 ? (
          <p className="px-4 py-6 text-center text-sm text-muted">No admin grants have been tracked from Mission Control yet.</p>
        ) : (
          <div className="divide-y divide-line">
            {admins.map((admin) => {
              const status = admin.status ?? "active";
              return (
                <div key={admin.id} className="grid gap-3 px-4 py-3 sm:grid-cols-[1fr_auto]">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="truncate text-sm font-medium text-ink">{admin.email ?? admin.id}</p>
                      <StatusPill status={status} />
                    </div>
                    <p className="mt-1 text-xs text-muted">
                      UID: {admin.uid ?? admin.id}
                      {admin.grantedByEmail ? ` · Granted by ${admin.grantedByEmail}` : ""}
                      {admin.revokedByEmail ? ` · Revoked by ${admin.revokedByEmail}` : ""}
                    </p>
                  </div>
                  <button
                    type="button"
                    disabled={busy !== null || status === "revoked" || !admin.email}
                    onClick={() => admin.email && run("revoke", admin.email)}
                    className="rounded-md border border-red-200 bg-red-50 px-3 py-1.5 text-xs font-semibold text-red-700 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    {busy === "revoke" ? "Revoking..." : "Revoke"}
                  </button>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
