import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";

export async function GET() {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const apiKey = process.env.BRAVE_SEARCH_API_KEY || process.env.BRAVE_API_KEY;
  const hasApiKey = Boolean(apiKey);
  const requestCap = requestCapFromEnv();
  const manualUrlConfigured = Boolean(process.env.FIRECRAWL_API_KEY || process.env.FIRECRAWL_API_TOKEN);

  if (!apiKey) {
    return NextResponse.json({
      ok: false,
      configured: false,
      provider: "brave_web",
      hasApiKey,
      requestCap,
      manualUrlProvider: "firecrawl",
      manualUrlConfigured,
      error: "Brave Search credentials are missing from Mission Control environment variables."
    });
  }

  try {
    const params = new URLSearchParams({
      q: '"Georgia State University" "student organizations"',
      country: (process.env.BRAVE_SEARCH_COUNTRY || "US").toUpperCase(),
      search_lang: (process.env.BRAVE_SEARCH_LANGUAGE || "en").toLowerCase(),
      ui_lang: process.env.BRAVE_SEARCH_UI_LANGUAGE || "en-US",
      count: "1",
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
    });

    const data = (await response.json().catch(() => ({}))) as {
      web?: { results?: unknown[] };
      error?: { message?: string; code?: string };
      message?: string;
      type?: string;
      warning?: string;
    };

    if (!response.ok) {
      return NextResponse.json({
        ok: false,
        configured: true,
        provider: "brave_web",
        hasApiKey,
        requestCap,
        manualUrlProvider: "firecrawl",
        manualUrlConfigured,
        status: response.status,
        braveErrorCode: data.error?.code,
        error: data.error?.message || data.message || data.type || `Brave Search returned HTTP ${response.status}.`
      });
    }

    return NextResponse.json({
      ok: true,
      configured: true,
      provider: "brave_web",
      hasApiKey,
      requestCap,
      manualUrlProvider: "firecrawl",
      manualUrlConfigured,
      status: response.status,
      resultCount: data.web?.results?.length ?? 0,
      warning: data.warning ?? null
    });
  } catch (error) {
    return NextResponse.json({
      ok: false,
      configured: true,
      provider: "brave_web",
      hasApiKey,
      requestCap,
      manualUrlProvider: "firecrawl",
      manualUrlConfigured,
      error: error instanceof Error ? error.message : "Unable to reach Brave Search."
    });
  }
}

function requestCapFromEnv() {
  const value = Number(process.env.CAMPUS_DISCOVERY_MAX_SEARCH_REQUESTS_PER_RUN);
  if (!Number.isFinite(value)) return 100;
  return Math.min(Math.max(value, 1), 1000);
}
