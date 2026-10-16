import { NextRequest, NextResponse } from "next/server";
import { MISSION_CONTROL_PATH_HEADER } from "@/lib/missionControlAccess";
const prefix = /^\/workspaces\/(test|live-beta)(\/.*|$)/;
export function proxy(request: NextRequest) {
  const pathname = request.nextUrl.pathname;
  const match = pathname.match(prefix);
  const isApi = pathname.startsWith("/api/");
  let workspace = match?.[1];
  if (isApi) {
    const explicit = request.headers.get("x-rydr-workspace");
    if (explicit === "test" || explicit === "live-beta") workspace = explicit;
    else {
      try {
        const ref = new URL(request.headers.get("referer") ?? "");
        if (ref.origin === request.nextUrl.origin)
          workspace = ref.pathname.match(prefix)?.[1];
      } catch {}
    }
    if (
      !workspace &&
      pathname === "/api/waitlist" &&
      ["POST", "OPTIONS"].includes(request.method)
    )
      workspace = "live-beta";
    if (!workspace && !["/api/session"].includes(pathname))
      return NextResponse.json(
        { error: "Workspace context is required" },
        { status: 400 },
      );
  }
  const publicPath =
    pathname === "/login" ||
    pathname.startsWith("/api/") ||
    pathname.startsWith("/_next/") ||
    pathname === "/favicon.ico";
  if (!match && !isApi && !publicPath) {
    const url = request.nextUrl.clone();
    url.pathname =
      "/workspaces/test" + (pathname === "/" ? "/dashboard" : pathname);
    return NextResponse.redirect(url);
  }
  const requestHeaders = new Headers(request.headers);
  requestHeaders.delete("x-rydr-workspace");
  if (workspace) requestHeaders.set("x-rydr-workspace", workspace);
  requestHeaders.set(MISSION_CONTROL_PATH_HEADER, match?.[2] || pathname);
  if (match) {
    const url = request.nextUrl.clone();
    url.pathname = match[2] || "/dashboard";
    return NextResponse.rewrite(url, { request: { headers: requestHeaders } });
  }
  return NextResponse.next({ request: { headers: requestHeaders } });
}
export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
