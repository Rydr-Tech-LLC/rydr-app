import "server-only";
import { FieldValue } from "firebase-admin/firestore";
import { adminDb, adminStorage } from "./firebaseAdmin";

// Mission Control's side of the Vehicle Library System. The Firestore
// `vehicleLibrary` collection and `vehicle-library/` Storage layout here are
// the SAME schema the Firebase Cloud Functions in Rydr_Firebase/functions
// (VehicleLibraryService) read from — see VEHICLE_LIBRARY_README.md. Mission
// Control writes directly via the Admin SDK (consistent with every other
// privileged write in this app — driver approval, report actions, etc.)
// rather than round-tripping through Cloud Functions, since it already runs
// fully trusted, server-side, behind its own admin-session gate.

export const VEHICLE_COLORS = [
  "Black",
  "White",
  "Silver",
  "Gray",
  "Blue",
  "Red",
  "Green",
  "Brown",
  "Gold",
  "Yellow",
  "Orange"
] as const;

export type VehicleColor = (typeof VEHICLE_COLORS)[number];

export type VehicleBodyStyle =
  | "sedan"
  | "suv"
  | "truck"
  | "coupe"
  | "hatchback"
  | "minivan"
  | "crossover"
  | "wagon"
  | "convertible"
  | "van"
  | "unknown";

export const VEHICLE_BODY_STYLES: VehicleBodyStyle[] = [
  "sedan",
  "suv",
  "truck",
  "coupe",
  "hatchback",
  "minivan",
  "crossover",
  "wagon",
  "convertible",
  "van",
  "unknown"
];

export const RYDR_RIDE_TYPES = ["Rydr Go", "Rydr Eco", "Rydr XL"] as const;
export type RydrRideType = (typeof RYDR_RIDE_TYPES)[number];

export interface VehicleLibraryEntry {
  vehicleId: string;
  make: string;
  model: string;
  yearStart: number;
  yearEnd: number;
  trim: string | null;
  bodyStyle: VehicleBodyStyle;
  eligibleRideTypes?: RydrRideType[];
  availableColors: VehicleColor[];
  defaultImage: string | null;
  defaultImageUrl?: string | null;
  colorImages: Partial<Record<VehicleColor, string>>;
  colorImageUrls?: Partial<Record<VehicleColor, string>>;
  createdAt?: unknown;
  updatedAt?: unknown;
  createdBy?: string;
  updatedBy?: string;
}

const COLLECTION = "vehicleLibrary";
const STORAGE_ROOT = "vehicle-library";

export const GENERIC_MAKE_PREFIX = "_generic_make";
export const GENERIC_BODY_PREFIX = "_generic_body";

function slugify(value: string): string {
  return value
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

export function buildVehicleId(make: string, model: string, yearStart: number, yearEnd: number, trim?: string | null): string {
  const parts = [slugify(make), slugify(model), String(yearStart), String(yearEnd)];
  if (trim) parts.push(slugify(trim));
  return parts.join("_");
}

export function genericMakeVehicleId(make: string): string {
  return `${GENERIC_MAKE_PREFIX}_${slugify(make)}`;
}

export function genericBodyVehicleId(bodyStyle: VehicleBodyStyle): string {
  return `${GENERIC_BODY_PREFIX}_${slugify(bodyStyle)}`;
}

function storagePathFor(make: string, model: string, year: number, fileName: string): string {
  return `${STORAGE_ROOT}/${slugify(make)}/${slugify(model)}/${year}/${fileName}`;
}

function normalizedText(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

function normalizeRideTypes(values: unknown): RydrRideType[] {
  if (!Array.isArray(values)) return [];
  const selected = new Set<string>();
  for (const value of values) {
    if (typeof value !== "string") continue;
    const match = RYDR_RIDE_TYPES.find((rideType) => rideType.toLowerCase() === value.trim().toLowerCase());
    if (match) selected.add(match);
  }
  return RYDR_RIDE_TYPES.filter((rideType) => selected.has(rideType));
}

function stringValue(value: unknown, fallback: string): string {
  if (typeof value !== "string") return fallback;
  const normalized = normalizedText(value);
  return normalized || fallback;
}

function optionalString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = normalizedText(value);
  return normalized || null;
}

function numberValue(value: unknown, fallback: number): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

function normalizeBodyStyle(value: unknown): VehicleBodyStyle {
  return VEHICLE_BODY_STYLES.includes(value as VehicleBodyStyle) ? (value as VehicleBodyStyle) : "unknown";
}

function normalizeColor(value: unknown): VehicleColor | null {
  if (typeof value !== "string") return null;
  return VEHICLE_COLORS.find((color) => color.toLowerCase() === value.trim().toLowerCase()) ?? null;
}

function normalizeColorImages(value: unknown): Partial<Record<VehicleColor, string>> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const colorImages: Partial<Record<VehicleColor, string>> = {};
  for (const [key, path] of Object.entries(value)) {
    const color = normalizeColor(key);
    if (color && typeof path === "string" && path.trim()) {
      colorImages[color] = path.trim();
    }
  }
  return colorImages;
}

function normalizeVehicleLibraryEntry(data: unknown, fallbackVehicleId?: string): VehicleLibraryEntry {
  const record = data && typeof data === "object" && !Array.isArray(data) ? (data as Record<string, unknown>) : {};
  const make = stringValue(record.make, "Unknown make");
  const model = stringValue(record.model, "Unknown model");
  const yearStart = Math.trunc(numberValue(record.yearStart, numberValue(record.year, new Date().getFullYear())));
  const yearEnd = Math.trunc(numberValue(record.yearEnd, yearStart));
  const colorImages = normalizeColorImages(record.colorImages);
  const colors = new Set<VehicleColor>();
  if (Array.isArray(record.availableColors)) {
    for (const value of record.availableColors) {
      const color = normalizeColor(value);
      if (color) colors.add(color);
    }
  }
  for (const color of Object.keys(colorImages)) {
    colors.add(color as VehicleColor);
  }

  return {
    vehicleId: stringValue(record.vehicleId, fallbackVehicleId ?? buildVehicleId(make, model, yearStart, yearEnd, optionalString(record.trim))),
    make,
    model,
    yearStart,
    yearEnd,
    trim: optionalString(record.trim),
    bodyStyle: normalizeBodyStyle(record.bodyStyle),
    eligibleRideTypes: normalizeRideTypes(record.eligibleRideTypes),
    availableColors: VEHICLE_COLORS.filter((color) => colors.has(color)),
    defaultImage: optionalString(record.defaultImage),
    colorImages
  };
}

function storageBucketName(): string | null {
  return (
    process.env.FIREBASE_STORAGE_BUCKET ||
    process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET ||
    (process.env.FIREBASE_ADMIN_PROJECT_ID ? `${process.env.FIREBASE_ADMIN_PROJECT_ID}.firebasestorage.app` : null)
  );
}

function bucket() {
  return adminStorage.bucket(storageBucketName() ?? undefined);
}

function publicUrl(path: string): string | null {
  const bucketName = storageBucketName();
  if (!bucketName) return null;
  return `https://storage.googleapis.com/${bucketName}/${encodeURI(path)}`;
}

function withUrls(data: unknown, fallbackVehicleId?: string): VehicleLibraryEntry {
  const entry = normalizeVehicleLibraryEntry(data, fallbackVehicleId);
  const colorImageUrls: Partial<Record<VehicleColor, string>> = {};
  for (const [color, path] of Object.entries(entry.colorImages ?? {})) {
    if (path) {
      const url = publicUrl(path);
      if (url) colorImageUrls[color as VehicleColor] = url;
    }
  }
  return {
    ...entry,
    defaultImageUrl: entry.defaultImage ? publicUrl(entry.defaultImage) : null,
    colorImageUrls
  };
}

function collection() {
  return adminDb.collection(COLLECTION);
}

export async function getVehicleLibraryEntry(vehicleId: string): Promise<VehicleLibraryEntry | null> {
  const snap = await collection().doc(vehicleId).get();
  if (!snap.exists) return null;
  return withUrls(snap.data(), snap.id);
}

export interface VehicleLibrarySearchFilters {
  make?: string;
  model?: string;
  year?: number;
  trim?: string;
  color?: VehicleColor;
  missingImagesOnly?: boolean;
  incompleteColorsOnly?: boolean;
  limit?: number;
}

export async function searchVehicleLibrary(filters: VehicleLibrarySearchFilters): Promise<VehicleLibraryEntry[]> {
  const snap = await collection().limit(filters.limit ?? 500).get();
  let entries = snap.docs.map((d) => withUrls(d.data(), d.id));

  if (filters.make) {
    const make = filters.make.trim().toLowerCase();
    entries = entries.filter((e) => e.make.toLowerCase().includes(make));
  }
  if (filters.model) {
    const model = filters.model.trim().toLowerCase();
    entries = entries.filter((e) => e.model.toLowerCase().includes(model));
  }
  if (filters.trim) {
    const trim = filters.trim.trim().toLowerCase();
    entries = entries.filter((e) => (e.trim ?? "").toLowerCase().includes(trim));
  }

  if (filters.year != null) {
    entries = entries.filter((e) => filters.year! >= e.yearStart && filters.year! <= e.yearEnd);
  }
  if (filters.color) {
    entries = entries.filter((e) => e.availableColors?.includes(filters.color!));
  }
  if (filters.missingImagesOnly) {
    entries = entries.filter((e) => !e.defaultImage && Object.keys(e.colorImages ?? {}).length === 0);
  }
  if (filters.incompleteColorsOnly) {
    entries = entries.filter((e) => (e.availableColors?.length ?? 0) > 0 && (e.availableColors?.length ?? 0) < VEHICLE_COLORS.length);
  }

  return entries.sort((a, b) => (a.make + a.model + a.yearStart).localeCompare(b.make + b.model + b.yearStart));
}

export async function listVehicleLibrary(limit = 1000): Promise<VehicleLibraryEntry[]> {
  const snap = await collection().limit(limit).get();
  return snap.docs.map((d) => withUrls(d.data(), d.id));
}

export async function upsertVehicleLibraryEntry(
  input: {
    vehicleId?: string;
    make: string;
    model: string;
    yearStart: number;
    yearEnd: number;
    trim?: string | null;
    bodyStyle: VehicleBodyStyle;
    eligibleRideTypes?: unknown;
  },
  adminUid: string
): Promise<VehicleLibraryEntry> {
  const make = normalizedText(input.make);
  const model = normalizedText(input.model);
  const trim = typeof input.trim === "string" && input.trim.trim() ? normalizedText(input.trim) : null;
  const eligibleRideTypes = normalizeRideTypes(input.eligibleRideTypes);
  const vehicleId = input.vehicleId ?? buildVehicleId(make, model, input.yearStart, input.yearEnd, trim);
  const ref = collection().doc(vehicleId);
  const existing = await ref.get();

  if (!existing.exists) {
    const entry: VehicleLibraryEntry = {
      vehicleId,
      make,
      model,
      yearStart: input.yearStart,
      yearEnd: input.yearEnd,
      trim,
      bodyStyle: input.bodyStyle,
      eligibleRideTypes,
      availableColors: [],
      defaultImage: null,
      colorImages: {},
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      createdBy: adminUid,
      updatedBy: adminUid
    };
    await ref.set(entry);
    return withUrls({ ...entry, vehicleId });
  }

  await ref.update({
    make,
    model,
    yearStart: input.yearStart,
    yearEnd: input.yearEnd,
    trim,
    bodyStyle: input.bodyStyle,
    eligibleRideTypes,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: adminUid
  });
  return withUrls((await ref.get()).data(), ref.id);
}

export async function uploadVehicleImage(params: {
  vehicleId: string;
  color?: VehicleColor;
  contentType: string;
  data: Buffer;
  adminUid: string;
}): Promise<VehicleLibraryEntry> {
  const ref = collection().doc(params.vehicleId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new Error(`Vehicle library entry "${params.vehicleId}" does not exist. Create it before uploading images.`);
  }
  const entry = snap.data() as VehicleLibraryEntry;
  const fileName = params.color ? `${slugify(params.color)}.webp` : "default.webp";
  const path = storagePathFor(entry.make, entry.model, entry.yearStart, fileName);

  const file = bucket().file(path);
  await file.save(params.data, {
    contentType: params.contentType,
    metadata: { cacheControl: "public, max-age=31536000, immutable" }
  });
  await file.makePublic();

  const update: Record<string, unknown> = {
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: params.adminUid
  };
  if (params.color) {
    update[`colorImages.${params.color}`] = path;
    const nextColors = Array.from(new Set([...(entry.availableColors ?? []), params.color]));
    update.availableColors = nextColors;
  } else {
    update.defaultImage = path;
  }
  await ref.update(update);
  return withUrls((await ref.get()).data(), ref.id);
}

function normalizedCompare(value: unknown): string {
  return typeof value === "string" ? normalizedText(value).toLowerCase() : "";
}

function yearValue(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return Math.trunc(value);
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return Math.trunc(parsed);
  }
  return null;
}

function matchingVehicleImagePath(entry: VehicleLibraryEntry, color?: VehicleColor): { path: string; matchedColor: VehicleColor | null } | null {
  if (color && entry.colorImages?.[color]) {
    return { path: entry.colorImages[color]!, matchedColor: color };
  }
  if (entry.defaultImage) {
    return { path: entry.defaultImage, matchedColor: null };
  }
  return null;
}

export async function backfillDriverVehicleImagesForEntry(entry: VehicleLibraryEntry, color?: VehicleColor): Promise<number> {
  const snap = await adminDb.collection("drivers").limit(1000).get();
  let count = 0;
  let pendingWrites = 0;
  let batch = adminDb.batch();

  async function commitIfNeeded(force = false) {
    if (pendingWrites === 0) return;
    if (!force && pendingWrites < 450) return;
    await batch.commit();
    batch = adminDb.batch();
    pendingWrites = 0;
  }

  for (const doc of snap.docs) {
    const data = doc.data();
    const vehicle = data.vehicle && typeof data.vehicle === "object" && !Array.isArray(data.vehicle)
      ? (data.vehicle as Record<string, unknown>)
      : null;
    if (!vehicle) continue;

    const vehicleYear = yearValue(vehicle.year);
    if (vehicleYear == null || vehicleYear < entry.yearStart || vehicleYear > entry.yearEnd) continue;
    if (normalizedCompare(vehicle.make) !== normalizedCompare(entry.make)) continue;
    if (normalizedCompare(vehicle.model) !== normalizedCompare(entry.model)) continue;
    const vehicleColor = normalizeColor(vehicle.color);
    if (color && vehicleColor !== color) continue;
    const match = matchingVehicleImagePath(entry, color ?? vehicleColor ?? undefined);
    if (!match) continue;
    const imageUrl = publicUrl(match.path);
    if (!imageUrl) continue;

    const nextVehicle = {
      ...vehicle,
      imagePath: match.path,
      imageUrl,
      imageMatchTier: match.matchedColor ? 1 : 2,
      libraryVehicleId: entry.vehicleId,
      libraryMatchedColor: match.matchedColor
    };
    const libraryRideTypes = entry.eligibleRideTypes ?? [];
    const driverUpdate: Record<string, unknown> = {
      vehicle: nextVehicle,
      vehicleImageStatus: "matched",
      updatedAt: FieldValue.serverTimestamp()
    };
    if (libraryRideTypes.length > 0) {
      driverUpdate.vehicleEligibility = {
        rideTypes: libraryRideTypes,
        source: "vehicleLibrary",
        matchedVehicleId: entry.vehicleId,
        evaluatedAt: FieldValue.serverTimestamp()
      };
      driverUpdate.qualifiedRideTypes = libraryRideTypes;
      driverUpdate.supportedRideTypes = libraryRideTypes;
      driverUpdate.selectedRideTypes = libraryRideTypes;
      driverUpdate.rideTypes = libraryRideTypes;
    }

    batch.set(doc.ref, driverUpdate, { merge: true });
    pendingWrites += 1;
    batch.set(
      adminDb.collection("publicDriverProfiles").doc(doc.id),
      {
        vehicleColor: typeof vehicle.color === "string" ? vehicle.color : "",
        vehicleImageURL: imageUrl,
        vehicleSummary: [vehicle.year, vehicle.make, vehicle.model].filter(Boolean).join(" "),
        updatedAt: FieldValue.serverTimestamp()
      },
      { merge: true }
    );
    pendingWrites += 1;
    count += 1;
    await commitIfNeeded();
  }

  await commitIfNeeded(true);
  return count;
}

export async function deleteVehicleImage(params: { vehicleId: string; color?: VehicleColor; adminUid: string }): Promise<VehicleLibraryEntry> {
  const ref = collection().doc(params.vehicleId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new Error(`Vehicle library entry "${params.vehicleId}" does not exist.`);
  }
  const entry = snap.data() as VehicleLibraryEntry;
  const path = params.color ? entry.colorImages?.[params.color] : entry.defaultImage;
  if (path) {
    await bucket().file(path).delete({ ignoreNotFound: true });
  }

  const update: Record<string, unknown> = {
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: params.adminUid
  };
  if (params.color) {
    update[`colorImages.${params.color}`] = FieldValue.delete();
    update.availableColors = (entry.availableColors ?? []).filter((c) => c !== params.color);
  } else {
    update.defaultImage = null;
  }
  await ref.update(update);
  return withUrls((await ref.get()).data(), ref.id);
}

export async function deleteVehicleLibraryEntry(vehicleId: string): Promise<void> {
  const ref = collection().doc(vehicleId);
  const snap = await ref.get();
  if (!snap.exists) return;
  const entry = snap.data() as VehicleLibraryEntry;
  const paths = [entry.defaultImage, ...Object.values(entry.colorImages ?? {})].filter(Boolean) as string[];
  await Promise.all(paths.map((p) => bucket().file(p).delete({ ignoreNotFound: true })));
  await ref.delete();
}
