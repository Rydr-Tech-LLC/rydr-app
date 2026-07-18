import { NextRequest, NextResponse } from "next/server";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { getAdminSession } from "@/lib/session";
import { adminAuth, adminDb } from "@/lib/firebaseAdmin";
import { writeAuditLog } from "@/lib/auditLog";

type ProfilePayload = {
  firstName?: unknown;
  lastName?: unknown;
  email?: unknown;
  phoneNumber?: unknown;
  dob?: unknown;
  address?: {
    street?: unknown;
    line2?: unknown;
    city?: unknown;
    state?: unknown;
    zip?: unknown;
  };
  license?: {
    number?: unknown;
    state?: unknown;
  };
  vehicle?: {
    year?: unknown;
    make?: unknown;
    model?: unknown;
    trim?: unknown;
    color?: unknown;
    plate?: unknown;
    vin?: unknown;
    class?: unknown;
  };
};

export async function PATCH(request: NextRequest, { params }: { params: { uid: string } }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const body = (await request.json().catch(() => null)) as ProfilePayload | null;
  if (!body) return NextResponse.json({ error: "Invalid profile payload." }, { status: 400 });

  const driverRef = adminDb.collection("drivers").doc(params.uid);
  const driverSnap = await driverRef.get();
  if (!driverSnap.exists) return NextResponse.json({ error: "Driver not found." }, { status: 404 });

  const firstName = cleanText(body.firstName, 80);
  const lastName = cleanText(body.lastName, 80);
  const legalName = [firstName, lastName].filter(Boolean).join(" ");
  const email = cleanEmail(body.email);
  const phoneNumber = cleanPhone(body.phoneNumber);
  const dob = cleanDate(body.dob);

  if (body.email !== undefined && !email) {
    return NextResponse.json({ error: "Enter a valid email address." }, { status: 400 });
  }
  if (body.phoneNumber !== undefined && phoneNumber && !phoneNumber.startsWith("+")) {
    return NextResponse.json({ error: "Phone number must use E.164 format, for example +14045551212." }, { status: 400 });
  }

  const update: Record<string, unknown> = {
    updatedAt: FieldValue.serverTimestamp(),
    profileLastEditedAt: FieldValue.serverTimestamp(),
    profileLastEditedBy: session.uid,
    profileLastEditedByEmail: session.email ?? ""
  };

  if (body.firstName !== undefined) {
    update.firstName = firstName;
    update.legalFirstName = firstName;
  }
  if (body.lastName !== undefined) {
    update.lastName = lastName;
    update.legalLastName = lastName;
  }
  if (body.firstName !== undefined || body.lastName !== undefined) {
    update.legalName = legalName;
    update.displayName = legalName || FieldValue.delete();
    update.nameDOBStepCompleted = Boolean(firstName && lastName);
  }
  if (body.email !== undefined) update.email = email;
  if (body.phoneNumber !== undefined) {
    update.phoneNumber = phoneNumber;
    update.phoneE164 = phoneNumber;
  }
  if (body.dob !== undefined) update.dob = dob ? Timestamp.fromDate(dob) : FieldValue.delete();

  if (body.address) {
    update.address = {
      street: cleanText(body.address.street, 180),
      line2: cleanText(body.address.line2, 120),
      city: cleanText(body.address.city, 100),
      state: cleanText(body.address.state, 30).toUpperCase(),
      zip: cleanText(body.address.zip, 20)
    };
  }

  if (body.license) {
    update.license = {
      ...(driverSnap.data()?.license ?? {}),
      number: cleanText(body.license.number, 80),
      state: cleanText(body.license.state, 30).toUpperCase()
    };
  }

  if (body.vehicle) {
    update.vehicle = {
      ...(driverSnap.data()?.vehicle ?? {}),
      year: cleanText(body.vehicle.year, 10),
      make: cleanText(body.vehicle.make, 80),
      model: cleanText(body.vehicle.model, 80),
      trim: cleanText(body.vehicle.trim, 80),
      color: cleanText(body.vehicle.color, 60),
      plate: cleanText(body.vehicle.plate, 30).toUpperCase(),
      vin: cleanText(body.vehicle.vin, 40).toUpperCase(),
      class: cleanText(body.vehicle.class, 60)
    };
  }

  const authUpdate: Parameters<typeof adminAuth.updateUser>[1] = {};
  if (body.email !== undefined && email) {
    authUpdate.email = email;
    authUpdate.emailVerified = false;
  }
  if ((body.firstName !== undefined || body.lastName !== undefined) && legalName) {
    authUpdate.displayName = legalName;
  }
  if (body.phoneNumber !== undefined && phoneNumber) {
    authUpdate.phoneNumber = phoneNumber;
  }
  if (Object.keys(authUpdate).length > 0) {
    await adminAuth.updateUser(params.uid, authUpdate);
  }

  await driverRef.set(update, { merge: true });

  await writeAuditLog({
    adminUid: session.uid,
    adminEmail: session.email ?? undefined,
    action: "Driver Profile Updated",
    targetType: "driver",
    targetId: params.uid,
    metadata: {
      fields: Object.keys(update).filter((key) => !key.startsWith("profileLast") && key !== "updatedAt")
    }
  });

  return NextResponse.json({ ok: true });
}

function cleanText(value: unknown, maxLength: number): string {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

function cleanEmail(value: unknown): string {
  const email = cleanText(value, 180).toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : "";
}

function cleanPhone(value: unknown): string {
  return cleanText(value, 30).replace(/[^\d+]/g, "");
}

function cleanDate(value: unknown): Date | null {
  if (typeof value !== "string" || !value.trim()) return null;
  const date = new Date(`${value}T00:00:00.000Z`);
  return Number.isNaN(date.getTime()) ? null : date;
}
