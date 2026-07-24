"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { signInWithEmailAndPassword } from "firebase/auth";
import { clientAuth } from "@/lib/firebaseClient";

export default function LoginForm() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      const credential = await signInWithEmailAndPassword(clientAuth, email, password);
      const idToken = await credential.user.getIdToken();

      const response = await fetch("/api/session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ idToken })
      });

      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        await clientAuth.signOut();
        setError(body.error ?? "Unable to sign in.");
        return;
      }

      const body = await response.json() as { role?: string };
      router.push(body.role === "marketing" ? "/campus-growth" : "/dashboard");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unable to sign in.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3 rounded-lg bg-white/5 p-6 backdrop-blur">
      <div>
        <label className="mb-1 block text-xs font-medium text-white/70">Email</label>
        <input
          type="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="w-full rounded-md border border-white/10 bg-white/10 px-3 py-2 text-sm text-white placeholder-white/30 outline-none focus:border-rydr-red"
          placeholder="you@rydr-go.com"
        />
      </div>
      <div>
        <label className="mb-1 block text-xs font-medium text-white/70">Password</label>
        <input
          type="password"
          required
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className="w-full rounded-md border border-white/10 bg-white/10 px-3 py-2 text-sm text-white placeholder-white/30 outline-none focus:border-rydr-red"
          placeholder="••••••••"
        />
      </div>
      {error && <p className="text-xs text-rydr-red">{error}</p>}
      <button
        type="submit"
        disabled={loading}
        className="w-full rounded-md bg-gradient-to-r from-rydr-red to-rydr-burgundy py-2 text-sm font-semibold text-white transition disabled:opacity-50"
      >
        {loading ? "Signing in…" : "Sign in"}
      </button>
      <p className="pt-1 text-center text-[11px] text-white/30">
        Access is restricted to approved Rydr staff accounts.
      </p>
    </form>
  );
}
