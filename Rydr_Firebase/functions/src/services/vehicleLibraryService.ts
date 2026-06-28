import { db, storage, FieldValue } from "../admin";
import { VEHICLE_COLORS, type VehicleBodyStyle, type VehicleColor, type VehicleLibraryEntry } from "../types";

const COLLECTION = "vehicleLibrary";
const STORAGE_ROOT = "vehicle-library";

/** Reserved pseudo-make used for tier-4 ("any model of this make") fallback
 * library entries. Kept distinct from real makes by the leading underscore
 * so it can never collide with a real manufacturer name. */
export const GENERIC_MAKE_PREFIX = "_generic_make";
/** Reserved pseudo-make used for tier-5 ("any vehicle of this body style at
 * all") fallback library entries — the system's hard floor. */
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

export function storagePathFor(make: string, model: string, year: number, fileName: string): string {
  return `${STORAGE_ROOT}/${slugify(make)}/${slugify(model)}/${year}/${fileName}`;
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

export class VehicleLibraryService {
  private collection() {
    return db.collection(COLLECTION);
  }

  async get(vehicleId: string): Promise<VehicleLibraryEntry | null> {
    const snap = await this.collection().doc(vehicleId).get();
    return snap.exists ? (snap.data() as VehicleLibraryEntry) : null;
  }

  /** Loads every candidate entry for a make/model and filters year-range +
   * trim in memory. Firestore range queries on yearStart/yearEnd together
   * with equality on make/model would need a composite index per
   * combination, so for a library sized in the hundreds-of-models range
   * (not rows), client-side filtering after a cheap make+model query is
   * simpler and just as fast. */
  async findCandidates(make: string, model: string): Promise<VehicleLibraryEntry[]> {
    const snap = await this.collection()
      .where("make", "==", make)
      .where("model", "==", model)
      .get();
    return snap.docs.map((d) => d.data() as VehicleLibraryEntry);
  }

  async findGenericForMake(make: string): Promise<VehicleLibraryEntry | null> {
    return this.get(genericMakeVehicleId(make));
  }

  async findGenericForBodyStyle(bodyStyle: VehicleBodyStyle): Promise<VehicleLibraryEntry | null> {
    return this.get(genericBodyVehicleId(bodyStyle));
  }

  async search(filters: VehicleLibrarySearchFilters): Promise<VehicleLibraryEntry[]> {
    let query: FirebaseFirestore.Query = this.collection();
    if (filters.make) query = query.where("make", "==", filters.make);
    if (filters.model) query = query.where("model", "==", filters.model);
    if (filters.trim) query = query.where("trim", "==", filters.trim);

    const snap = await query.limit(filters.limit ?? 500).get();
    let entries = snap.docs.map((d) => d.data() as VehicleLibraryEntry);

    if (filters.year != null) {
      entries = entries.filter((e) => filters.year! >= e.yearStart && filters.year! <= e.yearEnd);
    }
    if (filters.color) {
      entries = entries.filter((e) => e.availableColors.includes(filters.color!));
    }
    if (filters.missingImagesOnly) {
      entries = entries.filter((e) => !e.defaultImage && Object.keys(e.colorImages ?? {}).length === 0);
    }
    if (filters.incompleteColorsOnly) {
      entries = entries.filter((e) => e.availableColors.length > 0 && e.availableColors.length < VEHICLE_COLORS.length);
    }

    return entries.sort((a, b) => (a.make + a.model + a.yearStart).localeCompare(b.make + b.model + b.yearStart));
  }

  async listAll(limit = 1000): Promise<VehicleLibraryEntry[]> {
    const snap = await this.collection().limit(limit).get();
    return snap.docs.map((d) => d.data() as VehicleLibraryEntry);
  }

  /** Creates or updates a library entry's metadata (not images — use
   * `uploadImage`/`deleteImage` for those, since those also touch Storage). */
  async upsertEntry(
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
    const ref = this.collection().doc(vehicleId);
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
      return { ...entry, vehicleId };
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
    return (await ref.get()).data() as VehicleLibraryEntry;
  }

  /** Uploads (or replaces) one color image — or the default image when
   * `color` is omitted — for a library entry, writing the bytes to Storage
   * and updating the Firestore doc's `colorImages`/`defaultImage`/
   * `availableColors` fields in one pass. */
  async uploadImage(params: {
    vehicleId: string;
    color?: VehicleColor; // omit to set the default/fallback image
    contentType: string;
    data: Buffer;
    adminUid: string;
  }): Promise<VehicleLibraryEntry> {
    const ref = this.collection().doc(params.vehicleId);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new Error(`Vehicle library entry "${params.vehicleId}" does not exist. Create it before uploading images.`);
    }
    const entry = snap.data() as VehicleLibraryEntry;
    const fileName = params.color ? `${slugify(params.color)}.webp` : "default.webp";
    const path = storagePathFor(entry.make, entry.model, entry.yearStart, fileName);

    const bucket = storage.bucket();
    const file = bucket.file(path);
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
    return (await ref.get()).data() as VehicleLibraryEntry;
  }

  async deleteImage(params: { vehicleId: string; color?: VehicleColor; adminUid: string }): Promise<VehicleLibraryEntry> {
    const ref = this.collection().doc(params.vehicleId);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new Error(`Vehicle library entry "${params.vehicleId}" does not exist.`);
    }
    const entry = snap.data() as VehicleLibraryEntry;
    const path = params.color ? entry.colorImages?.[params.color] : entry.defaultImage;
    if (path) {
      await storage.bucket().file(path).delete({ ignoreNotFound: true });
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
    return (await ref.get()).data() as VehicleLibraryEntry;
  }

  async deleteEntry(vehicleId: string): Promise<void> {
    const ref = this.collection().doc(vehicleId);
    const snap = await ref.get();
    if (!snap.exists) return;
    const entry = snap.data() as VehicleLibraryEntry;
    const bucket = storage.bucket();
    const paths = [entry.defaultImage, ...Object.values(entry.colorImages ?? {})].filter(Boolean) as string[];
    await Promise.all(paths.map((p) => bucket.file(p).delete({ ignoreNotFound: true })));
    await ref.delete();
  }
}

export const vehicleLibraryService = new VehicleLibraryService();
