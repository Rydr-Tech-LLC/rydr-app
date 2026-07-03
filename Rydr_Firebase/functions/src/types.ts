// Shared types for the Vehicle Library System.
// Mirrors the Firestore schema documented in Rydr_Firebase/VEHICLE_LIBRARY_README.md.

/** The fixed color list drivers choose from. Keep in sync with RydrDriver's
 * VehicleColorPicker and Mission Control's color filter. */
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

export const RYDR_RIDE_TYPES = ["Rydr Go", "Rydr Eco", "Rydr XL"] as const;
export type RydrRideType = (typeof RYDR_RIDE_TYPES)[number];

/** A single entry in the managed vehicle image library. One document per
 * make/model/year-range/trim combination Mission Control has uploaded
 * imagery for. `_generic` is a reserved pseudo-make used for two tiers of
 * fallback entries (see VehicleImageService): `_generic/{Make}` (any model
 * of that make) and `_generic/Body/{BodyStyle}` (any vehicle of that body
 * style at all). */
export interface VehicleLibraryEntry {
  vehicleId: string;
  make: string;
  model: string;
  yearStart: number;
  yearEnd: number;
  trim: string | null;
  bodyStyle: VehicleBodyStyle;
  /** Optional Mission Control override for the ride types this vehicle may support. */
  eligibleRideTypes?: RydrRideType[];
  /** Colors that actually have an uploaded image in `colorImages`. */
  availableColors: VehicleColor[];
  /** Storage path (not a download URL) to the default/fallback image for
   * this entry, used when the driver's chosen color has no image. */
  defaultImage: string | null;
  /** Map of color name -> Storage path, populated only for colors that
   * have been uploaded via Mission Control. */
  colorImages: Partial<Record<VehicleColor, string>>;
  createdAt: unknown;
  updatedAt: unknown;
  createdBy?: string;
  updatedBy?: string;
}

/** Cached NHTSA decode result, keyed by VIN. VIN -> vehicle specs is a
 * permanent fact (a VIN is never re-issued for a different vehicle), so
 * this cache has no TTL/expiry — once decoded, always reused. */
export interface VinDecodeCacheEntry {
  vin: string;
  decodedAt: unknown;
  source: "nhtsa";
  make: string | null;
  model: string | null;
  modelYear: number | null;
  trim: string | null;
  bodyClass: string | null;
  bodyStyle: VehicleBodyStyle;
  driveType: string | null;
  fuelTypePrimary: string | null;
  fuelTypeSecondary: string | null;
  vehicleType: string | null;
  plantCountry: string | null;
  errorCode: string | null;
  errorText: string | null;
  /** Trimmed raw NHTSA response (non-empty Variable/Value pairs only), kept
   * for forward-compatibility / debugging without re-calling the API. */
  raw: Record<string, string>;
}

export type ImageMatchTier = 1 | 2 | 3 | 4 | 5;

export interface VehicleImageQuery {
  make: string;
  model: string;
  year: number;
  trim?: string | null;
  bodyStyle?: VehicleBodyStyle | null;
  color: string;
}

export interface VehicleImageResult {
  /** Storage path (gs:// object path, not a signed URL) of the matched image. */
  storagePath: string;
  /** Public HTTPS download URL for the storage path, ready for AsyncImage. */
  imageUrl: string;
  /** Which fallback tier produced this match. 1 is the best (exact) match. */
  tier: ImageMatchTier;
  matchedVehicleId: string;
  matchedColor: string | null;
  eligibleRideTypes?: RydrRideType[];
}

export type VehicleImageStatus = "matched" | "fallback" | "missing";
export type VinDecodeStatus = "pending" | "decoded" | "failed" | "manual";
