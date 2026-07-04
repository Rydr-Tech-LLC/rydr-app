import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { db, FieldValue } from "../admin";

type DriverApprovalStatus = "pending" | "needs_attention" | "approved" | "rejected";

interface DriverDoc {
  firstName?: string;
  lastName?: string;
  email?: string;
  phoneNumber?: string;
  phoneE164?: string;
  dob?: unknown;
  address?: {
    street?: string;
    city?: string;
    state?: string;
    zip?: string;
  };
  license?: {
    number?: string;
    state?: string;
  };
  vehicle?: {
    make?: string;
    model?: string;
    year?: string | number;
    plate?: string;
  };
  selectedRideTypes?: string[];
  rideTypes?: string[];
  tierRates?: Record<string, unknown>;
  betaWaiverAccepted?: boolean;
  betaAgreementAccepted?: boolean;
  backgroundCheckAcknowledged?: boolean;
  identityVerified?: boolean;
  identityStatus?: string;
  stripeIdentityStatus?: string;
  stripeAccountId?: string;
  stripeConnectStatus?: string;
  stripeChargesEnabled?: boolean;
  stripePayoutsEnabled?: boolean;
  emailPasswordStepCompleted?: boolean;
  addressStepCompleted?: boolean;
  licenseStepCompleted?: boolean;
  vehicleStepCompleted?: boolean;
  backgroundCheckStepCompleted?: boolean;
  payoutsStepCompleted?: boolean;
  driverSignupCompleted?: boolean;
  driverApprovalStatus?: DriverApprovalStatus;
  accountStatus?: string;
  safetyReviewStatus?: string;
  safetyHold?: boolean;
}

function hasText(value: unknown): boolean {
  return typeof value === "string" && value.trim().length > 0;
}

function identityVerified(driver: DriverDoc): boolean {
  return (
    driver.identityVerified === true ||
    driver.identityStatus === "verified" ||
    (driver.stripeIdentityStatus === "verified" && driver.identityVerified !== false)
  );
}

function stripeConnectCompleted(driver: DriverDoc): boolean {
  if (hasText(driver.stripeAccountId) && driver.stripeChargesEnabled === true && driver.stripePayoutsEnabled === true) {
    return true;
  }
  return driver.stripeConnectStatus === "completed" && driver.stripeChargesEnabled !== false && driver.stripePayoutsEnabled !== false;
}

function hasRideSetup(driver: DriverDoc): boolean {
  const rideTypes = driver.selectedRideTypes ?? driver.rideTypes ?? [];
  return Array.isArray(rideTypes) && rideTypes.length > 0 && driver.tierRates != null;
}

function isSafetyBlocked(driver: DriverDoc): boolean {
  return driver.accountStatus === "suspended" || driver.safetyReviewStatus === "suspended" || driver.safetyHold === true;
}

function missingAutoApprovalRequirements(driver: DriverDoc): string[] {
  const missing: string[] = [];

  if (!driver.driverSignupCompleted) missing.push("Driver signup completed");
  if (!driver.emailPasswordStepCompleted) missing.push("Email/password step completed");
  if (!driver.addressStepCompleted) missing.push("Address step completed");
  if (!driver.licenseStepCompleted) missing.push("License step completed");
  if (!driver.vehicleStepCompleted) missing.push("Vehicle step completed");
  if (!driver.backgroundCheckStepCompleted) missing.push("Background check acknowledgement step completed");
  if (!driver.payoutsStepCompleted) missing.push("Payouts step completed");
  if (!driver.betaWaiverAccepted) missing.push("Beta waiver accepted");
  if (!driver.betaAgreementAccepted) missing.push("Beta background agreement accepted");
  if (!driver.backgroundCheckAcknowledged) missing.push("Background check acknowledged");
  if (!hasText(driver.firstName) || !hasText(driver.lastName) || !hasText(driver.email) || !hasText(driver.phoneNumber ?? driver.phoneE164) || !driver.dob) {
    missing.push("Profile complete");
  }
  if (!driver.address || !hasText(driver.address.street) || !hasText(driver.address.city) || !hasText(driver.address.state) || !hasText(driver.address.zip)) {
    missing.push("Address complete");
  }
  if (!driver.license || !hasText(driver.license.number) || !hasText(driver.license.state)) {
    missing.push("License complete");
  }
  if (!driver.vehicle || !hasText(driver.vehicle.make) || !hasText(driver.vehicle.model) || driver.vehicle.year == null || !hasText(driver.vehicle.plate)) {
    missing.push("Vehicle complete");
  }
  if (!hasRideSetup(driver)) missing.push("Ride types and rates configured");
  if (!identityVerified(driver)) missing.push("Stripe Identity verified");
  if (!stripeConnectCompleted(driver)) missing.push("Stripe Connect completed");

  return missing;
}

async function hasApprovedDriverBetaInvite(driver: DriverDoc): Promise<boolean> {
  const phone = driver.phoneE164 ?? driver.phoneNumber;
  if (!hasText(phone)) return false;
  const snap = await db.collection("betaInvites").doc("driver").collection("phones").doc(phone!.trim()).get();
  return snap.exists && snap.data()?.status === "approved";
}

export const onDriverAutoApprovalEligibility = onDocumentWritten("drivers/{uid}", async (event) => {
  const after = event.data?.after.data() as DriverDoc | undefined;
  if (!after) return;

  if (after.driverApprovalStatus === "approved" || after.driverApprovalStatus === "rejected") return;
  if (isSafetyBlocked(after)) return;

  const missing = missingAutoApprovalRequirements(after);
  if (missing.length > 0) return;
  if (!(await hasApprovedDriverBetaInvite(after))) return;

  await db.collection("drivers").doc(event.params.uid).set(
    {
      driverApprovalStatus: "approved",
      isApproved: true,
      canGoOnline: true,
      approvedAt: FieldValue.serverTimestamp(),
      approvedBy: "system:auto-approval",
      autoApprovedAt: FieldValue.serverTimestamp(),
      autoApprovedBy: "driver-signup-completion",
      autoApprovalReason: "Closed beta driver completed all required onboarding steps.",
      betaInviteVerifiedForAutoApproval: true,
      backgroundCheckStatus: "beta_deferred",
      updatedAt: FieldValue.serverTimestamp()
    },
    { merge: true }
  );
});
