import { driverResumeTarget, resumeDriverOnboarding } from "@/lib/driverOnboardingResume";
import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { getWorkspaceDb } from "@/lib/firebaseAdmin";
import type { DriverRecord } from "@/lib/types";
import { buildDriverOnboardingProgress } from "@/lib/driverOnboardingProgress";

export async function GET(_request: Request, props: { params: Promise<{ uid: string }> }) {
  const params = await props.params;
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const snap = await (await getWorkspaceDb()).collection("drivers").doc(params.uid).get();
  if (!snap.exists) return NextResponse.json({ error: "Driver not found." }, { status: 404 });

  const driver = { ...(snap.data() as DriverRecord), uid: snap.id };
  return NextResponse.json({ progress: buildDriverOnboardingProgress(driver), resumeTarget: await driverResumeTarget(params.uid, driver as unknown as Record<string, unknown>) }, { headers: { "Cache-Control": "no-store" } });
}

export async function POST(_request: Request, props: { params: Promise<{ uid: string }> }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  const { uid } = await props.params;
  try {
    const target = await resumeDriverOnboarding(uid, session);
    return NextResponse.json({ ok: true, resumeTarget: target });
  } catch (error) {
    const failure = error as Error & { statusCode?: number };
    return NextResponse.json({ error: failure.statusCode ? failure.message : "Unable to resume onboarding. Please retry." }, { status: failure.statusCode ?? 500 });
  }
}
