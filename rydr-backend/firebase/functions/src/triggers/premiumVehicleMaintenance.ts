import { refreshDriverVehicleEligibility } from "../services/refreshDriverVehicleEligibility";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { db } from "../admin";

// Refresh driver-app eligibility when the calendar rolls or documents expire.
// Dispatch also evaluates dates at request time and does not rely on this job.
async function refreshPremiumQualifications() {
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  while (true) {
    let query = db.collection("drivers").orderBy("__name__").limit(200);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;
    for (const doc of page.docs) {
      await refreshDriverVehicleEligibility(doc.ref);
    }
    cursor = page.docs[page.docs.length - 1];
  }
}

export const maintainPremiumVehicleEligibility = onSchedule({ schedule: "every day 00:15", timeZone: "America/New_York" }, refreshPremiumQualifications);
export const onExecutiveAvailabilityChanged = onDocumentWritten("platformConfig/rydrExecutive", refreshPremiumQualifications);

// Library approval, body-style changes and revocations propagate without a new app build.
export const onVehicleLibraryEligibilityChanged = onDocumentWritten("vehicleLibrary/{vehicleId}", refreshPremiumQualifications);
