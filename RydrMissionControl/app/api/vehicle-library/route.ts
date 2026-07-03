import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
import {
  searchVehicleLibrary,
  upsertVehicleLibraryEntry,
  VEHICLE_BODY_STYLES,
  VEHICLE_COLORS,
  type VehicleBodyStyle,
  type VehicleColor
} from "@/lib/vehicleLibrary";

// GET /api/vehicle-library?make=&model=&year=&trim=&color=&missingImagesOnly=1&incompleteColorsOnly=1
export async function GET(request: NextRequest) {
  const session = await getAdminSession();
  if (!session) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const params = request.nextUrl.searchParams;
  const year = params.get("year");
  const color = params.get("color");
  const parsedYear = year ? Number(year) : undefined;
  if (year && (parsedYear === undefined || !Number.isInteger(parsedYear) || parsedYear < 1980 || parsedYear > 2100)) {
    return NextResponse.json({ error: "`year` must be a valid four-digit vehicle year." }, { status: 400 });
  }
  if (color && !(VEHICLE_COLORS as readonly string[]).includes(color)) {
    return NextResponse.json({ error: `"${color}" is not one of the supported vehicle colors.` }, { status: 400 });
  }

  const entries = await searchVehicleLibrary({
    make: params.get("make") || undefined,
    model: params.get("model") || undefined,
    trim: params.get("trim") || undefined,
    color: (color as VehicleColor) || undefined,
    year: parsedYear,
    missingImagesOnly: params.get("missingImagesOnly") === "1",
    incompleteColorsOnly: params.get("incompleteColorsOnly") === "1"
  });

  return NextResponse.json({ entries });
}

// POST /api/vehicle-library — create a new vehicle library entry (metadata only; upload images separately).
export async function POST(request: NextRequest) {
  const session = await getAdminSession();
  if (!session) {
    return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body || typeof body.make !== "string" || typeof body.model !== "string" || !body.make.trim() || !body.model.trim()) {
    return NextResponse.json({ error: "`make` and `model` are required." }, { status: 400 });
  }

  const yearStart = Number(body.yearStart);
  const yearEnd = Number(body.yearEnd ?? body.yearStart);
  if (
    !Number.isInteger(yearStart) ||
    !Number.isInteger(yearEnd) ||
    yearStart < 1980 ||
    yearEnd > 2100 ||
    yearEnd < yearStart
  ) {
    return NextResponse.json({ error: "`yearStart`/`yearEnd` must be valid years between 1980 and 2100 with yearEnd >= yearStart." }, { status: 400 });
  }

  const bodyStyle: VehicleBodyStyle = VEHICLE_BODY_STYLES.includes(body.bodyStyle) ? body.bodyStyle : "unknown";

  const entry = await upsertVehicleLibraryEntry(
    {
      vehicleId: typeof body.vehicleId === "string" && body.vehicleId.trim() ? body.vehicleId.trim() : undefined,
      make: body.make.trim(),
      model: body.model.trim(),
      yearStart,
      yearEnd,
      trim: typeof body.trim === "string" && body.trim.trim() ? body.trim.trim() : null,
      bodyStyle,
      eligibleRideTypes: body.eligibleRideTypes
    },
    session.uid
  );

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: "Vehicle Library Entry Created",
    targetType: "vehicleLibrary",
    targetId: entry.vehicleId
  });

  return NextResponse.json({ entry }, { status: 201 });
}
