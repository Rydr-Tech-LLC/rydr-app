import "server-only";
import {
  normalizeMechanics,
  validateOffer,
  localTimeToISO,
} from "../../rydr-backend/services/stripe/promotionPolicy";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { getWorkspaceDb } from "./firebaseAdmin";

export type PromotionStatus =
  | "draft"
  | "scheduled"
  | "active"
  | "paused"
  | "ended"
  | "archived";
export type PromotionType =
  | "rider_fare_discount"
  | "rider_milestone_reward"
  | "driver_per_ride_bonus"
  | "driver_milestone_reward";
export type PromotionAudience = "riders" | "drivers";
export type PromotionAppliesTo = "normalRydr" | "cashHub" | "both";
export type PromotionDiscountKind = "percent" | "fixed" | "free_ride";
export type PromotionRewardKind =
  | "cash_bonus"
  | "rydr_bank_credit"
  | "free_ride"
  | "fixed";

export interface PromotionRecord {
  schemaVersion?: number;
  applicationMode?: "automatic" | "code";
  promoCode?: string | null;
  audienceRule?: "all" | "new" | "beta" | "specific";
  audienceUserIds?: string[];
  limitKind?: "amount" | "distance";
  maxDistanceMiles?: number | null;
  rewardExpiresAfterDays?: number;
  payExcessFare?: boolean;

  id: string;
  title: string;
  description?: string | null;
  status: PromotionStatus;
  type: PromotionType;
  audience: PromotionAudience;
  appliesTo: PromotionAppliesTo;
  startsAt: Timestamp;
  endsAt: Timestamp;
  timezone: string;
  markets: string[];
  rideTypes: string[];
  discountKind?: PromotionDiscountKind;
  discountPercent?: number | null;
  discountCents?: number | null;
  maxDiscountCents?: number | null;
  bonusCents?: number | null;
  milestoneRideCount?: number | null;
  rewardKind?: PromotionRewardKind | null;
  rewardQuantity?: number | null;
  rewardCents?: number | null;
  maxRedemptions?: number | null;
  perUserLimit?: number | null;
  betaOnly?: boolean;
  reusableSourcePromotionId?: string | null;
  createdAt?: Timestamp | null;
  createdBy?: string | null;
  createdByEmail?: string | null;
  updatedAt?: Timestamp | null;
  updatedBy?: string | null;
  updatedByEmail?: string | null;
  archivedAt?: Timestamp | null;
}

export interface PromotionInput {
  schemaVersion?: unknown;
  applicationMode?: unknown;
  promoCode?: unknown;
  audienceRule?: unknown;
  audienceUserIds?: unknown;
  limitKind?: unknown;
  maxDistanceMiles?: unknown;
  rewardExpiresAfterDays?: unknown;
  payExcessFare?: unknown;
  startsLocal?: unknown;
  endsLocal?: unknown;
  startNow?: unknown;

  title?: unknown;
  description?: unknown;
  status?: unknown;
  type?: unknown;
  appliesTo?: unknown;
  startsAt?: unknown;
  endsAt?: unknown;
  timezone?: unknown;
  markets?: unknown;
  rideTypes?: unknown;
  discountKind?: unknown;
  discountPercent?: unknown;
  discountCents?: unknown;
  maxDiscountCents?: unknown;
  bonusCents?: unknown;
  milestoneRideCount?: unknown;
  rewardKind?: unknown;
  rewardQuantity?: unknown;
  rewardCents?: unknown;
  maxRedemptions?: unknown;
  perUserLimit?: unknown;
  betaOnly?: unknown;
}

export const PROMOTION_TYPES: PromotionType[] = [
  "rider_fare_discount",
  "rider_milestone_reward",
  "driver_per_ride_bonus",
  "driver_milestone_reward",
];
export const PROMOTION_STATUSES: PromotionStatus[] = [
  "draft",
  "scheduled",
  "active",
  "paused",
  "ended",
  "archived",
];
export const PROMOTION_APPLIES_TO: PromotionAppliesTo[] = [
  "normalRydr",
  "cashHub",
  "both",
];
export const PROMOTION_DISCOUNT_KINDS: PromotionDiscountKind[] = [
  "percent",
  "fixed",
  "free_ride",
];
export const PROMOTION_REWARD_KINDS: PromotionRewardKind[] = [
  "cash_bonus",
  "rydr_bank_credit",
  "free_ride",
  "fixed",
];

const COLLECTION = "promotions";

async function collection() {
  return (await getWorkspaceDb()).collection(COLLECTION);
}

function asString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asOptionalString(value: unknown): string | null {
  const trimmed = asString(value);
  return trimmed ? trimmed : null;
}

function asStringArray(value: unknown): string[] {
  if (Array.isArray(value)) {
    return [...new Set(value.map(asString).filter(Boolean))];
  }
  if (typeof value === "string") {
    return [
      ...new Set(
        value
          .split(",")
          .map((item) => item.trim())
          .filter(Boolean),
      ),
    ];
  }
  return [];
}

function asNullableInteger(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0)
    throw new Error(
      "Amounts and usage limits must be whole, non-negative numbers.",
    );
  return parsed;
}

function asTimestamp(value: unknown, label: string): Timestamp {
  if (value instanceof Timestamp) return value;
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${label} is required.`);
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`${label} must be a valid date/time.`);
  }
  return Timestamp.fromDate(date);
}

function audienceForType(type: PromotionType): PromotionAudience {
  return type.startsWith("rider_") ? "riders" : "drivers";
}

function enumValue<T extends string>(
  value: unknown,
  allowed: readonly T[],
  fallback: T,
): T {
  return allowed.includes(value as T) ? (value as T) : fallback;
}

export function normalizePromotionInput(input: PromotionInput) {
  const title = asString(input.title);
  if (!title) throw new Error("Promotion title is required.");
  if (title.length > 200 || asString(input.description).length > 2000)
    throw new Error(
      "Use a title under 200 characters and description under 2,000 characters.",
    );

  const type = enumValue(input.type, PROMOTION_TYPES, "rider_fare_discount");
  const status = enumValue(input.status, PROMOTION_STATUSES, "draft");
  if (status === "archived")
    throw new Error(
      "Create or edit promotions as draft, scheduled, active, paused, or ended.",
    );

  const startsAt =
    input.startNow === true
      ? Timestamp.now()
      : asTimestamp(
          typeof input.startsLocal === "string"
            ? localTimeToISO(input.startsLocal)
            : input.startsAt,
          "Start date",
        );
  const endsAt = asTimestamp(
    typeof input.endsLocal === "string"
      ? localTimeToISO(input.endsLocal)
      : input.endsAt,
    "End date",
  );
  if (endsAt.toMillis() <= startsAt.toMillis()) {
    throw new Error("End date must be after start date.");
  }

  const discountKind = enumValue(
    input.discountKind,
    PROMOTION_DISCOUNT_KINDS,
    "percent",
  );
  const discountPercent = asNullableInteger(input.discountPercent);
  const discountCents = asNullableInteger(input.discountCents);
  const maxDiscountCents = asNullableInteger(input.maxDiscountCents);
  const bonusCents = asNullableInteger(input.bonusCents);
  const milestoneRideCount = asNullableInteger(input.milestoneRideCount);
  const rewardKind = enumValue(
    input.rewardKind,
    PROMOTION_REWARD_KINDS,
    type.startsWith("driver_") ? "cash_bonus" : "free_ride",
  );
  const rewardQuantity = asNullableInteger(input.rewardQuantity);
  const rewardCents = asNullableInteger(input.rewardCents);

  if (type === "rider_fare_discount") {
    if (
      discountKind === "percent" &&
      (!discountPercent || discountPercent < 1 || discountPercent > 100)
    ) {
      throw new Error("Percent rider discounts must be between 1 and 100.");
    }
    if (discountKind === "fixed" && (!discountCents || discountCents < 1)) {
      throw new Error("Fixed rider discounts require a positive cents amount.");
    }
  }

  if (type === "driver_per_ride_bonus" && (!bonusCents || bonusCents < 1)) {
    throw new Error("Driver per-ride bonuses require a positive bonus amount.");
  }

  if (type === "driver_milestone_reward") {
    if (!milestoneRideCount || milestoneRideCount < 1) {
      throw new Error(
        "Driver milestone rewards require a ride count of at least 1.",
      );
    }
    if (
      rewardKind === "rydr_bank_credit" &&
      (!rewardQuantity || rewardQuantity < 1)
    ) {
      throw new Error("Rydr Bank milestone rewards require at least 1 credit.");
    }
    if (rewardKind === "cash_bonus" && (!rewardCents || rewardCents < 1)) {
      throw new Error(
        "Cash milestone rewards require a positive reward amount.",
      );
    }
  }

  const normalized = {
    ...normalizeMechanics(input, status),
    title,
    description: asOptionalString(input.description),
    status,
    type,
    audience: audienceForType(type),
    appliesTo: enumValue(input.appliesTo, PROMOTION_APPLIES_TO, "normalRydr"),
    startsAt,
    endsAt,
    timezone: "America/New_York",
    markets: asStringArray(input.markets),
    rideTypes: asStringArray(input.rideTypes),
    discountKind: type === "rider_fare_discount" ? discountKind : null,
    discountPercent:
      type === "rider_fare_discount" && discountKind === "percent"
        ? discountPercent
        : null,
    discountCents:
      type === "rider_fare_discount" && discountKind === "fixed"
        ? discountCents
        : null,
    maxDiscountCents: type.startsWith("rider_") ? maxDiscountCents : null,
    bonusCents: type === "driver_per_ride_bonus" ? bonusCents : null,
    milestoneRideCount: type.endsWith("milestone_reward")
      ? milestoneRideCount
      : null,
    rewardKind: type.endsWith("milestone_reward") ? rewardKind : null,
    rewardQuantity:
      type === "driver_milestone_reward" && rewardKind === "rydr_bank_credit"
        ? rewardQuantity
        : null,
    rewardCents:
      type.endsWith("milestone_reward") && rewardKind !== "free_ride"
        ? rewardCents
        : null,
    maxRedemptions: asNullableInteger(input.maxRedemptions),
    perUserLimit: asNullableInteger(input.perUserLimit),
    betaOnly: input.audienceRule === "beta" || input.betaOnly === true,
  };
  validateOffer(normalized);
  if (
    ["active", "scheduled"].includes(status) &&
    endsAt.toMillis() <= Date.now()
  )
    throw new Error("Publication requires an end date in the future.");
  return normalized;
}

export async function listPromotions(
  includeArchived = false,
): Promise<PromotionRecord[]> {
  const snap = await (await collection()).orderBy("startsAt", "desc").limit(200).get();
  return snap.docs
    .map((doc) => ({
      ...(doc.data() as Omit<PromotionRecord, "id">),
      id: doc.id,
    }))
    .filter((promotion) => includeArchived || promotion.status !== "archived");
}

export async function getPromotion(
  id: string,
): Promise<PromotionRecord | null> {
  const snap = await (await collection()).doc(id).get();
  return snap.exists
    ? { ...(snap.data() as Omit<PromotionRecord, "id">), id: snap.id }
    : null;
}

export async function createPromotion(
  input: PromotionInput,
  admin: { uid: string; email?: string | null },
  sourcePromotionId?: string | null,
) {
  const normalized = normalizePromotionInput(input);
  const ref = (await collection()).doc();
  await persistPromotion(ref.id, {
    ...normalized,
    reusableSourcePromotionId: sourcePromotionId ?? null,
    createdAt: FieldValue.serverTimestamp(),
    createdBy: admin.uid,
    createdByEmail: admin.email ?? null,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: admin.uid,
    updatedByEmail: admin.email ?? null,
  });
  return ref.id;
}

export async function updatePromotion(
  id: string,
  input: PromotionInput,
  admin: { uid: string; email?: string | null },
) {
  const existing = await getPromotion(id);
  if (!existing) throw new Error("Promotion not found.");
  if (existing.status === "archived")
    throw new Error(
      "Archived promotions cannot be edited. Reuse it to create a new draft.",
    );

  const normalized = normalizePromotionInput(input);
  await persistPromotion(id, {
    ...normalized,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: admin.uid,
    updatedByEmail: admin.email ?? null,
  });
}

export async function setPromotionStatus(
  id: string,
  status: PromotionStatus,
  admin: { uid: string; email?: string | null },
) {
  if (!PROMOTION_STATUSES.includes(status))
    throw new Error("Unsupported promotion status.");
  const existing = await getPromotion(id);
  if (!existing) throw new Error("Promotion not found.");
  if (existing.status === "archived")
    throw new Error("Reuse the archived promotion to create a new draft.");
  if (["active", "scheduled"].includes(status)) {
    if (existing.schemaVersion === 2)
      normalizePromotionInput({ ...existing, status });
    if (existing.endsAt.toMillis() <= Date.now())
      throw new Error(
        "This promotion has ended. Reuse it with a new schedule.",
      );
  }
  await persistPromotion(id, {
    ...existing,
    status,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: admin.uid,
    updatedByEmail: admin.email ?? null,
    ...(status === "archived"
      ? { archivedAt: FieldValue.serverTimestamp() }
      : {}),
    ...(status === "paused" ? { pausedAt: FieldValue.serverTimestamp() } : {}),
  });
}

async function persistPromotion(id: string, data: Record<string, unknown>) {
  const ref = (await collection()).doc(id);
  await (await getWorkspaceDb()).runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    const before = existing.data();
    if (
      before?.schemaVersion === 2 &&
      (before.hasBeenPublished === true || before.status !== "draft") &&
      data.schemaVersion === 2
    ) {
      const terms = [
        "type",
        "applicationMode",
        "promoCode",
        "audienceRule",
        "audienceUserIds",
        "markets",
        "rideTypes",
        "discountKind",
        "discountPercent",
        "discountCents",
        "maxDiscountCents",
        "bonusCents",
        "milestoneRideCount",
        "rewardKind",
        "rewardCents",
        "limitKind",
        "maxDistanceMiles",
        "rewardExpiresAfterDays",
        "payExcessFare",
        "perUserLimit",
        "maxRedemptions",
      ];
      if (
        terms.some(
          (field) =>
            JSON.stringify(before[field] ?? null) !==
            JSON.stringify(data[field] ?? null),
        )
      )
        throw new Error(
          "Published promotion terms cannot be changed. Reuse this promotion to create a new draft.",
        );
    }
    const oldCode = existing.data()?.promoCode as string | undefined;
    const newCode = data.promoCode as string | undefined;
    const oldRef = oldCode
      ? (await getWorkspaceDb()).collection("promotionCodes").doc(oldCode)
      : null;
    const newRef = newCode
      ? (await getWorkspaceDb()).collection("promotionCodes").doc(newCode)
      : null;
    const [oldIndex, newIndex] = await Promise.all([
      oldRef ? transaction.get(oldRef) : null,
      newRef ? transaction.get(newRef) : null,
    ]);
    if (newIndex?.exists && newIndex.data()?.promotionId !== id)
      throw new Error("That promo code already belongs to another promotion.");
    if (oldRef && oldCode !== newCode && oldIndex?.data()?.promotionId === id)
      transaction.delete(oldRef);
    if (newRef)
      transaction.set(newRef, {
        promotionId: id,
        updatedAt: FieldValue.serverTimestamp(),
      });
    const { id: ignoredId, ...record } = data;
    if (
      before?.status === "paused" &&
      record.status !== "paused" &&
      before.pausedAt
    ) {
      record.pauseIntervals = [
        ...(before.pauseIntervals ?? []),
        { startsAt: before.pausedAt, endsAt: Timestamp.now() },
      ];
    }
    transaction.set(
      ref,
      {
        ...record,
        hasBeenPublished:
          before?.hasBeenPublished === true ||
          ["active", "scheduled"].includes(String(record.status)),
      },
      { merge: true },
    );
  });
}

export async function duplicatePromotion(
  id: string,
  admin: { uid: string; email?: string | null },
) {
  const existing = await getPromotion(id);
  if (!existing) throw new Error("Promotion not found.");
  return createPromotion(
    {
      ...existing,
      title: `${existing.title} Copy`,
      status: "draft",
      promoCode: null,
      ...(existing.type === "driver_milestone_reward"
        ? {
            rewardKind: "cash_bonus",
            rewardCents: existing.rewardCents || 1000,
          }
        : {}),
      startsAt: existing.startsAt.toDate().toISOString(),
      endsAt: existing.endsAt.toDate().toISOString(),
    },
    admin,
    id,
  );
}
