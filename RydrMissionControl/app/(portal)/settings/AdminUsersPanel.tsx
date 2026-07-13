"use client";

import { useRouter } from "next/navigation";
import { FormEvent, useState } from "react";
import StatusPill from "@/components/StatusPill";

interface AdminUserRecord {
  id: string;
  uid?: string;
  email?: string;
  displayName?: string;
  status?: string;
  passwordStatus?: string;
  createdLogin?: boolean;
  grantedByEmail?: string | null;
  revokedByEmail?: string | null;
}

export default function AdminUsersPanel({ admins }: { admins: AdminUserRecord[] }) {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [temporaryPassword, setTemporaryPassword] = useState("");
  const [grantEmail, setGrantEmail] = useState("");
  const [busy, setBusy] = useState<"create" | "grant" | "resetPassword" | "revoke" | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function submitCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await run("create", email, { displayName, temporaryPassword });
  }

  async function submitGrant(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await run("grant", grantEmail);
  }

  async function run(
    action: "create" | "grant" | "resetPassword" | "revoke",
    targetEmail: string,
    options: { displayName?: string; temporaryPassword?: string } = {}
  ) {
    setBusy(action);
    setMessage(null);
    try {
      const response = await fetch("/api/admin-users", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, email: targetEmail, ...options })
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? "Unable to update admin access.");
      if (action === "create") {
        setMessage(`Created admin login for ${body.email}. Share the temporary password through a secure channel.`);
        setEmail("");
        setDisplayName("");
        setTemporaryPassword("");
      } else if (action === "resetPassword") {
        setMessage(`Temporary password updated for ${body.email}. Share it through a secure channel.`);
      } else if (action === "grant") {
        setMessage(`Granted Mission Control access to ${body.email}. They must sign out and back in.`);
        setGrantEmail("");
      } else {
        setMessage(`Revoked Mission Control access for ${body.email}.`);
      }
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Unable to update admin access.");
    } finally {
      setBusy(null);
    }
  }

  function generatePassword() {
    const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%";
    const values = crypto.getRandomValues(new Uint32Array(16));
    const password = Array.from(values, (value) => alphabet[value % alphabet.length]).join("");
    setTemporaryPassword(password);
  }

  async function resetTemporaryPassword(targetEmail: string) {
    const nextPassword = window.prompt("Enter a new temporary password. Use at least 10 characters with uppercase, lowercase, number, and symbol.");
    if (!nextPassword) return;
    await run("resetPassword", targetEmail, { temporaryPassword: nextPassword });
  }

  return (
    <div className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 className="text-sm font-semibold text-ink">Mission Control Admins</h2>
          <p className="mt-1 text-sm text-muted">
            Create or grant admin access for <code className="rounded bg-grouped px-1">@rydr-go.com</code> staff accounts. Temporary passwords are never stored.
          </p>
        </div>
      </div>

      <div className="mt-4 grid gap-4 xl:grid-cols-[1.4fr_1fr]">
        <form onSubmit={submitCreate} className="rounded-md border border-line bg-grouped/40 p-4">
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="text-sm font-semibold text-ink">Create admin login</p>
              <p className="mt-1 text-xs text-muted">Creates the Firebase Auth account, verifies the email domain, and applies the admin role.</p>
            </div>
            <StatusPill status="active" label="Secure" />
          </div>
          <div className="mt-4 grid gap-3 md:grid-cols-2">
            <label className="text-xs font-semibold text-muted">
              Email
              <input
                type="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                placeholder="name@rydr-go.com"
                className="mt-1 w-full rounded-md border border-line bg-white px-3 py-2 text-sm font-normal text-ink outline-none focus:border-ink"
                required
              />
            </label>
            <label className="text-xs font-semibold text-muted">
              Display name
              <input
                type="text"
                value={displayName}
                onChange={(event) => setDisplayName(event.target.value)}
                placeholder="Optional"
                className="mt-1 w-full rounded-md border border-line bg-white px-3 py-2 text-sm font-normal text-ink outline-none focus:border-ink"
              />
            </label>
          </div>
          <label className="mt-3 block text-xs font-semibold text-muted">
            Temporary password
            <div className="mt-1 grid gap-2 sm:grid-cols-[1fr_auto]">
              <input
                type="text"
                value={temporaryPassword}
                onChange={(event) => setTemporaryPassword(event.target.value)}
                placeholder="At least 10 chars, mixed case, number, symbol"
                className="w-full rounded-md border border-line bg-white px-3 py-2 text-sm font-normal text-ink outline-none focus:border-ink"
                required
              />
              <button type="button" onClick={generatePassword} className="rounded-md border border-line bg-white px-3 py-2 text-xs font-semibold text-ink">
                Generate
              </button>
            </div>
          </label>
          <button type="submit" disabled={busy !== null} className="mt-4 rounded-md bg-ink px-4 py-2 text-xs font-semibold text-white disabled:opacity-50">
            {busy === "create" ? "Creating..." : "Create Admin Login"}
          </button>
        </form>

        <form onSubmit={submitGrant} className="rounded-md border border-line p-4">
          <p className="text-sm font-semibold text-ink">Grant existing user</p>
          <p className="mt-1 text-xs text-muted">Use this only when the Firebase Auth account already exists.</p>
          <input
            type="email"
            value={grantEmail}
            onChange={(event) => setGrantEmail(event.target.value)}
            placeholder="name@rydr-go.com"
            className="mt-4 w-full rounded-md border border-line bg-white px-3 py-2 text-sm text-ink outline-none focus:border-ink"
            required
          />
          <button type="submit" disabled={busy !== null} className="mt-3 rounded-md bg-ink px-4 py-2 text-xs font-semibold text-white disabled:opacity-50">
            {busy === "grant" ? "Granting..." : "Grant Admin"}
          </button>
        </form>
      </div>

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
                      {admin.passwordStatus === "temporary" ? <StatusPill status="queued" label="Temp password" /> : null}
                    </div>
                    <p className="mt-1 text-xs text-muted">
                      {admin.displayName ? `${admin.displayName} · ` : ""}
                      UID: {admin.uid ?? admin.id}
                      {admin.createdLogin ? " · Created in Mission Control" : ""}
                      {admin.grantedByEmail ? ` · Granted by ${admin.grantedByEmail}` : ""}
                      {admin.revokedByEmail ? ` · Revoked by ${admin.revokedByEmail}` : ""}
                    </p>
                  </div>
                  <div className="flex flex-wrap items-center gap-2">
                    <button
                      type="button"
                      disabled={busy !== null || status === "revoked" || !admin.email}
                      onClick={() => admin.email && resetTemporaryPassword(admin.email)}
                      className="rounded-md border border-line bg-white px-3 py-1.5 text-xs font-semibold text-ink disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      {busy === "resetPassword" ? "Saving..." : "Set Temp Password"}
                    </button>
                    <button
                      type="button"
                      disabled={busy !== null || status === "revoked" || !admin.email}
                      onClick={() => admin.email && run("revoke", admin.email)}
                      className="rounded-md border border-red-200 bg-red-50 px-3 py-1.5 text-xs font-semibold text-red-700 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      {busy === "revoke" ? "Revoking..." : "Revoke"}
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
