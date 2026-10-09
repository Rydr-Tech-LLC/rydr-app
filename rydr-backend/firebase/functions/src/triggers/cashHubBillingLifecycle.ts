import { onSchedule } from "firebase-functions/v2/scheduler";
import { db, FieldValue, Timestamp } from "../admin";

const FEE_CENTS = 499;
const GRACE_DAYS = 5;
const TIME_ZONE = "America/New_York";

function periodId(date: Date): string {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: TIME_ZONE, year: "numeric", month: "2-digit" }).formatToParts(date);
  const year = parts.find((part) => part.type === "year")?.value;
  const month = parts.find((part) => part.type === "month")?.value;
  return `${year}-${month}`;
}

function periodStart(date: Date): Date {
  const [year, month] = periodId(date).split("-").map(Number);
  // Midnight Eastern is never later than 05:00 UTC. The lifecycle runs daily,
  // so this stable representation avoids DST ambiguity in stored audit data.
  return new Date(Date.UTC(year, month - 1, 1, 5));
}

function acceptedDate(value: unknown): Date | null {
  if (value && typeof (value as { toDate?: () => Date }).toDate === "function") return (value as { toDate: () => Date }).toDate();
  return null;
}

export const maintainCashHubBilling = onSchedule(
  { schedule: "15 0 * * *", timeZone: TIME_ZONE, retryCount: 3 },
  async () => {
    const now = new Date();
    const currentPeriod = periodId(now);
    const configSnap = await db.collection("platformConfig").doc("cashRydrHub").get();
    const config = configSnap.exists ? configSnap.data() ?? {} : {};
    const launchAt = acceptedDate(config.cashHubBillingLaunchAt);
    if (config.termsAcceptanceEnabled !== true || config.cashHubBillingEnabled !== true || (launchAt && now < launchAt)) return;
    const feeCents = Math.max(0, Number(config.cashHubMonthlyFeeCents) || FEE_CENTS);
    const currentTermsVersion = String(config.cashHubTermsVersion ?? "legacy");
    const drivers = await db.collection("drivers").where("cashHubTermsAccepted", "==", true).get();

    for (const driverSnap of drivers.docs) {
      const driver = driverSnap.data();
      const accessStatus = String(driver.cashHubAccessStatus ?? "active").toLowerCase();
      const acceptedVersion = String(driver.cashHubTermsVersion ?? "");
      const currentTermsAccepted = acceptedVersion === currentTermsVersion || (!acceptedVersion && currentTermsVersion === "legacy");
      if (!currentTermsAccepted || driver.cashHubOptedOut === true || ["past_due", "review_required", "suspended", "revoked", "optedout", "opted_out"].includes(accessStatus)) continue;

      const billingRef = driverSnap.ref.collection("cashHubBilling").doc(currentPeriod);
      const billingSnap = await billingRef.get();
      if (billingSnap.exists) continue;
      const priorBilling = await driverSnap.ref.collection("cashHubBilling").limit(24).get();
      const hasOutstandingPeriod = priorBilling.docs.some((doc) => {
        const value = doc.data();
        return (Number(value.remainingCents) || 0) > 0 && ["fee_pending", "partially_collected", "past_due"].includes(String(value.status ?? ""));
      });
      if (hasOutstandingPeriod) continue;
      const acceptedAt = acceptedDate(driver.cashHubTermsAcceptedAt);
      const candidates = [periodStart(now)];
      if (acceptedAt && periodId(acceptedAt) === currentPeriod) candidates.push(acceptedAt);
      if (launchAt && periodId(launchAt) === currentPeriod) candidates.push(launchAt);
      const start = new Date(Math.max(...candidates.map((candidate) => candidate.getTime())));
      const graceEndsAt = new Date(start.getTime() + GRACE_DAYS * 24 * 60 * 60 * 1000);
      await billingRef.create({
        periodId: currentPeriod,
        feeCents,
        collectedCents: 0,
        remainingCents: feeCents,
        reservedCents: 0,
        status: "fee_pending",
        collectionSource: "dispatch_earnings",
        graceStartedAt: Timestamp.fromDate(start),
        graceEndsAt: Timestamp.fromDate(graceEndsAt),
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp()
      });
    }

    const expired = await db.collectionGroup("cashHubBilling")
      .where("graceEndsAt", "<=", Timestamp.fromDate(now))
      .limit(500)
      .get();
    for (const billingSnap of expired.docs) {
      const billing = billingSnap.data();
      if (!["fee_pending", "partially_collected"].includes(String(billing.status ?? ""))) continue;
      if ((Number(billing.remainingCents) || 0) <= 0) continue;
      const driverRef = billingSnap.ref.parent.parent;
      if (!driverRef) continue;
      await db.runTransaction(async (tx) => {
        const [freshBilling, driverSnap] = await Promise.all([tx.get(billingSnap.ref), tx.get(driverRef)]);
        if (!freshBilling.exists || !driverSnap.exists) return;
        const current = freshBilling.data() ?? {};
        if (!["fee_pending", "partially_collected"].includes(String(current.status ?? "")) || (Number(current.remainingCents) || 0) <= 0) return;
        tx.set(billingSnap.ref, { status: "past_due", pastDueAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
        tx.set(driverRef, { cashHubAccessStatus: "past_due", cashHubAccessSuspendedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      });
    }
  }
);
