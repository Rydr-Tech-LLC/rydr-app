import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
import {
  backfillDriverVehicleImagesForEntry,
  deleteVehicleImage,
  uploadVehicleImage,
  VEHICLE_COLORS,
  type VehicleColor
} from "@/lib/vehicleLibrary";

const MAX_SIZE = 5 * 1024 * 1024;

function isValidColor(value: unknown): value is VehicleColor {
  return typeof value === "string" && (VEHICLE_COLORS as readonly string[]).includes(value);
}

// POST /api/vehicle-library/{vehicleId}/image — multipart/form-data with
// fields: `file` (image), `color` (optional — omit to set the default image).
export async function POST(request: NextRequest, { params }: { params: { vehicleId: string } }) {
  const session = await getAdminSession();
  if (!session) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const form = await request.formData().catch(() => null);
  const file = form?.get("file");
  const colorRaw = form?.get("color");

  if (!(file instanceof File)) {
    return NextResponse.json({ error: "A `file` field with an image is required." }, { status: 400 });
  }
  if (file.size === 0 || file.size > MAX_SIZE) {
    return NextResponse.json({ error: "Image must be non-empty and under 5MB." }, { status: 400 });
  }
  if (!file.type.startsWith("image/")) {
    return NextResponse.json({ error: "File must be an image." }, { status: 400 });
  }

  const color = colorRaw ? String(colorRaw) : undefined;
  if (color && !isValidColor(color)) {
    return NextResponse.json({ error: `"${color}" is not one of the supported vehicle colors.` }, { status: 400 });
  }

  try {
    const data = Buffer.from(await file.arrayBuffer());
    const entry = await uploadVehicleImage({
      vehicleId: params.vehicleId,
      color: color as VehicleColor | undefined,
      contentType: file.type,
      data,
      adminUid: session.uid
    });
    const matchedDriverCount = await backfillDriverVehicleImagesForEntry(entry, color as VehicleColor | undefined);

    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: `Vehicle Image Uploaded${color ? ` (${color})` : " (default)"} · ${matchedDriverCount} driver profile${matchedDriverCount === 1 ? "" : "s"} updated`,
      targetType: "vehicleLibrary",
      targetId: params.vehicleId
    });

    return NextResponse.json({ entry, matchedDriverCount });
  } catch (err) {
    return NextResponse.json({ error: err instanceof Error ? err.message : "Upload failed" }, { status: 400 });
  }
}

// DELETE /api/vehicle-library/{vehicleId}/image?color=Red (omit color to delete the default image)
export async function DELETE(request: NextRequest, { params }: { params: { vehicleId: string } }) {
  const session = await getAdminSession();
  if (!session) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const color = request.nextUrl.searchParams.get("color") || undefined;
  if (color && !isValidColor(color)) {
    return NextResponse.json({ error: `"${color}" is not one of the supported vehicle colors.` }, { status: 400 });
  }

  try {
    const entry = await deleteVehicleImage({
      vehicleId: params.vehicleId,
      color: color as VehicleColor | undefined,
      adminUid: session.uid
    });

    await writeAuditLog({
      adminUid: session.uid,
      adminEmail: session.email ?? undefined,
      action: `Vehicle Image Deleted${color ? ` (${color})` : " (default)"}`,
      targetType: "vehicleLibrary",
      targetId: params.vehicleId
    });

    return NextResponse.json({ entry });
  } catch (err) {
    return NextResponse.json({ error: err instanceof Error ? err.message : "Delete failed" }, { status: 400 });
  }
}
