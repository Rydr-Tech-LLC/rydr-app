"use client";

import { FormEvent, useState } from "react";
import {
  EmailAuthProvider,
  reauthenticateWithCredential,
  updatePassword
} from "firebase/auth";
import { clientAuth } from "@/lib/firebaseClient";

export default function PasswordChangeForm() {
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setMessage(null);

    if (newPassword !== confirmation) {
      setMessage("The new passwords do not match.");
      return;
    }
    const passwordError = validatePassword(newPassword);
    if (passwordError) {
      setMessage(passwordError);
      return;
    }

    await clientAuth.authStateReady();
    const user = clientAuth.currentUser;
    if (!user?.email) {
      setMessage("Your sign-in session is unavailable. Sign out and sign back in before changing your password.");
      return;
    }

    setBusy(true);
    try {
      const credential = EmailAuthProvider.credential(user.email, currentPassword);
      await reauthenticateWithCredential(user, credential);
      await updatePassword(user, newPassword);
      setCurrentPassword("");
      setNewPassword("");
      setConfirmation("");
      setMessage("Password updated.");
    } catch {
      setMessage("The password could not be updated. Check your current password and try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit} className="rounded-lg border border-line bg-white p-5 shadow-sm">
      <h2 className="text-sm font-semibold text-ink">Change Password</h2>
      <p className="mt-1 text-sm text-muted">Confirm your current password before choosing a new one.</p>

      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <label className="text-xs font-semibold text-muted sm:col-span-2">
          Current password
          <input
            type="password"
            autoComplete="current-password"
            value={currentPassword}
            onChange={(event) => setCurrentPassword(event.target.value)}
            className="mt-1 w-full rounded-md border border-line bg-white px-3 py-2 text-sm font-normal text-ink outline-none focus:border-ink"
            required
          />
        </label>
        <label className="text-xs font-semibold text-muted">
          New password
          <input
            type="password"
            autoComplete="new-password"
            value={newPassword}
            onChange={(event) => setNewPassword(event.target.value)}
            className="mt-1 w-full rounded-md border border-line bg-white px-3 py-2 text-sm font-normal text-ink outline-none focus:border-ink"
            required
          />
        </label>
        <label className="text-xs font-semibold text-muted">
          Confirm new password
          <input
            type="password"
            autoComplete="new-password"
            value={confirmation}
            onChange={(event) => setConfirmation(event.target.value)}
            className="mt-1 w-full rounded-md border border-line bg-white px-3 py-2 text-sm font-normal text-ink outline-none focus:border-ink"
            required
          />
        </label>
      </div>

      {message ? <p className="mt-3 text-xs text-muted">{message}</p> : null}

      <button
        type="submit"
        disabled={busy}
        className="mt-4 rounded-md bg-ink px-4 py-2 text-xs font-semibold text-white disabled:opacity-50"
      >
        {busy ? "Updating..." : "Update Password"}
      </button>
    </form>
  );
}

function validatePassword(password: string) {
  if (password.length < 10) return "Password must be at least 10 characters.";
  if (!/[A-Z]/.test(password)) return "Password must include an uppercase letter.";
  if (!/[a-z]/.test(password)) return "Password must include a lowercase letter.";
  if (!/[0-9]/.test(password)) return "Password must include a number.";
  if (!/[^A-Za-z0-9]/.test(password)) return "Password must include a symbol.";
  return "";
}
