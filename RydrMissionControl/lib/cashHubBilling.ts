import { adminDb } from "./firebaseAdmin";
import type { DriverRecord } from "./types";

export type CashHubBillingStatus = "active" | "feePending" | "partiallyCollected" | "collected" | "unknown";

export interface CashHubBillingRecord {
  id: string;
  status: CashHubBillingStatus;
  feeCents: number;
  collectedCents: number;
  remainingCents: number;
  lastCollectionRideId?: string;
  updatedAt?: { toDate?: () => Date } | null;
}

export interface CashHubGateConfig {
  termsAcceptanceEnabled: boolean;
  cashHubTermsVersion: string | null;
}

export function currentCashHubBillingPeriod(date = new Date()) {
  const id = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
  const label = date.toLocaleString("en-US", { month: "long" });
  return { id, label };
}

export async function getCurrentCashHubBilling(driverUid: string): Promise<CashHubBillingRecord | null> {
  const period = currentCashHubBillingPeriod();
  const snap = await adminDb.collection("drivers").doc(driverUid).collection("cashHubBilling").doc(period.id).get();
  if (!snap.exists) return null;

  const data = snap.data() ?? {};
  return {
    id: snap.id,
    status: normalizeCashHubBillingStatus(data.status),
    feeCents: numberValue(data.feeCents) ?? 499,
    collectedCents: numberValue(data.collectedCents) ?? 0,
    remainingCents: numberValue(data.remainingCents) ?? Math.max(0, (numberValue(data.feeCents) ?? 499) - (numberValue(data.collectedCents) ?? 0)),
    lastCollectionRideId: typeof data.lastCollectionRideId === "string" ? data.lastCollectionRideId : undefined,
    updatedAt: data.updatedAt ?? null
  };
}

export function cashHubAccessActive(driver: DriverRecord, config?: CashHubGateConfig | null) {
  const acceptedCurrentTerms = !config?.cashHubTermsVersion ||
    driver.cashHubTermsVersion === config.cashHubTermsVersion ||
    (!driver.cashHubTermsVersion && config.cashHubTermsVersion === "legacy");
  return driver.cashHubTermsAccepted === true &&
    driver.cashHubOptedOut !== true &&
    acceptedCurrentTerms &&
    config?.termsAcceptanceEnabled !== false;
}

export function cashHubBillingDisplay(driver: DriverRecord, billing: CashHubBillingRecord | null, config?: CashHubGateConfig | null) {
  const period = currentCashHubBillingPeriod();
  if (!cashHubAccessActive(driver, config)) {
    const staleTerms = config?.cashHubTermsVersion && driver.cashHubTermsVersion !== config.cashHubTermsVersion;
    return {
      status: "inactive",
      label: driver.cashHubOptedOut ? "Opted out" : "Inactive",
      detail: driver.cashHubOptedOut
        ? "Driver opted out of CashRydr Hub."
        : staleTerms
          ? "Driver must accept the current CashRydr Hub terms."
          : "Driver has not accepted CashRydr Hub terms."
    };
  }

  if (!billing) {
    return {
      status: "active",
      label: "Active",
      detail: `No ${period.label} billing record yet.`
    };
  }

  switch (billing.status) {
    case "feePending":
      return {
        status: "feePending",
        label: "Fee pending",
        detail: `${formatCents(billing.feeCents)} pending for ${period.label}.`
      };
    case "partiallyCollected":
      return {
        status: "partiallyCollected",
        label: "Partially collected",
        detail: `${formatCents(billing.collectedCents)} collected, ${formatCents(billing.remainingCents)} remaining.`
      };
    case "collected":
      return {
        status: "collected",
        label: `Collected for ${period.label}`,
        detail: `${formatCents(billing.collectedCents || billing.feeCents)} collected.`
      };
    case "active":
      return {
        status: "active",
        label: "Active",
        detail: `CashRydr Hub active for ${period.label}.`
      };
    default:
      return {
        status: "unknown",
        label: "Unknown",
        detail: "Billing status is not available."
      };
  }
}

export function formatCents(cents: number) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(cents / 100);
}

function normalizeCashHubBillingStatus(value: unknown): CashHubBillingStatus {
  if (value === "active") return "active";
  if (value === "feePending" || value === "fee_pending") return "feePending";
  if (value === "partiallyCollected" || value === "partially_collected") return "partiallyCollected";
  if (value === "collected") return "collected";
  return "unknown";
}

function numberValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return Math.round(value);
  if (typeof value === "string" && /^-?\d+$/.test(value.trim())) return Number.parseInt(value, 10);
  return null;
}
