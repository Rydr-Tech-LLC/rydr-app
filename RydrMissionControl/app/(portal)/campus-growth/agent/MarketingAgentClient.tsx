"use client";

import { useCallback, useEffect, useState } from "react";
import RowenIdentity from "@/components/RowenIdentity";
import { useWorkspace, WorkspaceLink } from "@/components/WorkspaceContext";
import { MARKETING_AGENT_EMAIL, PILOT_END, type AgentConfig } from "@/lib/marketingAgentPolicy";

type Contact = { id: string; name: string; campusName: string; email: string; state: string; sourceUrl: string;
  reason?: string; subject?: string; body?: string; emailBody?: string; instagramDraft?: string; instagramUrl?: string };
type Run = { id: string; startedAt: number; discovered: number; excluded: number; drafted: number; sent: number; simulated: number; error: string; warnings: string[] };
type Snapshot = { campaign: (AgentConfig & { firstRunAt?: number; totalReserved: number; lastRunAt?: number; lastError?: string; inboxVerifiedAt?: number }) | null;
  leads: Contact[]; runs: Run[]; readiness: Record<string, boolean | string>; inboundAddress: string;
  shift: { day: string; status: string; onShift: boolean; activity: string; activityAt: number | null; discovered: number; excluded: number; drafted: number; outreach: number; followups: number; responses: number; replies: number; simulated: number; errors: number; batches: number; limited: boolean } };
const defaults: AgentConfig = {
  name: "Rowen", status: "paused", mode: "automatic", startsAt: "2026-10-27T04:00:00.000Z", endsAt: PILOT_END,
  campuses: ["Clark Atlanta University", "Morehouse College", "Spelman College", "Georgia State University", "Georgia Institute of Technology"],
  facts: "Rydr Tech LLC is seeking students for a Live Beta. Invite student organizations and student-life groups to discuss piloting the Live Beta at their school with Khris Nunnally. Ask whether they are interested in a conversation. Do not promise a launch, incentives, pricing, school approval, or a partnership. Rydr Instagram: @rydr_tech.",
  postalAddress: "", dailyLimit: 10, totalLimit: 50
};
const field = "mt-1 w-full rounded-lg border border-line bg-white px-3 py-2 text-sm text-ink disabled:bg-grouped";
const button = "rounded-xl border border-line bg-white px-3 py-2 text-xs font-semibold text-ink shadow-sm hover:bg-grouped disabled:opacity-40";
const formatDate = (n?: number) => n ? new Date(n).toLocaleString("en-US", { timeZone: "America/New_York" }) + " ET" : "Not run yet";
type MailMessage = { id: string; direction: string; subject: string; body: string; status: string; createdAt: number };
function AgentConversation({ lead, workspace, onChanged }: { lead: Contact; workspace: string; onChanged: () => Promise<Snapshot> }) {
  const [messages, setMessages] = useState<MailMessage[] | null>(null);
  const [body, setBody] = useState("");
  const [operationId, setOperationId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  async function load() {
    const response = await fetch(`/api/campus-growth/agent?leadId=${lead.id}`, { headers: { "x-rydr-workspace": workspace } });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || "Could not load conversation");
    setMessages(data.messages);
  }
  async function reply() {
    setBusy(true); setError("");
    const id = operationId || crypto.randomUUID(); setOperationId(id);
    try {
      const response = await fetch("/api/campus-growth/agent", { method: "POST", headers: { "Content-Type": "application/json", "x-rydr-workspace": workspace }, body: JSON.stringify({ action: "reply", id: lead.id, subject: lead.subject, message: body, operationId: id }) });
      const data = await response.json(); if (!response.ok) throw new Error(data.error || "Reply failed");
      setBody(""); setOperationId(""); await load(); await onChanged();
    } catch (e) { setError(e instanceof Error ? e.message : "Reply failed"); }
    finally { setBusy(false); }
  }
  return <div className="mt-3">
    <button className={button} disabled={busy} onClick={() => load().catch(e => setError(e.message))}>{messages ? "Refresh conversation" : "View conversation"}</button>
    {messages && <div className="mt-3 space-y-3">{!messages.length && <p className="text-sm text-muted">No conversation messages recorded.</p>}{messages.map(m => <div key={m.id} className="rounded-lg bg-grouped p-3"><p className="text-xs text-muted">{m.direction === "inbound" ? "Received" : "Rowen"} · {m.status} · {formatDate(m.createdAt)}</p><p className="mt-1 text-sm font-medium">{m.subject}</p><p className="mt-2 whitespace-pre-wrap text-sm">{m.body}</p></div>)}
      {lead.state === "replied" && <div><label className="text-sm">Reply from Rowen<textarea rows={4} maxLength={8000} className={field} value={body} disabled={busy || Boolean(operationId)} onChange={e => setBody(e.target.value)} /></label><button className={`${button} mt-2`} disabled={busy || !body.trim()} onClick={reply}>{busy ? "Sending…" : "Send reply"}</button><p className="mt-2 text-xs text-muted">Reply-To goes to support@rydr-go.com; BCC goes to Khris. A send with an uncertain outcome requires reconciliation before a new message.</p></div>}
    </div>}
    {error && <p role="status" className="mt-2 text-sm text-red-700">{error}</p>}
  </div>;
}
function localDate(iso: string) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat("en-CA", { timeZone: "America/New_York", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(new Date(iso)).map(p => [p.type, p.value]));
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}`;
}

export default function MarketingAgentClient() {
  const workspace = useWorkspace();
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [config, setConfig] = useState<AgentConfig>(defaults);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [loaded, setLoaded] = useState(false);
  const [endsLocal, setEndsLocal] = useState(localDate(PILOT_END));
  const headers = { "Content-Type": "application/json", "x-rydr-workspace": workspace };
  const refresh = useCallback(async () => {
    const response = await fetch("/api/campus-growth/agent", { headers: { "x-rydr-workspace": workspace } });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || "Could not load agent.");
    setSnapshot(data);
    return data as Snapshot;
  }, [workspace]);
  useEffect(() => { refresh().then(data => { if (data.campaign) { setConfig(data.campaign); setEndsLocal(localDate(data.campaign.endsAt)); } setLoaded(true); }).catch(error => setMessage(error.message)); }, [refresh]);
  useEffect(() => { const timer = setInterval(() => { if (document.visibilityState === "visible") void refresh().catch(e => setMessage(e.message)); }, 30000); return () => clearInterval(timer); }, [refresh]);
  async function act(action: string, extra: object = {}) {
    setBusy(true); setMessage("");
    try {
      const response = await fetch(`/api/campus-growth/agent${action === "run" ? "/run" : ""}`, {
        method: "POST", headers, body: JSON.stringify({ action, ...extra }) });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "Action failed.");
      setMessage(data.subject ? `Send an email to support@rydr-go.com in Gmail with this exact subject within 30 minutes: ${data.subject}. The forwarding rule should deliver its copy here.` : data.reason || (action === "run" ? `Run finished: ${data.drafted ?? 0} drafted, ${data.sent ?? 0} sent, ${data.simulated ?? 0} simulated.` : "Saved."));
      await refresh();
    } catch (error) { setMessage(error instanceof Error ? error.message : "Action failed."); }
    finally { setBusy(false); }
  }
  const locked = Boolean(snapshot?.campaign?.firstRunAt);
  const expired = Date.now() >= Date.parse(snapshot?.campaign?.endsAt ?? PILOT_END);
  const readyCount = snapshot?.leads.filter(lead => lead.state === "review" || lead.state === "ready").length ?? 0;

  return <div className="space-y-5">
    <div className="flex flex-wrap items-start justify-between gap-4">
      <div><WorkspaceLink href="/campus-growth" className="text-sm text-muted">Campus Growth /</WorkspaceLink>
        <h1 className="mt-2 text-2xl font-semibold text-ink">Marketing Agent</h1>
        <p className="mt-2 max-w-2xl text-sm text-muted">{config.name} represents Rydr Tech LLC on behalf of Khris Nunnally, inviting student groups to discuss a Live Beta at their school.</p>
      </div>
      <span className="rounded-full bg-grouped px-4 py-2 text-sm font-semibold">{expired ? "Pilot ended" : snapshot?.campaign?.status ?? "Not configured"} · {workspace === "test" ? "Test workspace" : "Live Beta"}</span>
    </div>
    <RowenIdentity active="email" status={snapshot?.shift.status ?? "Ready when you are"} />
    <div className="rounded-2xl border border-line bg-white px-5 py-4 text-xs text-muted shadow-sm">
      Monday–Friday, 9 a.m.–5 p.m. Eastern (follows daylight saving time). Campaign ends {formatDate(Date.parse(snapshot?.campaign?.endsAt ?? PILOT_END))}; extend it below when needed. {workspace === "test" ? "Test runs use AI/search credits but never deliver email." : "Automatic mode sends eligible invitations once the campaign is activated."}
    </div>
    <section className="rounded-2xl border border-line bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-center justify-between gap-3"><h2 className="text-base font-semibold">Today’s shift · {snapshot?.shift.day}</h2><span className="rounded-full bg-grouped px-3 py-1 text-sm font-semibold">{snapshot?.shift.status ?? "Loading"}</span></div>
      <p className="mt-2 text-sm text-muted">Last activity: {snapshot?.shift.activity ?? "Waiting for first run"}{snapshot?.shift.activityAt ? ` · ${formatDate(snapshot.shift.activityAt)}` : ""}</p>
      <div className="mt-4 grid grid-cols-2 gap-4 md:grid-cols-4">
        {[["New eligible groups", snapshot?.shift.discovered], ["Drafts prepared", snapshot?.shift.drafted], ["Invitations sent", snapshot?.shift.outreach], ["Follow-ups sent", snapshot?.shift.followups], ["Replies received", snapshot?.shift.replies], ["Inbox responses sent", snapshot?.shift.responses], ["Test sends", snapshot?.shift.simulated], ["Run / send issues", snapshot?.shift.errors]].map(([label, value]) => <div key={label}><p className="text-xs text-muted">{label}</p><p className="mt-1 text-2xl font-semibold text-ink">{value ?? 0}</p></div>)}
      </div>
      <p className="mt-4 text-xs text-muted">9 a.m.–5 p.m. activity only · {snapshot?.shift.batches ?? 0} completed batches · {snapshot?.shift.excluded ?? 0} unsuitable candidates excluded. Updates every 30 seconds. Waiting between batches is normal; no productivity quota. Sent means accepted by the email provider.{snapshot?.shift.limited ? " Metrics capped at 1,000 records per category." : ""}</p>
    </section>
    <div className="grid gap-4 md:grid-cols-3">
      {[ ["Contacts", snapshot?.leads.length ?? 0], ["Drafts to review / send", readyCount], ["Reserved against campaign limit", snapshot?.campaign?.totalReserved ?? 0] ].map(([label, value]) =>
        <div key={label} className="rounded-2xl border border-line bg-white p-5 shadow-sm"><p className="text-sm text-muted">{label}</p><p className="mt-2 text-3xl font-semibold">{value}</p></div>)}
    </div>
    <div className="grid gap-5 xl:grid-cols-[1.3fr_1fr]">
      <section className="rounded-2xl border border-line bg-white p-5 shadow-sm">
        <h2 className="text-base font-semibold">Campaign brief</h2>
        <p className="mt-1 text-sm text-muted">Targets student groups and student-life teams. Excludes deans and administration. The brief locks after the first run; dates and limits remain editable.</p>
        <fieldset disabled={locked || busy || !loaded} className="mt-4 space-y-4">
          <label className="block text-sm font-medium">Agent name<input className={field} value={config.name} onChange={e => setConfig({ ...config, name: e.target.value })} /></label>
          <label className="block text-sm font-medium">Sending mode<select className={field} value={config.mode} onChange={e => setConfig({ ...config, mode: e.target.value as AgentConfig["mode"] })}><option value="automatic">Automatic within this campaign</option><option value="review">Review each email before sending</option></select></label>
          <label className="block text-sm font-medium">Target campuses · one per line<textarea rows={5} className={field} value={config.campuses.join("\n")} onChange={e => setConfig({ ...config, campuses: e.target.value.split("\n") })} /></label>
          <label className="block text-sm font-medium">Approved Live Beta facts and invitation<textarea rows={6} className={field} value={config.facts} onChange={e => setConfig({ ...config, facts: e.target.value })} /></label>
          <label className="block text-sm font-medium">Rydr mailing address for email footer<input className={field} placeholder="Required before live outreach" value={config.postalAddress} onChange={e => setConfig({ ...config, postalAddress: e.target.value })} /></label>
          <div className="grid grid-cols-2 gap-4"><label className="text-sm font-medium">Daily email limit<input type="number" min={1} max={50} className={field} value={config.dailyLimit} onChange={e => setConfig({ ...config, dailyLimit: Number(e.target.value) })} /></label>
            <label className="text-sm font-medium">Total email limit<input type="number" min={1} max={10000} className={field} value={config.totalLimit} onChange={e => setConfig({ ...config, totalLimit: Number(e.target.value) })} /></label></div>
          <button className={button} onClick={() => act("save", { config })}>Save campaign</button>
        </fieldset>
      </section>
      <div className="space-y-5">
        <section className="rounded-2xl border border-line bg-white p-5 shadow-sm">
          <h2 className="text-base font-semibold">Schedule & follow-ups</h2>
          <p className="mt-2 text-sm text-muted">Eight-hour shift, Monday–Friday. These limits are safety caps, not productivity targets. Extend the end date at any time, then resume if paused.</p>
          <label className="mt-3 block text-sm">Stop at this Eastern date/time<input type="datetime-local" className={field} value={endsLocal} onChange={e => setEndsLocal(e.target.value)} /></label>
          <div className="mt-3 grid grid-cols-2 gap-3">
            <label className="text-sm">Daily email cap<input type="number" min={1} max={50} className={field} value={config.dailyLimit} onChange={e => setConfig({ ...config, dailyLimit: Number(e.target.value) })} /></label>
            <label className="text-sm">Campaign email cap<input type="number" min={1} max={10000} className={field} value={config.totalLimit} onChange={e => setConfig({ ...config, totalLimit: Number(e.target.value) })} /></label>
            <label className="text-sm">Follow-ups per group<select className={field} value={config.maxFollowUps ?? 2} onChange={e => setConfig({ ...config, maxFollowUps: Number(e.target.value) })}>{[0, 1, 2].map(n => <option key={n} value={n}>{n}</option>)}</select></label>
            <label className="text-sm">Days between emails<input type="number" min={2} max={14} className={field} value={config.followUpDays ?? 3} onChange={e => setConfig({ ...config, followUpDays: Number(e.target.value) })} /></label>
          </div>
          <button className={`${button} mt-3`} disabled={busy || !snapshot?.campaign} onClick={() => act("schedule", { endsLocal, dailyLimit: config.dailyLimit, totalLimit: config.totalLimit, maxFollowUps: config.maxFollowUps ?? 2, followUpDays: config.followUpDays ?? 3 })}>Save schedule & limits</button>
          <p className="mt-3 text-xs text-muted">Follow-ups wait until the next shift when due outside work hours. Live follow-ups require a verified reply connection; replies, opt-outs, and delivery failures stop them.</p>
        </section>
        <section className="rounded-2xl border border-line bg-white p-5 shadow-sm">
          <h2 className="text-base font-semibold">Run controls</h2>
          <p className="mt-2 text-sm text-muted">Last run: {formatDate(snapshot?.campaign?.lastRunAt)}</p>
          <p className="mt-2 text-sm text-muted">Activation allows the configured scheduler to work while this page is closed. Run once executes one bounded batch. Pausing stops queued work; an email already handed to the provider may still arrive.</p>
          <div className="mt-4 flex flex-wrap gap-2">
            <button disabled={busy || !snapshot?.campaign || expired || snapshot.campaign.status === "active"} className={button} onClick={() => {
              if (workspace === "live-beta" && !window.confirm(`Activate ${config.name} for the saved ${snapshot?.campaign?.mode} email campaign until ${formatDate(Date.parse(snapshot!.campaign!.endsAt))}?`)) return;
              void act("activate"); }}>Activate</button>
            <button disabled={busy || snapshot?.campaign?.status !== "active"} className={button} onClick={() => act("pause")}>Pause</button>
            <button disabled={busy || expired || snapshot?.campaign?.status !== "active" || !snapshot.shift.onShift} className={button} onClick={() => act("run")}>{busy ? "Working…" : "Run once"}</button>
            <button disabled={busy} className={button} onClick={() => refresh().catch(e => setMessage(e.message))}>Refresh</button>
          </div>
          <p className="mt-3 text-xs text-muted">Only Mission Control admins can configure, activate, or run the agent.</p>
          {message && <p role="status" className="mt-3 rounded-lg bg-grouped p-3 text-sm">{message}</p>}
          {snapshot?.campaign?.lastError && <p className="mt-3 text-sm text-red-700">Last run: {snapshot.campaign.lastError}</p>}
        </section>
        <section className="rounded-2xl border border-line bg-white p-5 shadow-sm">
          <h2 className="text-base font-semibold">Connections</h2>
          <p className="mt-2 text-sm text-muted">Email sender: {config.name} | Rydr Tech LLC &lt;{MARKETING_AGENT_EMAIL}&gt;</p>
          <ul className="mt-3 space-y-2 text-sm">{Object.entries(snapshot?.readiness ?? {}).filter(([name]) => name !== "instagram").map(([name, ready]) => <li key={name} className="flex justify-between gap-3"><span className="capitalize">{name === "scheduler" ? "Scheduler credential" : name}</span><span>{ready ? "Configured" : "Needs setup"}</span></li>)}</ul>
          <p className="mt-3 text-xs text-muted">A configured scheduler credential does not mean a schedule is running. Confirm scheduled runs in the activity log after deployment.</p>
          <p className="mt-3 text-sm text-muted">Reply-To: support@rydr-go.com | BCC: khris.nunnally@rydr-go.com. Gmail campaign forwarding destination: {snapshot?.inboundAddress || "the receiving address configured during setup"}.</p>
          <button className={`${button} mt-3`} disabled={busy || !snapshot?.readiness.inbound} onClick={() => act("probe")}>Check Gmail reply connection</button>
          <p className="mt-2 text-xs text-muted">{snapshot?.campaign?.inboxVerifiedAt ? `Reply connection verified: ${formatDate(snapshot.campaign.inboxVerifiedAt)}` : "Reply connection has not been verified. Live follow-ups are held."}</p>
        </section>
        <section className="rounded-2xl border border-line bg-white p-5 shadow-sm">
          <h2 className="text-base font-semibold">Instagram · @rydr_tech</h2>
          <p className="mt-2 text-sm text-muted">Manage Instagram drafts, scheduled posts, incoming replies, and insights in Rowen’s Social Workspace. Check Social Connections for account status. First-contact DMs remain manual; Rowen replies to eligible incoming conversations without scraping profiles.</p>
          <p className="mt-3 text-sm text-muted">Email conversations appear below once Gmail forwarding is connected. No-reply messages are discarded from Mission Control; Gmail originals are retained.</p>
        </section>
      </div>
    </div>
    <section className="space-y-3"><h2 className="text-xl font-semibold">Contact decisions & messages</h2><p className="text-xs text-muted">Most recent 250 contacts. Shift metrics use the current shift’s records independently.</p>
      {!snapshot?.leads.length && <p className="rounded-2xl border border-line bg-white p-5 shadow-sm text-sm text-muted">No contacts yet. A run searches public campus listings, checks published email evidence, and drafts invitations for eligible student groups.</p>}
      {snapshot?.leads.map(lead => <article key={lead.id} className="rounded-2xl border border-line bg-white p-5 shadow-sm">
        <div className="flex flex-wrap justify-between gap-3"><div><h3 className="font-semibold">{lead.name}</h3><p className="text-sm text-muted">{lead.campusName} · {lead.email}</p></div><span className="text-sm font-semibold">{lead.state === "sending" ? "Sending / awaiting reconciliation" : lead.state}</span></div>
        <a className="mt-2 inline-block text-sm text-rydr-burgundy underline" href={lead.sourceUrl} target="_blank" rel="noreferrer">Public organization source</a>
        {lead.reason && <p className="mt-2 text-sm text-muted">{lead.reason}</p>}
        {lead.body && <details className="mt-3"><summary className="cursor-pointer font-medium">Email: {lead.subject}</summary><p className="mt-3 whitespace-pre-wrap text-sm">{lead.emailBody ?? lead.body}</p></details>}
        <AgentConversation lead={lead} workspace={workspace} onChanged={refresh} />
        {lead.instagramDraft && <details className="mt-3"><summary className="cursor-pointer font-medium">Instagram DM draft · manual sending</summary><p className="mt-3 whitespace-pre-wrap text-sm">{lead.instagramDraft}</p>{lead.instagramUrl && <a href={lead.instagramUrl} target="_blank" rel="noreferrer" className="mt-2 inline-block text-sm underline">Open organization Instagram</a>}</details>}
        <div className="mt-4 flex flex-wrap gap-2">
          {lead.state === "review" && <button disabled={busy} className={button} onClick={() => act("lead", { id: lead.id, leadAction: "approve" })}>Approve email</button>}
          <button disabled={busy || lead.state === "blocked"} className={button} onClick={() => act("lead", { id: lead.id, leadAction: "block" })}>Do not contact</button>
          <button disabled={busy || lead.state === "replied"} className={button} onClick={() => act("lead", { id: lead.id, leadAction: "replied" })}>Mark replied</button>
          {lead.instagramDraft && ["review", "ready"].includes(lead.state) && <button disabled={busy} className={button} onClick={() => act("lead", { id: lead.id, leadAction: "instagram_sent" })}>Mark DM sent · stop queued email</button>}
        </div>
      </article>)}
    </section>
    <section className="rounded-2xl border border-line bg-white p-5 shadow-sm"><h2 className="text-base font-semibold">Run history</h2>
      <p className="mt-1 text-xs text-muted">Public search only. Excluded candidates are counted without retaining their contact details.</p>
      {!snapshot?.runs.length && <p className="mt-3 text-sm text-muted">No runs recorded. The agent is not running until configured, activated, and invoked.</p>}
      {snapshot?.runs.map(run => <div key={run.id} className="mt-3 border-t border-line pt-3 text-sm"><p>{formatDate(run.startedAt)}</p><p className="text-muted">{run.discovered} discovered · {run.excluded} excluded · {run.drafted} drafted · {run.sent} sent · {run.simulated} simulated</p>{run.error && <p className="text-red-700">{run.error}</p>}{run.warnings.map((w, i) => <p key={i} className="text-amber-800">{w}</p>)}</div>)}
    </section>
  </div>;
}
