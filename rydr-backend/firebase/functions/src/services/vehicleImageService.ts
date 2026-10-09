import { firebaseLibraryProvider, type VehicleImageProvider } from "./vehicleImageProvider";
import type { VehicleImageQuery, VehicleImageResult, VehicleImageStatus } from "../types";

export interface VehicleImageLookup {
  status: VehicleImageStatus;
  result: VehicleImageResult | null;
  provider: string | null;
}

const CACHE_TTL_MS = 10 * 60 * 1000; // 10 minutes — long enough to absorb bursty
// driver-app lookups, short enough that a freshly-uploaded Mission Control
// image shows up without needing an explicit cache-bust mechanism.

interface CacheRecord {
  value: VehicleImageLookup;
  expiresAt: number;
}

function cacheKey(query: VehicleImageQuery): string {
  return [query.make, query.model, query.year, query.trim ?? "", query.bodyStyle ?? "", query.color]
    .join("|")
    .toLowerCase();
}

/**
 * Resolves the best available vehicle image for a decoded VIN + chosen
 * color, trying each registered `VehicleImageProvider` in order and
 * falling through tiers within each provider. This is the ONLY thing the
 * driver app, rider app, and Mission Control should call to get an image
 * — they never know (or need to know) whether the image ultimately came
 * from our own Storage library or, in the future, a commercial provider.
 *
 * In-process lookup caching (per warm function instance) avoids repeat
 * Firestore reads for the same vehicle+color within a short window; this
 * is in addition to (not instead of) VehicleDecoderService's permanent
 * VIN-decode cache, which caches a different thing (NHTSA's answer, not
 * the image match).
 */
export class VehicleImageService {
  private cache = new Map<string, CacheRecord>();

  constructor(private providers: VehicleImageProvider[] = [firebaseLibraryProvider]) {}

  /** Allows a future commercial provider to be registered without
   * redeploying every caller — e.g. `vehicleImageService.addProvider(chromeDataProvider)`. */
  addProvider(provider: VehicleImageProvider, position: "first" | "last" = "last") {
    if (position === "first") this.providers.unshift(provider);
    else this.providers.push(provider);
  }

  async getImage(query: VehicleImageQuery): Promise<VehicleImageLookup> {
    const key = cacheKey(query);
    const cached = this.cache.get(key);
    if (cached && cached.expiresAt > Date.now()) {
      return cached.value;
    }

    let lookup: VehicleImageLookup = { status: "missing", result: null, provider: null };
    for (const provider of this.providers) {
      const result = await provider.getImage(query).catch(() => null);
      if (result) {
        lookup = { status: result.tier <= 2 ? "matched" : "fallback", result, provider: provider.name };
        break;
      }
    }

    this.cache.set(key, { value: lookup, expiresAt: Date.now() + CACHE_TTL_MS });
    return lookup;
  }

  /** Drop everything cached for one vehicle key family — call this after a
   * Mission Control upload/delete so the next lookup doesn't serve a stale
   * "missing" result for up to the full TTL. */
  invalidate(makeModelPrefix?: string) {
    if (!makeModelPrefix) {
      this.cache.clear();
      return;
    }
    const prefix = makeModelPrefix.toLowerCase();
    for (const key of this.cache.keys()) {
      if (key.startsWith(prefix)) this.cache.delete(key);
    }
  }
}

export const vehicleImageService = new VehicleImageService();
