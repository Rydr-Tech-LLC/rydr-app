import fetch from "node-fetch";
import { db, Timestamp } from "../admin";
import type { VehicleBodyStyle, VinDecodeCacheEntry } from "../types";

const NHTSA_BASE = "https://vpic.nhtsa.dot.gov/api/vehicles";
const CACHE_COLLECTION = "vinDecodeCache";
const VIN_REGEX = /^[A-HJ-NPR-Z0-9]{17}$/i; // 17 chars, no I/O/Q per VIN spec

export class VinDecodeError extends Error {
  constructor(message: string, public readonly code: "invalid_vin" | "nhtsa_unavailable" | "decode_failed") {
    super(message);
    this.name = "VinDecodeError";
  }
}

function normalizeVin(vin: string): string {
  return vin.trim().toUpperCase();
}

function inferBodyStyle(bodyClass: string | null, vehicleType: string | null): VehicleBodyStyle {
  const haystack = `${bodyClass ?? ""} ${vehicleType ?? ""}`.toLowerCase();
  if (!haystack.trim()) return "unknown";
  if (haystack.includes("pickup") || haystack.includes("truck")) return "truck";
  if (haystack.includes("suv") || haystack.includes("sport utility") || haystack.includes("crossover")) {
    return haystack.includes("crossover") ? "crossover" : "suv";
  }
  if (haystack.includes("minivan") || haystack.includes("van")) {
    return haystack.includes("minivan") ? "minivan" : "van";
  }
  if (haystack.includes("convertible") || haystack.includes("cabriolet")) return "convertible";
  if (haystack.includes("wagon")) return "wagon";
  if (haystack.includes("coupe")) return "coupe";
  if (haystack.includes("hatchback")) return "hatchback";
  if (haystack.includes("sedan")) return "sedan";
  return "unknown";
}

/** Pulls the non-empty fields we actually care about out of NHTSA's much
 * larger DecodeVinValuesExtended payload, so the cached `raw` blob stays
 * small and stable even if NHTSA adds/reorders fields upstream. */
function extractRaw(result: Record<string, unknown>): Record<string, string> {
  const keep = [
    "Make",
    "Model",
    "ModelYear",
    "Trim",
    "Trim2",
    "Series",
    "BodyClass",
    "VehicleType",
    "DriveType",
    "FuelTypePrimary",
    "FuelTypeSecondary",
    "PlantCountry",
    "PlantCity",
    "PlantState",
    "EngineCylinders",
    "DisplacementL",
    "TransmissionStyle",
    "GVWR",
    "ErrorCode",
    "ErrorText"
  ];
  const out: Record<string, string> = {};
  for (const key of keep) {
    const value = result[key];
    if (typeof value === "string" && value.trim().length > 0) {
      out[key] = value.trim();
    }
  }
  return out;
}

function toEntry(vin: string, raw: Record<string, string>): VinDecodeCacheEntry {
  const modelYear = raw.ModelYear ? Number.parseInt(raw.ModelYear, 10) : null;
  return {
    vin,
    decodedAt: Timestamp.now(),
    source: "nhtsa",
    make: raw.Make ?? null,
    model: raw.Model ?? null,
    modelYear: Number.isFinite(modelYear) ? modelYear : null,
    trim: raw.Trim ?? raw.Trim2 ?? raw.Series ?? null,
    bodyClass: raw.BodyClass ?? null,
    bodyStyle: inferBodyStyle(raw.BodyClass ?? null, raw.VehicleType ?? null),
    driveType: raw.DriveType ?? null,
    fuelTypePrimary: raw.FuelTypePrimary ?? null,
    fuelTypeSecondary: raw.FuelTypeSecondary ?? null,
    vehicleType: raw.VehicleType ?? null,
    plantCountry: raw.PlantCountry ?? null,
    errorCode: raw.ErrorCode ?? null,
    errorText: raw.ErrorText ?? null,
    raw
  };
}

/**
 * Decodes a VIN via the free NHTSA vPIC API, caching the result in
 * Firestore (`vinDecodeCache/{vin}`) so the same VIN is never decoded
 * twice. A VIN's factory specs never change, so the cache has no expiry.
 */
export class VehicleDecoderService {
  async decode(vinInput: string, opts: { forceRefresh?: boolean } = {}): Promise<VinDecodeCacheEntry> {
    const vin = normalizeVin(vinInput);
    if (!VIN_REGEX.test(vin)) {
      throw new VinDecodeError(`"${vinInput}" is not a valid 17-character VIN.`, "invalid_vin");
    }

    const cacheRef = db.collection(CACHE_COLLECTION).doc(vin);

    if (!opts.forceRefresh) {
      const cached = await cacheRef.get();
      if (cached.exists) {
        return cached.data() as VinDecodeCacheEntry;
      }
    }

    let payload: { Results?: Array<Record<string, unknown>> };
    try {
      const res = await fetch(`${NHTSA_BASE}/DecodeVinValuesExtended/${encodeURIComponent(vin)}?format=json`, {
        method: "GET"
      });
      if (!res.ok) {
        throw new Error(`NHTSA responded with HTTP ${res.status}`);
      }
      payload = (await res.json()) as { Results?: Array<Record<string, unknown>> };
    } catch (err) {
      throw new VinDecodeError(
        `Could not reach the NHTSA VIN decoder: ${err instanceof Error ? err.message : String(err)}`,
        "nhtsa_unavailable"
      );
    }

    const result = payload.Results?.[0];
    if (!result) {
      throw new VinDecodeError("NHTSA returned no decode result for this VIN.", "decode_failed");
    }

    const raw = extractRaw(result);
    const errorCode = raw.ErrorCode ?? "0";
    // NHTSA error code "0" means a clean decode. Non-zero codes still
    // often carry usable data (warnings), so only hard-fail when there's
    // truly no make/model recovered.
    if (errorCode !== "0" && !raw.Make && !raw.Model) {
      throw new VinDecodeError(raw.ErrorText ?? "NHTSA could not decode this VIN.", "decode_failed");
    }

    const entry = toEntry(vin, raw);
    await cacheRef.set(entry, { merge: false });
    return entry;
  }
}

export const vehicleDecoderService = new VehicleDecoderService();
