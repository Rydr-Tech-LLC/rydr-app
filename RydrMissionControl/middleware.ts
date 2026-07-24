import { NextRequest, NextResponse } from "next/server";
import { MISSION_CONTROL_PATH_HEADER } from "@/lib/missionControlAccess";

export function middleware(request: NextRequest) {
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set(MISSION_CONTROL_PATH_HEADER, request.nextUrl.pathname);
  return NextResponse.next({ request: { headers: requestHeaders } });
}

export const config = {
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico).*)"]
};
