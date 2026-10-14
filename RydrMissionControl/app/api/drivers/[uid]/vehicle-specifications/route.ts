import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import { FieldValue } from "firebase-admin/firestore";
import { seatCount, exactLibraryEntry, resolveSpecifications } from "../../../../../../rydr-backend/firebase/functions/src/services/vehicleSpecificationPolicy";
export async function POST(_request: NextRequest, props: { params: Promise<{ uid: string }> }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });
  const { uid } = await props.params;
  const ref = adminDb.collection("drivers").doc(uid);
  const initial = await ref.get(); const vehicle = initial.data()?.vehicle;
  if (!vehicle?.vin || !/^[A-HJ-NPR-Z0-9]{17}$/i.test(vehicle.vin)) return NextResponse.json({ error: "A valid VIN is required. Review manufacturer evidence for manually entered vehicles." }, { status: 422 });
  try {
    const response = await fetch(`https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValuesExtended/${encodeURIComponent(vehicle.vin)}?format=json`, { signal: AbortSignal.timeout(20000), cache: "no-store" });
    if (!response.ok) throw new Error("VIN specifications are unavailable. Try again later.");
    const raw = (await response.json()).Results?.[0];
    const clean=(v:unknown)=>String(v??'').trim().toLowerCase();
    if (!raw || clean(raw.Make)!==clean(vehicle.make) || clean(raw.Model)!==clean(vehicle.model) || Number(raw.ModelYear)!==Number(vehicle.year)) throw new Error("VIN details conflict with the current vehicle. Review its make/model/year first.");
    const library = await adminDb.collection("vehicleLibrary").limit(1000).get();
    const updated = { ...vehicle, vinReportedSeatCapacity: seatCount(raw.Seats), vinReportedSeatRows: seatCount(raw.SeatRows) };
    const specifications = resolveSpecifications(updated, exactLibraryEntry(library.docs.map(doc=>doc.data()), updated));
    await adminDb.runTransaction(async tx=>{
      const current = await tx.get(ref);
      if (current.updateTime?.toMillis() !== initial.updateTime?.toMillis()) throw new Error("Driver profile changed. Refresh and try again.");
      tx.update(ref, { "vehicle.vinReportedSeatCapacity": updated.vinReportedSeatCapacity, "vehicle.vinReportedSeatRows": updated.vinReportedSeatRows, "vehicle.specifications": specifications, vehicleSpecificationsRefreshedBy: session.uid, vehicleSpecificationsRefreshedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    });
    return NextResponse.json(specifications);
  } catch (error) { return NextResponse.json({ error: error instanceof Error ? error.message : "Specification refresh failed." }, { status: 422 }); }
}
