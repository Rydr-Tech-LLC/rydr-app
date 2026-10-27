export const PILOT_END = "2026-11-01T04:00:00.000Z"; // Initial deadline; editable in Mission Control.
export const AGENT_TIME_ZONE = "America/New_York";
export const MARKETING_AGENT_EMAIL = "marketing@rydr-go.com";
export const MARKETING_REPLY_EMAIL = "support@rydr-go.com";
export const MARKETING_BCC_EMAIL = "khris.nunnally@rydr-go.com";
export const MARKETING_SUBJECT_TAG = "[Rydr Campus]";

export interface AgentConfig {
  name: string;
  status: "paused" | "active";
  mode: "review" | "automatic";
  startsAt: string;
  endsAt: string;
  campuses: string[];
  facts: string;
  postalAddress: string;
  dailyLimit: number;
  totalLimit: number;
  maxFollowUps?: number;
  followUpDays?: number;
}

export function normalizeAgentConfig(value: Record<string, unknown>): AgentConfig {
  const text = (key: string, max: number) => String(value[key] ?? "").trim().slice(0, max);
  const name = text("name", 60);
  if (!/^[\p{L}\p{N} .'-]{1,60}$/u.test(name)) throw new Error("Enter a simple agent name.");
  const startsAt = new Date(String(value.startsAt)).toISOString();
  const endsAt = new Date(String(value.endsAt)).toISOString();
  if (Date.parse(startsAt) >= Date.parse(endsAt)) {
    throw new Error("The campaign end must be after its start.");
  }
  const campuses = Array.isArray(value.campuses)
    ? [...new Set(value.campuses.map(v => String(v).trim().slice(0, 180)).filter(Boolean))].slice(0, 10) : [];
  if (!campuses.length) throw new Error("Select at least one target campus.");
  const facts = text("facts", 6000);
  if (facts.length < 30) throw new Error("Provide the approved Live Beta facts and invitation details.");
  const integer = (key: string, max: number) => {
    const n = Number(value[key]);
    if (!Number.isInteger(n) || n < 1 || n > max) throw new Error(`${key} must be between 1 and ${max}.`);
    return n;
  };
  if (!["review", "automatic"].includes(String(value.mode))) throw new Error("Choose a sending mode.");
  return { name, status: "paused", mode: value.mode as AgentConfig["mode"], startsAt, endsAt,
    campuses, facts, postalAddress: text("postalAddress", 300),
    dailyLimit: integer("dailyLimit", 50), totalLimit: integer("totalLimit", 10000),
    ...normalizeFollowUps(value) };
}

export function campaignOpen(config: AgentConfig, now = new Date()): boolean {
  return config.status === "active" && now.getTime() >= Date.parse(config.startsAt)
    && now.getTime() < Date.parse(config.endsAt);
}

export function normalizeFollowUps(value: Record<string, unknown>) {
  const maxFollowUps = Number(value.maxFollowUps ?? 2), followUpDays = Number(value.followUpDays ?? 3);
  if (!Number.isInteger(maxFollowUps) || maxFollowUps < 0 || maxFollowUps > 2) throw new Error("Choose zero, one, or two follow-ups.");
  if (!Number.isInteger(followUpDays) || followUpDays < 2 || followUpDays > 14) throw new Error("Follow-ups must be 2–14 days apart.");
  return { maxFollowUps, followUpDays };
}

export function normalizeEmailAddress(value: string): string {
  const candidate = (value.match(/<([^<>]+)>/)?.[1] ?? value).trim().toLowerCase();
  return /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(candidate) ? candidate : "";
}

export function isNoReplyEmail(value: string): boolean {
  const local = normalizeEmailAddress(value).split("@")[0].replace(/[._+-]/g, "");
  return /noreply|donotreply|donotrespond|mailerdaemon|postmaster/.test(local);
}

export function campaignSubject(subject: string): string {
  const clean = subject.replace(/[\r\n]/g, " ").trim().slice(0, 180);
  return clean.includes(MARKETING_SUBJECT_TAG) ? clean : `${MARKETING_SUBJECT_TAG} ${clean}`;
}

export function followUpDueAt(config: AgentConfig, sentAt: number, followUpsSent: number): number | null {
  const due = sentAt + (config.followUpDays ?? 3) * 86400_000;
  return followUpsSent < (config.maxFollowUps ?? 2) && due < Date.parse(config.endsAt) ? due : null;
}

export function easternDay(now = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: AGENT_TIME_ZONE, year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
}

export function withinSendingHours(now = new Date()): boolean {
  const weekday = new Intl.DateTimeFormat("en-US", { timeZone: AGENT_TIME_ZONE, weekday: "short" }).format(now);
  const hour = Number(new Intl.DateTimeFormat("en-US", { timeZone: AGENT_TIME_ZONE, hour: "numeric", hourCycle: "h23" }).format(now));
  return !["Sat", "Sun"].includes(weekday) && hour >= 9 && hour < 17;
}

export interface AgentLead {
  name: string; campusName: string; category: string; kind: string;
  publicEmail?: string; publicContactTitle?: string; sourceUrl: string;
  sourceSnippet?: string; description?: string; relevanceScore: number;
}

/** Fail closed: the model cannot invent an address or expand the audience. */
export function leadExclusion(lead: AgentLead, campuses: string[], evidence: string): string | null {
  const email = (lead.publicEmail ?? "").trim().toLowerCase();
  if (!/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(email)) return "No public email";
  if (isNoReplyEmail(email)) return "No-reply address";
  if (!campuses.some(c => c.toLowerCase() === lead.campusName.toLowerCase())) return "Outside selected campuses";
  const identity = `${lead.name} ${lead.category} ${lead.publicContactTitle ?? ""} ${email}`;
  if (/\b(dean|deans|provost|chancellor|admissions|registrar)\b/i.test(identity)
    || /dean|provost|chancellor|admissions|registrar/i.test(email.split("@")[0])) return "Excluded university administration";
  if (!["organization", "club", "chapter", "student_government", "student_media", "department"].includes(lead.kind)) return "Outside student group audience";
  if (!/student|club|chapter|society|association|campus life|residence hall|commuter/i.test(`${lead.name} ${lead.category}`)) return "Student group role not established";
  let host: string;
  try { const url = new URL(lead.sourceUrl); if (url.protocol !== "https:") return "Source must use HTTPS"; host = url.hostname; }
  catch { return "Missing public source"; }
  if (!host.endsWith(".edu")) return "Automatic pilot requires an official .edu source";
  const addresses: string[] = evidence.toLowerCase().match(/[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,}/g) ?? [];
  if (!addresses.includes(email)) return "Email not present in retrieved source evidence";
  if (lead.relevanceScore < 65) return "Low student outreach relevance";
  return null;
}
