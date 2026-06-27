import { NextRequest, NextResponse } from "next/server";
import { getAdminSession } from "@/lib/session";
import { adminDb } from "@/lib/firebaseAdmin";
import type { DriverRecord, RiderRecord } from "@/lib/types";

// Lightweight in-memory search: pulls a bounded page of drivers/riders and
// filters server-side. Fine for beta-scale data; swap for a real search
// index (Algolia/Typesense) once collections grow past a few thousand docs.
export async function GET(request: NextRequest) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const q = (request.nextUrl.searchParams.get("q") ?? "").trim().toLowerCase();
  if (!q) return NextResponse.json({ drivers: [], riders: [] });

  const [driverSnap, riderSnap] = await Promise.all([
    adminDb.collection("drivers").limit(500).get(),
    adminDb.collection("riders").limit(500).get()
  ]);

  function matches(fields: (string | undefined)[]) {
    return fields.some((f) => f && f.toLowerCase().includes(q));
  }

  const drivers = driverSnap.docs
    .map((doc) => ({ ...(doc.data() as DriverRecord), uid: doc.id }))
    .filter((d) =>
      matches([
        d.firstName,
        d.lastName,
        d.email,
        d.phoneNumber,
        d.phoneE164,
        d.uid,
        d.license?.number,
        d.vehicle?.vin,
        d.vehicle?.plate
      ])
    )
    .slice(0, 25)
    .map((d) => ({ uid: d.uid, name: `${d.firstName ?? ""} ${d.lastName ?? ""}`.trim(), email: d.email }));

  const riders = riderSnap.docs
    .map((doc) => ({ ...(doc.data() as RiderRecord), uid: doc.id }))
    .filter((r) => matches([r.firstName, r.lastName, r.email, r.phoneNumber, r.phoneE164, r.uid]))
    .slice(0, 25)
    .map((r) => ({ uid: r.uid, name: `${r.firstName ?? ""} ${r.lastName ?? ""}`.trim(), email: r.email }));

  return NextResponse.json({ drivers, riders });
}
