import { NextRequest, NextResponse } from "next/server";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { getWorkspaceDb } from "@/lib/firebaseAdmin";
import { removeDriverVehicle } from "../../../../../../rydr-backend/firebase/functions/src/services/driverVehicleArchivePolicy";

export async function DELETE(request: NextRequest, props: { params: Promise<{ uid: string }> }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  const { uid } = await props.params;
  const body = await request.json().catch(() => null);
  if (!body || typeof body.vehicleId !== "string" || typeof body.reason !== "string" || !body.reason.trim()) return NextResponse.json({ error: "Select a vehicle and enter a removal reason." }, { status: 400 });
  try {
    await removeDriverVehicle({ db: (await getWorkspaceDb()), FieldValue, uid, vehicleId: body.vehicleId, expectedVin: body.vin, expectedPlate: body.plate, actorUid: session.uid, actorRole: "admin", reason: body.reason.trim().slice(0, 1000) });
    return NextResponse.json({ removed: true });
  } catch (error: any) {
    return NextResponse.json({ error: error.message ?? "Removal failed." }, { status: error.code === "not-found" ? 404 : error.code === "failed-precondition" ? 409 : 400 });
  }
}
