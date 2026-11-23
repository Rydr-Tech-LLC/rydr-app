import { documentDeadline, georgiaDate } from "./driverCompliancePolicy";
import { extractDriverProofFields, vehicleMakeToken, vehicleToken, type ExtractedFields } from "./driverDocumentFields";

type DriverDocumentKind = "driverLicense" | "insurance" | "registration" | "vehicleInspection";
export type ReviewStatus = "pending" | "approved" | "expired" | "needs_review" | "rejected";

type DriverProfile = {
  firstName?: string | null;
  lastName?: string | null;
  dob?: Date | null;
  licenseNumber?: string | null;
  licenseState?: string | null;
  vehicleVin?: string | null;
  vehiclePlate?: string | null;
  vehicleMake?: string | null;
  vehicleModel?: string | null;
  vehicleYear?: string | null;
};

export type ReviewDecision = {
  status: ReviewStatus;
  reviewReason: string;
  checks: Record<string, boolean | string | null>;
};

function decideDriverDocument(
  kind: DriverDocumentKind,
  extractedText: string,
  fields: ExtractedFields,
  profile: DriverProfile
): ReviewDecision {
  const checks: ReviewDecision["checks"] = {
    readable: extractedText.trim().length >= 35,
    documentTypeMatched: fields.documentType === kind,
    expirationPresent: Boolean(fields.expirationDate),
    expirationValid: null,
    nameMatches: null,
    vehicleMatches: null
  };

  const failures: string[] = [];
  if (!checks.readable) failures.push("Image appears unreadable or OCR returned too little text.");
  if (!checks.documentTypeMatched) failures.push("Document type is uncertain.");
  const missing = missingDriverFields(kind, fields);
  checks.requiredFieldsPresent = missing.length === 0;
  if (missing.length) failures.push(`Missing or unreadable: ${missing.join(", ")}.`);

  const expiration = fields.expirationDate ? parseDate(fields.expirationDate) : null;
  let expired = false;
  if (fields.expirationDate && expiration) {
    checks.expirationValid = documentDeadline(fields.expirationDate) > Date.now();
    expired = !checks.expirationValid;
  } else if (requiresExpiration(kind)) {
    checks.expirationValid = false;
  }

  if (kind === "driverLicense") {
    if (fields.name) {
      checks.nameMatches = namesMatch(fields.name, profile);
      if (!checks.nameMatches) failures.push("Extracted name does not match the driver profile.");
    } else if (!profile.licenseNumber) {
      failures.push("Driver name is unreadable and no profile license number is available for matching.");
    }

    if (fields.state && profile.licenseState) {
      checks.licenseStateMatches = normalizeToken(fields.state) === normalizeToken(profile.licenseState);
      if (!checks.licenseStateMatches) failures.push("Issuing state does not match the driver profile.");
    }
    if (fields.issuanceDate && fields.expirationDate && fields.issuanceDate >= fields.expirationDate) {
      failures.push("The license issue date must precede expiration.");
    }
    if (fields.issuanceDate && fields.issuanceDate > georgiaDate(Date.now())) {
      failures.push("The license issue date is in the future.");
    }

    if (fields.dateOfBirth && profile.dob) {
      const dobMatches = sameCalendarDate(parseDate(fields.dateOfBirth), profile.dob);
      checks.dateOfBirthMatches = dobMatches;
      if (!dobMatches) failures.push("Extracted date of birth does not match the driver profile.");
    }

    if (fields.licenseNumber && profile.licenseNumber) {
      const licenseMatches = normalizeToken(fields.licenseNumber) === normalizeToken(profile.licenseNumber);
      checks.licenseNumberMatches = licenseMatches;
      if (!licenseMatches) failures.push("Extracted license number does not match the driver profile.");
    }
  }

  if (kind === "insurance") {
    if (fields.policyholderFirstName && fields.policyholderLastName) {
      checks.policyholderMatches = normalizeNamePart(fields.policyholderFirstName) === normalizeNamePart(profile.firstName ?? "")
        && normalizeNamePart(fields.policyholderLastName) === normalizeNamePart(profile.lastName ?? "");
      if (!checks.policyholderMatches) failures.push("The named insured does not match the driver profile.");
    }
    if (fields.effectiveDate && fields.expirationDate && fields.effectiveDate >= fields.expirationDate) {
      failures.push("The policy effective date must precede expiration.");
    }
    if (fields.effectiveDate && fields.effectiveDate > georgiaDate(Date.now())) {
      failures.push("Insurance coverage has not started.");
    }
  }

  if (kind === "registration" || kind === "insurance") {
    checks.vinMatches = Boolean(fields.vin && profile.vehicleVin && normalizeVin(fields.vin) === normalizeVin(profile.vehicleVin));
    if (!checks.vinMatches && fields.vin) failures.push("The VIN could not be matched to the driver vehicle.");
    const evidence = [
      [fields.vehicleYear, profile.vehicleYear, vehicleToken],
      [fields.vehicleMake, profile.vehicleMake, vehicleMakeToken],
      [fields.vehicleModel, profile.vehicleModel, vehicleToken]
    ] as const;
    const printed = evidence.filter(([value]) => value);
    const detailsMatch = printed.every(([value, expected, normalize]) => Boolean(expected)
      && normalize(value) === normalize(expected));
    checks.vehicleMatches = checks.vinMatches && detailsMatch;
    if (!detailsMatch) failures.push("The printed year, make or model could not be matched to the driver vehicle.");
  } else if (kind === "vehicleInspection") {
    const vehicleMatch = vehicleFieldsMatch(fields, profile);
    checks.vehicleMatches = vehicleMatch.matched;
    if (!vehicleMatch.matched) failures.push(vehicleMatch.reason);
  }

  if (failures.length > 0) {
    return { status: "needs_review", reviewReason: failures.join(" "), checks };
  }

  if (expired) return { status: "expired", reviewReason: `Document expired on ${fields.expirationDate}.`, checks };
  return { status: "approved", reviewReason: "OCR fields matched required driver and vehicle profile data.", checks };
}

function missingDriverFields(kind: DriverDocumentKind, fields: ExtractedFields): string[] {
  const required: Partial<Record<keyof ExtractedFields, string>> = {
    driverLicense: { licenseClass: "class", state: "issuing state", issuanceDate: "issue date", expirationDate: "expiration date", licenseNumber: "license number" },
    insurance: { insurancePolicyNumber: "policy number", effectiveDate: "effective date", expirationDate: "end date", policyholderFirstName: "policyholder first name", policyholderLastName: "policyholder last name", vin: "VIN" },
    registration: { vin: "VIN", vehicleMake: "make", vehicleModel: "model", vehicleYear: "year", expirationDate: "expiration date" },
    vehicleInspection: {}
  }[kind];
  if (kind === "vehicleInspection" && !(fields.expirationDate || fields.vin || fields.plateNumber)) {
    return ["expiration date, VIN or license plate"];
  }
  return Object.entries(required).filter(([key]) => !fields[key as keyof ExtractedFields]).map(([, label]) => label);
}

function requiresExpiration(kind: DriverDocumentKind): boolean {
  return kind === "driverLicense" || kind === "insurance" || kind === "registration";
}

function namesMatch(extractedName: string | undefined, profile: DriverProfile): boolean {
  if (!extractedName || !profile.firstName || !profile.lastName) return false;
  const extractedTokens = new Set(nameTokens(extractedName));
  return extractedTokens.has(normalizeNamePart(profile.firstName)) && extractedTokens.has(normalizeNamePart(profile.lastName));
}

function vehicleFieldsMatch(
  fields: ExtractedFields,
  profile: DriverProfile
): { matched: boolean; reason: string } {
  const expectedVin = normalizeVin(profile.vehicleVin);
  const expectedPlate = normalizePlate(profile.vehiclePlate);
  const extractedVin = normalizeVin(fields.vin);
  const extractedPlate = normalizePlate(fields.plateNumber);

  if (expectedVin && extractedVin) {
    return {
      matched: expectedVin === extractedVin,
      reason: "Extracted VIN does not match the driver vehicle profile."
    };
  }

  if (expectedPlate && extractedPlate) {
    return {
      matched: expectedPlate === extractedPlate,
      reason: "Extracted plate number does not match the driver vehicle profile."
    };
  }

  return {
    matched: false,
    reason: "No matching VIN or plate number could be confirmed against the driver vehicle profile."
  };
}

export function reviewDriverProof(kind: Exclude<DriverDocumentKind, "vehicleInspection">, text: string, data: Record<string, unknown>) {
  const profile = driverProfile(data);
  const extractedFields = extractDriverProofFields(kind, text, {
    make: profile.vehicleMake, model: profile.vehicleModel, year: profile.vehicleYear
  });
  return { extractedFields, decision: decideDriverDocument(kind, text, extractedFields, profile) };
}

export function reviewVehicleInspection(text: string, fields: ExtractedFields, data: Record<string, unknown>): ReviewDecision {
  return decideDriverDocument("vehicleInspection", text, fields, driverProfile(data));
}

function driverProfile(data: Record<string, unknown>): DriverProfile {
  const vehicle = asRecord(data.vehicle);
  const license = asRecord(data.license);
  return {
    firstName: asString(data.firstName),
    lastName: asString(data.lastName),
    dob: asDate(data.dob),
    licenseNumber: asString(license.number) ?? asString(data.licenseNumber) ?? asString(data.driverLicenseNumber),
    licenseState: asString(license.state) ?? asString(data.licenseState),
    vehicleVin: asString(vehicle.vin) ?? asString(data.vin),
    vehiclePlate: asString(vehicle.plate) ?? asString(data.plate) ?? asString(data.licensePlate),
    vehicleMake: asString(vehicle.make) ?? asString(data.vehicleMake),
    vehicleModel: asString(vehicle.model) ?? asString(data.vehicleModel),
    vehicleYear: asString(String(vehicle.year ?? data.vehicleYear ?? ""))
  };
}

export function parseDate(value: string | undefined | null): Date | null {
  if (!value) return null;
  const clean = value.trim().replace(/\./g, "/");
  const slash = clean.match(/^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$/);
  if (slash) {
    const month = Number(slash[1]);
    const day = Number(slash[2]);
    const year = normalizeYear(Number(slash[3]));
    return validUtcDate(year, month, day);
  }
  const iso = clean.match(/^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$/);
  if (iso) {
    return validUtcDate(Number(iso[1]), Number(iso[2]), Number(iso[3]));
  }
  const parsed = new Date(clean);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function normalizeYear(year: number): number {
  if (year >= 100) return year;
  return year >= 70 ? 1900 + year : 2000 + year;
}

function validUtcDate(year: number, month: number, day: number): Date | null {
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
  return date;
}

function sameCalendarDate(lhs: Date | null, rhs: Date | null): boolean {
  if (!lhs || !rhs) return false;
  return lhs.getUTCFullYear() === rhs.getUTCFullYear()
    && lhs.getUTCMonth() === rhs.getUTCMonth()
    && lhs.getUTCDate() === rhs.getUTCDate();
}

function asDate(value: unknown): Date | null {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value === "object" && "toDate" in value && typeof value.toDate === "function") {
    return value.toDate();
  }
  if (typeof value === "string") return parseDate(value);
  return null;
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : {};
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function normalizeNamePart(value: string): string {
  return value.normalize("NFKD").toLowerCase().replace(/[^a-z]/g, "");
}

function nameTokens(value: string): string[] {
  return value.split(/\s+/).map(normalizeNamePart).filter(Boolean);
}

function normalizeToken(value: string | null | undefined): string {
  return (value ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
}

function normalizeVin(value: string | null | undefined): string {
  return normalizeToken(value);
}

function normalizePlate(value: string | null | undefined): string {
  return normalizeToken(value);
}
