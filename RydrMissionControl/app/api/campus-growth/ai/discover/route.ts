import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { discoverCampusLeads, discoveryFingerprint } from "@/lib/ai/campusGrowthAI";
import { writeAuditLog } from "@/lib/auditLog";
import { campusCollections, cleanText, listCampuses } from "@/lib/campusGrowth";
import { adminDb } from "@/lib/firebaseAdmin";
import { getAdminSession } from "@/lib/session";

const DISCOVERY_RATE_LIMIT = new Map<string, number[]>();
const MAX_DISCOVERY_RUNS_PER_HOUR = 10;

export async function POST(request: NextRequest) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  if (!allowDiscoveryRun(session.uid)) {
    return NextResponse.json({ error: "Lead discovery rate limit reached. Try again later." }, { status: 429 });
  }

  const body = await request.json().catch(() => null);
  if (!body) return NextResponse.json({ error: "Invalid discovery payload." }, { status: 400 });

  const result = await discoverCampusLeads({
    discoveryGoal: body.discoveryGoal,
    leadIntents: body.leadIntents,
    campusNames: body.campusNames,
    categories: body.categories,
    manualUrls: body.manualUrls,
    maxSearchResults: body.maxSearchResults
  });

  const campuses = await listCampuses(500);
  const campusByName = new Map(campuses.map((campus) => [cleanText(campus.name, 180).toLowerCase(), campus]));
  const savedIds: string[] = [];

  for (const lead of result.leads) {
    const campus = campusByName.get(lead.campusName.toLowerCase());
    const id = discoveryFingerprint(lead);
    const ref = adminDb.collection(campusCollections.discoveredLeads).doc(id);
    const existing = await ref.get();
    if (existing.exists && existing.data()?.reviewStatus === "approved") continue;

    await ref.set(
      {
        kind: lead.kind,
        reviewStatus: "pending_review",
        campusId: campus?.id ?? "",
        campusName: lead.campusName,
        name: lead.name,
        category: lead.category,
        description: lead.description ?? "",
        website: lead.website ?? "",
        instagramUrl: lead.instagramUrl ?? "",
        linkedInUrl: lead.linkedInUrl ?? "",
        discordUrl: lead.discordUrl ?? "",
        facebookUrl: lead.facebookUrl ?? "",
        meetingSchedule: lead.meetingSchedule ?? "",
        tags: lead.tags ?? [],
        estimatedStudentReach: lead.estimatedStudentReach ?? 0,
        sourceType: lead.sourceType,
        sourceUrl: lead.sourceUrl,
        sourceTitle: lead.sourceTitle ?? "",
        sourceSnippet: lead.sourceSnippet ?? "",
        publicEmail: lead.publicEmail ?? "",
        publicContactName: lead.publicContactName ?? "",
        publicContactTitle: lead.publicContactTitle ?? "",
        venue: lead.venue ?? "",
        startsAtText: lead.startsAtText ?? "",
        relevanceScore: lead.relevanceScore,
        discoveryConfidence: lead.discoveryConfidence,
        scoreReason: lead.scoreReason,
        summary: lead.summary,
        outreachAngle: lead.outreachAngle,
        aiRecommendations: lead.aiRecommendations,
        priorityLevel: lead.priorityLevel,
        relationshipStrength: lead.relationshipStrength,
        lastAIRecommendation: lead.aiRecommendations[0] ?? "",
        customTags: lead.tags ?? [],
        interactionTimeline: [
          {
            type: "ai_recommendation",
            summary: lead.scoreReason || lead.outreachAngle,
            createdBy: "AI Campus Agent",
            createdAt: FieldValue.serverTimestamp()
          }
        ],
        discoveryRunId: result.runId,
        searchQuery: lead.searchQuery ?? "",
        searchStrategy: lead.searchStrategy ?? lead.searchQuery ?? "",
        aiModel: result.model,
        discoveredBy: session.email ?? session.uid,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: existing.exists ? existing.data()?.createdAt ?? FieldValue.serverTimestamp() : FieldValue.serverTimestamp()
      },
      { merge: true }
    );
    savedIds.push(id);
  }

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: "AI Campus Lead Discovery Run",
    targetType: "campusDiscoveredLead",
    targetId: result.runId,
    metadata: {
      savedCount: savedIds.length,
      searchResultCount: result.searchResults.length,
      searchStrategyCount: result.searchStrategies.length,
      searchProviderConfigured: result.searchProviderConfigured,
      searchErrorCount: result.searchErrors.length,
      warnings: result.warnings,
      rejectedSourceCount: result.rejectedSources.length,
      model: result.model
    }
  });

  return NextResponse.json({
    runId: result.runId,
    savedCount: savedIds.length,
    searchResultCount: result.searchResults.length,
    searchStrategyCount: result.searchStrategies.length,
    searchProviderConfigured: result.searchProviderConfigured,
    searchErrors: result.searchErrors.slice(0, 10),
    warnings: result.warnings,
    rejectedSources: result.rejectedSources
  });
}

function allowDiscoveryRun(uid: string) {
  const now = Date.now();
  const windowStart = now - 1000 * 60 * 60;
  const recent = (DISCOVERY_RATE_LIMIT.get(uid) ?? []).filter((timestamp) => timestamp > windowStart);
  if (recent.length >= MAX_DISCOVERY_RUNS_PER_HOUR) {
    DISCOVERY_RATE_LIMIT.set(uid, recent);
    return false;
  }
  recent.push(now);
  DISCOVERY_RATE_LIMIT.set(uid, recent);
  return true;
}
