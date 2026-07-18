import { NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import type { DriverRecord } from "@/lib/types";
import { buildDriverOnboardingProgress } from "@/lib/driverOnboardingProgress";

export async function GET(_request: Request, { params }: { params: { uid: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const snap = await adminDb.collection("drivers").doc(params.uid).get();
  if (!snap.exists) return NextResponse.json({ error: "Driver not found." }, { status: 404 });

  const driver = { ...(snap.data() as DriverRecord), uid: snap.id };
  return NextResponse.json({ progress: buildDriverOnboardingProgress(driver) });
}
