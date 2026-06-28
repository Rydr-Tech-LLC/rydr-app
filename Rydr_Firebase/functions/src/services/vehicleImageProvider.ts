import { storage } from "../admin";
import { vehicleLibraryService } from "./vehicleLibraryService";
import type { ImageMatchTier, VehicleColor, VehicleImageQuery, VehicleImageResult, VehicleLibraryEntry } from "../types";

/**
 * Abstraction over "where vehicle images come from." `getImage` must never
 * throw for a well-formed query — it returns `null` when it has nothing,
 * letting `VehicleImageService` fall through to the next provider/tier.
 *
 * Today there's exactly one implementation (`FirebaseLibraryProvider`,
 * backed by our own Storage library). Down the road, a commercial source
 * — ChromeData, MarketCheck, J.D. Power, etc. — can implement this same
 * interface and be added to `VehicleImageService`'s provider list without
 * any change to the driver/rider apps or Mission Control: they only ever
 * see a `VehicleImageResult` with an `imageUrl`, never which provider
 * produced it.
 */
export interface VehicleImageProvider {
  readonly name: string;
  getImage(query: VehicleImageQuery): Promise<VehicleImageResult | null>;
}

function toPublicUrl(storagePath: string): string {
  const bucket = storage.bucket();
  return `https://storage.googleapis.com/${bucket.name}/${encodeURI(storagePath)}`;
}

function resultFor(entry: VehicleLibraryEntry, path: string, tier: ImageMatchTier, color: string | null): VehicleImageResult {
  return {
    storagePath: path,
    imageUrl: toPublicUrl(path),
    tier,
    matchedVehicleId: entry.vehicleId,
    matchedColor: color
  };
}

/** Picks the entry whose [yearStart, yearEnd] is closest to the query year
 * — used for tier 3 ("nearest year / same generation"). Exact containment
 * wins; otherwise the entry with the smallest distance to either edge of
 * its range is chosen. */
function closestByYear(entries: VehicleLibraryEntry[], year: number): VehicleLibraryEntry | null {
  if (entries.length === 0) return null;
  const withImage = entries.filter((e) => e.defaultImage);
  const pool = withImage.length > 0 ? withImage : entries;

  let best: VehicleLibraryEntry | null = null;
  let bestDistance = Number.POSITIVE_INFINITY;
  for (const entry of pool) {
    const distance =
      year >= entry.yearStart && year <= entry.yearEnd
        ? 0
        : Math.min(Math.abs(year - entry.yearStart), Math.abs(year - entry.yearEnd));
    if (distance < bestDistance) {
      bestDistance = distance;
      best = entry;
    }
  }
  return best;
}

/**
 * Our own managed vehicle image library (Firestore `vehicleLibrary` +
 * Firebase Storage `vehicle-library/`). Implements the full 5-tier
 * fallback chain described in the Vehicle Library System spec:
 *   1. exact year + make + model + trim + color
 *   2. exact year + make + model + default color
 *   3. nearest year / same generation + default color
 *   4. generic make/model placeholder (any vehicle of that make)
 *   5. generic body-style placeholder (sedan/SUV/truck/etc.)
 * Tier 6 — "no image at all" — is not a provider concern; it's signaled by
 * this method returning `null`, and `VehicleImageService` turns that into
 * `status: "missing"` for the caller to render a local icon.
 */
export class FirebaseLibraryProvider implements VehicleImageProvider {
  readonly name = "firebase-library";

  async getImage(query: VehicleImageQuery): Promise<VehicleImageResult | null> {
    const candidates = await vehicleLibraryService.findCandidates(query.make, query.model);
    const inYear = candidates.filter((e) => query.year >= e.yearStart && query.year <= e.yearEnd);

    // Tier 1: exact year + make + model + trim + color.
    if (query.trim) {
      const trimMatch = inYear.find((e) => (e.trim ?? "").toLowerCase() === query.trim!.toLowerCase());
      const colorPath = trimMatch?.colorImages?.[query.color as VehicleColor];
      if (trimMatch && colorPath) {
        return resultFor(trimMatch, colorPath, 1, query.color);
      }
    }
    // Also allow tier-1 without trim filtering if any in-year entry has the exact color.
    for (const entry of inYear) {
      const colorPath = entry.colorImages?.[query.color as VehicleColor];
      if (colorPath) {
        return resultFor(entry, colorPath, 1, query.color);
      }
    }

    // Tier 2: exact year + make + model + default color.
    const inYearWithDefault = inYear.find((e) => e.defaultImage);
    if (inYearWithDefault?.defaultImage) {
      return resultFor(inYearWithDefault, inYearWithDefault.defaultImage, 2, null);
    }

    // Tier 3: nearest year / same generation + default color.
    const nearest = closestByYear(candidates, query.year);
    if (nearest?.defaultImage) {
      return resultFor(nearest, nearest.defaultImage, 3, null);
    }

    // Tier 4: generic make/model placeholder.
    const genericMake = await vehicleLibraryService.findGenericForMake(query.make);
    if (genericMake?.defaultImage) {
      return resultFor(genericMake, genericMake.defaultImage, 4, null);
    }

    // Tier 5: generic body-style placeholder.
    if (query.bodyStyle) {
      const genericBody = await vehicleLibraryService.findGenericForBodyStyle(query.bodyStyle);
      if (genericBody?.defaultImage) {
        return resultFor(genericBody, genericBody.defaultImage, 5, null);
      }
    }

    return null;
  }
}

export const firebaseLibraryProvider = new FirebaseLibraryProvider();
