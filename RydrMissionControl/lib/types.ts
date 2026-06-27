// Shared types matching the real Firestore schema already written by
// RydrDriver / RydrPlayground (see DriverSignupCoordinator.swift,
// DriverDashboardVM.swift). Mission Control reads this schema as-is and
// only ever writes the backend-owned fields (driverApprovalStatus,
// approvedAt, approvedBy, rejectionReason, etc.) via the Admin SDK.

export type DriverApprovalStatus =
  | "pending"
  | "needs_attention"
  | "approved"
  | "rejected";

export type BackgroundCheckStatus = "beta_deferred" | "pending" | "passed" | "failed";

export interface DriverAddress {
  street?: string;
  line2?: string;
  city?: string;
  state?: string;
  zip?: string;
}

export interface DriverLicense {
  number?: string;
  state?: string;
  // Not yet populated by the app today (documents are picked but never
  // uploaded — see beta readiness audit, P0 #10). Field is here so the
  // review screen lights up the moment that gets wired up.
  imageUrl?: string;
}

export interface DriverVehicle {
  make?: string;
  model?: string;
  year?: string | number;
  fuelType?: string;
  class?: string;
  plate?: string;
  vin?: string;
  registrationImageUrl?: string;
  insuranceImageUrl?: string;
}

export interface DriverRecord {
  uid: string;
  firstName?: string;
  lastName?: string;
  email?: string;
  phoneNumber?: string;
  phoneE164?: string;
  dob?: { toDate?: () => Date } | null;
  address?: DriverAddress;
  license?: DriverLicense;
  vehicle?: DriverVehicle;
  qualifiedRideTypes?: string[];
  selectedRideTypes?: string[];
  createdAt?: { toDate?: () => Date } | null;
  updatedAt?: { toDate?: () => Date } | null;

  // Backend-owned / admin-managed fields:
  driverApprovalStatus?: DriverApprovalStatus;
  approvedAt?: { toDate?: () => Date } | null;
  approvedBy?: string;
  rejectionReason?: string;
  backgroundCheckStatus?: BackgroundCheckStatus;
  backgroundCheckAcknowledgedAt?: { toDate?: () => Date } | null;
  betaAgreementAccepted?: boolean;
  betaAgreementAcceptedAt?: { toDate?: () => Date } | null;
  stripeAccountId?: string;
  stripeConnectStatus?: "not_started" | "pending" | "completed";
  stripeIdentityStatus?: "not_started" | "pending" | "verified" | "failed";
  isApproved?: boolean;
}

export interface DriverApprovalRequest {
  uid: string;
  requestType: "backgroundCheck" | "debugApprovalBypass" | "identityReview";
  source?: string;
  requested?: boolean;
  updatedAt?: { toDate?: () => Date } | null;
}

export interface RiderRecord {
  uid: string;
  firstName?: string;
  lastName?: string;
  email?: string;
  phoneNumber?: string;
  phoneE164?: string;
  rideCount?: number;
  verifiedRider?: boolean;
  accountStatus?: "active" | "suspended" | "removed";
  createdAt?: { toDate?: () => Date } | null;
}

export type SafetyReportStatus = "open" | "dismissed" | "escalated";

export interface SafetyReport {
  id: string;
  reportType?: string;
  rideId?: string;
  driverId?: string;
  riderId?: string;
  driverName?: string;
  riderName?: string;
  description?: string;
  status: SafetyReportStatus;
  createdAt?: { toDate?: () => Date } | null;
}

export interface AuditLogEntry {
  adminUid: string;
  adminEmail?: string;
  action: string;
  targetType: "driver" | "rider" | "report";
  targetId: string;
  reason?: string;
  createdAt: unknown;
}

export const DRIVER_APPROVAL_REQUIREMENTS: { key: string; label: string }[] = [
  { key: "profileComplete", label: "Profile complete" },
  { key: "licenseUploaded", label: "Driver license uploaded" },
  { key: "insuranceUploaded", label: "Insurance uploaded" },
  { key: "registrationUploaded", label: "Registration uploaded" },
  { key: "stripeIdentityVerified", label: "Stripe Identity verified" },
  { key: "stripeConnectCompleted", label: "Stripe Connect completed" },
  { key: "backgroundCheckDeferred", label: "Background check (beta deferred)" },
  { key: "agreementAccepted", label: "Driver agreement accepted" }
];

export function evaluateDriverRequirements(driver: DriverRecord) {
  const checks: Record<string, boolean> = {
    profileComplete: Boolean(driver.firstName && driver.lastName && driver.email && driver.phoneNumber),
    licenseUploaded: Boolean(driver.license?.imageUrl),
    insuranceUploaded: Boolean(driver.vehicle?.insuranceImageUrl),
    registrationUploaded: Boolean(driver.vehicle?.registrationImageUrl),
    stripeIdentityVerified: driver.stripeIdentityStatus === "verified",
    stripeConnectCompleted: driver.stripeConnectStatus === "completed" || Boolean(driver.stripeAccountId),
    backgroundCheckDeferred: driver.backgroundCheckStatus === "beta_deferred" || driver.backgroundCheckStatus === "passed",
    agreementAccepted: Boolean(driver.betaAgreementAccepted)
  };
  const missing = DRIVER_APPROVAL_REQUIREMENTS.filter((r) => !checks[r.key]).map((r) => r.label);
  return { checks, missing, canApprove: missing.length === 0 };
}
