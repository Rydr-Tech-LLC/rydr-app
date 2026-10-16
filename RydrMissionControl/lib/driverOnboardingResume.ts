import "server-only";
import { randomUUID } from "node:crypto";
import { FieldValue } from "firebase-admin/firestore";
import { getWorkspaceDb, getWorkspaceAuth } from "./firebaseAdmin";
const { onboardingState } = require("../../rydr-backend/firebase/functions/src/services/onboardingProgress") as {
  onboardingState: (role: string, profile: Record<string, unknown>, token: Record<string, unknown>) => { nextStep: string | null };
};
const labels: Record<string, string> = { phone: "Phone Verification", betaWaiver: "Beta Waiver", nameDOB: "Legal Name & DOB", emailPassword: "Login Credentials", address: "Address", license: "Driver License", vehicle: "Vehicle & Documents", identity: "Identity Verification", backgroundCheck: "Background Check", payouts: "Payouts" };
export async function driverResumeTarget(uid: string, profile: Record<string, unknown>) {
  const user = await (await getWorkspaceAuth()).getUser(uid);
  const { nextStep } = onboardingState("driver", { ...profile, driverSignupCompleted: false }, { phone_number: user.phoneNumber, email: user.email });
  return { key: nextStep!, label: labels[nextStep!] ?? "Onboarding" };
}
export async function resumeDriverOnboarding(uid: string, admin: { uid: string; email?: string | null }) {
  const db = await getWorkspaceDb();
  const ref = db.collection("drivers").doc(uid);
  const requestID = randomUUID();
  return db.runTransaction(async transaction => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) throw Object.assign(new Error("Driver not found."), { statusCode: 404 });
    const driver = snapshot.data()!;
    const rides = await transaction.get(db.collection("rides").where("driverId", "==", uid));
    const active = new Set(["pending", "accepted", "enRouteToPickup", "navigatingToPickup", "arrivedAtPickup", "inProgress", "navigatingToStop", "arrivedAtStop", "navigatingToDropoff"]);
    if (driver.hasActiveRide === true || rides.docs.some(ride => active.has(ride.data().status))) {
      throw Object.assign(new Error("Finish or resolve the driver's active ride before resuming onboarding."), { statusCode: 409 });
    }
    const target = await driverResumeTarget(uid, driver);
    const now = FieldValue.serverTimestamp();
    const keys: Record<string, string> = { phone: "phone_verification", betaWaiver: "beta_waiver", nameDOB: "legal_name_dob", emailPassword: "login_credentials", address: "address", license: "driver_license", vehicle: "vehicle_documents", identity: "identity_verification", backgroundCheck: "background_check", payouts: "payouts" };
    transaction.set(ref, { driverOnboardingCurrentStep: keys[target.key], driverOnboardingCurrentStepLabel: target.label, driverOnboardingCurrentStepIndex: Object.keys(keys).indexOf(target.key) + 1, driverSignupCompleted: false, canGoOnline: false, isOnline: false, online: false,
      onboardingResumeRequestID: requestID, onboardingResumeRequestedAt: now, onboardingResumeRequestedBy: admin.uid, updatedAt: now }, { merge: true });
    for (const collection of ["driver_status", "publicDriverProfiles", "cashHubDriverProfiles"]) {
      transaction.set(db.collection(collection).doc(uid), { isOnline: false, online: false, availabilityStatus: "offline", updatedAt: now }, { merge: true });
    }
    transaction.set(db.collection("audits").doc(), { adminUid: admin.uid, adminEmail: admin.email ?? null, action: "Driver Onboarding Resumed", targetType: "driver", targetId: uid, reason: `Resume at ${target.label}`, requestID, createdAt: now });
    return target;
  });
}
