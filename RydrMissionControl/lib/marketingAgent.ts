import { rowenShift } from './rowenShift';
import "server-only";
import { createHash, createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { getWorkspaceDb } from "./firebaseAdmin";
import { currentWorkspace } from "./workspace";
import { discoverCampusLeads, discoveryFingerprint } from "./ai/campusGrowthAI";
import { draftMarketingCopy } from "./ai/marketingCopy";
import { MARKETING_BCC_EMAIL, MARKETING_AGENT_EMAIL, MARKETING_REPLY_EMAIL, MARKETING_SUBJECT_TAG, campaignSubject, campaignOpen, easternDay, followUpDueAt, isNoReplyEmail, leadExclusion, normalizeAgentConfig, normalizeFollowUps, withinSendingHours, type AgentConfig, type AgentLead } from "./marketingAgentPolicy";
import { localTimeToISO } from "../../rydr-backend/services/stripe/promotionPolicy";
import { notificationService } from "../src/services/notifications/NotificationService";

const CAMPAIGN = "student-beta-october-2026";
const replyTo = MARKETING_REPLY_EMAIL;
const key = (email: string) => createHash("sha256").update(email.trim().toLowerCase()).digest("hex");
type Actor = { uid: string; email: string | null };
type LeadRecord = AgentLead & { email: string; state: string; subject?: string; body?: string; instagramDraft?: string; instagramUrl?: string; reason?: string; updatedAt: number; followUpsSent?: number; nextFollowUpAt?: number | null };
async function refs() {
  const db = await getWorkspaceDb();
  const campaign = db.collection("marketingAgentCampaigns").doc(CAMPAIGN);
  return { db, campaign, leads: campaign.collection("leads"), runs: campaign.collection("runs") };
}

export function agentReadiness() {
  return { ai: Boolean(process.env.OPENAI_API_KEY), discovery: Boolean(process.env.BRAVE_SEARCH_API_KEY),
    email: Boolean(process.env.RESEND_API_KEY), unsubscribe: Boolean(process.env.MARKETING_AGENT_SECRET && process.env.MARKETING_AGENT_PUBLIC_URL),
    scheduler: Boolean(process.env.MARKETING_AGENT_RUN_SECRET), instagram: "manual_drafts" };
}

export async function agentSnapshot() {
  const { campaign, leads, runs } = await refs();
  const [config, contacts, history] = await Promise.all([campaign.get(), leads.orderBy("updatedAt", "desc").limit(250).get(), runs.orderBy("startedAt", "desc").limit(20).get()]);
  const data = config.data();
  const workspace = await currentWorkspace();
  const suffix = workspace === "test" ? "TEST" : "LIVE_BETA";
  const day = easternDay();
  const start = Date.parse(localTimeToISO(`${day}T09:00`));
  const end = Date.parse(localTimeToISO(`${day}T17:00`));
  const [shiftRuns, shiftMessages] = await Promise.all([
    runs.where("startedAt", ">=", start).where("startedAt", "<", end).limit(1000).get(),
    campaign.collection("messages").where("createdAt", ">=", start).where("createdAt", "<", end).limit(1000).get(),
  ]);
  const batches = shiftRuns.docs.map(doc => doc.data());
  const messages = shiftMessages.docs.map(doc => doc.data());
  const count = (kind: string) => messages.filter(m => m.direction === "outbound" && m.kind === kind && m.status === "sent").length;
  const onShift = withinSendingHours();
  const shift = { day, start, end, onShift,
    status: !data ? "Not configured" : data.status !== "active" ? "Paused" : !campaignOpen(data as AgentConfig) ? "Outside campaign dates" : !onShift ? rowenShift().label : data.leaseUntil > Date.now() ? "Working" : "Available for next run",
    activity: data?.activity ?? "Waiting for first run", activityAt: data?.activityAt ?? null,
    discovered: batches.reduce((n, r) => n + (r.discovered ?? 0), 0),
    excluded: batches.reduce((n, r) => n + (r.excluded ?? 0), 0),
    drafted: batches.reduce((n, r) => n + (r.drafted ?? 0), 0),
    outreach: count("initial"), followups: count("followup"), responses: count("reply"),
    replies: messages.filter(m => m.direction === "inbound").length,
    simulated: messages.filter(m => m.status === "simulated").length,
    errors: batches.filter(r => r.error).length + messages.filter(m => m.status === "unknown").length,
    batches: batches.length, limited: batches.length === 1000 || messages.length === 1000,
  };
  return { campaign: data ? { ...data, runToken: undefined } : null,
    shift,
    leads: contacts.docs.map(doc => ({ id: doc.id, ...doc.data() })),
    runs: history.docs.map(doc => ({ id: doc.id, ...doc.data() })), readiness: { ...agentReadiness(),
      inbound: Boolean(process.env[`MARKETING_AGENT_INBOUND_EMAIL_${suffix}`] && process.env[`MARKETING_AGENT_WEBHOOK_SECRET_${suffix}`]) },
    inboundAddress: process.env[`MARKETING_AGENT_INBOUND_EMAIL_${suffix}`] ?? "" };
}

export async function updateAgentSchedule(input: Record<string, unknown>, actor: Actor) {
  const endsAt = input.endsLocal ? localTimeToISO(String(input.endsLocal)) : new Date(String(input.endsAt)).toISOString();
  if (Date.parse(endsAt) <= Date.now()) throw new Error("Choose a future campaign end date.");
  const followUps = normalizeFollowUps(input);
  const dailyLimit = Number(input.dailyLimit), totalLimit = Number(input.totalLimit);
  if (!Number.isInteger(dailyLimit) || dailyLimit < 1 || dailyLimit > 50 || !Number.isInteger(totalLimit) || totalLimit < 1 || totalLimit > 10000) throw new Error("Choose daily limits of 1–50 and a total of 1–10,000 emails.");
  const { db, campaign } = await refs();
  await db.runTransaction(async tx => {
    const data = (await tx.get(campaign)).data();
    if (!data || Date.parse(endsAt) <= Date.parse(data.startsAt)) throw new Error("Save a campaign before changing its schedule.");
    if (totalLimit < (data.totalReserved ?? 0)) throw new Error("Total limit cannot be lower than emails already reserved.");
    tx.update(campaign, { endsAt, ...followUps, dailyLimit, totalLimit, updatedAt: Date.now(), updatedBy: actor.email ?? actor.uid });
  });
}

export async function createInboxProbe() {
  const { campaign } = await refs();
  if (!(await campaign.get()).exists) throw new Error("Save the campaign first.");
  const subject = `${MARKETING_SUBJECT_TAG} Inbox check ${randomUUID()}`;
  await campaign.update({ inboxProbeSubject: subject, inboxProbeExpiresAt: Date.now() + 30 * 60_000 });
  return subject;
}

export async function saveAgent(input: Record<string, unknown>, actor: Actor) {
  const config = normalizeAgentConfig(input);
  const { db, campaign } = await refs();
  await db.runTransaction(async tx => {
    const previous = (await tx.get(campaign)).data();
    if (previous?.firstRunAt) throw new Error("Campaign settings are locked after its first run. Pause or resume the existing pilot.");
    // Editing an unstarted campaign must preserve activation, inbox verification,
    // counters and operational metadata. Only a new campaign starts paused.
    tx.set(campaign, { ...config, status: previous?.status ?? config.status,
      ...(!previous ? { totalReserved: 0, dayReserved: 0, day: "", createdBy: actor.email ?? actor.uid } : {}),
      updatedAt: Date.now(), updatedBy: actor.email ?? actor.uid }, { merge: true });
  });
}

export async function setAgentStatus(status: "active" | "paused", actor: Actor) {
  const { db, campaign } = await refs();
  const workspace = await currentWorkspace();
  await db.runTransaction(async tx => {
    const config = (await tx.get(campaign)).data();
    if (!config) throw new Error("Save campaign settings first.");
    if (status === "active") {
      if (Date.now() >= Date.parse(config.endsAt)) throw new Error("The campaign deadline has passed.");
      const ready = agentReadiness();
      if (!ready.ai || !ready.discovery) throw new Error("Configure OpenAI and Brave Search before starting.");
      if (workspace === "live-beta" && (!ready.email || !ready.unsubscribe || !config.postalAddress)) {
        throw new Error("Live outreach requires Resend, unsubscribe configuration, and Rydr's mailing address.");
      }
    }
    tx.update(campaign, { status, updatedAt: Date.now(), updatedBy: actor.email ?? actor.uid });
  });
}

export async function actOnAgentLead(id: string, action: string, actor: Actor) {
  if (!/^[a-f0-9]{64}$/.test(id)) throw new Error("Invalid contact.");
  if (!["approve", "block", "replied", "instagram_sent"].includes(action)) throw new Error("Invalid contact action.");
  const { db, campaign, leads } = await refs();
  await db.runTransaction(async tx => {
    const ref = leads.doc(id);
    const snap = await tx.get(ref);
    const config = (await tx.get(campaign)).data();
    if (!snap.exists) throw new Error("Contact not found.");
    const lead = snap.data()!;
    const suppression = (await tx.get(db.collection("marketingAgentContacts").doc(id))).data();
    if (suppression?.blocked && !["reply_received", "replied"].includes(suppression.reason) && action !== "block") throw new Error("This contact is suppressed.");
    if (action === "approve" && (lead.state !== "review" || !config || Date.now() >= Date.parse(config.endsAt))) throw new Error("This draft cannot be approved.");
    if (action === "instagram_sent" && ["sending", "sent", "unknown", "replied", "blocked"].includes(lead.state)) throw new Error("This contact is already handled or has an email in flight.");
    tx.update(ref, { state: action === "approve" ? "ready" : action === "block" ? "blocked" : action === "instagram_sent" ? "instagram_sent" : "replied", ...(action !== "approve" ? { nextFollowUpAt: null } : {}), updatedAt: Date.now(), updatedBy: actor.email ?? actor.uid });
    if (action !== "approve") tx.set(db.collection("marketingAgentContacts").doc(id), { blocked: true, reason: action, updatedAt: Date.now() }, { merge: true });
  });
}

export function unsubscribeToken(id: string, workspace: string) {
  const secret = process.env.MARKETING_AGENT_SECRET;
  if (!secret) throw new Error("Unsubscribe signing is not configured.");
  const signature = createHmac("sha256", secret).update(`${workspace}:${id}`).digest("hex");
  return `${id}.${signature}`;
}

export async function unsubscribe(token: string) {
  const workspace = await currentWorkspace();
  const [id] = token.split(".");
  if (!/^[a-f0-9]{64}\.[a-f0-9]{64}$/.test(token)) throw new Error("Invalid unsubscribe link.");
  const expected = unsubscribeToken(id, workspace);
  if (!timingSafeEqual(Buffer.from(token), Buffer.from(expected))) throw new Error("Invalid unsubscribe link.");
  const { db } = await refs();
  await db.collection("marketingAgentContacts").doc(id).set({ blocked: true, reason: "unsubscribe", updatedAt: Date.now() }, { merge: true });
}

/** One bounded invocation, safe to call from a scheduler or an admin. */
export async function runMarketingAgent() {
  if (!withinSendingHours()) return { skipped: true, reason: "Off shift. Rowen works Monday–Friday, 9 a.m.–5 p.m. Eastern." };
  const { db, campaign, leads, runs } = await refs();
  const workspace = await currentWorkspace();
  const token = randomUUID();
  const startedAt = Date.now();
  const config = await db.runTransaction(async tx => {
    const data = (await tx.get(campaign)).data();
    if (!data || !campaignOpen(data as AgentConfig)) return null;
    if ((data.totalReserved ?? 0) >= data.totalLimit) return null;
    if ((data.leaseUntil ?? 0) > Date.now()) return null;
    if ((data.nextRunAt ?? 0) > Date.now()) return null;
    tx.update(campaign, { runToken: token, leaseUntil: Date.now() + 600_000, nextRunAt: Date.now() + 60_000, firstRunAt: data.firstRunAt || startedAt,
      activity: "Starting shift batch", activityAt: Date.now() });
    return data as AgentConfig & { lastDiscoveryAt?: number; discoveryCursor?: number; inboxVerifiedAt?: number };
  });
  if (!config) return { skipped: true, reason: "Paused, expired, campaign limit reached, scheduled for later, or already running." };
  const report = { startedAt, finishedAt: 0, discovered: 0, excluded: 0, exclusionReasons: {} as Record<string, number>, drafted: 0, sent: 0, simulated: 0, error: "", warnings: [] as string[] };
  try {
    if (!config.lastDiscoveryAt || Date.now() - config.lastDiscoveryAt > 30 * 60_000) {
      // Rotate schools; public search snippets only. Never invoke manual URL scraping.
      const cursor = config.discoveryCursor ?? 0;
      await campaign.update({ activity: `Researching ${config.campuses[cursor % config.campuses.length]}`, activityAt: Date.now() });
      const result = await discoverCampusLeads({ campusNames: [config.campuses[cursor % config.campuses.length]],
        categories: ["student organizations", "student life groups", "student government", "commuter student groups"],
        discoveryGoal: "Find official .edu listings for student groups to discuss a Rydr Live Beta pilot. Exclude deans, administrators and individual students. Need a published organization email, never guess one.",
        leadIntents: ["Invite for Beta"], manualUrls: [], emailOutreach: true, maxSearchResults: 10, strategyLimit: 4 });
      report.warnings = result.warnings.slice(0, 5);
      for (const lead of result.leads) {
        const source = result.searchResults.find(r => r.link === lead.sourceUrl);
        const exclusion = leadExclusion(lead, config.campuses, source ? `${source.title}\n${source.snippet}\n${source.content ?? ""}` : "");
        if (exclusion) { report.excluded++; report.exclusionReasons[exclusion] = (report.exclusionReasons[exclusion] ?? 0) + 1; continue; }
        const email = lead.publicEmail!.trim().toLowerCase();
        const ref = leads.doc(key(email));
        const inserted = await db.runTransaction(async tx => {
          const old = await tx.get(ref);
          const block = await tx.get(db.collection("marketingAgentContacts").doc(key(email)));
          const reviewed = await tx.get(db.collection("campusDiscoveredLeads").doc(discoveryFingerprint(lead)));
          if (old.exists || block.exists || reviewed.data()?.reviewStatus === "rejected") return false;
          tx.create(ref, { name: lead.name, campusName: lead.campusName, category: lead.category, kind: lead.kind,
            publicEmail: email, email, publicContactTitle: lead.publicContactTitle ?? "", sourceUrl: lead.sourceUrl,
            sourceSnippet: source?.snippet ?? "", description: lead.description ?? "", relevanceScore: lead.relevanceScore,
            instagramUrl: verifiedInstagram(lead.instagramUrl, result.searchResults.map(r => `${r.link} ${r.snippet}`).join("\n")),
            state: "queued", createdAt: Date.now(), updatedAt: Date.now() });
          return true;
        });
        if (inserted) report.discovered++;
      }
      await campaign.update({ lastDiscoveryAt: Date.now(), discoveryCursor: cursor + 1 });
    }
    // Recompute due times from persisted send times so extending the campaign also
    // enables eligible follow-ups that previously fell beyond its old deadline.
    const delivered = await leads.where("state", "in", ["sent", "simulated"]).limit(10000).get();
    for (const doc of delivered.docs) {
      const lead = doc.data();
      if (!lead.lastSentAt || lead.lastReplyAt) continue;
      const due = followUpDueAt(config, lead.lastSentAt, lead.followUpsSent ?? 0);
      if (due !== (lead.nextFollowUpAt ?? null)) await db.runTransaction(async tx => {
        const current = (await tx.get(doc.ref)).data();
        if (current && ["sent", "simulated"].includes(current.state) && !current.lastReplyAt && current.lastSentAt === lead.lastSentAt)
          tx.update(doc.ref, { nextFollowUpAt: due });
      });
    }
    const due = config.mode === "automatic" && (workspace === "test" || config.inboxVerifiedAt)
      ? await leads.where("nextFollowUpAt", ">", 0).where("nextFollowUpAt", "<=", Date.now()).orderBy("nextFollowUpAt").limit(3).get()
      : { docs: [] };
    const pending = await leads.where("state", "in", ["queued", "ready"]).limit(3).get();
    const candidates = [...due.docs, ...pending.docs];
    let processed = 0;
    for (const doc of candidates) {
      if (processed++ >= 3 || Date.now() - startedAt > 240_000) break;
      const latest = (await campaign.get()).data();
      if (!latest || !campaignOpen(latest as AgentConfig) || latest.runToken !== token || !withinSendingHours()) break;
      let lead = (await doc.ref.get()).data() as LeadRecord;
      if (isNoReplyEmail(lead.email)) {
        await actOnAgentLead(doc.id, "block", { uid: "marketing-agent", email: null });
        continue;
      }
      if (lead.state === "queued") {
        await campaign.update({ activity: `Drafting an invitation for ${lead.name}`, activityAt: Date.now() });
        const copy = await draftMarketingCopy(config, lead);
        await db.runTransaction(async tx => {
          const current = (await tx.get(doc.ref)).data();
          if (current?.state !== "queued") return;
          tx.update(doc.ref, { ...copy, subject: campaignSubject(copy.subject), state: copy.suitable ? config.mode === "automatic" ? "ready" : "review" : "excluded", updatedAt: Date.now() });
        });
        report.drafted++;
        lead = (await doc.ref.get()).data() as LeadRecord;
      }
      const followUp = ["sent", "simulated"].includes(lead.state);
      if (lead.state !== "ready" && !followUp) continue;
      if (followUp && config.mode !== "automatic") continue;
      const body = followUp
        ? (lead.followUpsSent ?? 0) === 0
          ? `Hello ${lead.name},\n\nI'm following up on our invitation to discuss a Rydr Live Beta pilot at ${lead.campusName}. Would your student group be interested in a brief conversation with Khris Nunnally? If this isn't a fit, let us know and we won't follow up again.`
          : `Hello ${lead.name},\n\nOne last check-in on our invitation to discuss a Rydr Live Beta pilot at ${lead.campusName}. If your group is interested, reply here and Khris can discuss next steps. We'll leave it here if we don't hear back. Thank you for your time.`
        : lead.body!;
      const result = await sendAgentMessage(doc.id, { kind: followUp ? "followup" : "initial", subject: lead.subject!, body, runToken: token });
      if (result.status === "sent") report.sent++;
      if (result.status === "simulated") report.simulated++;
    }
  } catch (error) {
    report.error = error instanceof Error ? error.message : "Agent run failed.";
  } finally {
    report.finishedAt = Date.now();
    await runs.doc(token).set(report);
    await db.runTransaction(async tx => {
      const latest = (await tx.get(campaign)).data();
      if (latest?.runToken === token) tx.update(campaign, { leaseUntil: 0, lastRunAt: report.finishedAt, lastError: report.error,
        activity: report.error ? "Needs attention" : "Batch finished; waiting for next scheduled run", activityAt: Date.now() });
    });
  }
  return report;
}

type SendAgentMessageInput = { kind: "initial" | "followup" | "reply"; subject: string; body: string; runToken?: string; operationId?: string; actor?: string; manualInitial?: boolean };

export async function prepareRowenCommand(command: string, actor: {uid:string;email:string|null}) {
  if (typeof command !== 'string' || command.length > 2000) throw new Error('Enter a request under 2,000 characters.');
  const emails = [...new Set((command.match(/[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g) ?? []).map(e=>e.toLowerCase()))];
  if (emails.length !== 1) throw new Error('Include exactly one recipient email address in your request.');
  const email=emails[0]; if(isNoReplyEmail(email))throw new Error('Rowen cannot contact a no-reply address.');
  const {db,campaign,leads}=await refs(), ref=leads.doc(key(email));
  const config=(await campaign.get()).data() as AgentConfig;
  if(!config)throw new Error('Configure Rowen’s campaign first.');
  if((await ref.get()).exists)throw new Error('This contact already exists. Open its conversation in Marketing Agent to avoid duplicate outreach.');
  if((await db.collection('marketingAgentContacts').doc(key(email)).get()).exists)throw new Error('This contact has prior outreach or suppression history. Review its conversation first.');
  const lead: AgentLead={name:email,campusName:'Specified by admin',category:'Admin-requested outreach',kind:'organization',publicEmail:email,sourceUrl:'',description:command,relevanceScore:100};
  const copy=await draftMarketingCopy(config,lead,command);
  if(!copy.suitable)throw new Error(copy.reason || 'This request does not fit Rowen’s student-group campaign.');
  await db.runTransaction(async tx=>{const [existing,blocked]=await Promise.all([tx.get(ref),tx.get(db.collection('marketingAgentContacts').doc(key(email)))]);if(existing.exists||blocked.exists)throw new Error('Contact history changed. Review the existing conversation.');tx.create(ref,{...lead,...copy,email,subject:campaignSubject(copy.subject),state:'review',commandDraft:true,sourceType:'admin_provided',createdBy:actor.email??actor.uid,createdAt:Date.now(),updatedAt:Date.now()});});
  return {id:ref.id,email,subject:campaignSubject(copy.subject),body:copy.body};
}

export async function sendRowenCommand(id:string, actor:{uid:string;email:string|null}) {
  if(!/^[a-f0-9]{64}$/.test(id))throw new Error('Invalid command draft.');
  const {db,leads}=await refs(), ref=leads.doc(id);
  const draft=await db.runTransaction(async tx=>{const d=(await tx.get(ref)).data();if(!d?.commandDraft || !['review','ready','sending','sent','unknown','simulated'].includes(d.state))throw new Error('Command draft is unavailable.');if(d.state==='review')tx.update(ref,{state:'ready',updatedAt:Date.now()});return d;});
  return sendAgentMessage(id,{kind:'initial',subject:draft.subject,body:draft.body,manualInitial:true,actor:actor.email??actor.uid});
}

/** Shared outbox for scheduled outreach, follow-ups, and Mission Control replies. */
export async function sendAgentMessage(id: string, input: SendAgentMessageInput) {
  if (!/^[a-f0-9]{64}$/.test(id)) throw new Error("Invalid contact.");
  if (!input.body?.trim() || input.body.length > 8000) throw new Error("Enter a message of 1–8,000 characters.");
  if (input.kind === "reply" && !/^[a-f0-9-]{36}$/.test(input.operationId ?? "")) throw new Error("A reply request ID is required.");
  const { db, campaign, leads } = await refs();
  const workspace = await currentWorkspace();
  const leadRef = leads.doc(id), contactRef = db.collection("marketingAgentContacts").doc(id);
  const captured = (await leadRef.get()).data();
  if (!captured) throw new Error("Contact not found.");
  if (input.manualInitial && (input.kind !== 'initial' || !captured.commandDraft)) throw new Error('Only an admin-created command draft can use manual sending.');
  const sequence = input.kind === "followup" ? (captured.followUpsSent ?? 0) + 1 : 0;
  const messageId = `${id}-${input.kind}-${input.kind === "reply" ? input.operationId : sequence}`;
  const messageRef = campaign.collection("messages").doc(messageId);
  const subject = campaignSubject(input.subject || captured.subject || "Live Beta invitation");
  const config = (await campaign.get()).data() as AgentConfig;
  if (!config) throw new Error("Campaign not configured.");
  const footer = workspace === "test" ? "[Test workspace: no email will be delivered]" : unsubscribeURL(id, workspace);
  const body = `${input.body.trim()}\n\n${config.name}\nRydr's AI campus outreach assistant, on behalf of Khris Nunnally\nRydr Tech LLC · Instagram: @rydr_tech\n${config.postalAddress}\n\nTo stop these invitations: ${footer}`;
  const reserved = await db.runTransaction(async tx => {
    const live = (await tx.get(campaign)).data();
    const lead = (await tx.get(leadRef)).data();
    const contact = (await tx.get(contactRef)).data();
    const previous = (await tx.get(messageRef)).data();
    const prior = input.kind === "initial" ? await tx.get(db.collection("campusOutreachDrafts").where("recipientEmail", "==", captured.email).limit(100)) : null;
    if (previous) return { status: previous.status as string };
    if (!live || !lead || !campaignOpen(live as AgentConfig)) return { status: "skipped", reason: "Campaign is paused or outside its dates." };
    if (input.kind !== "reply" && ((!input.manualInitial && live.runToken !== input.runToken) || !withinSendingHours())) return { status: "skipped", reason:'Queued for the next working period.' };
    if (isNoReplyEmail(lead.email)) {
      tx.update(leadRef, { state: "blocked", nextFollowUpAt: null, reason: "No-reply address", updatedAt: Date.now() });
      tx.set(contactRef, { blocked: true, reason: "no_reply", updatedAt: Date.now() }, { merge: true });
      return { status: "skipped" };
    }
    const optOut = contact?.blocked && !(input.kind === "reply" && ["reply_received", "replied"].includes(contact.reason));
    if (optOut || ["blocked", "instagram_sent"].includes(lead.state)) {
      tx.update(leadRef, { state: lead.state === "replied" ? "replied" : "blocked", nextFollowUpAt: null, reason: "Contact is suppressed", updatedAt: Date.now() });
      return { status: "skipped", reason: "Contact is suppressed." };
    }
    if (lead.activeMessageId) return { status: "skipped", reason: "An earlier send needs reconciliation." };
    if (input.kind === "initial") {
      if (lead.state !== "ready") return { status: "skipped" };
      if (contact || prior?.docs.some(d => ["sent", "replied"].includes(d.data().status))) {
        tx.update(leadRef, { state: "blocked", reason: "Previously contacted or suppressed", updatedAt: Date.now() });
        return { status: "skipped" };
      }
    } else if (input.kind === "followup") {
      const due = followUpDueAt(live as AgentConfig, lead.lastSentAt ?? 0, lead.followUpsSent ?? 0);
      if (live.mode !== "automatic" || !["sent", "simulated"].includes(lead.state) || lead.lastReplyAt || !due || due > Date.now()
        || (lead.followUpsSent ?? 0) + 1 !== sequence) return { status: "skipped" };
      if (workspace === "live-beta" && !live.inboxVerifiedAt) return { status: "skipped", reason: "Verify the Gmail reply connection before follow-ups." };
    } else if (!lead.lastInboundMessageId || lead.state !== "replied") {
      return { status: "skipped", reason: "Receive a contact reply before responding from this inbox." };
    }
    const day = easternDay(), dayReserved = live.day === day ? live.dayReserved ?? 0 : 0;
    if (dayReserved >= live.dailyLimit || (live.totalReserved ?? 0) >= live.totalLimit) return { status: "skipped", reason: "Email limit reached." };
    tx.update(campaign, { day, dayReserved: dayReserved + 1, totalReserved: (live.totalReserved ?? 0) + 1 });
    if (input.kind === "initial") tx.set(contactRef, { blocked: false, campaign: CAMPAIGN, reservedAt: Date.now() });
    tx.create(messageRef, { leadId: id, direction: "outbound", kind: input.kind, sequence, subject, body, to: lead.email,
      from: MARKETING_AGENT_EMAIL, status: "sending", createdAt: Date.now(), actor: input.actor ?? "Rowen" });
    tx.update(leadRef, { activeMessageId: messageId, ...(input.kind !== "reply" ? { state: "sending" } : {}), nextFollowUpAt: null, updatedAt: Date.now() });
    return { status: "reserved", email: lead.email as string, threadId: (input.kind === "reply" ? lead.lastInboundMessageId : lead.lastMessageId) as string | undefined };
  });
  if (reserved.status !== "reserved") return reserved;
  const [beforeSend, suppression, freshLead] = await Promise.all([campaign.get(), contactRef.get(), leadRef.get()]);
  const blocked = suppression.data()?.blocked && !(input.kind === "reply" && ["reply_received", "replied"].includes(suppression.data()?.reason));
  if (!campaignOpen(beforeSend.data() as AgentConfig) || blocked || (input.kind !== "reply" && (!withinSendingHours() || freshLead.data()?.lastReplyAt))) {
    await db.runTransaction(async tx => {
      const current = (await tx.get(leadRef)).data()!;
      tx.update(messageRef, { status: "cancelled" });
      tx.update(leadRef, { state: current.state === "sending" ? "blocked" : current.state, reason: "Send cancelled; review before further contact", activeMessageId: null, nextFollowUpAt: null });
    });
    return { status: "cancelled" };
  }
  const threadId = reserved.threadId && /^<[^\s<>]+>$/.test(reserved.threadId) ? reserved.threadId : undefined;
  await campaign.update({ activity: `${input.kind === "followup" ? "Following up with" : input.kind === "reply" ? "Replying to" : "Contacting"} ${captured.name}`, activityAt: Date.now() });
  const result = await notificationService.sendGenericEmail({ from: `${config.name} | Rydr Tech LLC <${MARKETING_AGENT_EMAIL}>`,
    to: reserved.email!, bcc: MARKETING_BCC_EMAIL, replyTo, subject: input.kind === "initial" || /^re:/i.test(subject) ? subject : `Re: ${subject}`, body,
    ...(threadId ? { headers: { "In-Reply-To": threadId, References: threadId } } : {}),
    eyebrow: "Rydr Live Beta · Campus Invitation", idempotencyKey: `marketing/${workspace}/${CAMPAIGN}/${messageId}` });
  const status = result.ok ? workspace === "test" ? "simulated" : "sent" : "unknown";
  await db.runTransaction(async tx => {
    const current = (await tx.get(leadRef)).data()!;
    const suppression = (await tx.get(contactRef)).data();
    const live = (await tx.get(campaign)).data() as AgentConfig;
    const count = input.kind === "followup" && result.ok ? sequence : current.followUpsSent ?? 0;
    const stopped = suppression?.blocked || current.lastReplyAt || ["blocked", "replied", "instagram_sent"].includes(current.state);
    tx.update(messageRef, { status, providerMessageId: result.providerMessageId ?? null, error: result.error ?? "", sentAt: result.ok ? Date.now() : null });
    tx.update(leadRef, { state: stopped ? current.state === "sending" ? "blocked" : current.state : status, activeMessageId: result.ok ? null : messageId,
      providerMessageId: result.providerMessageId ?? null, reason: result.error ?? current.reason ?? "",
      ...(result.ok ? { lastSentAt: Date.now(), followUpsSent: count, emailBody: body } : {}),
      nextFollowUpAt: result.ok && !stopped && input.kind !== "reply" ? followUpDueAt(live, Date.now(), count) : null, updatedAt: Date.now() });
    if (result.providerMessageId && workspace !== "test") tx.set(db.collection("marketingAgentDeliveryIndex").doc(result.providerMessageId), { leadId: id, messageId });
  });
  return { status, error: result.error };
}

export { refs as marketingAgentRefs, key as marketingContactKey };

function unsubscribeURL(id: string, workspace: string) {
  const base = process.env.MARKETING_AGENT_PUBLIC_URL;
  if (!base || new URL(base).protocol !== "https:") throw new Error("Configure an HTTPS Mission Control public URL.");
  const url = new URL("/api/campus-growth/agent/unsubscribe", base);
  url.searchParams.set("workspace", workspace);
  url.searchParams.set("token", unsubscribeToken(id, workspace));
  return url.toString();
}

function verifiedInstagram(value: string | undefined, evidence: string) {
  if (!value || !evidence.includes(value)) return "";
  try {
    const url = new URL(value);
    if (url.protocol === "https:" && ["instagram.com", "www.instagram.com"].includes(url.hostname) && /^\/[a-zA-Z0-9_.]+\/?$/.test(url.pathname)) return url.toString();
  } catch {}
  return "";
}
