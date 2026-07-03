import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
import { deleteVehicleLibraryEntry, getVehicleLibraryEntry, upsertVehicleLibraryEntry, VEHICLE_BODY_STYLES, type VehicleBodyStyle } from "@/lib/vehicleLibrary";

export async function GET(_request: NextRequest, { params }: { params: { vehicleId: string } }) {
  const session = await getAdminSession();
  if (!session) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const entry = await getVehicleLibraryEntry(params.vehicleId);
  if (!entry) {
    return NextResponse.json({ error: "Vehicle library entry not found" }, { status: 404 });
  }
  return NextResponse.json({ entry });
}

export async function PATCH(request: NextRequest, { params }: { params: { vehicleId: string } }) {
  const session = await getAdminSession();
  if (!session) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const existing = await getVehicleLibraryEntry(params.vehicleId);
  if (!existing) {
    return NextResponse.json({ error: "Vehicle library entry not found" }, { status: 404 });
  }

  const body = await request.json().catch(() => ({}));
  const bodyStyle: VehicleBodyStyle = VEHICLE_BODY_STYLES.includes(body.bodyStyle) ? body.bodyStyle : existing.bodyStyle;
  const yearStart = Number.isFinite(Number(body.yearStart)) ? Number(body.yearStart) : existing.yearStart;
  const yearEnd = Number.isFinite(Number(body.yearEnd)) ? Number(body.yearEnd) : existing.yearEnd;
  if (
    !Number.isInteger(yearStart) ||
    !Number.isInteger(yearEnd) ||
    yearStart < 1980 ||
    yearEnd > 2100 ||
    yearEnd < yearStart
  ) {
    return NextResponse.json({ error: "`yearStart`/`yearEnd` must be valid years between 1980 and 2100 with yearEnd >= yearStart." }, { status: 400 });
  }

  const entry = await upsertVehicleLibraryEntry(
    {
      vehicleId: params.vehicleId,
      make: typeof body.make === "string" && body.make.trim() ? body.make.trim() : existing.make,
      model: typeof body.model === "string" && body.model.trim() ? body.model.trim() : existing.model,
      yearStart,
      yearEnd,
      trim: typeof body.trim === "string" ? (body.trim.trim() || null) : existing.trim,
      bodyStyle,
      eligibleRideTypes: Array.isArray(body.eligibleRideTypes) ? body.eligibleRideTypes : existing.eligibleRideTypes
    },
    session.uid
  );

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: "Vehicle Library Entry Updated",
    targetType: "vehicleLibrary",
    targetId: params.vehicleId
  });

  return NextResponse.json({ entry });
}

export async function DELETE(_request: NextRequest, { params }: { params: { vehicleId: string } }) {
  const session = await getAdminSession();
  if (!session) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  await deleteVehicleLibraryEntry(params.vehicleId);

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: "Vehicle Library Entry Deleted",
    targetType: "vehicleLibrary",
    targetId: params.vehicleId
  });

  return NextResponse.json({ ok: true });
}
