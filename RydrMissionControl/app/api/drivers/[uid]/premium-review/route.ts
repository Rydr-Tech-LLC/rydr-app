import { NextRequest, NextResponse } from "next/server";
import { adminDb } from "@/lib/firebaseAdmin";
import { getAdminSession } from "@/lib/session";
import { writeAuditLog } from "@/lib/auditLog";
import { DOCUMENTS, vehicleKey, evaluatePremiumVehicle, availablePremiumRideTypes } from "../../../../../../rydr-backend/firebase/functions/src/services/premiumVehiclePolicy";

export async function POST(request: NextRequest, props: { params: Promise<{ uid: string }> }) {
  const session = await getAdminSession();
  if (!session) return NextResponse.json({ error: "Admin access required" }, { status: 401 });
  const { uid } = await props.params;
  const input = await request.json();
  if (!["sedan", "suv"].includes(input.bodyType)) return NextResponse.json({ error: "Choose Sedan or SUV" }, { status: 400 });
  const now = new Date();
  // Date-only expirations are inclusive through the end of the Georgia day.
  const expiry = (date: unknown, startOfDay = false) => {
    if (typeof date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
    const day = new Date(`${date}T12:00:00Z`);
    if (!Number.isFinite(day.getTime()) || day.toISOString().slice(0, 10) !== date) return null;
    const offset = new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", timeZoneName: "longOffset" }).formatToParts(startOfDay ? new Date(`${date}T05:00:00Z`) : day).find(part => part.type === "timeZoneName")?.value.replace("GMT", "") ?? "-05:00";
    const end = new Date(`${date}T${startOfDay ? "00:00:00" : "23:59:59"}${offset}`);
    return Number.isFinite(end.getTime()) ? end.toISOString() : null;
  };
  let result;
  try {
    result = await adminDb.runTransaction(async tx => {
      const ref = adminDb.collection("drivers").doc(uid);
      const [snap, executiveConfig] = await Promise.all([tx.get(ref), tx.get(adminDb.collection("platformConfig").doc("rydrExecutive"))]);
      if (!snap.exists) throw new Error("Driver not found");
      const driver = snap.data() ?? {};
      const key = vehicleKey(driver.vehicle);
      const previous = driver.premiumReview?.vehicleKey === key ? driver.premiumReview : {};
      const documents: Record<string, unknown> = {};
      for (const spec of [...DOCUMENTS, { key: "airportAuthorization", label: "ATL airport authorization", expires: true }]) {
        const source = input.documents?.[spec.key] ?? {};
        const reference = typeof source.reference === "string" ? source.reference.trim().slice(0, 500) : "";
        if (source.verified === true && (!reference || (spec.expires && !expiry(source.expiresAt)) || ("maxDays" in spec && spec.maxDays && !expiry(source.completedAt)))) throw new Error(`${spec.label}: evidence reference and expiration and report/inspection completion date are required`);
        documents[spec.key] = { status: source.verified === true ? "verified" : "missing", reference, expiresAt: expiry(source.expiresAt), completedAt: expiry(source.completedAt, true), verifiedAt: now.toISOString(), verifiedBy: session.uid };
      }
      const insurance = documents.commercialInsurance as Record<string, unknown>;
      for (const field of ["combinedLimit", "bodilyPerPerson", "bodilyPerAccident", "propertyDamage"]) {
        const value = Number(input.documents?.commercialInsurance?.[field] ?? 0);
        insurance[field] = Number.isFinite(value) && value >= 0 ? value : 0;
      }
      const review = {
        vehicleKey: key, bodyType: input.bodyType, seatCapacity: Number(input.seatCapacity) || 0, operatingState: "GA", reviewedBy: session.uid, reviewedAt: now.toISOString(),
        luxuryVehicleApproved: input.luxuryVehicleApproved === true,
        conditionApproved: input.conditionApproved === true,
        conditionReview: { status: input.conditionApproved === true ? "verified" : "missing", reference: String(input.conditionEvidence ?? "").trim().slice(0, 500), verifiedBy: session.uid, verifiedAt: now.toISOString(), expiresAt: expiry(input.conditionExpiresAt) },
        blackLeatherInteriorApproved: input.blackLeatherInteriorApproved === true,
        registrationPlate: String(driver.vehicle?.plate ?? ""),
        reviewedColor: String(driver.vehicle?.color ?? ""),
        temporaryLimoRegistration: input.temporaryLimoRegistration === true,
        carrierIdentityMatched: input.carrierIdentityMatched === true,
        insuranceCoversRydr: input.insuranceCoversRydr === true,
        prestineApprovedAt: input.approvePrestine === true ? previous.prestineApprovedAt ?? now.toISOString() : null,
        documents
      };
      const evaluation = evaluatePremiumVehicle({ ...driver, premiumReview: review }, now.getTime());
      if (input.approvePrestine === true && !evaluation.prestine.eligible) throw new Error(evaluation.prestine.issues.join("; "));
      const standard = (driver.qualifiedRideTypes ?? driver.supportedRideTypes ?? []).filter((value: string) => !/prestine|pristine|executive/i.test(value));
      const qualified = [...standard, ...availablePremiumRideTypes(evaluation, executiveConfig.data() ?? {})];
      tx.update(ref, { premiumReview: review, qualifiedRideTypes: qualified, supportedRideTypes: qualified, updatedAt: now });
      return evaluation;
    });
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : "Review failed" }, { status: 422 });
  }
  await writeAuditLog({ adminUid: session.uid, adminEmail: session.email ?? undefined, action: "Premium vehicle verification updated", targetType: "driver", targetId: uid, metadata: { policyVersion: result.policyVersion, rideTypes: result.rideTypes } });
  return NextResponse.json(result);
}
