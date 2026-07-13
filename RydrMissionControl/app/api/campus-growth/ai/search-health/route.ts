import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";

export async function GET() {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const apiKey = process.env.FIRECRAWL_API_KEY || process.env.FIRECRAWL_API_TOKEN;
  const hasApiKey = Boolean(apiKey);

  if (!apiKey) {
    return NextResponse.json({
      ok: false,
      configured: false,
      provider: "firecrawl",
      hasApiKey,
      error: "Firecrawl credentials are missing from Mission Control environment variables."
    });
  }

  try {
    const response = await fetch("https://api.firecrawl.dev/v2/search", {
      method: "POST",
      cache: "no-store",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        query: '"Georgia State University" "student organizations"',
        limit: 1,
        sources: ["web"],
        country: "US",
        location: process.env.FIRECRAWL_SEARCH_LOCATION || "Atlanta, Georgia, United States",
        timeout: 30000,
        ignoreInvalidURLs: true,
        scrapeOptions: {
          formats: [{ type: "markdown" }],
          onlyMainContent: true
        }
      })
    });

    const data = (await response.json().catch(() => ({}))) as {
      success?: boolean;
      data?: { web?: unknown[] };
      error?: string;
      code?: string;
      warning?: string;
      creditsUsed?: number;
    };

    if (!response.ok || data.success === false) {
      return NextResponse.json({
        ok: false,
        configured: true,
        provider: "firecrawl",
        hasApiKey,
        status: response.status,
        firecrawlErrorCode: data.code,
        error: data.error || `Firecrawl returned HTTP ${response.status}.`
      });
    }

    return NextResponse.json({
      ok: true,
      configured: true,
      provider: "firecrawl",
      hasApiKey,
      status: response.status,
      resultCount: data.data?.web?.length ?? 0,
      creditsUsed: data.creditsUsed ?? null,
      warning: data.warning ?? null
    });
  } catch (error) {
    return NextResponse.json({
      ok: false,
      configured: true,
      provider: "firecrawl",
      hasApiKey,
      error: error instanceof Error ? error.message : "Unable to reach Firecrawl."
    });
  }
}
