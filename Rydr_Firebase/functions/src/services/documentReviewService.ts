import { createHash } from "crypto";
import fetch from "node-fetch";
import { db, FieldValue } from "../admin";

type OwnerType = "driver" | "rider";
type DriverDocumentKind = "driverLicense" | "insurance" | "registration" | "vehicleInspection";
type RiderDocumentKind = "identity" | "driverLicense" | "passport" | "stateId";
type DocumentKind = DriverDocumentKind | RiderDocumentKind;
type ReviewStatus = "pending" | "approved" | "expired" | "needs_review" | "rejected";

type ParsedDocumentPath = {
  ownerType: OwnerType;
  uid: string;
  kind: DocumentKind;
  side: "front" | "back" | "single" | string;
  storagePath: string;
};

type ExtractedFields = {
  documentType?: string;
  name?: string;
  dateOfBirth?: string;
  licenseNumber?: string;
  state?: string;
  expirationDate?: string;
  insurancePolicyNumber?: string;
  vin?: string;
  plateNumber?: string;
};

type DriverProfile = {
  firstName?: string | null;
  lastName?: string | null;
  dob?: Date | null;
  licenseNumber?: string | null;
  licenseState?: string | null;
  vehicleVin?: string | null;
  vehiclePlate?: string | null;
};

type ReviewDecision = {
  status: ReviewStatus;
  reviewReason: string;
  checks: Record<string, boolean | string | null>;
};

type VisionAnnotateResponse = {
  responses?: Array<{
    fullTextAnnotation?: { text?: string };
    textAnnotations?: Array<{ description?: string }>;
    error?: { message?: string };
  }>;
  error?: { message?: string };
};

const DRIVER_DOCUMENT_KINDS = new Set(["driverLicense", "insurance", "registration", "vehicleInspection"]);
const RIDER_DOCUMENT_KINDS = new Set(["identity", "driverLicense", "passport", "stateId"]);
const METADATA_TOKEN_URL =
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token";
const MAX_STORED_OCR_CHARS = 20000;

const DOCUMENT_KEYWORDS: Record<DocumentKind, string[]> = {
  driverLicense: ["driver license", "drivers license", "license", "class", "date of birth", "dob", "sex", "eyes"],
  insurance: ["insurance", "policy", "coverage", "insured", "liability", "naic", "effective"],
  registration: ["registration", "plate", "tag", "vin", "vehicle", "county", "registered"],
  vehicleInspection: ["inspection", "vehicle inspection", "emissions", "odometer", "pass", "fail"],
  identity: ["identification", "identity", "driver license", "passport", "date of birth", "dob"],
  passport: ["passport", "nationality", "date of birth", "surname", "given names"],
  stateId: ["identification", "identity card", "date of birth", "dob", "state"]
};

const US_STATE_CODES = new Set([
  "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "IA", "ID", "IL", "IN", "KS",
  "KY", "LA", "MA", "MD", "ME", "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NE", "NH", "NJ", "NM",
  "NV", "NY", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VA", "VT", "WA", "WI",
  "WV", "WY", "DC"
]);

export function parseDocumentStoragePath(rawPath: string | undefined): ParsedDocumentPath | null {
  if (!rawPath) return null;
  const storagePath = decodeStoragePath(rawPath);
  const segments = storagePath.split("/").filter(Boolean);
  if (segments.length < 4) return null;

  const [prefix, uid, kind, fileName] = segments;
  if (!uid || !kind || !fileName) return null;

  if (prefix === "driverDocuments" && DRIVER_DOCUMENT_KINDS.has(kind)) {
    return {
      ownerType: "driver",
      uid,
      kind: kind as DriverDocumentKind,
      side: sideFromFileName(fileName),
      storagePath
    };
  }

  if ((prefix === "riderVerificationDocuments" || prefix === "riderDocuments") && RIDER_DOCUMENT_KINDS.has(kind)) {
    return {
      ownerType: "rider",
      uid,
      kind: kind as RiderDocumentKind,
      side: sideFromFileName(fileName),
      storagePath
    };
  }

  return null;
}

export async function reviewUploadedDocument(params: {
  bucket: string;
  contentType?: string;
  generation?: string | number;
  metadata?: Record<string, string>;
  storagePath?: string;
}): Promise<void> {
  const parsed = parseDocumentStoragePath(params.storagePath);
  if (!parsed) return;

  const reviewId = documentReviewId(params.bucket, parsed.storagePath);
  const downloadURL = downloadURLForObject(params.bucket, parsed.storagePath, params.metadata);
  const generation = params.generation == null ? null : String(params.generation);
  await writePendingReview(parsed, reviewId, params.bucket, generation, downloadURL);

  if (!params.contentType?.startsWith("image/")) {
    await writeFinalReview(parsed, {
      bucket: params.bucket,
      generation,
      downloadURL,
      reviewId,
      extractedText: "",
      extractedFields: { documentType: parsed.kind },
      decision: {
        status: "rejected",
        reviewReason: "Unsupported upload type. Documents must be uploaded as readable images.",
        checks: { supportedContentType: false }
      }
    });
    return;
  }

  let extractedText = "";
  try {
    extractedText = await detectDocumentText(`gs://${params.bucket}/${parsed.storagePath}`);
  } catch (error) {
    await writeFinalReview(parsed, {
      bucket: params.bucket,
      generation,
      downloadURL,
      reviewId,
      extractedText: "",
      extractedFields: { documentType: parsed.kind },
      decision: {
        status: "needs_review",
        reviewReason: error instanceof Error ? `Vision OCR failed: ${error.message}` : "Vision OCR failed.",
        checks: { visionOcrCompleted: false }
      }
    });
    throw error;
  }

  const extractedFields = extractFields(parsed.kind, extractedText);

  if (parsed.ownerType === "driver") {
    const profile = await loadDriverProfile(parsed.uid);
    const decision = decideDriverDocument(parsed.kind as DriverDocumentKind, extractedText, extractedFields, profile);
    await writeFinalReview(parsed, {
      bucket: params.bucket,
      generation,
      downloadURL,
      reviewId,
      extractedText,
      extractedFields,
      decision
    });
    return;
  }

  await writeFinalReview(parsed, {
    bucket: params.bucket,
    generation,
    downloadURL,
    reviewId,
    extractedText,
    extractedFields,
    decision: decideRiderDocument(extractedText, extractedFields)
  });
}

function decideDriverDocument(
  kind: DriverDocumentKind,
  extractedText: string,
  fields: ExtractedFields,
  profile: DriverProfile
): ReviewDecision {
  const checks: ReviewDecision["checks"] = {
    readable: extractedText.trim().length >= 35,
    documentTypeMatched: inferredTypeMatches(kind, fields.documentType),
    expirationPresent: Boolean(fields.expirationDate),
    expirationValid: null,
    requiredFieldsPresent: requiredDriverFieldsPresent(kind, fields),
    nameMatches: null,
    vehicleMatches: null
  };

  const failures: string[] = [];
  if (!checks.readable) failures.push("Image appears unreadable or OCR returned too little text.");
  if (!checks.documentTypeMatched) failures.push("Document type is uncertain.");
  if (!checks.requiredFieldsPresent) failures.push("Required document fields are missing.");

  const expiration = fields.expirationDate ? parseDate(fields.expirationDate) : null;
  if (fields.expirationDate && expiration) {
    checks.expirationValid = expiration.getTime() >= startOfToday().getTime();
    if (!checks.expirationValid) {
      return {
        status: "expired",
        reviewReason: `Document expired on ${fields.expirationDate}.`,
        checks
      };
    }
  } else if (requiresExpiration(kind)) {
    checks.expirationValid = false;
    failures.push("Expiration date is missing or unreadable.");
  }

  if (kind === "driverLicense") {
    const nameMatch = namesMatch(fields.name, profile);
    checks.nameMatches = nameMatch;
    if (!nameMatch) failures.push("Extracted name does not match the driver profile.");

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

  if (kind === "registration" || kind === "insurance" || kind === "vehicleInspection") {
    const vehicleMatch = vehicleFieldsMatch(fields, profile, kind);
    checks.vehicleMatches = vehicleMatch.matched;
    if (!vehicleMatch.matched) failures.push(vehicleMatch.reason);
  }

  if (failures.length > 0) {
    return { status: "needs_review", reviewReason: failures.join(" "), checks };
  }

  return { status: "approved", reviewReason: "OCR fields matched required driver and vehicle profile data.", checks };
}

function decideRiderDocument(extractedText: string, fields: ExtractedFields): ReviewDecision {
  const readable = extractedText.trim().length >= 35;
  const hasIdentitySignal = Boolean(fields.name || fields.dateOfBirth || fields.licenseNumber || fields.state);
  if (!readable || !hasIdentitySignal) {
    return {
      status: "needs_review",
      reviewReason: "Rider verification document needs manual review.",
      checks: { readable, requiredFieldsPresent: hasIdentitySignal }
    };
  }
  return {
    status: "needs_review",
    reviewReason: "Rider verification document OCR completed and is ready for manual verification.",
    checks: { readable, requiredFieldsPresent: hasIdentitySignal }
  };
}

function extractFields(kind: DocumentKind, text: string): ExtractedFields {
  const aamva = extractAamvaFields(text);
  const inferredDocumentType = inferDocumentType(kind, text);
  return compactFields({
    documentType: inferredDocumentType,
    name: aamva.name ?? extractName(text),
    dateOfBirth: aamva.dateOfBirth ?? extractDateOfBirth(text),
    licenseNumber: aamva.licenseNumber ?? extractLicenseNumber(text),
    state: aamva.state ?? extractState(text),
    expirationDate: aamva.expirationDate ?? extractExpirationDate(text),
    insurancePolicyNumber: extractPolicyNumber(text),
    vin: extractVin(text),
    plateNumber: extractPlateNumber(text)
  });
}

function extractAamvaFields(text: string): Partial<ExtractedFields> {
  const fields: Partial<ExtractedFields> = {};
  const lines = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  const get = (code: string) => {
    const line = lines.find((candidate) => candidate.startsWith(code));
    return line ? line.slice(code.length).trim() : undefined;
  };

  const firstName = get("DAC");
  const lastName = get("DCS");
  const fullName = [firstName, lastName].filter(Boolean).join(" ").trim();
  if (fullName) fields.name = fullName;
  fields.licenseNumber = get("DAQ");
  fields.expirationDate = parseAamvaDate(get("DBA"));
  fields.dateOfBirth = parseAamvaDate(get("DBB"));
  fields.state = get("DAJ") ?? get("DAI");
  return compactFields(fields);
}

function inferDocumentType(kind: DocumentKind, text: string): string {
  const normalizedText = normalizeText(text);
  const matches = Object.entries(DOCUMENT_KEYWORDS).map(([documentType, keywords]) => ({
    documentType,
    score: keywords.filter((keyword) => normalizedText.includes(normalizeText(keyword))).length
  }));
  const best = matches.sort((a, b) => b.score - a.score)[0];
  return best && best.score > 0 ? best.documentType : kind;
}

function inferredTypeMatches(expected: DriverDocumentKind, inferred: string | undefined): boolean {
  if (!inferred) return false;
  if (expected === inferred) return true;
  if (expected === "vehicleInspection" && inferred === "registration") return false;
  return expected === "driverLicense" && ["identity", "stateId"].includes(inferred);
}

function requiredDriverFieldsPresent(kind: DriverDocumentKind, fields: ExtractedFields): boolean {
  switch (kind) {
    case "driverLicense":
      return Boolean(fields.name && fields.expirationDate && (fields.licenseNumber || fields.dateOfBirth));
    case "insurance":
      return Boolean(fields.insurancePolicyNumber && fields.expirationDate);
    case "registration":
      return Boolean(fields.expirationDate && (fields.vin || fields.plateNumber));
    case "vehicleInspection":
      return Boolean(fields.expirationDate || fields.vin || fields.plateNumber);
  }
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
  profile: DriverProfile,
  kind: DriverDocumentKind
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

  if (kind === "insurance" && !expectedVin && !expectedPlate) {
    return { matched: true, reason: "" };
  }

  return {
    matched: false,
    reason: "No matching VIN or plate number could be confirmed against the driver vehicle profile."
  };
}

async function loadDriverProfile(uid: string): Promise<DriverProfile> {
  const snap = await db.collection("drivers").doc(uid).get();
  const data = snap.data() ?? {};
  const vehicle = asRecord(data.vehicle);
  const license = asRecord(data.license);
  return {
    firstName: asString(data.firstName),
    lastName: asString(data.lastName),
    dob: asDate(data.dob),
    licenseNumber: asString(license.number) ?? asString(data.licenseNumber) ?? asString(data.driverLicenseNumber),
    licenseState: asString(license.state) ?? asString(data.licenseState),
    vehicleVin: asString(vehicle.vin) ?? asString(data.vin),
    vehiclePlate: asString(vehicle.plate) ?? asString(data.plate) ?? asString(data.licensePlate)
  };
}

async function detectDocumentText(gcsUri: string): Promise<string> {
  const accessToken = await getCloudFunctionsAccessToken();
  if (!accessToken) {
    throw new Error("Could not acquire Google Cloud access token for Vision OCR.");
  }

  const response = await fetch("https://vision.googleapis.com/v1/images:annotate", {
    method: "POST",
    headers: {
      authorization: `Bearer ${accessToken}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      requests: [
        {
          image: { source: { imageUri: gcsUri } },
          features: [{ type: "DOCUMENT_TEXT_DETECTION" }]
        }
      ]
    })
  });

  const payload = (await response.json()) as VisionAnnotateResponse;
  if (!response.ok) {
    throw new Error(payload.error?.message ?? `Vision OCR failed with HTTP ${response.status}`);
  }

  const first = payload.responses?.[0];
  if (first?.error?.message) {
    throw new Error(first.error.message);
  }

  return first?.fullTextAnnotation?.text?.trim()
    ?? first?.textAnnotations?.[0]?.description?.trim()
    ?? "";
}

async function getCloudFunctionsAccessToken(): Promise<string | null> {
  const response = await fetch(METADATA_TOKEN_URL, {
    headers: { "Metadata-Flavor": "Google" }
  });
  if (!response.ok) {
    throw new Error(`Metadata token request failed with HTTP ${response.status}`);
  }

  const payload = (await response.json()) as { access_token?: string };
  return payload.access_token ?? null;
}

async function writePendingReview(
  parsed: ParsedDocumentPath,
  reviewId: string,
  bucket: string,
  generation: string | null,
  downloadURL: string | null
): Promise<void> {
  const now = FieldValue.serverTimestamp();
  const payload = {
    documentType: parsed.kind,
    storagePath: parsed.storagePath,
    downloadURL,
    storageBucket: bucket,
    generation,
    status: "pending" as ReviewStatus,
    reviewReason: "Document uploaded. OCR review pending.",
    createdAt: now,
    reviewedAt: null
  };

  if (parsed.ownerType === "driver") {
    const driverRef = db.collection("drivers").doc(parsed.uid);
    const batch = db.batch();
    batch.set(driverRef.collection("documentReviews").doc(reviewId), payload, { merge: true });
    batch.set(
      driverRef,
      {
        [`documents.${parsed.kind}.status`]: "pending",
        [`documents.${parsed.kind}.reviewReason`]: "Document uploaded. OCR review pending.",
        [`documents.${parsed.kind}.reviewId`]: reviewId,
        [`documents.${parsed.kind}.lastUploadedSide`]: parsed.side,
        [`documents.${parsed.kind}.storagePath`]: parsed.storagePath,
        [`documents.${parsed.kind}.downloadURL`]: downloadURL,
        ...sideSpecificDocumentPointers(parsed, downloadURL),
        ...legacyDriverDocumentImagePointers(parsed, downloadURL),
        updatedAt: now
      },
      { merge: true }
    );
    await batch.commit();
  } else {
    const riderRef = db.collection("riders").doc(parsed.uid);
    const batch = db.batch();
    batch.set(riderRef.collection("documentReviews").doc(reviewId), payload, { merge: true });
    batch.set(
      riderRef,
      {
        documentReviewStatus: "pending",
        [`verificationDocuments.${parsed.kind}.status`]: "pending",
        [`verificationDocuments.${parsed.kind}.reviewReason`]: "Document uploaded. OCR review pending.",
        [`verificationDocuments.${parsed.kind}.reviewId`]: reviewId,
        [`verificationDocuments.${parsed.kind}.storagePath`]: parsed.storagePath,
        [`verificationDocuments.${parsed.kind}.downloadURL`]: downloadURL,
        updatedAt: now
      },
      { merge: true }
    );
    await batch.commit();
  }
}

async function writeFinalReview(
  parsed: ParsedDocumentPath,
  options: {
    bucket: string;
    generation: string | null;
    downloadURL: string | null;
    reviewId: string;
    extractedText: string;
    extractedFields: ExtractedFields;
    decision: ReviewDecision;
  }
): Promise<void> {
  const now = FieldValue.serverTimestamp();
  const extractedText = truncate(options.extractedText, MAX_STORED_OCR_CHARS);
  const reviewPayload = {
    documentType: options.extractedFields.documentType ?? parsed.kind,
    storagePath: parsed.storagePath,
    downloadURL: options.downloadURL,
    storageBucket: options.bucket,
    generation: options.generation,
    extractedText,
    extractedTextHash: options.extractedText ? createHash("sha256").update(options.extractedText).digest("hex") : null,
    extractedFields: options.extractedFields,
    status: options.decision.status,
    reviewReason: options.decision.reviewReason,
    checks: options.decision.checks,
    visionFeature: "DOCUMENT_TEXT_DETECTION",
    reviewedByAutomation: true,
    reviewedAt: now,
    updatedAt: now
  };

  const batch = db.batch();

  if (parsed.ownerType === "driver") {
    const driverRef = db.collection("drivers").doc(parsed.uid);
    batch.set(driverRef.collection("documentReviews").doc(options.reviewId), reviewPayload, { merge: true });
    batch.set(
      driverRef,
      {
        [`documents.${parsed.kind}.status`]: options.decision.status,
        [`documents.${parsed.kind}.reviewReason`]: options.decision.reviewReason,
        [`documents.${parsed.kind}.reviewId`]: options.reviewId,
        [`documents.${parsed.kind}.lastUploadedSide`]: parsed.side,
        [`documents.${parsed.kind}.storagePath`]: parsed.storagePath,
        [`documents.${parsed.kind}.downloadURL`]: options.downloadURL,
        ...sideSpecificDocumentPointers(parsed, options.downloadURL),
        ...legacyDriverDocumentImagePointers(parsed, options.downloadURL),
        [`documents.${parsed.kind}.extractedFields`]: options.extractedFields,
        [`documents.${parsed.kind}.reviewedAt`]: now,
        updatedAt: now
      },
      { merge: true }
    );
  } else {
    const riderRef = db.collection("riders").doc(parsed.uid);
    batch.set(riderRef.collection("documentReviews").doc(options.reviewId), reviewPayload, { merge: true });
    batch.set(
      riderRef,
      {
        identityStatus: "pending_manual_review",
        documentReviewStatus: options.decision.status,
        verifiedRider: false,
        [`verificationDocuments.${parsed.kind}.status`]: options.decision.status,
        [`verificationDocuments.${parsed.kind}.reviewReason`]: options.decision.reviewReason,
        [`verificationDocuments.${parsed.kind}.reviewId`]: options.reviewId,
        [`verificationDocuments.${parsed.kind}.storagePath`]: parsed.storagePath,
        [`verificationDocuments.${parsed.kind}.downloadURL`]: options.downloadURL,
        [`verificationDocuments.${parsed.kind}.extractedFields`]: options.extractedFields,
        [`verificationDocuments.${parsed.kind}.reviewedAt`]: now,
        updatedAt: now
      },
      { merge: true }
    );
  }

  await batch.commit();
}

function extractName(text: string): string | undefined {
  const patterns = [
    /\b(?:name|insured|operator)\s*[:#]?\s*([A-Z][A-Z.'-]+(?:\s+[A-Z][A-Z.'-]+){1,3})\b/i,
    /\b([A-Z][A-Z.'-]+,\s*[A-Z][A-Z.'-]+(?:\s+[A-Z][A-Z.'-]+)?)\b/
  ];
  for (const pattern of patterns) {
    const match = text.match(pattern)?.[1];
    if (match) return match.replace(",", " ").replace(/\s+/g, " ").trim();
  }
  return undefined;
}

function extractDateOfBirth(text: string): string | undefined {
  return extractLabeledDate(text, ["date of birth", "dob", "birth date", "dbb"]);
}

function extractExpirationDate(text: string): string | undefined {
  return extractLabeledDate(text, ["expiration", "expires", "exp", "exp date", "valid until", "dba"]);
}

function extractLicenseNumber(text: string): string | undefined {
  return extractLabeledValue(text, [
    "license no",
    "license number",
    "lic no",
    "lic",
    "dl no",
    "driver license",
    "daq"
  ], /[A-Z0-9-]{5,20}/i);
}

function extractPolicyNumber(text: string): string | undefined {
  return extractLabeledValue(text, ["policy number", "policy no", "policy", "pol no"], /[A-Z0-9-]{5,30}/i);
}

function extractVin(text: string): string | undefined {
  const labeled = extractLabeledValue(text, ["vin", "vehicle identification number"], /[A-HJ-NPR-Z0-9]{17}/i);
  if (labeled) return labeled.toUpperCase();
  return text.match(/\b[A-HJ-NPR-Z0-9]{17}\b/i)?.[0]?.toUpperCase();
}

function extractPlateNumber(text: string): string | undefined {
  return extractLabeledValue(text, ["plate", "plate no", "tag", "tag no", "license plate"], /[A-Z0-9-]{2,10}/i);
}

function extractState(text: string): string | undefined {
  const labeled = extractLabeledValue(text, ["state", "st"], /[A-Z]{2}/i);
  if (labeled && US_STATE_CODES.has(labeled.toUpperCase())) return labeled.toUpperCase();
  const state = text.match(/\b(AL|AK|AZ|AR|CA|CO|CT|DE|FL|GA|HI|IA|ID|IL|IN|KS|KY|LA|MA|MD|ME|MI|MN|MO|MS|MT|NC|ND|NE|NH|NJ|NM|NV|NY|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VA|VT|WA|WI|WV|WY|DC)\b/i)?.[1];
  return state?.toUpperCase();
}

function extractLabeledDate(text: string, labels: string[]): string | undefined {
  for (const label of labels) {
    const value = extractLabeledValue(text, [label], /\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}[/-]\d{1,2}[/-]\d{1,2}|[A-Z]{3,9}\s+\d{1,2},?\s+\d{4}/i);
    const parsed = value ? parseDate(value) : null;
    if (parsed) return formatDate(parsed);
  }
  return undefined;
}

function extractLabeledValue(text: string, labels: string[], valuePattern: RegExp): string | undefined {
  const escapedLabels = labels.map((label) => label.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|");
  const pattern = new RegExp(`(?:${escapedLabels})\\s*[:#]?\\s*(${valuePattern.source})`, "i");
  return text.match(pattern)?.[1]?.trim();
}

function parseAamvaDate(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const compact = value.replace(/\D/g, "");
  if (compact.length === 8) {
    const month = Number(compact.slice(0, 2));
    const day = Number(compact.slice(2, 4));
    const year = Number(compact.slice(4, 8));
    const date = new Date(Date.UTC(year, month - 1, day));
    if (date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day) {
      return formatDate(date);
    }
  }
  return formatDate(parseDate(value));
}

function parseDate(value: string | undefined | null): Date | null {
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

function formatDate(date: Date | null): string | undefined {
  if (!date) return undefined;
  return date.toISOString().slice(0, 10);
}

function startOfToday(): Date {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
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

function compactFields<T extends Record<string, unknown>>(fields: T): T {
  return Object.fromEntries(Object.entries(fields).filter(([, value]) => value !== undefined && value !== null && value !== "")) as T;
}

function decodeStoragePath(rawPath: string): string {
  try {
    return decodeURIComponent(rawPath);
  } catch {
    return rawPath;
  }
}

function sideFromFileName(fileName: string): ParsedDocumentPath["side"] {
  const prefix = fileName.split("-")[0]?.split(".")[0]?.trim();
  if (prefix === "front" || prefix === "back") return prefix;
  return prefix || "single";
}

function documentReviewId(bucket: string, storagePath: string): string {
  return createHash("sha256").update(`${bucket}/${storagePath}`).digest("hex");
}

function downloadURLForObject(
  bucket: string,
  storagePath: string,
  metadata: Record<string, string> | undefined
): string | null {
  const token = metadata?.firebaseStorageDownloadTokens?.split(",")[0]?.trim();
  if (!token) return null;
  return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(storagePath)}?alt=media&token=${token}`;
}

function sideSpecificDocumentPointers(parsed: ParsedDocumentPath, downloadURL: string | null): Record<string, string | null> {
  if (parsed.side === "front") {
    return {
      [`documents.${parsed.kind}.frontPath`]: parsed.storagePath,
      [`documents.${parsed.kind}.frontURL`]: downloadURL
    };
  }
  if (parsed.side === "back") {
    return {
      [`documents.${parsed.kind}.backPath`]: parsed.storagePath,
      [`documents.${parsed.kind}.backURL`]: downloadURL
    };
  }
  return {
    [`documents.${parsed.kind}.documentPath`]: parsed.storagePath,
    [`documents.${parsed.kind}.documentURL`]: downloadURL
  };
}

function legacyDriverDocumentImagePointers(parsed: ParsedDocumentPath, downloadURL: string | null): Record<string, string | null> {
  if (parsed.ownerType !== "driver" || parsed.side === "back") return {};

  if (parsed.kind === "driverLicense") {
    return { "license.imageUrl": downloadURL };
  }
  if (parsed.kind === "insurance") {
    return { "vehicle.insuranceImageUrl": downloadURL };
  }
  if (parsed.kind === "registration") {
    return { "vehicle.registrationImageUrl": downloadURL };
  }

  return {};
}

function truncate(value: string, maxLength: number): string {
  return value.length > maxLength ? value.slice(0, maxLength) : value;
}

function normalizeText(value: string): string {
  return value.toLowerCase().replace(/\s+/g, " ").trim();
}

function normalizeNamePart(value: string): string {
  return value.toLowerCase().replace(/[^a-z]/g, "");
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
