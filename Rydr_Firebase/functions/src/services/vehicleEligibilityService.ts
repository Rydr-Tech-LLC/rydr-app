import type { RydrRideType } from "../types";

const ORDERED_RIDE_TYPES = ["Rydr Go", "Rydr Eco", "Rydr XL", "Rydr Prestine", "Rydr Executive"] as const;

const GO_ELIGIBLE_MAKES = new Set([
  "acura", "audi", "bmw", "buick", "cadillac", "chevrolet", "chevy", "chrysler", "dodge", "ford",
  "genesis", "gmc", "honda", "hyundai", "infiniti", "kia", "lexus", "lincoln", "mazda",
  "mercedes benz", "mercedes-benz", "mitsubishi", "nissan", "subaru", "tesla", "toyota",
  "volkswagen", "volvo"
]);

const GO_MODEL_FRAGMENTS = [
  "accord", "altima", "camry", "civic", "corolla", "elantra", "equinox", "fusion", "malibu", "maxima",
  "sentra", "sonata", "soul", "sportage", "tucson", "cr v", "crv", "cx 5", "cx5", "escape",
  "forester", "rav4", "rogue", "model 3", "model y", "ioniq", "leaf", "mach e", "mustang mach e",
  "ev6", "bolt"
];

const XL_MODEL_FRAGMENTS = [
  "armada", "ascent", "atlas", "carnival", "enclave", "escalade", "expedition", "explorer",
  "grand caravan", "highlander", "navigator", "odyssey", "pacifica", "palisade", "pilot", "sienna",
  "suburban", "tahoe", "telluride", "traverse", "yukon"
];

const BASELINE_RATES: Record<string, { minimumFare: number; perMile: number; perMinute: number }> = {
  go: { minimumFare: 7, perMile: 1, perMinute: 0.25 },
  eco: { minimumFare: 7, perMile: 1.10, perMinute: 0.25 },
  xl: { minimumFare: 7, perMile: 1.25, perMinute: 0.25 },
  prestine: { minimumFare: 7, perMile: 1.50, perMinute: 0.35 },
  executive: { minimumFare: 7, perMile: 2, perMinute: 0.50 }
};

function normalized(value: unknown): string {
  return String(value ?? "").toLowerCase().replace(/[-_]/g, " ").trim();
}

export function canonicalRideType(value: unknown): string {
  const key = normalized(value);
  if (["rydr", "rydr go", "go"].includes(key)) return "go";
  if (["rydr eco", "eco"].includes(key)) return "eco";
  if (["rydr xl", "xl"].includes(key)) return "xl";
  if (["rydr prestine", "rydr pristine", "prestine", "pristine"].includes(key)) return "prestine";
  if (["rydr executive", "executive"].includes(key)) return "executive";
  return key;
}

function normalizeRideTypes(values: unknown): string[] {
  if (!Array.isArray(values)) return [];
  const keys = new Set(values.map(canonicalRideType));
  return ORDERED_RIDE_TYPES.filter((rideType) => keys.has(canonicalRideType(rideType)));
}

function isElectric(fuelType: unknown): boolean {
  return normalized(fuelType).includes("electric");
}

export function evaluateVehicleEligibility(input: {
  make: unknown;
  model: unknown;
  fuelType: unknown;
  libraryRideTypes?: RydrRideType[] | string[];
  approvedRideTypes?: unknown;
}) {
  const make = normalized(input.make);
  const model = normalized(input.model);
  const xlEligible = XL_MODEL_FRAGMENTS.some((fragment) => model.includes(fragment));
  const goEligible = isElectric(input.fuelType)
    || GO_ELIGIBLE_MAKES.has(make)
    || GO_MODEL_FRAGMENTS.some((fragment) => model.includes(fragment));
  const libraryRideTypes = normalizeRideTypes(input.libraryRideTypes);
  const baseRideTypes = libraryRideTypes.length > 0
    ? libraryRideTypes
    : [
        ...(goEligible ? ["Rydr Go"] : []),
        ...(isElectric(input.fuelType) ? ["Rydr Eco"] : []),
        ...(xlEligible ? ["Rydr XL"] : [])
      ];
  const expanded = new Set([...baseRideTypes, ...normalizeRideTypes(input.approvedRideTypes)]);
  if (expanded.has("Rydr Executive")) {
    expanded.add("Rydr Prestine");
    expanded.add("Rydr Go");
    if (xlEligible) expanded.add("Rydr XL");
  }
  if (expanded.has("Rydr Prestine")) {
    expanded.add("Rydr Go");
    if (xlEligible) expanded.add("Rydr XL");
  }
  const rideTypes = ORDERED_RIDE_TYPES.filter((rideType) => expanded.has(rideType));
  const vehicleClass = rideTypes.includes("Rydr XL")
    ? "xl"
    : rideTypes.includes("Rydr Eco")
      ? "electric"
      : rideTypes.includes("Rydr Go")
        ? "go"
        : "manual_review";
  return {
    rideTypes,
    vehicleClass,
    requiresManualReview: baseRideTypes.length === 0,
    source: libraryRideTypes.length > 0 ? "vehicleLibrary" : "backendRules"
  };
}

export function mergeDefaultTierRates(existing: unknown, rideTypes: string[]) {
  const current = existing && typeof existing === "object" ? existing as Record<string, unknown> : {};
  const merged: Record<string, unknown> = { ...current };
  for (const rideType of rideTypes) {
    const key = canonicalRideType(rideType);
    if (!merged[key]) merged[key] = { ...BASELINE_RATES[key], useSuggestedPricing: false };
  }
  return merged;
}
