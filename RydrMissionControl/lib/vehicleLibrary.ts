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

export interface VehicleLibraryEntry {
  vehicleId: string;
  make: string;
  model: string;
  yearStart: number;
  yearEnd: number;
  trim: string | null;
  bodyStyle: VehicleBodyStyle;
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

function bucket() {
  return adminStorage.bucket(process.env.FIREBASE_STORAGE_BUCKET || process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET || undefined);
}

function publicUrl(path: string): string {
  return `https://storage.googleapis.com/${bucket().name}/${encodeURI(path)}`;
}

function withUrls(entry: VehicleLibraryEntry): VehicleLibraryEntry {
  const colorImageUrls: Partial<Record<VehicleColor, string>> = {};
  for (const [color, path] of Object.entries(entry.colorImages ?? {})) {
    if (path) colorImageUrls[color as VehicleColor] = publicUrl(path);
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
  return withUrls(snap.data() as VehicleLibraryEntry);
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
  let query: FirebaseFirestore.Query = collection();
  if (filters.make) query = query.where("make", "==", filters.make);
  if (filters.model) query = query.where("model", "==", filters.model);
  if (filters.trim) query = query.where("trim", "==", filters.trim);

  const snap = await query.limit(filters.limit ?? 500).get();
  let entries = snap.docs.map((d) => d.data() as VehicleLibraryEntry);

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

  return entries.sort((a, b) => (a.make + a.model + a.yearStart).localeCompare(b.make + b.model + b.yearStart)).map(withUrls);
}

export async function listVehicleLibrary(limit = 1000): Promise<VehicleLibraryEntry[]> {
  const snap = await collection().limit(limit).get();
  return snap.docs.map((d) => withUrls(d.data() as VehicleLibraryEntry));
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
  },
  adminUid: string
): Promise<VehicleLibraryEntry> {
  const vehicleId = input.vehicleId ?? buildVehicleId(input.make, input.model, input.yearStart, input.yearEnd, input.trim);
  const ref = collection().doc(vehicleId);
  const existing = await ref.get();

  if (!existing.exists) {
    const entry: VehicleLibraryEntry = {
      vehicleId,
      make: input.make,
      model: input.model,
      yearStart: input.yearStart,
      yearEnd: input.yearEnd,
      trim: input.trim ?? null,
      bodyStyle: input.bodyStyle,
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
    make: input.make,
    model: input.model,
    yearStart: input.yearStart,
    yearEnd: input.yearEnd,
    trim: input.trim ?? null,
    bodyStyle: input.bodyStyle,
    updatedAt: FieldValue.serverTimestamp(),
    updatedBy: adminUid
  });
  return withUrls((await ref.get()).data() as VehicleLibraryEntry);
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
  return withUrls((await ref.get()).data() as VehicleLibraryEntry);
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
  return withUrls((await ref.get()).data() as VehicleLibraryEntry);
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
