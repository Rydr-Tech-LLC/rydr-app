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
  "Georgia State University Perimeter College",
  "Clayton State University",
  "Georgia Institute of Technology"
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
  "Public campus-affiliated organization and student-leader social accounts",
  "Ticketmaster/public event APIs if already approved",
  "Manually entered URLs"
];

export const BLOCKED_LEAD_SOURCES = [
  "Unrelated personal social profiles without a clear public campus role",
  "Private or login-required social profiles and groups",
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
  content?: string;
  provider?: string;
}

export interface SearchProviderError {
  query: string;
  status?: number;
  error: string;
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
  tiktokUrl?: string;
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
  searchProviderConfigured: boolean;
  searchErrors: SearchProviderError[];
  warnings: string[];
  searchResults: SearchResult[];
  leads: AILeadCandidate[];
  rejectedSources: Array<{ url: string; reason: string }>;
}

const BLOCKED_PATH_TERMS = ["login", "signin", "sign-in", "auth", "portal", "blackboard", "canvas", "people", "person", "profile"];
const SEARCH_CACHE = new Map<string, { expiresAt: number; results: SearchResult[] }>();
const DEFAULT_MAX_SEARCH_STRATEGIES = 28;
const DEFAULT_BRAVE_REQUEST_CAP = 100;
const BRAVE_REQUEST_HARD_CAP = 1000;
const MAX_RESULTS_FOR_LEAD_EXTRACTION = 80;
const SOCIAL_HOSTS = ["instagram.com", "facebook.com", "tiktok.com"];
const CONTACTABLE_CAMPUS_TERMS = [
  "student organization",
  "student org",
  "club",
  "chapter",
  "association",
  "student government",
  "student media",
  "campus ambassador",
  "student ambassador",
  "student leader",
  "student leaders",
  "students",
  "commuter",
  "campus life",
  "university",
  "college",
  "official"
];

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
  const maxSearchResults = clamp(Number(input.maxSearchResults) || 5, 1, 20);
  const runId = crypto.randomUUID();
  const searchStrategies = await planSearchStrategies(campusNames, categories, discoveryGoal, leadIntents);
  const searchBatch = await runBraveSearches(searchStrategies, maxSearchResults);
  const manualBatch = await manualUrlResults(input.manualUrls);

  const rawResults = [
    ...searchBatch.results,
    ...manualBatch.results
  ];
  const warnings = [...searchBatch.warnings, ...manualBatch.warnings];

  const rejectedSources: DiscoveryResult["rejectedSources"] = [];
  const searchResults = rankSearchResults(uniqueByUrl(rawResults).filter((result) => {
    const blocked = blockedSourceReason(result.link, result);
    if (blocked) rejectedSources.push({ url: result.link, reason: blocked });
    return !blocked;
  })).slice(0, MAX_RESULTS_FOR_LEAD_EXTRACTION);

  if (!searchResults.length) {
    if (!searchBatch.providerConfigured) {
      warnings.push("Brave Search is not configured. Add BRAVE_SEARCH_API_KEY in Mission Control environment variables, or paste approved public URLs.");
    } else if (searchBatch.errors.length) {
      warnings.push("Brave Search returned search errors. Check the API key, quota, billing, and provider status.");
    } else {
      warnings.push("No public search results were returned. Try broader categories, fewer filters, or paste approved public URLs.");
    }
    return {
      runId,
      model: aiModel(),
      searchStrategies,
      searchProviderConfigured: searchBatch.providerConfigured,
      searchErrors: [...searchBatch.errors, ...manualBatch.errors],
      warnings,
      searchResults,
      leads: [],
      rejectedSources
    };
  }

  const leads = await extractLeadsWithAI({ campusNames, categories, leadIntents, discoveryGoal, searchStrategies, searchResults });
  const cleaned = leads
    .map((lead) => normalizeLead(lead, searchResults))
    .filter((lead): lead is AILeadCandidate => Boolean(lead))
    .slice(0, 50);

  if (!cleaned.length) {
    warnings.push("Public results were found, but the AI did not extract usable leads. Try a broader search goal or paste approved public URLs.");
  }

  return {
    runId,
    model: aiModel(),
    searchStrategies,
    searchProviderConfigured: searchBatch.providerConfigured,
    searchErrors: [...searchBatch.errors, ...manualBatch.errors],
    warnings,
    searchResults,
    leads: cleaned,
    rejectedSources
  };
}

async function planSearchStrategies(campusNames: string[], categories: string[], discoveryGoal: string, leadIntents: string[]): Promise<string[]> {
  const fallback = buildFallbackQueries(campusNames, categories, discoveryGoal, leadIntents);
  const apiKey = process.env.OPENAI_API_KEY;
  const maxStrategies = maxSearchStrategies();
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
            "You are the Rydr Campus Agent search planner. Generate contact-focused public-web queries, not article-research queries. Cover every selected campus. Prioritize official organization directories plus public Instagram, Facebook, and TikTok accounts for campus organizations, clubs, student government, student media, commuter groups, and people who publicly identify a campus ambassador or student-leader role. Do not target unrelated personal profiles, private groups, login-required pages, scraped personal data, or guessed contact details. Use site: operators for social platforms. Return JSON only."
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
                maxItems: maxStrategies,
                items: { type: "string" }
              }
            },
            required: ["queries"]
          }
        }
      }
    })
  }).catch(() => null);

  if (!response?.ok) return fallback;
  const data = (await response.json()) as { output_text?: string; output?: Array<{ content?: Array<{ text?: string }> }> };
  const jsonText = data.output_text ?? data.output?.flatMap((part) => part.content ?? []).map((content) => content.text).find(Boolean);
  if (!jsonText) return fallback;
  try {
    const parsed = JSON.parse(jsonText) as { queries?: string[] };
    const planned = (parsed.queries ?? []).map((query) => cleanText(query, 240)).filter(Boolean);
    return planned.length ? uniqueStrings([...fallback, ...planned]).slice(0, maxStrategies) : fallback;
  } catch {
    return fallback;
  }
}

async function runBraveSearches(
  queries: string[],
  maxSearchResults: number
): Promise<{ providerConfigured: boolean; results: SearchResult[]; errors: SearchProviderError[]; warnings: string[] }> {
  const apiKey = braveApiKey();
  if (!apiKey) {
    return {
      providerConfigured: false,
      results: [],
      errors: [],
      warnings: ["Brave Search credentials are missing in Mission Control environment variables."]
    };
  }

  const requestCap = braveRequestCap();
  const cappedQueries = queries.slice(0, requestCap);
  const batches = await mapWithConcurrency(
    cappedQueries,
    braveSearchConcurrency(),
    (query) => braveWebSearch(query, apiKey, maxSearchResults)
  );
  const warnings = queries.length > cappedQueries.length
    ? [`Brave Search request cap limited this run to ${cappedQueries.length} of ${queries.length} planned searches. The hard maximum is ${BRAVE_REQUEST_HARD_CAP} requests per run.`]
    : [];

  return {
    providerConfigured: true,
    results: batches.flatMap((batch) => batch.results),
    errors: batches.flatMap((batch) => (batch.error ? [batch.error] : [])),
    warnings
  };
}

export function buildFallbackQueries(
  campusNames: string[],
  categories: string[],
  discoveryGoal = "",
  leadIntents: string[] = []
) {
  const campuses = cleanList(campusNames);
  const intentTerms = uniqueStrings([
    ...cleanList(leadIntents),
    ...categories.slice(0, 4).map((category) => cleanText(category, 80))
  ]).slice(0, 6);
  const focus = intentTerms.length
    ? intentTerms.map((intent) => `"${intent}"`).join(" OR ")
    : '"student organization" OR club OR ambassador OR commuter';
  const goalTerms = discoveryGoal.toLowerCase().includes("beta") ? ' OR "beta tester"' : "";
  const queryGroups: Array<(campus: string) => string> = [
    (campus) => `"${campus}" ("student organization" OR club OR "student government" OR "student media" OR commuter) (contact OR Instagram OR Facebook OR TikTok) -news -article`,
    (campus) => `site:instagram.com "${campus}" (${focus}${goalTerms}) -news -article`,
    (campus) => `site:facebook.com "${campus}" (${focus}${goalTerms}) -news -article`,
    (campus) => `site:tiktok.com "${campus}" (${focus} OR "student leader" OR "campus life"${goalTerms}) -news -article`
  ];

  const queries = queryGroups.flatMap((buildQuery) => campuses.map(buildQuery));
  return uniqueStrings(queries).slice(0, maxSearchStrategies());
}

function maxSearchStrategies() {
  return clamp(Number(process.env.CAMPUS_DISCOVERY_MAX_STRATEGIES) || DEFAULT_MAX_SEARCH_STRATEGIES, 4, 40);
}

function braveRequestCap() {
  return clamp(Number(process.env.CAMPUS_DISCOVERY_MAX_SEARCH_REQUESTS_PER_RUN) || DEFAULT_BRAVE_REQUEST_CAP, 1, BRAVE_REQUEST_HARD_CAP);
}

function braveSearchConcurrency() {
  return clamp(Number(process.env.BRAVE_SEARCH_CONCURRENCY) || 3, 1, 10);
}

function braveApiKey() {
  return process.env.BRAVE_SEARCH_API_KEY || process.env.BRAVE_API_KEY || "";
}

function braveSearchCountry() {
  return cleanText(process.env.BRAVE_SEARCH_COUNTRY, 2).toUpperCase() || "US";
}

function braveSearchLanguage() {
  return cleanText(process.env.BRAVE_SEARCH_LANGUAGE, 12).toLowerCase() || "en";
}

async function braveWebSearch(query: string, apiKey: string, maxSearchResults: number): Promise<{ results: SearchResult[]; error?: SearchProviderError }> {
  const cacheKey = `brave-web|${query}|${maxSearchResults}`;
  const cached = SEARCH_CACHE.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) return { results: cached.results };

  const params = new URLSearchParams({
    q: query,
    country: braveSearchCountry(),
    search_lang: braveSearchLanguage(),
    ui_lang: process.env.BRAVE_SEARCH_UI_LANGUAGE || "en-US",
    count: String(maxSearchResults),
    result_filter: "web",
    safesearch: process.env.BRAVE_SEARCH_SAFESEARCH || "moderate",
    spellcheck: "true",
    text_decorations: "false",
    extra_snippets: process.env.BRAVE_SEARCH_EXTRA_SNIPPETS === "false" ? "false" : "true"
  });

  const response = await fetch(`https://api.search.brave.com/res/v1/web/search?${params.toString()}`, {
    method: "GET",
    cache: "no-store",
    headers: {
      Accept: "application/json",
      "Accept-Encoding": "gzip",
      "Cache-Control": "no-cache",
      "X-Subscription-Token": apiKey
    }
  }).catch((error) => {
    const message = error instanceof Error ? error.message : "Unable to reach Brave Search.";
    return { error: message };
  });
  if ("error" in response) {
    return {
      results: [],
      error: {
        query,
        error: response.error
      }
    };
  }
  const data = (await response.json().catch(() => ({}))) as {
    web?: {
      results?: Array<{
        title?: string;
        url?: string;
        description?: string;
        extra_snippets?: string[];
        profile?: { name?: string; url?: string };
      }>;
    };
    error?: { message?: string; code?: string };
    message?: string;
    type?: string;
  };
  if (!response.ok) {
    return {
      results: [],
      error: {
        query,
        status: response.status,
        error: data.error?.message || data.message || data.type || `Brave Search returned HTTP ${response.status}.`
      }
    };
  }

  const results = (data.web?.results ?? [])
    .map((item) => {
      const snippets = [item.description, ...(item.extra_snippets ?? [])].filter(Boolean);
      return {
        title: cleanText(item.title || item.profile?.name, 300),
        link: cleanUrl(item.url || item.profile?.url),
        snippet: cleanLongText(snippets.join("\n"), 1000),
        content: cleanLongText(snippets.join("\n\n"), 4000),
        query,
        provider: "brave_web"
      };
    })
    .filter((item) => item.title && item.link);
  SEARCH_CACHE.set(cacheKey, { expiresAt: Date.now() + 1000 * 60 * 30, results });
  return { results };
}

async function mapWithConcurrency<T, R>(items: T[], concurrency: number, worker: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = [];
  let index = 0;
  async function runNext() {
    while (index < items.length) {
      const currentIndex = index;
      index += 1;
      results[currentIndex] = await worker(items[currentIndex]!);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, runNext));
  return results;
}

function firecrawlApiKey() {
  return process.env.FIRECRAWL_API_KEY || process.env.FIRECRAWL_API_TOKEN || "";
}

async function manualUrlResults(
  urls: unknown
): Promise<{ results: SearchResult[]; errors: SearchProviderError[]; warnings: string[] }> {
  const values = Array.isArray(urls) ? urls : typeof urls === "string" ? urls.split(/\s+/) : [];
  const cleanUrls = values
    .map((value) => cleanUrl(value))
    .filter(Boolean);
  if (!cleanUrls.length) return { results: [], errors: [], warnings: [] };

  const apiKey = firecrawlApiKey();
  if (!apiKey) {
    return {
      results: cleanUrls.map((url) => manualUrlFallbackResult(url)),
      errors: [],
      warnings: ["Manual URLs were added without Firecrawl configured, so extraction is limited to URL/title context."]
    };
  }

  const batches = await mapWithConcurrency(
    cleanUrls,
    clamp(Number(process.env.FIRECRAWL_MANUAL_URL_CONCURRENCY) || 2, 1, 4),
    (url) => firecrawlScrapeManualUrl(url, apiKey)
  );
  return {
    results: batches.flatMap((batch) => batch.result ? [batch.result] : []),
    errors: batches.flatMap((batch) => batch.error ? [batch.error] : []),
    warnings: batches.some((batch) => batch.error)
      ? ["One or more manual URLs could not be scraped. Those URLs were skipped or need to be checked manually."]
      : []
  };
}

function manualUrlFallbackResult(url: string): SearchResult {
  return {
    title: "Manually entered URL",
    link: url,
    snippet: "Admin-approved manual URL for campus lead discovery.",
    query: "manual_url",
    provider: "manual"
  };
}

async function firecrawlScrapeManualUrl(
  url: string,
  apiKey: string
): Promise<{ result?: SearchResult; error?: SearchProviderError }> {
  const cacheKey = `firecrawl-scrape|${url}`;
  const cached = SEARCH_CACHE.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) return { result: cached.results[0] };

  const response = await fetch("https://api.firecrawl.dev/v2/scrape", {
    method: "POST",
    cache: "no-store",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      url,
      formats: ["markdown"],
      onlyMainContent: true,
      onlyCleanContent: true,
      timeout: clamp(Number(process.env.FIRECRAWL_MANUAL_URL_TIMEOUT_MS) || 30000, 10000, 60000),
      removeBase64Images: true,
      blockAds: true,
      location: {
        country: "US",
        languages: ["en-US"]
      }
    })
  }).catch((error) => {
    const message = error instanceof Error ? error.message : "Unable to scrape manual URL.";
    return { error: message };
  });

  if ("error" in response) {
    return { error: { query: "manual_url", error: response.error } };
  }

  const data = (await response.json().catch(() => ({}))) as {
    success?: boolean;
    data?: {
      markdown?: string;
      summary?: string;
      metadata?: {
        title?: string;
        description?: string;
        sourceURL?: string;
        url?: string;
        error?: string;
      };
      warning?: string;
    };
    error?: string;
    code?: string;
  };
  if (!response.ok || data.success === false) {
    return {
      error: {
        query: "manual_url",
        status: response.status,
        error: data.error || data.code || data.data?.metadata?.error || `Firecrawl scrape returned HTTP ${response.status}.`
      }
    };
  }

  const result = {
    title: cleanText(data.data?.metadata?.title, 300) || "Manually entered URL",
    link: cleanUrl(data.data?.metadata?.sourceURL || data.data?.metadata?.url) || url,
    snippet: cleanLongText(data.data?.metadata?.description || data.data?.summary, 1000) || "Admin-approved manual URL for campus lead discovery.",
    content: cleanLongText(data.data?.markdown, 9000),
    query: "manual_url",
    provider: "firecrawl_scrape"
  };
  SEARCH_CACHE.set(cacheKey, { expiresAt: Date.now() + 1000 * 60 * 30, results: [result] });
  return { result };
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
            "You are the Rydr AI Campus Agent. Extract contactable public campus recruiting leads for CashRydr rather than articles about campus topics. Prefer campus organizations, clubs, chapters, student government, student media, commuter groups, events, departments, and people who publicly identify a campus ambassador or student-leader role. A public Instagram, Facebook, or TikTok account may be a lead source only when the result title or snippet clearly establishes that campus affiliation and recruiting relevance. Never infer private facts, collect unrelated personal profiles, guess emails, or use private directories, private groups, login pages, or personal LinkedIn profiles. Store only public contact channels present in the supplied search results. Return concise JSON only."
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
                    tiktokUrl: { type: "string" },
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
                    "tiktokUrl",
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
  }).catch(() => null);

  if (!response?.ok) return ruleBasedCandidates(input.searchResults, input.campusNames, input.categories);
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
  const source = searchResults.find((result) => result.link === sourceUrl) ?? searchResults.find((result) => sourceUrl.includes(result.link));
  const blocked = blockedSourceReason(sourceUrl, source);
  if (!sourceUrl || blocked) return null;

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
    tiktokUrl: allowedOrgSocialUrl(lead.tiktokUrl, "tiktok.com"),
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
      instagramUrl: socialUrlForHost(result.link, "instagram.com"),
      linkedInUrl: "",
      discordUrl: "",
      facebookUrl: socialUrlForHost(result.link, "facebook.com"),
      tiktokUrl: socialUrlForHost(result.link, "tiktok.com"),
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

function blockedSourceReason(url: string, result?: SearchResult) {
  if (!url) return "Missing source URL.";
  try {
    const parsed = new URL(url);
    const host = parsed.hostname.replace(/^www\./, "").toLowerCase();
    if (isSocialHost(host) && !isContactableCampusSocialResult(result)) {
      return "Blocked social profile without clear public campus organization or student-leader context.";
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

function isContactableCampusSocialResult(result?: SearchResult) {
  if (!result) return false;
  if (result.query === "manual_url") return true;
  const text = `${result.title} ${result.snippet}`.toLowerCase();
  return CONTACTABLE_CAMPUS_TERMS.some((term) => text.includes(term));
}

function isSocialHost(host: string) {
  return SOCIAL_HOSTS.some((socialHost) => host === socialHost || host.endsWith(`.${socialHost}`));
}

function rankSearchResults(results: SearchResult[]) {
  return results
    .map((result, index) => ({ result, index, score: contactabilityScore(result) }))
    .sort((left, right) => right.score - left.score || left.index - right.index)
    .map(({ result }) => result);
}

function contactabilityScore(result: SearchResult) {
  const text = `${result.title} ${result.snippet} ${result.query}`.toLowerCase();
  let score = 0;
  try {
    const host = new URL(result.link).hostname.replace(/^www\./, "").toLowerCase();
    if (isSocialHost(host)) score += 45;
    if (host.endsWith(".edu")) score += 25;
  } catch {
    return -100;
  }
  if (CONTACTABLE_CAMPUS_TERMS.some((term) => text.includes(term))) score += 25;
  if (/(contact|email|dm|instagram|facebook|tiktok|join|officers|leadership)/.test(text)) score += 15;
  if (/(news|article|press release|opinion|research paper)/.test(text)) score -= 30;
  return score;
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

function socialUrlForHost(value: unknown, hostName: string) {
  return allowedOrgSocialUrl(value, hostName);
}

function confidenceFromSource(sourceUrl: string, lead: AILeadCandidate) {
  const text = `${sourceUrl} ${lead.sourceType}`.toLowerCase();
  if (text.includes(".edu")) return 80;
  if (SOCIAL_HOSTS.some((host) => text.includes(host))) return 65;
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
