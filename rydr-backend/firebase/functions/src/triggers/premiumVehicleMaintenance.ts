import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { db } from "../admin";
import { evaluatePremiumVehicle, availablePremiumRideTypes } from "../services/premiumVehiclePolicy";

// Refresh driver-app eligibility when the calendar rolls or documents expire.
// Dispatch also evaluates dates at request time and does not rely on this job.
async function refreshPremiumQualifications() {
  const executiveConfig = await db.collection("platformConfig").doc("rydrExecutive").get();
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  while (true) {
    let query = db.collection("drivers").orderBy("__name__").limit(200);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;
    for (const doc of page.docs) {
      const driver = doc.data();
      const evaluation = evaluatePremiumVehicle(driver);
      const stored = driver.qualifiedRideTypes ?? driver.supportedRideTypes ?? [];
      const standard = stored.filter((value: string) => !/prestine|pristine|executive/i.test(value));
      const qualified = [...standard, ...availablePremiumRideTypes(evaluation, executiveConfig.data() ?? {})];
      if (JSON.stringify(stored) !== JSON.stringify(qualified)) {
        await doc.ref.update({ qualifiedRideTypes: qualified, supportedRideTypes: qualified, selectedRideTypes: (driver.selectedRideTypes ?? []).filter((value: string) => qualified.includes(value)) });
      }
    }
    cursor = page.docs[page.docs.length - 1];
  }
}

export const maintainPremiumVehicleEligibility = onSchedule({ schedule: "every day 00:15", timeZone: "America/New_York" }, refreshPremiumQualifications);
export const onExecutiveAvailabilityChanged = onDocumentWritten("platformConfig/rydrExecutive", refreshPremiumQualifications);
