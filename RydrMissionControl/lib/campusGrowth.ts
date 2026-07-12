import "server-only";

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { adminDb } from "@/lib/firebaseAdmin";

export type CampusPriority = "low" | "medium" | "high";
export type CampusStatus = "researching" | "active" | "paused" | "archived";
export type LeadStatus = "new" | "qualified" | "queued" | "contacted" | "replied" | "archived";
export type OutreachStatus = "draft" | "approved" | "denied" | "sent" | "replied";
export type AmbassadorStatus = "prospect" | "interview" | "accepted" | "active" | "inactive";
export type DiscoveredLeadKind =
  | "organization"
  | "club"
  | "chapter"
  | "incubator"
  | "event"
  | "department"
  | "student_government"
  | "student_media";
export type DiscoveredLeadReviewStatus = "pending_review" | "approved" | "rejected";
export type CampusLeadPriority = "low" | "medium" | "high";
export type RelationshipStrength = "cold" | "warm" | "active" | "partner";
export type CampusAgentRecommendation =
  | "Recruit as Ambassador"
  | "Invite for Beta"
  | "Request Club Presentation"
  | "Sponsor Event"
  | "Offer Internship"
  | "Request Partnership";

export interface CampusTarget {
  id: string;
  name?: string;
  city?: string;
  state?: string;
  market?: string;
  priority?: CampusPriority;
  status?: CampusStatus;
  owner?: string;
  notes?: string;
  tags?: string[];
  createdAt?: { toDate?: () => Date } | null;
  updatedAt?: { toDate?: () => Date } | null;
}

export interface StudentOrganization {
  id: string;
  campusId?: string;
  campusName?: string;
  name?: string;
  category?: string;
  website?: string;
  publicEmail?: string;
  leaderName?: string;
  leaderTitle?: string;
  socialUrl?: string;
  instagramUrl?: string;
  linkedInUrl?: string;
  discordUrl?: string;
  facebookUrl?: string;
  meetingSchedule?: string;
  description?: string;
  tags?: string[];
  estimatedStudentReach?: number;
  discoveryConfidence?: number;
  scoreReason?: string;
  aiSummary?: string;
  aiRecommendations?: CampusAgentRecommendation[];
  interactionTimeline?: CampusInteraction[];
  conversationHistory?: CampusConversationEntry[];
  meetingNotes?: string;
  attachments?: CampusAttachment[];
  customTags?: string[];
  priorityLevel?: CampusLeadPriority;
  owner?: string;
  followUpReminderAt?: { toDate?: () => Date } | null;
  relationshipStrength?: RelationshipStrength;
  lastAIRecommendation?: string;
  relevanceScore?: number;
  status?: LeadStatus;
  source?: string;
  notes?: string;
  createdAt?: { toDate?: () => Date } | null;
  updatedAt?: { toDate?: () => Date } | null;
}

export interface CampusEvent {
  id: string;
  campusId?: string;
  campusName?: string;
  name?: string;
  venue?: string;
  category?: string;
  eventUrl?: string;
  website?: string;
  description?: string;
  tags?: string[];
  estimatedStudentReach?: number;
  discoveryConfidence?: number;
  scoreReason?: string;
  aiSummary?: string;
  aiRecommendations?: CampusAgentRecommendation[];
  interactionTimeline?: CampusInteraction[];
  conversationHistory?: CampusConversationEntry[];
  meetingNotes?: string;
  attachments?: CampusAttachment[];
  customTags?: string[];
  priorityLevel?: CampusLeadPriority;
  owner?: string;
  followUpReminderAt?: { toDate?: () => Date } | null;
  relationshipStrength?: RelationshipStrength;
  lastAIRecommendation?: string;
  opportunityScore?: number;
  status?: LeadStatus;
  source?: string;
  notes?: string;
  startsAt?: { toDate?: () => Date } | null;
  createdAt?: { toDate?: () => Date } | null;
  updatedAt?: { toDate?: () => Date } | null;
}

export interface OutreachDraft {
  id: string;
  targetType?: "organization" | "event" | "campus" | "manual";
  targetId?: string;
  campusId?: string;
  campusName?: string;
  organizationName?: string;
  fromEmail?: string;
  bccEmail?: string;
  recipientName?: string;
  recipientEmail?: string;
  channel?: "email" | "instagram" | "linkedin" | "discord" | "event_invitation" | "internship_invitation" | "ambassador_invitation" | "other";
  subject?: string;
  body?: string;
  status?: OutreachStatus;
  relevanceScore?: number;
  denialReason?: string;
  createdAt?: { toDate?: () => Date } | null;
  reviewedAt?: { toDate?: () => Date } | null;
  sentAt?: { toDate?: () => Date } | null;
}

export interface AmbassadorCandidate {
  id: string;
  campusId?: string;
  campusName?: string;
  name?: string;
  email?: string;
  status?: AmbassadorStatus;
  sourceLeadId?: string;
  goals?: string[];
  notes?: string;
  createdAt?: { toDate?: () => Date } | null;
  updatedAt?: { toDate?: () => Date } | null;
}

export interface CampusInteraction {
  type?: "note" | "email" | "meeting" | "reply" | "call" | "ai_recommendation";
  summary?: string;
  createdBy?: string;
  createdAt?: { toDate?: () => Date } | null;
}

export interface CampusConversationEntry {
  channel?: string;
  direction?: "inbound" | "outbound" | "internal";
  subject?: string;
  body?: string;
  createdAt?: { toDate?: () => Date } | null;
}

export interface CampusAttachment {
  name?: string;
  url?: string;
  contentType?: string;
  uploadedAt?: { toDate?: () => Date } | null;
}

export interface DiscoveredCampusLead {
  id: string;
  kind?: DiscoveredLeadKind;
  reviewStatus?: DiscoveredLeadReviewStatus;
  campusId?: string;
  campusName?: string;
  name?: string;
  category?: string;
  description?: string;
  website?: string;
  instagramUrl?: string;
  linkedInUrl?: string;
  discordUrl?: string;
  facebookUrl?: string;
  meetingSchedule?: string;
  tags?: string[];
  estimatedStudentReach?: number;
  sourceType?: string;
  sourceUrl?: string;
  sourceTitle?: string;
  sourceSnippet?: string;
  publicEmail?: string;
  publicContactName?: string;
  publicContactTitle?: string;
  venue?: string;
  startsAtText?: string;
  relevanceScore?: number;
  discoveryConfidence?: number;
  scoreReason?: string;
  summary?: string;
  outreachAngle?: string;
  aiRecommendations?: CampusAgentRecommendation[];
  priorityLevel?: CampusLeadPriority;
  owner?: string;
  followUpReminderAt?: { toDate?: () => Date } | null;
  relationshipStrength?: RelationshipStrength;
  lastAIRecommendation?: string;
  interactionTimeline?: CampusInteraction[];
  conversationHistory?: CampusConversationEntry[];
  meetingNotes?: string;
  attachments?: CampusAttachment[];
  customTags?: string[];
  discoveryRunId?: string;
  searchQuery?: string;
  searchStrategy?: string;
  aiModel?: string;
  rejectionReason?: string;
  approvedTargetId?: string;
  createdAt?: { toDate?: () => Date } | null;
  reviewedAt?: { toDate?: () => Date } | null;
}

const CAMPUS_COLLECTION = "campusTargets";
const ORG_COLLECTION = "campusStudentOrganizations";
const EVENT_COLLECTION = "campusEvents";
const OUTREACH_COLLECTION = "campusOutreachDrafts";
const AMBASSADOR_COLLECTION = "campusAmbassadors";
const DISCOVERED_LEAD_COLLECTION = "campusDiscoveredLeads";

export const CAMPUS_OUTREACH_FROM_EMAIL = process.env.CAMPUS_OUTREACH_FROM_EMAIL || "support@rydr-go.com";
export const CAMPUS_OUTREACH_BCC_EMAIL = process.env.CAMPUS_OUTREACH_BCC_EMAIL || "khris.nunnally@rydr-go.com";

export async function campusGrowthCounts() {
  const [campuses, orgs, events, drafts, ambassadors, pendingDiscoveredLeads, approvedDiscoveredLeads] = await Promise.all([
    adminDb.collection(CAMPUS_COLLECTION).count().get(),
    adminDb.collection(ORG_COLLECTION).count().get(),
    adminDb.collection(EVENT_COLLECTION).count().get(),
    adminDb.collection(OUTREACH_COLLECTION).where("status", "==", "draft").count().get(),
    adminDb.collection(AMBASSADOR_COLLECTION).count().get(),
    adminDb.collection(DISCOVERED_LEAD_COLLECTION).where("reviewStatus", "==", "pending_review").count().get(),
    adminDb.collection(DISCOVERED_LEAD_COLLECTION).where("reviewStatus", "==", "approved").count().get()
  ]);
  return {
    campuses: campuses.data().count,
    organizations: orgs.data().count,
    events: events.data().count,
    pendingDrafts: drafts.data().count,
    ambassadors: ambassadors.data().count,
    pendingDiscoveredLeads: pendingDiscoveredLeads.data().count,
    approvedDiscoveredLeads: approvedDiscoveredLeads.data().count
  };
}

export async function campusGrowthAnalytics() {
  const discovered = await listDiscoveredCampusLeads(500);
  const organizations = await listOrganizations(500);
  const events = await listCampusEvents(500);
  const pendingReview = discovered.filter((lead) => (lead.reviewStatus ?? "pending_review") === "pending_review").length;
  const approvedLeads = discovered.filter((lead) => lead.reviewStatus === "approved").length;
  const internProspects = discovered.filter((lead) => lead.aiRecommendations?.includes("Offer Internship")).length;
  const ambassadorProspects = discovered.filter((lead) => lead.aiRecommendations?.includes("Recruit as Ambassador")).length;
  return {
    organizationsDiscovered: discovered.filter((lead) => lead.kind !== "event").length,
    eventsDiscovered: discovered.filter((lead) => lead.kind === "event").length,
    pendingReview,
    approvedLeads,
    internProspects,
    ambassadorProspects,
    betaRecruitmentProgress: approvedLeads,
    topSchools: topValues(discovered.map((lead) => lead.campusName).filter(Boolean) as string[]),
    topCategories: topValues(discovered.map((lead) => lead.category).filter(Boolean) as string[]),
    funnel: [
      { label: "Discovered", value: discovered.length },
      { label: "Pending Review", value: pendingReview },
      { label: "Approved", value: approvedLeads },
      { label: "Organizations", value: organizations.length },
      { label: "Events", value: events.length }
    ]
  };
}

export async function listCampuses(limit = 100): Promise<CampusTarget[]> {
  const snap = await adminDb.collection(CAMPUS_COLLECTION).orderBy("updatedAt", "desc").limit(limit).get();
  return snap.docs.map((doc) => ({ id: doc.id, ...(doc.data() as Omit<CampusTarget, "id">) }));
}

export async function listOrganizations(limit = 200): Promise<StudentOrganization[]> {
  const snap = await adminDb.collection(ORG_COLLECTION).orderBy("relevanceScore", "desc").limit(limit).get();
  return snap.docs.map((doc) => ({ id: doc.id, ...(doc.data() as Omit<StudentOrganization, "id">) }));
}

export async function listCampusEvents(limit = 200): Promise<CampusEvent[]> {
  const snap = await adminDb.collection(EVENT_COLLECTION).orderBy("startsAt", "desc").limit(limit).get();
  return snap.docs.map((doc) => ({ id: doc.id, ...(doc.data() as Omit<CampusEvent, "id">) }));
}

export async function listOutreachDrafts(limit = 200): Promise<OutreachDraft[]> {
  const snap = await adminDb.collection(OUTREACH_COLLECTION).orderBy("createdAt", "desc").limit(limit).get();
  return snap.docs.map((doc) => ({ id: doc.id, ...(doc.data() as Omit<OutreachDraft, "id">) }));
}

export async function listAmbassadors(limit = 200): Promise<AmbassadorCandidate[]> {
  const snap = await adminDb.collection(AMBASSADOR_COLLECTION).orderBy("updatedAt", "desc").limit(limit).get();
  return snap.docs.map((doc) => ({ id: doc.id, ...(doc.data() as Omit<AmbassadorCandidate, "id">) }));
}

export async function listDiscoveredCampusLeads(limit = 200): Promise<DiscoveredCampusLead[]> {
  const snap = await adminDb.collection(DISCOVERED_LEAD_COLLECTION).orderBy("createdAt", "desc").limit(limit).get();
  return snap.docs.map((doc) => ({ id: doc.id, ...(doc.data() as Omit<DiscoveredCampusLead, "id">) }));
}

export function scoreCampusLead(input: { category?: string; name?: string; notes?: string }): number {
  const text = `${input.category ?? ""} ${input.name ?? ""} ${input.notes ?? ""}`.toLowerCase();
  let score = 25;
  const highIntent = ["computer", "software", "engineering", "entrepreneur", "startup", "business", "marketing"];
  const campusReach = ["student government", "commuter", "orientation", "greek", "fraternity", "sorority", "student activities"];
  for (const term of highIntent) if (text.includes(term)) score += 12;
  for (const term of campusReach) if (text.includes(term)) score += 8;
  return Math.min(score, 100);
}

export function splitTags(value: unknown): string[] {
  if (typeof value !== "string") return [];
  return value
    .split(",")
    .map((tag) => tag.trim())
    .filter(Boolean)
    .slice(0, 12);
}

export function cleanText(value: unknown, max = 500): string {
  if (typeof value !== "string") return "";
  return value.trim().replace(/\s+/g, " ").slice(0, max);
}

export function cleanLongText(value: unknown, max = 5000): string {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, max);
}

export function cleanUrl(value: unknown): string {
  const text = cleanText(value, 1000);
  if (!text) return "";
  try {
    const url = new URL(text.startsWith("http") ? text : `https://${text}`);
    return url.toString();
  } catch {
    return "";
  }
}

export function cleanEmail(value: unknown): string {
  const text = cleanText(value, 320).toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(text) ? text : "";
}

export function parseDate(value: unknown): Timestamp | null {
  if (typeof value !== "string" || !value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : Timestamp.fromDate(date);
}

function topValues(values: string[]) {
  const counts = new Map<string, number>();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([label, value]) => ({ label, value }));
}

export function serverTimestamps() {
  return {
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp()
  };
}

export const campusCollections = {
  campuses: CAMPUS_COLLECTION,
  organizations: ORG_COLLECTION,
  events: EVENT_COLLECTION,
  outreach: OUTREACH_COLLECTION,
  ambassadors: AMBASSADOR_COLLECTION,
  discoveredLeads: DISCOVERED_LEAD_COLLECTION
};
