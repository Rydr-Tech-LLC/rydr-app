"use client";
import { useCallback, useEffect, useState } from "react";
import { useWorkspace, WorkspaceLink } from "@/components/WorkspaceContext";
import { ShieldCheck, ArrowUpRight, RefreshCw, Link2 } from 'lucide-react';
import { Facebook, Instagram } from '@/components/SocialIcons';
import RowenIdentity from '@/components/RowenIdentity';
type Status = { configured: boolean; setupError: string; connected: boolean; expired: boolean; pageName: string | null; pageId: string | null; instagramUsername: string | null; connectedAt: number | null; expiresAt: number | null; lastWebhookAt: number | null; origin: string };
const date = (value: number | null | undefined) => value ? new Date(value).toLocaleString() : "Not recorded";
export default function SocialConnection() {
  const workspace = useWorkspace(), [status, setStatus] = useState<Status | null>(null), [error, setError] = useState(""), [busy, setBusy] = useState(false);
  const refresh = useCallback(async () => {
    const response = await fetch(`/api/meta/${workspace}/status`); const data = await response.json();
    if (!response.ok) throw new Error(data.error || "Could not load connection"); setStatus(data);
  }, [workspace]);
  useEffect(() => { setStatus(null); void refresh().catch(e => setError(e.message)); }, [refresh]);
  async function connect() {
    setBusy(true); setError("");
    try { const response = await fetch(`/api/meta/${workspace}/connect`, { method: "POST" }); const data = await response.json();
      if (!response.ok) throw new Error(data.error || "Connection failed"); window.location.assign(data.url);
    } catch (e) { setError((e as Error).message); setBusy(false); }
  }
  return <div className="space-y-5">
    <WorkspaceLink href="/campus-growth/agent" className="text-sm text-muted">Marketing Agent /</WorkspaceLink>
    <h1 className="text-2xl font-semibold text-ink">Social connections</h1>
    <p className="text-sm text-muted">Connect Rydr Tech’s business Facebook Page and @rydr_tech to Mission Control. Choose only Rydr’s business accounts in Meta’s authorization screen.</p>
    <RowenIdentity active="connections" status={status?.expired?'Reconnect required':status?.connected?'Connected to Rydr':'Let’s get connected'} subtitle="One home for Rydr’s social presence. The right accounts, connected with care."/>
    <div className="grid gap-4 md:grid-cols-2">
      <section className="rounded-2xl border border-line bg-white p-6 shadow-sm"><div className="flex items-center justify-between"><span className="rounded-2xl bg-blue-50 p-3 text-blue-600"><Facebook size={28}/></span><span className={`rounded-full px-3 py-1 text-xs font-semibold ${status?.connected&&!status.expired?'bg-emerald-50 text-emerald-700':'bg-grouped text-muted'}`}>{status?.expired?'Needs attention':status?.connected?'Connected':'Not connected'}</span></div><h2 className="mt-5 text-lg font-semibold">Facebook</h2><p className="mt-1 text-sm text-muted">{status?.pageName||'Rydr Tech'}</p><p className="mt-4 text-xs text-muted">Business Page identity and content access. Facebook publishing needs additional permissions.</p></section>
      <section className="rounded-2xl border border-line bg-white p-6 shadow-sm"><div className="flex items-center justify-between"><span className="rounded-2xl bg-gradient-to-br from-orange-100 via-pink-100 to-violet-100 p-3 text-pink-600"><Instagram size={28}/></span><span className={`rounded-full px-3 py-1 text-xs font-semibold ${status?.connected&&!status.expired?'bg-emerald-50 text-emerald-700':'bg-grouped text-muted'}`}>{status?.expired?'Needs attention':status?.connected?'Connected':'Not connected'}</span></div><h2 className="mt-5 text-lg font-semibold">Instagram</h2><p className="mt-1 text-sm text-muted">@{status?.instagramUsername||'rydr_tech'}</p><WorkspaceLink href="/campus-growth/social/workflows" className="mt-4 inline-flex items-center gap-2 text-xs font-semibold text-rydr-burgundy">Open Rowen’s social workspace <ArrowUpRight size={14}/></WorkspaceLink></section>
    </div>
    <section className="rounded-2xl border border-line bg-white p-6 shadow-sm">
      <div className="flex justify-between gap-3"><h2 className="text-lg font-semibold">Facebook & Instagram</h2><span className="rounded-full bg-grouped px-3 py-1 text-sm">{status?.expired ? "Reconnect required" : status?.connected ? "Connected" : "Not connected"}</span></div>
      <dl className="mt-4 grid grid-cols-2 gap-3 text-sm"><dt>Facebook Page</dt><dd>{status?.pageName || "Rydr Tech · pending"}</dd><dt>Instagram</dt><dd>@{status?.instagramUsername || "rydr_tech · pending"}</dd><dt>Connected</dt><dd>{date(status?.connectedAt)}</dd><dt>Token expiry</dt><dd>{date(status?.expiresAt)}</dd><dt>Last verified webhook</dt><dd>{date(status?.lastWebhookAt)}</dd></dl>
      <div className="mt-5 flex items-start gap-3 rounded-xl bg-violet-50 p-4"><ShieldCheck size={19} className="shrink-0 text-violet-600"/><p className="text-xs leading-relaxed text-muted">Your account tokens are encrypted on the server. Activate Rowen’s social brief to run scheduled posts and eligible replies during his weekday shift. Test and Live Beta keep separate connections; Test never publishes or sends replies.</p></div>
      {status?.setupError && <p className="mt-3 rounded-lg bg-grouped p-3 text-sm">{status.setupError}</p>}
      <div className="mt-5 flex flex-wrap gap-3"><button disabled={!status?.configured || busy} onClick={connect} className="flex items-center gap-2 rounded-xl bg-gradient-to-r from-rydr-red to-rydr-burgundy px-4 py-2.5 text-xs font-semibold text-white shadow-sm disabled:opacity-40"><Link2 size={15}/>{busy ? "Opening Meta…" : status?.connected ? "Reconnect business accounts" : "Connect business accounts"}</button><button className="flex items-center gap-2 rounded-xl border border-line px-4 py-2 text-xs font-semibold" onClick={() => refresh().catch(e => setError(e.message))}><RefreshCw size={14}/>Refresh</button></div>
      {error && <p role="status" className="mt-3 text-sm text-red-700">{error}</p>}
    </section>
    <details className="rounded-2xl border border-line bg-white p-5 text-xs text-muted shadow-sm"><summary className="cursor-pointer font-semibold text-ink">Developer connection details</summary><p className="mt-4">OAuth redirect</p><code className="mt-1 block break-all">{status?.origin}/api/meta/{workspace}/callback</code><p className="mt-3">Webhook callback</p><code className="mt-1 block break-all">{status?.origin}/api/meta/{workspace}/webhook</code></details>
  </div>;
}
