import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";

export async function GET() {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const apiKey = process.env.GOOGLE_CUSTOM_SEARCH_API_KEY;
  const cx = process.env.GOOGLE_CUSTOM_SEARCH_ENGINE_ID;
  const hasApiKey = Boolean(apiKey);
  const hasSearchEngineId = Boolean(cx);

  if (!apiKey || !cx) {
    return NextResponse.json({
      ok: false,
      configured: false,
      hasApiKey,
      hasSearchEngineId,
      error: "Google Custom Search credentials are missing from Mission Control environment variables."
    });
  }

  const params = new URLSearchParams({
    key: apiKey,
    cx,
    q: '"Georgia State University" "student organizations"',
    num: "1",
    safe: "active"
  });

  try {
    const response = await fetch(`https://www.googleapis.com/customsearch/v1?${params.toString()}`, { cache: "no-store" });
    const data = (await response.json().catch(() => ({}))) as {
      items?: unknown[];
      searchInformation?: { totalResults?: string };
      error?: { code?: number; message?: string; status?: string };
    };

    if (!response.ok) {
      return NextResponse.json({
        ok: false,
        configured: true,
        hasApiKey,
        hasSearchEngineId,
        status: response.status,
        googleErrorCode: data.error?.code,
        googleErrorStatus: data.error?.status,
        error: data.error?.message || `Google Custom Search returned HTTP ${response.status}.`
      });
    }

    return NextResponse.json({
      ok: true,
      configured: true,
      hasApiKey,
      hasSearchEngineId,
      status: response.status,
      resultCount: data.items?.length ?? 0,
      totalResults: data.searchInformation?.totalResults ?? "0"
    });
  } catch (error) {
    return NextResponse.json({
      ok: false,
      configured: true,
      hasApiKey,
      hasSearchEngineId,
      error: error instanceof Error ? error.message : "Unable to reach Google Custom Search."
    });
  }
}
