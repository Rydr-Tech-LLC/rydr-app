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

  // Vehicle Library System (VIN decode + managed image library) — written
  // by the `submitVehicleVin` Cloud Function when a driver decodes their
  // VIN and picks a color. See Rydr_Firebase/functions and
  // VEHICLE_LIBRARY_README.md.
  trim?: string | null;
  bodyStyle?: string | null;
  driveType?: string | null;
  color?: string | null;
  imagePath?: string | null;
  imageUrl?: string | null;
  imageMatchTier?: number | null;
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

  // Vehicle Library System
  vinDecodeStatus?: "pending" | "decoded" | "failed";
  vehicleImageStatus?: "matched" | "fallback" | "missing";
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
  targetType: "driver" | "rider" | "report" | "vehicleLibrary" | "accountDeletion" | "payment" | "supportTicket";
  targetId: string;
  reason?: string;
  createdAt: unknown;
}

// --- Account deletion (Part 12 of the beta hardening sprint) -------------
// Written by riders/drivers directly (rules: `accountDeletionRequests/{uid}`)
// or by rydr-backend's /driver/account-deletion-requests route — both key
// the document by uid so there is exactly one request per account.
// Mission Control's admin-only process route is the only thing that ever
// transitions `status` to "processing"/"completed"/"rejected".
export type AccountDeletionStatus = "requested" | "processing" | "completed" | "rejected";

export interface AccountDeletionRequestRecord {
  id: string;
  uid: string;
  userId?: string;
  role: "rider" | "driver";
  email?: string | null;
  reason?: string | null;
  status: AccountDeletionStatus;
  source?: string;
  processedAt?: { toDate?: () => Date } | null;
  processedBy?: string;
  rejectionReason?: string;
  requestedAt?: { toDate?: () => Date } | null;
  createdAt?: { toDate?: () => Date } | null;
  updatedAt?: { toDate?: () => Date } | null;
}

// --- Ride payment status (Part 2/5 — written by stripe-backend) ----------
export type RidePaymentStatus = "pending" | "processing" | "succeeded" | "failed" | "refunded";

export interface RideRecord {
  id: string;
  riderId?: string;
  driverId?: string;
  riderName?: string;
  driverName?: string;
  pickup?: string;
  dropoff?: string;
  status?: string;
  paymentStatus?: RidePaymentStatus;
  failureReason?: string | null;
  failureCode?: string | null;
  retryCount?: number;
  lastPaymentAttempt?: { toDate?: () => Date } | null;
  updatedAt?: { toDate?: () => Date } | null;
}

// --- Support tickets (Part 9 "support reply" notification trigger) -------
export interface SupportTicketRecord {
  id: string;
  userId?: string;
  userRole?: "rider" | "driver";
  subject?: string;
  category?: string;
  status?: "open" | "closed";
  createdAt?: { toDate?: () => Date } | null;
  updatedAt?: { toDate?: () => Date } | null;
}

export interface SupportMessageRecord {
  id: string;
  senderId?: string;
  senderRole?: "rider" | "driver" | "admin";
  text?: string;
  createdAt?: { toDate?: () => Date } | null;
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
