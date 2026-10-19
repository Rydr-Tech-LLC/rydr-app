"use client";

import { useCallback, useEffect, useState } from "react";
import { Bell, CalendarDays, CheckCircle2, Clock3, Radio, Send, Smartphone, Users, Car, Search } from "lucide-react";
import { useWorkspace } from "@/components/WorkspaceContext";
import StatCard from "@/components/StatCard";

type Campaign = { id: string; audience: string; title: string; body: string; status: string; sendAt: string; counts?: Record<string, number>; lastError?: string };
function easternISO(local: string) {
  for (const offset of ["-04:00", "-05:00"]) {
    const candidate = new Date(`${local}:00${offset}`);
    if (!Number.isFinite(candidate.getTime())) continue;
    const parts = new Intl.DateTimeFormat("sv-SE", { timeZone: "America/New_York", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(candidate).replace(" ", "T");
    if (parts === local) return candidate.toISOString();
  }
  return "";
}
const eastern = (value: string) => new Date(value).toLocaleString("en-US", { timeZone: "America/New_York", dateStyle: "medium", timeStyle: "short" });
const statusStyle: Record<string, string> = { scheduled: "bg-blue-50 text-blue-700", sending: "bg-violet-50 text-violet-700", completed: "bg-emerald-50 text-emerald-700", cancelled: "bg-slate-100 text-slate-600", expired: "bg-amber-50 text-amber-800", invalid: "bg-red-50 text-red-700" };
const milestones = [{ key: "five-days", date: "OCT 27", title: "5 days to go", description: "Build excitement for the beta." }, { key: "three-days", date: "OCT 29", title: "Get ready", description: "A reminder for riders and drivers." }, { key: "launch", date: "NOV 01", title: "We’re live", description: "First rides for riders. Go online for drivers." }];
export default function Notifications() {
  const workspace = useWorkspace();
  const [campaigns, setCampaigns] = useState<Campaign[]>([]);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [schedulerReady, setSchedulerReady] = useState(false);
  const [audience, setAudience] = useState("rider");
  const [filter, setFilter] = useState("all");
  const [search, setSearch] = useState("");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [sendAt, setSendAt] = useState("");
  const load = useCallback(async () => {
    try {
      const response = await fetch("/api/notifications", { cache: "no-store", headers: { "x-rydr-workspace": workspace } });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error);
      setCampaigns(data.campaigns); setSchedulerReady(data.schedulerReady);
    } catch (e) { setError(e instanceof Error ? e.message : "Could not load notifications."); }
    finally { setLoading(false); }
  }, [workspace]);
  useEffect(() => { void load(); const timer = setInterval(() => void load(), 30000); return () => clearInterval(timer); }, [load]);
  async function save(payload: object) {
    setBusy(true); setError(""); setNotice("");
    try {
      const response = await fetch("/api/notifications", { method: "POST", headers: { "Content-Type": "application/json", "x-rydr-workspace": workspace }, body: JSON.stringify(payload) });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error);
      setNotice("Announcement saved. Your schedule is up to date."); await load();
    } catch (e) { setError(e instanceof Error ? e.message : "Could not save notification."); }
    finally { setBusy(false); }
  }
  const scheduled = campaigns.filter(item => ["scheduled", "sending"].includes(item.status)).length;
  const sent = campaigns.reduce((sum, item) => sum + (item.counts?.sent ?? 0) + (item.counts?.partial ?? 0), 0);
  const failed = campaigns.reduce((sum, item) => sum + (item.counts?.failed ?? 0) + (item.counts?.unknown ?? 0), 0);
  const betaCount = campaigns.filter(item => item.id.startsWith("live-beta-2026-")).length;
  const visible = campaigns.filter(item => (filter === "all" || item.audience === filter) && `${item.title} ${item.body}`.toLowerCase().includes(search.toLowerCase()));
  const input = "mt-2 w-full border border-line px-3 py-2.5 text-sm text-ink";
  const action = "inline-flex min-h-11 items-center justify-center gap-2 rounded-xl px-5 py-3 text-sm font-semibold transition disabled:opacity-50";
  return <div className="space-y-6">
    <div className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-red-500 via-fuchsia-700 to-blue-700 p-6 text-white sm:p-8">
      <div className="pointer-events-none absolute -right-12 -top-16 h-64 w-64 rounded-full border-[32px] border-white/10" aria-hidden="true" />
      <div className="relative flex flex-col justify-between gap-5 sm:flex-row sm:items-center">
        <div><div className="mb-3 inline-flex items-center gap-2 rounded-full bg-white/15 px-3 py-1 text-[11px] font-semibold"><Bell size={13} /> Rider & driver communications</div><h1 className="text-3xl font-semibold tracking-tight">Notifications</h1><p className="mt-2 max-w-xl text-sm leading-6 text-white/85">The right message, at the right moment. Bring your beta community along for the ride.</p></div>
        <button onClick={() => document.getElementById("notification-title")?.focus()} className={`${action} shrink-0 bg-white text-fuchsia-800 shadow-sm`}><Send size={16} /> New announcement</button>
      </div>
    </div>
    {error && <p role="alert" className="rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-800">{error}</p>}
    {notice && <p role="status" className="flex items-center gap-2 rounded-2xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800"><CheckCircle2 size={17} />{notice}</p>}
    <div className="grid grid-cols-2 gap-3 lg:grid-cols-4"><StatCard label="Announcements" value={loading ? "—" : campaigns.length} /><StatCard label="Scheduled or sending" value={loading ? "—" : scheduled} /><StatCard label="Push accepted by provider" value={loading ? "—" : sent} tone="good" /><StatCard label="Delivery issues" value={loading ? "—" : failed} tone={failed ? "warning" : "default"} /></div>
    <section className="mc-panel !p-0 overflow-hidden" aria-labelledby="beta-heading">
      <div className="flex flex-wrap items-center justify-between gap-4 border-b border-line bg-gradient-to-r from-rose-50 via-white to-violet-50 p-5 sm:p-6">
        <div><p className="mc-eyebrow">Launch campaign</p><h2 id="beta-heading" className="mt-1 text-lg font-semibold text-ink">Live Beta starts November 1</h2><p className="mt-1 text-sm text-muted">9 AM Eastern · Both audiences · Tailored launch messages</p></div>
        <button disabled={busy || loading || betaCount === 6} onClick={() => void save({ action: "seedBeta" })} className={`${action} ${betaCount === 6 ? "border border-emerald-200 bg-emerald-50 text-emerald-800" : "bg-ink text-white"}`}>{betaCount === 6 ? <CheckCircle2 size={16} /> : <CalendarDays size={16} />}{betaCount === 6 ? "6 announcements saved" : "Schedule beta campaign"}</button>
      </div>
      <div className="grid gap-5 p-5 sm:grid-cols-3 sm:p-6">{milestones.map((milestone, index) => <div key={milestone.key} className="flex min-w-0 gap-3"><div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-rose-50 to-violet-100 text-fuchsia-700"><span className="text-sm font-bold">0{index + 1}</span></div><div><p className="text-[10px] font-bold tracking-widest text-fuchsia-700">{milestone.date} · 9 AM ET</p><h3 className="mt-1 font-semibold text-ink">{milestone.title}</h3><p className="mt-1 text-xs leading-5 text-muted">{milestone.description}</p></div></div>)}</div>
      <p className="border-t border-line px-5 py-3 text-xs text-muted sm:px-6">Daylight saving time is handled automatically. Saved messages and cancellations are preserved.</p>
    </section>
    <div className="grid items-start gap-6 xl:grid-cols-[minmax(0,1.2fr)_minmax(300px,.8fr)]">
      <form id="compose" className="mc-panel space-y-5" onSubmit={e => { e.preventDefault(); void save({ audience, title, body, sendAt: easternISO(sendAt) }); }}>
        <div className="flex items-center gap-3"><span className="rounded-xl bg-fuchsia-50 p-2.5 text-fuchsia-700"><Send size={18} /></span><div><h2 className="text-lg font-semibold text-ink">Create an announcement</h2><p className="mt-1 text-xs text-muted">Reach your community on their phones.</p></div></div>
        <fieldset><legend className="text-xs font-semibold text-ink">Who’s it for?</legend><div className="mt-2 grid grid-cols-2 gap-3">{[{ id: "rider", label: "Riders", Icon: Users }, { id: "driver", label: "Drivers", Icon: Car }].map(({ id, label, Icon }) => <button key={id} type="button" aria-pressed={audience === id} onClick={() => setAudience(id)} className={`flex min-h-12 items-center justify-center gap-2 rounded-xl border px-3 py-3 text-sm font-semibold ${audience === id ? "border-fuchsia-300 bg-fuchsia-50 text-fuchsia-800" : "border-line bg-white text-muted"}`}><Icon size={17} />{label}</button>)}</div></fieldset>
        <label className="block text-xs font-semibold text-ink" htmlFor="notification-title">Title<input id="notification-title" required maxLength={100} className={input} placeholder="Something exciting is on the way" value={title} onChange={e => setTitle(e.target.value)} /><span className="mt-1.5 block text-right text-[10px] font-normal text-muted">{title.length}/100</span></label>
        <label className="block text-xs font-semibold text-ink" htmlFor="notification-message">Message<textarea id="notification-message" required maxLength={500} rows={4} className={`${input} resize-y`} placeholder="Share the update and a clear next step…" value={body} onChange={e => setBody(e.target.value)} /><span className="mt-1.5 block text-right text-[10px] font-normal text-muted">{body.length}/500</span></label>
        <label className="block text-xs font-semibold text-ink" htmlFor="notification-time">Schedule for<input id="notification-time" required type="datetime-local" className={input} value={sendAt} onChange={e => setSendAt(e.target.value)} /><span className="mt-2 block text-xs font-normal text-muted">All dates and times use Eastern time.</span></label>
        <div className="flex flex-wrap gap-3 border-t border-line pt-5"><button disabled={busy || !sendAt} className={`${action} bg-ink text-white`}><CalendarDays size={16} />Schedule announcement</button><button type="button" disabled={busy || !title.trim() || !body.trim()} onClick={() => void save({ action: "sendNow", audience, title, body })} className={`${action} border border-line bg-white text-ink`}><Send size={15} />Send to {audience === "rider" ? "riders" : "drivers"} now</button></div>
        <p className="text-xs leading-5 text-muted">Send now queues your message for delivery, normally within one minute.</p>
      </form>
      <aside className="space-y-5">
        <section className="mc-panel"><div className="mb-5 flex items-center gap-2"><Smartphone size={17} className="text-fuchsia-700" /><h2 className="font-semibold text-ink">Notification preview</h2></div><div className="rounded-3xl border border-slate-200 bg-gradient-to-br from-slate-100 via-violet-100 to-rose-100 px-4 py-8"><p className="mb-6 text-center text-xs font-medium text-slate-500">Your {audience === "rider" ? "riders" : "drivers"} will see</p><div className="rounded-2xl border border-white/80 bg-white/90 p-4 shadow-sm"><div className="mb-3 flex items-center gap-2"><span className="flex h-7 w-7 items-center justify-center rounded-lg bg-gradient-to-br from-red-500 to-fuchsia-700 text-xs font-bold text-white">R</span><span className="text-[10px] font-semibold uppercase tracking-wider text-slate-500">Rydr</span><span className="ml-auto text-[10px] text-slate-400">now</span></div><p className="break-words text-sm font-semibold text-ink">{title.trim() || "Your announcement title"}</p><p className="mt-1 whitespace-pre-wrap break-words text-xs leading-5 text-slate-600">{body.trim() || "Your message appears here. Keep it clear, useful, and ready for a quick glance."}</p></div></div><p className="mt-4 text-[11px] leading-5 text-muted">An illustrative preview. Appearance varies by phone and notification settings.</p></section>
        <section className="mc-panel"><div className="flex items-center justify-between gap-3"><h2 className="font-semibold text-ink">Delivery status</h2><span className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[10px] font-semibold ${schedulerReady ? "bg-emerald-50 text-emerald-700" : "bg-amber-50 text-amber-800"}`}><Radio size={12} />{loading ? "Checking…" : schedulerReady ? "Active" : "Needs attention"}</span></div><p className="mt-3 text-xs leading-6 text-muted">{loading ? "Checking the delivery service." : schedulerReady ? "The delivery service is running. New announcements are checked every minute." : "Messages are saved, but delivery is awaiting service activation or recovery."}</p><div className="mt-4 space-y-3 border-t border-line pt-4 text-xs text-muted"><p className="flex gap-2"><CheckCircle2 size={15} className="shrink-0 text-fuchsia-600" />Phone alerts require notification permission and a registered app device.</p><p className="flex gap-2"><Clock3 size={15} className="shrink-0 text-fuchsia-600" />Provider acceptance confirms a push was submitted, not that it was read.</p></div></section>
      </aside>
    </div>
    <section className="mc-panel" aria-labelledby="history-heading"><div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center"><div><p className="mc-eyebrow">Communications log</p><h2 id="history-heading" className="mt-1 text-lg font-semibold text-ink">Schedule & history</h2></div><label className="relative block sm:w-64"><Search size={15} className="pointer-events-none absolute left-3 top-3 text-muted" /><input aria-label="Search announcements" placeholder="Find an announcement" className="w-full border border-line py-2.5 pl-9 pr-3 text-xs" value={search} onChange={e => setSearch(e.target.value)} /></label></div><div className="mc-segment mt-5 w-fit">{[{ id: "all", label: "All audiences" }, { id: "rider", label: "Riders" }, { id: "driver", label: "Drivers" }].map(item => <button key={item.id} aria-pressed={filter === item.id} onClick={() => setFilter(item.id)}>{item.label}</button>)}</div>
      <div className="mt-5 space-y-3">{loading ? <p role="status" className="py-10 text-center text-sm text-muted">Loading announcements…</p> : visible.length === 0 ? <div className="rounded-2xl border border-dashed border-line p-10 text-center"><Bell size={25} className="mx-auto text-fuchsia-400" /><p className="mt-3 text-sm text-muted">{search || filter !== "all" ? "No announcements match these filters." : "Your announcements will appear here."}</p></div> : visible.map(item => <article key={item.id} className="rounded-2xl border border-line bg-white p-4 transition hover:border-fuchsia-200 sm:p-5"><div className="flex items-start gap-3"><span className={`hidden shrink-0 rounded-xl p-2.5 sm:block ${item.audience === "rider" ? "bg-blue-50 text-blue-600" : "bg-violet-50 text-violet-600"}`}>{item.audience === "rider" ? <Users size={18} /> : <Car size={18} />}</span><div className="min-w-0 flex-1"><div className="flex flex-wrap items-center justify-between gap-2"><h3 className="break-words font-semibold text-ink">{item.title}</h3><span className={`rounded-full px-2.5 py-1 text-[10px] font-semibold capitalize ${statusStyle[item.status] ?? "bg-slate-100 text-slate-600"}`}>{item.status}</span></div><p className="mt-2 whitespace-pre-wrap break-words text-sm leading-6 text-muted">{item.body}</p><div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-2 text-[11px] text-muted"><span className="font-semibold text-fuchsia-700">{item.audience === "rider" ? "Riders" : "Drivers"}</span><span className="flex items-center gap-1.5"><CalendarDays size={13} />{eastern(item.sendAt)} Eastern</span></div><div className="mt-3 flex flex-wrap items-center justify-between gap-3 border-t border-line pt-3"><p className="text-[11px] text-muted">{Object.entries(item.counts ?? {}).map(([key, value]) => `${key.replaceAll("_", " ")}: ${value}`).join(" · ") || "No delivery attempts yet"}</p>{["scheduled", "sending"].includes(item.status) && <button disabled={busy} onClick={() => void save({ action: "cancel", id: item.id })} className="min-h-9 rounded-lg px-2 text-xs font-semibold text-red-700 hover:bg-red-50 disabled:opacity-50">Cancel announcement</button>}</div>{item.lastError && <p className="mt-2 text-xs text-amber-800">Processing was interrupted. An automatic retry is pending.</p>}</div></div></article>)}</div><p className="mt-4 text-[11px] leading-5 text-muted">Cancellation stops subsequent batches. A batch already being delivered may finish.</p>
    </section>
  </div>;
}
