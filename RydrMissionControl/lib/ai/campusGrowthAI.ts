import "server-only";

import crypto from "crypto";
import {
  cleanEmail,
  cleanLongText,
  cleanText,
  cleanUrl,
  scoreCampusLead,
  type CampusAgentRecommendation,
  type CampusLeadPriority,
  type DiscoveredLeadKind
} from "@/lib/campusGrowth";

export const DEFAULT_TARGET_CAMPUSES = [
  "Clark Atlanta University",
  "Morehouse College",
  "Spelman College",
  "Georgia State University",
  "Georgia State University previously Georgia Perimeter College",
  "Clayton State University",
  "Georgia Tech Institution"
];

export const DEFAULT_PRIORITY_CATEGORIES = [
  "computer science/software",
  "computer science clubs",
  "ACM chapters",
  "IEEE chapters",
  "entrepreneurship clubs",
  "startup incubators",
  "hackathons",
  "career fairs",
  "student government",
  "business/marketing",
  "transportation/sustainability",
  "commuter students",
  "residence hall associations",
  "campus transportation departments",
  "student media organizations"
];

export const APPROVED_LEAD_SOURCES = [
  "Official campus student organization directories",
  "Official campus event calendars",
  "Public campus department pages",
  "Ticketmaster/public event APIs if already approved",
  "Manually entered URLs"
];

export const BLOCKED_LEAD_SOURCES = [
  "Instagram personal profiles",
  "TikTok profiles",
  "LinkedIn personal profiles",
  "Guessed student emails",
  "Private directories",
  "Login-required pages"
];

export const CAMPUS_AGENT_RECOMMENDATIONS: CampusAgentRecommendation[] = [
  "Recruit as Ambassador",
  "Invite for Beta",
  "Request Club Presentation",
  "Sponsor Event",
  "Offer Internship",
  "Request Partnership"
];

export interface SearchResult {
  title: string;
  link: string;
  snippet: string;
  query: string;
}

export interface AILeadCandidate {
  kind: DiscoveredLeadKind;
  campusName: string;
  name: string;
  category: string;
  description?: string;
  website?: string;
  instagramUrl?: string;
  linkedInUrl?: string;
  discordUrl?: string;
  facebookUrl?: string;
  meetingSchedule?: string;
  tags?: string[];
  estimatedStudentReach?: number;
  sourceType: string;
  sourceUrl: string;
  sourceTitle?: string;
  sourceSnippet?: string;
  publicEmail?: string;
  publicContactName?: string;
  publicContactTitle?: string;
  venue?: string;
  startsAtText?: string;
  relevanceScore: number;
  discoveryConfidence: number;
  scoreReason: string;
  summary: string;
  outreachAngle: string;
  aiRecommendations: CampusAgentRecommendation[];
  priorityLevel: CampusLeadPriority;
  relationshipStrength: "cold" | "warm" | "active" | "partner";
  searchQuery?: string;
  searchStrategy?: string;
}

export interface DiscoveryInput {
  discoveryGoal?: string;
  leadIntents?: string[];
  campusNames?: string[];
  categories?: string[];
  manualUrls?: string[];
  maxSearchResults?: number;
}

export interface DiscoveryResult {
  runId: string;
  model: string;
  searchStrategies: string[];
  searchResults: SearchResult[];
  leads: AILeadCandidate[];
  rejectedSources: Array<{ url: string; reason: string }>;
}

const BLOCKED_HOSTS = ["tiktok.com"];
const BLOCKED_PATH_TERMS = ["login", "signin", "sign-in", "auth", "portal", "blackboard", "canvas", "people", "person", "profile"];
const SEARCH_CACHE = new Map<string, { expiresAt: number; results: SearchResult[] }>();

export function discoveryFingerprint(lead: Pick<AILeadCandidate, "campusName" | "name" | "sourceUrl">) {
  return crypto
    .createHash("sha256")
    .update(`${lead.campusName.toLowerCase()}|${lead.name.toLowerCase()}|${lead.sourceUrl.toLowerCase()}`)
    .digest("hex");
}

export async function discoverCampusLeads(input: DiscoveryInput): Promise<DiscoveryResult> {
  const discoveryGoal = cleanLongText(input.discoveryGoal, 1000);
  const leadIntents = cleanList(input.leadIntents);
  const campusNames = cleanList(input.campusNames).length ? cleanList(input.campusNames) : DEFAULT_TARGET_CAMPUSES;
  const categories = cleanList(input.categories).length ? cleanList(input.categories) : DEFAULT_PRIORITY_CATEGORIES;
  const maxSearchResults = clamp(Number(input.maxSearchResults) || 5, 1, 10);
  const runId = crypto.randomUUID();
  const searchStrategies = await planSearchStrategies(campusNames, categories, discoveryGoal, leadIntents);

  const rawResults = [
    ...(await runGoogleSearches(searchStrategies, maxSearchResults)),
    ...manualUrlResults(input.manualUrls)
  ];

  const rejectedSources: DiscoveryResult["rejectedSources"] = [];
  const searchResults = uniqueByUrl(rawResults).filter((result) => {
    const blocked = blockedSourceReason(result.link);
    if (blocked) rejectedSources.push({ url: result.link, reason: blocked });
    return !blocked;
  });

  if (!searchResults.length) {
    return { runId, model: aiModel(), searchStrategies, searchResults, leads: [], rejectedSources };
  }

  const leads = await extractLeadsWithAI({ campusNames, categories, leadIntents, discoveryGoal, searchStrategies, searchResults });
  const cleaned = leads
    .map((lead) => normalizeLead(lead, searchResults))
    .filter((lead): lead is AILeadCandidate => Boolean(lead))
    .slice(0, 50);

  return { runId, model: aiModel(), searchStrategies, searchResults, leads: cleaned, rejectedSources };
}

async function planSearchStrategies(campusNames: string[], categories: string[], discoveryGoal: string, leadIntents: string[]): Promise<string[]> {
  const fallback = buildFallbackQueries(campusNames, categories);
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) return fallback;

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: aiModel(),
      input: [
        {
          role: "system",
          content:
            "You are the Rydr Campus Agent search planner. Generate public-web search queries for campus recruiting leads. Prefer official campus domains and public event pages. Do not target personal profiles, private groups, login-required pages, or guessed emails. Return JSON only."
        },
        {
          role: "user",
          content: JSON.stringify({
            targetCampuses: campusNames,
            priorityCategories: categories,
            discoveryGoal,
            leadIntents,
            desiredLeadTypes: [
              "student organizations",
              "computer science clubs",
              "entrepreneurship clubs",
              "ACM chapters",
              "IEEE chapters",
              "startup incubators",
              "campus events",
              "hackathons",
              "career fairs",
              "student government",
              "residence hall associations",
              "commuter organizations",
              "campus transportation departments",
              "student media organizations"
            ]
          })
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "campus_search_strategy",
          strict: true,
          schema: {
            type: "object",
            additionalProperties: false,
            properties: {
              queries: {
                type: "array",
                maxItems: 60,
                items: { type: "string" }
              }
            },
            required: ["queries"]
          }
        }
      }
    })
  });

  if (!response.ok) return fallback;
  const data = (await response.json()) as { output_text?: string; output?: Array<{ content?: Array<{ text?: string }> }> };
  const jsonText = data.output_text ?? data.output?.flatMap((part) => part.content ?? []).map((content) => content.text).find(Boolean);
  if (!jsonText) return fallback;
  try {
    const parsed = JSON.parse(jsonText) as { queries?: string[] };
    const planned = (parsed.queries ?? []).map((query) => cleanText(query, 240)).filter(Boolean);
    return planned.length ? uniqueStrings([...planned, ...fallback]).slice(0, 60) : fallback;
  } catch {
    return fallback;
  }
}

async function runGoogleSearches(queries: string[], maxSearchResults: number): Promise<SearchResult[]> {
  const apiKey = process.env.GOOGLE_CUSTOM_SEARCH_API_KEY;
  const cx = process.env.GOOGLE_CUSTOM_SEARCH_ENGINE_ID;
  if (!apiKey || !cx) return [];

  const batches = await Promise.all(queries.map((query) => googleSearch(query, apiKey, cx, maxSearchResults)));
  return batches.flat();
}

function buildFallbackQueries(campusNames: string[], categories: string[]) {
  const queries: string[] = [];
  for (const campus of campusNames) {
    queries.push(`"${campus}" "student organizations"`);
    queries.push(`"${campus}" "event calendar"`);
    queries.push(`"${campus}" "student government"`);
    queries.push(`"${campus}" "commuter student"`);
    queries.push(`"${campus}" "career fair"`);
    queries.push(`"${campus}" "hackathon"`);
    queries.push(`"${campus}" "startup incubator"`);
    queries.push(`"${campus}" "innovation lab"`);
    queries.push(`"${campus}" "transportation" "students"`);
    queries.push(`"${campus}" "student media"`);
    queries.push(`"${campus}" "residence hall association"`);
    queries.push(`"${campus}" "ACM"`);
    queries.push(`"${campus}" "IEEE"`);
    for (const category of categories) {
      queries.push(`"${campus}" "${category}" "student organization"`);
    }
  }
  return uniqueStrings(queries).slice(0, 60);
}

async function googleSearch(query: string, apiKey: string, cx: string, maxSearchResults: number): Promise<SearchResult[]> {
  const cacheKey = `${query}|${maxSearchResults}`;
  const cached = SEARCH_CACHE.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) return cached.results;

  const params = new URLSearchParams({
    key: apiKey,
    cx,
    q: query,
    num: String(maxSearchResults),
    safe: "active"
  });
  const response = await fetch(`https://www.googleapis.com/customsearch/v1?${params.toString()}`, { cache: "no-store" });
  if (!response.ok) return [];
  const data = (await response.json()) as { items?: Array<{ title?: string; link?: string; snippet?: string }> };
  const results = (data.items ?? [])
    .map((item) => ({
      title: cleanText(item.title, 300),
      link: cleanUrl(item.link),
      snippet: cleanLongText(item.snippet, 1000),
      query
    }))
    .filter((item) => item.title && item.link);
  SEARCH_CACHE.set(cacheKey, { expiresAt: Date.now() + 1000 * 60 * 30, results });
  return results;
}

function manualUrlResults(urls: unknown): SearchResult[] {
  const values = Array.isArray(urls) ? urls : typeof urls === "string" ? urls.split(/\s+/) : [];
  return values
    .map((value) => cleanUrl(value))
    .filter(Boolean)
    .map((url) => ({
      title: "Manually entered URL",
      link: url,
      snippet: "Admin-approved manual URL for campus lead discovery.",
      query: "manual_url"
    }));
}

async function extractLeadsWithAI(input: {
  campusNames: string[];
  categories: string[];
  leadIntents: string[];
  discoveryGoal: string;
  searchStrategies: string[];
  searchResults: SearchResult[];
}): Promise<AILeadCandidate[]> {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) return ruleBasedCandidates(input.searchResults, input.campusNames, input.categories);

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: aiModel(),
      input: [
        {
          role: "system",
          content:
            "You are the Rydr AI Campus Agent. Extract public campus recruiting leads for CashRydr. Use only official public campus pages, public organization pages, public event listings, public department pages, Ticketmaster/public event API results, public organization social pages, or manually entered URLs. Do not include personal student profiles, guessed emails, private directories, private Discord servers, private Facebook groups, login pages, TikTok profiles, personal Instagram profiles, or personal LinkedIn profiles. LinkedIn organization pages are allowed only when clearly organizational. Return concise JSON only."
        },
        {
          role: "user",
          content: JSON.stringify({
            approvedSources: APPROVED_LEAD_SOURCES,
            blockedSources: BLOCKED_LEAD_SOURCES,
            targetCampuses: input.campusNames,
            priorityCategories: input.categories,
            leadIntents: input.leadIntents,
            discoveryGoal: input.discoveryGoal,
            allowedRecommendations: CAMPUS_AGENT_RECOMMENDATIONS,
            searchStrategies: input.searchStrategies,
            searchResults: input.searchResults
          })
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "campus_lead_discovery",
          strict: true,
          schema: {
            type: "object",
            additionalProperties: false,
            properties: {
              leads: {
                type: "array",
                maxItems: 50,
                items: {
                  type: "object",
                  additionalProperties: false,
                  properties: {
                    kind: {
                      type: "string",
                      enum: ["organization", "club", "chapter", "incubator", "event", "department", "student_government", "student_media"]
                    },
                    campusName: { type: "string" },
                    name: { type: "string" },
                    category: { type: "string" },
                    description: { type: "string" },
                    website: { type: "string" },
                    instagramUrl: { type: "string" },
                    linkedInUrl: { type: "string" },
                    discordUrl: { type: "string" },
                    facebookUrl: { type: "string" },
                    meetingSchedule: { type: "string" },
                    tags: { type: "array", maxItems: 12, items: { type: "string" } },
                    estimatedStudentReach: { type: "number" },
                    sourceType: { type: "string" },
                    sourceUrl: { type: "string" },
                    sourceTitle: { type: "string" },
                    sourceSnippet: { type: "string" },
                    publicEmail: { type: "string" },
                    publicContactName: { type: "string" },
                    publicContactTitle: { type: "string" },
                    venue: { type: "string" },
                    startsAtText: { type: "string" },
                    relevanceScore: { type: "number" },
                    discoveryConfidence: { type: "number" },
                    scoreReason: { type: "string" },
                    summary: { type: "string" },
                    outreachAngle: { type: "string" },
                    aiRecommendations: {
                      type: "array",
                      maxItems: 6,
                      items: {
                        type: "string",
                        enum: [
                          "Recruit as Ambassador",
                          "Invite for Beta",
                          "Request Club Presentation",
                          "Sponsor Event",
                          "Offer Internship",
                          "Request Partnership"
                        ]
                      }
                    },
                    priorityLevel: { type: "string", enum: ["low", "medium", "high"] },
                    relationshipStrength: { type: "string", enum: ["cold", "warm", "active", "partner"] },
                    searchQuery: { type: "string" },
                    searchStrategy: { type: "string" }
                  },
                  required: [
                    "kind",
                    "campusName",
                    "name",
                    "category",
                    "description",
                    "website",
                    "instagramUrl",
                    "linkedInUrl",
                    "discordUrl",
                    "facebookUrl",
                    "meetingSchedule",
                    "tags",
                    "estimatedStudentReach",
                    "sourceType",
                    "sourceUrl",
                    "sourceTitle",
                    "sourceSnippet",
                    "publicEmail",
                    "publicContactName",
                    "publicContactTitle",
                    "venue",
                    "startsAtText",
                    "relevanceScore",
                    "discoveryConfidence",
                    "scoreReason",
                    "summary",
                    "outreachAngle",
                    "aiRecommendations",
                    "priorityLevel",
                    "relationshipStrength",
                    "searchQuery",
                    "searchStrategy"
                  ]
                }
              }
            },
            required: ["leads"]
          }
        }
      }
    })
  });

  if (!response.ok) return ruleBasedCandidates(input.searchResults, input.campusNames, input.categories);
  const data = (await response.json()) as { output_text?: string; output?: Array<{ content?: Array<{ text?: string }> }> };
  const jsonText = data.output_text ?? data.output?.flatMap((part) => part.content ?? []).map((content) => content.text).find(Boolean);
  if (!jsonText) return [];
  try {
    const parsed = JSON.parse(jsonText) as { leads?: AILeadCandidate[] };
    return parsed.leads ?? [];
  } catch {
    return [];
  }
}

function normalizeLead(lead: AILeadCandidate, searchResults: SearchResult[]): AILeadCandidate | null {
  const sourceUrl = cleanUrl(lead.sourceUrl);
  const blocked = blockedSourceReason(sourceUrl);
  if (!sourceUrl || blocked) return null;

  const source = searchResults.find((result) => result.link === sourceUrl) ?? searchResults.find((result) => sourceUrl.includes(result.link));
  const name = cleanText(lead.name, 180);
  const campusName = cleanText(lead.campusName, 180);
  const category = cleanText(lead.category, 120);
  if (!name || !campusName) return null;

  const relevanceScore = clamp(Math.round(Number(lead.relevanceScore) || scoreCampusLead({ name, category, notes: lead.summary })), 1, 100);
  const discoveryConfidence = clamp(Math.round(Number(lead.discoveryConfidence) || confidenceFromSource(sourceUrl, lead)), 1, 100);
  const aiRecommendations = normalizeRecommendations(lead.aiRecommendations, name, category, lead.summary);
  const priorityLevel = normalizePriority(lead.priorityLevel, relevanceScore, discoveryConfidence);
  return {
    kind: normalizeKind(lead.kind),
    campusName,
    name,
    category,
    description: cleanLongText(lead.description, 1000),
    website: cleanUrl(lead.website) || sourceUrl,
    instagramUrl: allowedOrgSocialUrl(lead.instagramUrl, "instagram.com"),
    linkedInUrl: allowedOrgSocialUrl(lead.linkedInUrl, "linkedin.com"),
    discordUrl: cleanUrl(lead.discordUrl),
    facebookUrl: allowedOrgSocialUrl(lead.facebookUrl, "facebook.com"),
    meetingSchedule: cleanText(lead.meetingSchedule, 300),
    tags: cleanStringArray(lead.tags, 12),
    estimatedStudentReach: clamp(Math.round(Number(lead.estimatedStudentReach) || 0), 0, 100000),
    sourceType: cleanText(lead.sourceType, 140) || "approved_public_source",
    sourceUrl,
    sourceTitle: cleanText(lead.sourceTitle || source?.title, 300),
    sourceSnippet: cleanLongText(lead.sourceSnippet || source?.snippet, 1000),
    publicEmail: cleanEmail(lead.publicEmail),
    publicContactName: cleanText(lead.publicContactName, 140),
    publicContactTitle: cleanText(lead.publicContactTitle, 140),
    venue: cleanText(lead.venue, 180),
    startsAtText: cleanText(lead.startsAtText, 120),
    relevanceScore,
    discoveryConfidence,
    scoreReason: cleanLongText(lead.scoreReason, 1000) || defaultScoreReason(relevanceScore, discoveryConfidence),
    summary: cleanLongText(lead.summary, 1200),
    outreachAngle: cleanLongText(lead.outreachAngle, 1200),
    aiRecommendations,
    priorityLevel,
    relationshipStrength: ["cold", "warm", "active", "partner"].includes(lead.relationshipStrength) ? lead.relationshipStrength : "cold",
    searchQuery: cleanText(lead.searchQuery || source?.query, 500),
    searchStrategy: cleanText(lead.searchStrategy || source?.query, 500)
  };
}

function ruleBasedCandidates(searchResults: SearchResult[], campuses: string[], categories: string[]): AILeadCandidate[] {
  return searchResults.slice(0, 30).map((result) => {
    const campusName = campuses.find((campus) => `${result.title} ${result.snippet}`.toLowerCase().includes(campus.toLowerCase())) ?? campuses[0] ?? "";
    const text = `${result.title} ${result.snippet}`.toLowerCase();
    const category = categories.find((item) => text.includes(item.toLowerCase().split("/")[0])) ?? inferCategory(text);
    const kind: DiscoveredLeadKind = text.includes("event") || text.includes("calendar") ? "event" : text.includes("department") ? "department" : "organization";
    return {
      kind,
      campusName,
      name: result.title,
      category,
      sourceType: result.query === "manual_url" ? "Manually entered URL" : "Public web search result",
      sourceUrl: result.link,
      sourceTitle: result.title,
      sourceSnippet: result.snippet,
      description: result.snippet,
      website: result.link,
      instagramUrl: "",
      linkedInUrl: "",
      discordUrl: "",
      facebookUrl: "",
      meetingSchedule: "",
      tags: [category],
      estimatedStudentReach: 0,
      publicEmail: "",
      publicContactName: "",
      publicContactTitle: "",
      venue: "",
      startsAtText: "",
      relevanceScore: scoreCampusLead({ name: result.title, category, notes: result.snippet }),
      discoveryConfidence: result.query === "manual_url" ? 80 : 55,
      scoreReason: `Matched public search result for ${category}.`,
      summary: result.snippet,
      outreachAngle: `Potential ${category} outreach opportunity for ${campusName}.`,
      aiRecommendations: recommendedActions(result.title, category, result.snippet),
      priorityLevel: "medium",
      relationshipStrength: "cold",
      searchQuery: result.query,
      searchStrategy: result.query
    };
  });
}

function inferCategory(text: string) {
  if (text.includes("computer") || text.includes("software") || text.includes("technology")) return "computer science/software";
  if (text.includes("government")) return "student government";
  if (text.includes("business") || text.includes("marketing")) return "business/marketing";
  if (text.includes("transport") || text.includes("sustain")) return "transportation/sustainability";
  if (text.includes("commuter")) return "commuter students";
  return "general campus outreach";
}

function blockedSourceReason(url: string) {
  if (!url) return "Missing source URL.";
  try {
    const parsed = new URL(url);
    const host = parsed.hostname.replace(/^www\./, "").toLowerCase();
    if (BLOCKED_HOSTS.some((blockedHost) => host === blockedHost || host.endsWith(`.${blockedHost}`))) {
      return "Blocked social or personal-profile source.";
    }
    if ((host === "instagram.com" || host.endsWith(".instagram.com")) && parsed.pathname.split("/").filter(Boolean).length <= 1) {
      return "Blocked likely personal Instagram profile source.";
    }
    if ((host === "linkedin.com" || host.endsWith(".linkedin.com")) && !parsed.pathname.toLowerCase().startsWith("/company/")) {
      return "Blocked personal LinkedIn profile source.";
    }
    const path = parsed.pathname.toLowerCase();
    if (BLOCKED_PATH_TERMS.some((term) => path.includes(term))) {
      return "Blocked login, private directory, or personal profile path.";
    }
    return "";
  } catch {
    return "Invalid source URL.";
  }
}

function uniqueByUrl(results: SearchResult[]) {
  const seen = new Set<string>();
  return results.filter((result) => {
    const key = result.link.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function cleanList(values: unknown): string[] {
  const list = Array.isArray(values) ? values : typeof values === "string" ? values.split(/\n|,/) : [];
  return list.map((value) => cleanText(value, 180)).filter(Boolean).slice(0, 20);
}

function uniqueStrings(values: string[]) {
  const seen = new Set<string>();
  return values.filter((value) => {
    const key = value.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function cleanStringArray(values: unknown, max: number) {
  if (!Array.isArray(values)) return [];
  return values.map((value) => cleanText(value, 80)).filter(Boolean).slice(0, max);
}

function normalizeKind(kind: string): DiscoveredLeadKind {
  const allowed: DiscoveredLeadKind[] = ["organization", "club", "chapter", "incubator", "event", "department", "student_government", "student_media"];
  return allowed.includes(kind as DiscoveredLeadKind) ? (kind as DiscoveredLeadKind) : "organization";
}

function normalizePriority(priority: string | undefined, relevanceScore: number, confidence: number): CampusLeadPriority {
  if (priority === "low" || priority === "medium" || priority === "high") return priority;
  if (relevanceScore >= 75 && confidence >= 60) return "high";
  if (relevanceScore >= 45) return "medium";
  return "low";
}

function normalizeRecommendations(values: unknown, name: string, category: string, summary: string): CampusAgentRecommendation[] {
  const parsed = Array.isArray(values)
    ? values.filter((value): value is CampusAgentRecommendation => CAMPUS_AGENT_RECOMMENDATIONS.includes(value as CampusAgentRecommendation))
    : [];
  const fallback = recommendedActions(name, category, summary);
  return uniqueStrings([...parsed, ...fallback]).filter((value): value is CampusAgentRecommendation =>
    CAMPUS_AGENT_RECOMMENDATIONS.includes(value as CampusAgentRecommendation)
  ).slice(0, 6);
}

function recommendedActions(name: string, category: string, summary: string): CampusAgentRecommendation[] {
  const text = `${name} ${category} ${summary}`.toLowerCase();
  const recommendations: CampusAgentRecommendation[] = [];
  if (text.includes("ambassador") || text.includes("student government") || text.includes("commuter")) recommendations.push("Recruit as Ambassador");
  if (text.includes("commuter") || text.includes("transport") || text.includes("student")) recommendations.push("Invite for Beta");
  if (text.includes("club") || text.includes("chapter") || text.includes("association")) recommendations.push("Request Club Presentation");
  if (text.includes("event") || text.includes("hackathon") || text.includes("fair")) recommendations.push("Sponsor Event");
  if (text.includes("computer") || text.includes("software") || text.includes("engineering")) recommendations.push("Offer Internship");
  if (text.includes("department") || text.includes("incubator") || text.includes("innovation")) recommendations.push("Request Partnership");
  return recommendations.length ? recommendations : ["Invite for Beta"];
}

function allowedOrgSocialUrl(value: unknown, hostName: string) {
  const url = cleanUrl(value);
  if (!url) return "";
  try {
    const parsed = new URL(url);
    const host = parsed.hostname.replace(/^www\./, "").toLowerCase();
    if (hostName === "linkedin.com") return parsed.pathname.toLowerCase().startsWith("/company/") ? url : "";
    if (host === hostName || host.endsWith(`.${hostName}`)) return url;
    return "";
  } catch {
    return "";
  }
}

function confidenceFromSource(sourceUrl: string, lead: AILeadCandidate) {
  const text = `${sourceUrl} ${lead.sourceType}`.toLowerCase();
  if (text.includes(".edu")) return 80;
  if (text.includes("ticketmaster") || text.includes("eventbrite")) return 65;
  if (lead.publicEmail || lead.meetingSchedule) return 70;
  return 55;
}

function defaultScoreReason(relevanceScore: number, confidence: number) {
  return `Score reflects campus fit, recruiting potential, and source confidence (${confidence}/100). Relevance score: ${relevanceScore}/100.`;
}

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max);
}

function aiModel() {
  return process.env.OPENAI_CAMPUS_MODEL || process.env.OPENAI_MODEL || "gpt-4o-mini";
}
