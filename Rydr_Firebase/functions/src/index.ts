import { onCall, HttpsError } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";
import { db, FieldValue } from "./admin";
import { vehicleDecoderService, VinDecodeError } from "./services/vehicleDecoderService";
import { vehicleImageService } from "./services/vehicleImageService";
import { VEHICLE_COLORS, type VehicleColor, type VehicleBodyStyle } from "./types";

// Push notification sender architecture (Part 9 of the beta hardening
// sprint). Each trigger below listens to the same Firestore documents the
// rider/driver apps and Mission Control already write/read, so every
// notification is a reflection of real, persisted server state.
export { onRideUpdated } from "./triggers/rideNotifications";
export { onSupportMessageCreated } from "./triggers/supportNotifications";
export { onDriverApprovalDecision } from "./triggers/driverApprovalNotifications";

const VEHICLE_BODY_STYLES: readonly VehicleBodyStyle[] = [
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

function asBodyStyle(value: unknown): VehicleBodyStyle | null {
  return typeof value === "string" && (VEHICLE_BODY_STYLES as readonly string[]).includes(value)
    ? (value as VehicleBodyStyle)
    : null;
}

setGlobalOptions({ region: "us-central1", maxInstances: 20 });

function requireAuth(auth: { uid: string } | undefined): { uid: string } {
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign in is required to use the Vehicle Library System.");
  }
  return auth;
}

function isValidColor(color: unknown): color is VehicleColor {
  return typeof color === "string" && (VEHICLE_COLORS as readonly string[]).includes(color);
}

/**
 * Decodes a VIN via NHTSA (cached in Firestore — see VehicleDecoderService).
 * Callable from both iOS apps and Mission Control (any signed-in user;
 * decoding a VIN reveals nothing sensitive — it's public vehicle spec data).
 *
 * Request:  { vin: string, forceRefresh?: boolean }
 * Response: VinDecodeCacheEntry
 */
export const decodeVin = onCall(async (request) => {
  requireAuth(request.auth);
  const vin = request.data?.vin;
  if (typeof vin !== "string" || vin.trim().length === 0) {
    throw new HttpsError("invalid-argument", "A `vin` string is required.");
  }

  try {
    return await vehicleDecoderService.decode(vin, { forceRefresh: Boolean(request.data?.forceRefresh) });
  } catch (err) {
    if (err instanceof VinDecodeError) {
      const code = err.code === "invalid_vin" ? "invalid-argument" : "unavailable";
      throw new HttpsError(code, err.message);
    }
    throw new HttpsError("internal", "VIN decode failed unexpectedly.");
  }
});

/**
 * Resolves the best matching vehicle image for a make/model/year/color
 * (+ optional trim/body style), running the 5-tier fallback chain via
 * VehicleImageService. Returns `status: "missing"` (never throws) when no
 * image exists anywhere in the chain, so callers can render a local icon.
 *
 * Request:  { make, model, year, color, trim?, bodyStyle? }
 * Response: VehicleImageLookup
 */
export const getVehicleImage = onCall(async (request) => {
  requireAuth(request.auth);
  const { make, model, year, color, trim, bodyStyle } = request.data ?? {};
  if (!make || !model || !year || !color) {
    throw new HttpsError("invalid-argument", "`make`, `model`, `year`, and `color` are required.");
  }
  if (!isValidColor(color)) {
    throw new HttpsError("invalid-argument", `"${color}" is not one of the supported vehicle colors.`);
  }

  return vehicleImageService.getImage({
    make: String(make),
    model: String(model),
    year: Number(year),
    color,
    trim: trim ? String(trim) : null,
    bodyStyle: bodyStyle ?? null
  });
});

/**
 * The single end-to-end entry point for the driver app's "enter VIN, pick
 * color" flow: decodes the VIN, resolves the matching image, and writes
 * every resulting field onto `drivers/{uid}.vehicle` in one atomic update
 * — so the client never has to orchestrate multiple writes or risk a
 * half-decoded vehicle record. Only the calling driver may submit for
 * their own uid.
 *
 * Request:  { vin: string, color: string }
 * Response: { vehicle: {...fields written...}, vinDecodeStatus, vehicleImageStatus }
 */
export const submitVehicleVin = onCall(async (request) => {
  const auth = requireAuth(request.auth);
  const vin = request.data?.vin;
  const color = request.data?.color;

  if (typeof vin !== "string" || vin.trim().length === 0) {
    throw new HttpsError("invalid-argument", "A `vin` string is required.");
  }
  if (!isValidColor(color)) {
    throw new HttpsError("invalid-argument", `A valid \`color\` is required (one of: ${VEHICLE_COLORS.join(", ")}).`);
  }

  const driverRef = db.collection("drivers").doc(auth.uid);

  let decoded;
  try {
    decoded = await vehicleDecoderService.decode(vin);
  } catch (err) {
    await driverRef.set(
      { vinDecodeStatus: "failed", vehicleImageStatus: "missing", updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    if (err instanceof VinDecodeError) {
      const code = err.code === "invalid_vin" ? "invalid-argument" : "unavailable";
      throw new HttpsError(code, err.message);
    }
    throw new HttpsError("internal", "VIN decode failed unexpectedly.");
  }

  if (!decoded.make || !decoded.model || !decoded.modelYear) {
    await driverRef.set(
      { vinDecodeStatus: "failed", vehicleImageStatus: "missing", updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
    throw new HttpsError("failed-precondition", "NHTSA could not determine the make/model/year for this VIN.");
  }

  const lookup = await vehicleImageService.getImage({
    make: decoded.make,
    model: decoded.model,
    year: decoded.modelYear,
    trim: decoded.trim,
    bodyStyle: decoded.bodyStyle,
    color
  });

  const vehicleFields = {
    vin: decoded.vin,
    make: decoded.make,
    model: decoded.model,
    year: decoded.modelYear,
    trim: decoded.trim,
    bodyStyle: decoded.bodyStyle,
    driveType: decoded.driveType,
    fuelType: decoded.fuelTypePrimary,
    color,
    imagePath: lookup.result?.storagePath ?? null,
    imageUrl: lookup.result?.imageUrl ?? null,
    imageMatchTier: lookup.result?.tier ?? null
  };

  await driverRef.set(
    {
      vehicle: vehicleFields,
      vinDecodeStatus: "decoded",
      vehicleImageStatus: lookup.status,
      updatedAt: FieldValue.serverTimestamp()
    },
    { merge: true }
  );

  return { vehicle: vehicleFields, vinDecodeStatus: "decoded", vehicleImageStatus: lookup.status };
});

/**
 * Fallback entry point for the driver app's "Decode Vehicle" flow when VIN
 * decoding fails (NHTSA has no data for the VIN, the VIN is unreadable on
 * the registration, etc.). The driver types in make/model/year (and
 * optionally trim/body style) themselves instead of having them pulled from
 * NHTSA; everything downstream (image matching, eligibility, the written
 * `drivers/{uid}.vehicle` record) is identical to the VIN path, just with
 * `vinDecodeStatus: "manual"` so Mission Control can flag manually-entered
 * vehicles for a quick human review.
 *
 * Request:  { vin?: string, make, model, year, color, trim?, bodyStyle?, driveType?, fuelType? }
 * Response: { vehicle: {...fields written...}, vinDecodeStatus, vehicleImageStatus }
 */
export const submitVehicleManual = onCall(async (request) => {
  const auth = requireAuth(request.auth);
  const data = request.data ?? {};
  const make = typeof data.make === "string" ? data.make.trim() : "";
  const model = typeof data.model === "string" ? data.model.trim() : "";
  const yearNum = Number(data.year);
  const color = data.color;

  if (!make || !model || !Number.isFinite(yearNum) || yearNum < 1980) {
    throw new HttpsError("invalid-argument", "Valid `make`, `model`, and `year` are required.");
  }
  if (!isValidColor(color)) {
    throw new HttpsError("invalid-argument", `A valid \`color\` is required (one of: ${VEHICLE_COLORS.join(", ")}).`);
  }

  const trim = typeof data.trim === "string" && data.trim.trim().length > 0 ? data.trim.trim() : null;
  const bodyStyle = asBodyStyle(data.bodyStyle);
  const driveType = typeof data.driveType === "string" && data.driveType.trim().length > 0 ? data.driveType.trim() : null;
  const fuelType = typeof data.fuelType === "string" && data.fuelType.trim().length > 0 ? data.fuelType.trim() : null;
  const vin = typeof data.vin === "string" && data.vin.trim().length > 0 ? data.vin.trim().toUpperCase() : null;

  const driverRef = db.collection("drivers").doc(auth.uid);

  const lookup = await vehicleImageService.getImage({
    make,
    model,
    year: yearNum,
    trim,
    bodyStyle,
    color
  });

  const vehicleFields = {
    vin,
    make,
    model,
    year: yearNum,
    trim,
    bodyStyle,
    driveType,
    fuelType,
    color,
    imagePath: lookup.result?.storagePath ?? null,
    imageUrl: lookup.result?.imageUrl ?? null,
    imageMatchTier: lookup.result?.tier ?? null
  };

  await driverRef.set(
    {
      vehicle: vehicleFields,
      vinDecodeStatus: "manual",
      vehicleImageStatus: lookup.status,
      updatedAt: FieldValue.serverTimestamp()
    },
    { merge: true }
  );

  return { vehicle: vehicleFields, vinDecodeStatus: "manual", vehicleImageStatus: lookup.status };
});
