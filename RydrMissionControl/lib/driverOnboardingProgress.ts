import { driverConnectStatus, driverDocumentUrl, driverIdentityStatus, type DriverRecord } from "@/lib/types";
import { toDateSafe } from "@/lib/format";

export interface DriverOnboardingStepView {
  index: number;
  key: string;
  label: string;
  complete: boolean;
  active: boolean;
}

export interface DriverOnboardingProgressView {
  currentStep: string;
  currentIndex: number | null;
  totalSteps: number;
  lastSeen: string | null;
  completedCount: number;
  steps: DriverOnboardingStepView[];
}

const ONBOARDING_STEPS: Array<{
  index: number;
  key: string;
  label: string;
  complete: (driver: DriverRecord) => boolean;
}> = [
  {
    index: 1,
    key: "phone_verification",
    label: "Phone Verification",
    complete: (driver) => Boolean(driver.phoneVerificationStepCompleted || driver.phoneE164 || driver.phoneNumber)
  },
  {
    index: 2,
    key: "beta_waiver",
    label: "Beta Waiver",
    complete: (driver) => Boolean(driver.betaWaiverAccepted)
  },
  {
    index: 3,
    key: "legal_name_dob",
    label: "Legal Name & DOB",
    complete: (driver) => Boolean(driver.nameDOBStepCompleted || ((driver.firstName || driver.legalFirstName) && (driver.lastName || driver.legalLastName) && driver.dob))
  },
  {
    index: 4,
    key: "login_credentials",
    label: "Login Credentials",
    complete: (driver) => Boolean(driver.emailPasswordStepCompleted || driver.email)
  },
  {
    index: 5,
    key: "address",
    label: "Address",
    complete: (driver) => Boolean(driver.addressStepCompleted || (driver.address?.street && driver.address?.city && driver.address?.state && driver.address?.zip))
  },
  {
    index: 6,
    key: "driver_license",
    label: "Driver License",
    complete: (driver) => Boolean(driver.licenseStepCompleted || driverDocumentUrl(driver, "license"))
  },
  {
    index: 7,
    key: "vehicle_documents",
    label: "Vehicle & Documents",
    complete: (driver) => Boolean(driver.vehicleStepCompleted || (driver.vehicle?.vin && driverDocumentUrl(driver, "insurance") && driverDocumentUrl(driver, "registration")))
  },
  {
    index: 8,
    key: "identity_verification",
    label: "Identity Verification",
    complete: (driver) => Boolean(driver.identityVerificationStepCompleted || driver.identityVerified || driverIdentityStatus(driver) === "verified")
  },
  {
    index: 9,
    key: "background_check",
    label: "Background Check",
    complete: (driver) => Boolean(driver.backgroundCheckStepCompleted || driver.backgroundCheckAcknowledged)
  },
  {
    index: 10,
    key: "payouts",
    label: "Payouts",
    complete: (driver) => Boolean(driver.payoutsStepCompleted || driverConnectStatus(driver) === "completed")
  },
  {
    index: 11,
    key: "complete",
    label: "Signup Complete",
    complete: (driver) => Boolean(driver.driverSignupCompleted)
  }
];

export function buildDriverOnboardingProgress(driver: DriverRecord): DriverOnboardingProgressView {
  const currentStep = driver.driverOnboardingCurrentStepLabel ?? onboardingStepLabel(driver.driverOnboardingCurrentStep);
  const currentIndex = typeof driver.driverOnboardingCurrentStepIndex === "number" ? driver.driverOnboardingCurrentStepIndex : null;
  const totalSteps = typeof driver.driverOnboardingTotalSteps === "number" ? driver.driverOnboardingTotalSteps : ONBOARDING_STEPS.length;
  const lastSeen = toDateSafe(driver.driverOnboardingLastSeenAt);
  const completedCount = ONBOARDING_STEPS.filter((step) => step.complete(driver)).length;
  return {
    currentStep: driver.driverSignupCompleted ? "Complete" : currentStep || "Not reported yet",
    currentIndex,
    totalSteps,
    lastSeen: lastSeen ? lastSeen.toISOString() : null,
    completedCount,
    steps: ONBOARDING_STEPS.map((step) => {
      const complete = step.complete(driver);
      return {
        index: step.index,
        key: step.key,
        label: step.label,
        complete,
        active: !driver.driverSignupCompleted && driver.driverOnboardingCurrentStep === step.key
      };
    })
  };
}

function onboardingStepLabel(key?: string): string {
  return ONBOARDING_STEPS.find((step) => step.key === key)?.label ?? "";
}
