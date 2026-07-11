import "server-only";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { adminDb } from "./firebaseAdmin";

export type PromotionStatus = "draft" | "scheduled" | "active" | "paused" | "ended" | "archived";
export type PromotionType = "rider_fare_discount" | "driver_per_ride_bonus" | "driver_milestone_reward";
export type PromotionAudience = "riders" | "drivers";
export type PromotionAppliesTo = "normalRydr" | "cashHub" | "both";
export type PromotionDiscountKind = "percent" | "fixed";
export type PromotionRewardKind = "cash_bonus" | "rydr_bank_credit";

export interface PromotionRecord {
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

export const PROMOTION_TYPES: PromotionType[] = ["rider_fare_discount", "driver_per_ride_bonus", "driver_milestone_reward"];
export const PROMOTION_STATUSES: PromotionStatus[] = ["draft", "scheduled", "active", "paused", "ended", "archived"];
export const PROMOTION_APPLIES_TO: PromotionAppliesTo[] = ["normalRydr", "cashHub", "both"];
export const PROMOTION_DISCOUNT_KINDS: PromotionDiscountKind[] = ["percent", "fixed"];
export const PROMOTION_REWARD_KINDS: PromotionRewardKind[] = ["cash_bonus", "rydr_bank_credit"];

const COLLECTION = "promotions";

function collection() {
  return adminDb.collection(COLLECTION);
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
    return [...new Set(value.split(",").map((item) => item.trim()).filter(Boolean))];
  }
  return [];
}

function asNullableInteger(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : null;
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
  return type === "rider_fare_discount" ? "riders" : "drivers";
}

function enumValue<T extends string>(value: unknown, allowed: readonly T[], fallback: T): T {
  return allowed.includes(value as T) ? (value as T) : fallback;
}

export function normalizePromotionInput(input: PromotionInput) {
  const title = asString(input.title);
  if (!title) throw new Error("Promotion title is required.");

  const type = enumValue(input.type, PROMOTION_TYPES, "rider_fare_discount");
  const status = enumValue(input.status, PROMOTION_STATUSES, "draft");
  if (status === "archived") throw new Error("Create or edit promotions as draft, scheduled, active, paused, or ended.");

  const startsAt = asTimestamp(input.startsAt, "Start date");
  const endsAt = asTimestamp(input.endsAt, "End date");
  if (endsAt.toMillis() <= startsAt.toMillis()) {
    throw new Error("End date must be after start date.");
  }

  const discountKind = enumValue(input.discountKind, PROMOTION_DISCOUNT_KINDS, "percent");
  const discountPercent = asNullableInteger(input.discountPercent);
  const discountCents = asNullableInteger(input.discountCents);
  const maxDiscountCents = asNullableInteger(input.maxDiscountCents);
  const bonusCents = asNullableInteger(input.bonusCents);
  const milestoneRideCount = asNullableInteger(input.milestoneRideCount);
  const rewardKind = enumValue(input.rewardKind, PROMOTION_REWARD_KINDS, "rydr_bank_credit");
  const rewardQuantity = asNullableInteger(input.rewardQuantity);
  const rewardCents = asNullableInteger(input.rewardCents);

  if (type === "rider_fare_discount") {
    if (discountKind === "percent" && (!discountPercent || discountPercent < 1 || discountPercent > 100)) {
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
      throw new Error("Driver milestone rewards require a ride count of at least 1.");
    }
    if (rewardKind === "rydr_bank_credit" && (!rewardQuantity || rewardQuantity < 1)) {
      throw new Error("Rydr Bank milestone rewards require at least 1 credit.");
    }
    if (rewardKind === "cash_bonus" && (!rewardCents || rewardCents < 1)) {
      throw new Error("Cash milestone rewards require a positive reward amount.");
    }
  }

  return {
    title,
    description: asOptionalString(input.description),
    status,
    type,
    audience: audienceForType(type),
    appliesTo: enumValue(input.appliesTo, PROMOTION_APPLIES_TO, "normalRydr"),
    startsAt,
    endsAt,
    timezone: asString(input.timezone) || "America/New_York",
    markets: asStringArray(input.markets),
    rideTypes: asStringArray(input.rideTypes),
    discountKind: type === "rider_fare_discount" ? discountKind : null,
    discountPercent: type === "rider_fare_discount" && discountKind === "percent" ? discountPercent : null,
    discountCents: type === "rider_fare_discount" && discountKind === "fixed" ? discountCents : null,
    maxDiscountCents: type === "rider_fare_discount" ? maxDiscountCents : null,
    bonusCents: type === "driver_per_ride_bonus" ? bonusCents : null,
    milestoneRideCount: type === "driver_milestone_reward" ? milestoneRideCount : null,
    rewardKind: type === "driver_milestone_reward" ? rewardKind : null,
    rewardQuantity: type === "driver_milestone_reward" && rewardKind === "rydr_bank_credit" ? rewardQuantity : null,
    rewardCents: type === "driver_milestone_reward" && rewardKind === "cash_bonus" ? rewardCents : null,
    maxRedemptions: asNullableInteger(input.maxRedemptions),
    perUserLimit: asNullableInteger(input.perUserLimit),
    betaOnly: input.betaOnly === true
  };
}

export async function listPromotions(includeArchived = false): Promise<PromotionRecord[]> {
  const snap = await collection().orderBy("startsAt", "desc").limit(200).get();
  return snap.docs
    .map((doc) => ({ ...(doc.data() as Omit<PromotionRecord, "id">), id: doc.id }))
    .filter((promotion) => includeArchived || promotion.status !== "archived");
}

export async function getPromotion(id: string): Promise<PromotionRecord | null> {
  const snap = await collection().doc(id).get();
  return snap.exists ? ({ ...(snap.data() as Omit<PromotionRecord, "id">), id: snap.id }) : null;
}

export async function createPromotion(input: PromotionInput, admin: { uid: string; email?: string | null }, sourcePromotionId?: string | null) {
  const normalized = normalizePromotionInput(input);
  const ref = collection().doc();
  await ref.set({
    ...normalized,
    reusableSourcePromotionId: sourcePromotionId ?? null,
    createdAt: FieldValue.serverTimestamp(),
    createdBy: admin.uid,
    createdByEmail: admin.email ?? null,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: admin.uid,
    updatedByEmail: admin.email ?? null
  });
  return ref.id;
}

export async function updatePromotion(id: string, input: PromotionInput, admin: { uid: string; email?: string | null }) {
  const existing = await getPromotion(id);
  if (!existing) throw new Error("Promotion not found.");
  if (existing.status === "archived") throw new Error("Archived promotions cannot be edited. Reuse it to create a new draft.");

  const normalized = normalizePromotionInput(input);
  await collection().doc(id).set(
    {
      ...normalized,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: admin.uid,
      updatedByEmail: admin.email ?? null
    },
    { merge: true }
  );
}

export async function setPromotionStatus(id: string, status: PromotionStatus, admin: { uid: string; email?: string | null }) {
  if (!PROMOTION_STATUSES.includes(status)) throw new Error("Unsupported promotion status.");
  await collection().doc(id).set(
    {
      status,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: admin.uid,
      updatedByEmail: admin.email ?? null,
      ...(status === "archived" ? { archivedAt: FieldValue.serverTimestamp() } : {})
    },
    { merge: true }
  );
}

export async function duplicatePromotion(id: string, admin: { uid: string; email?: string | null }) {
  const existing = await getPromotion(id);
  if (!existing) throw new Error("Promotion not found.");
  return createPromotion(
    {
      ...existing,
      title: `${existing.title} Copy`,
      status: "draft",
      startsAt: existing.startsAt.toDate().toISOString(),
      endsAt: existing.endsAt.toDate().toISOString()
    },
    admin,
    id
  );
}
