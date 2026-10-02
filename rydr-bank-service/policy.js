import { createHmac, timingSafeEqual } from "node:crypto";

function policyError(code, statusCode = 400) {
  const error = new Error(code);
  error.statusCode = statusCode;
  return error;
}

function finiteNonNegative(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

export function completedRideEvidence(ride, callerUid) {
  if (!ride || typeof ride !== "object") throw policyError("ride_not_found", 404);
  if (ride.riderId !== callerUid) throw policyError("not_ride_rider", 403);
  if (ride.status !== "completed") throw policyError("ride_not_completed", 409);
  const backendFinalized = ride.lifecycleOwner === "backend"
    && ride.financialOutcomeStatus === "finalized";
  if (!backendFinalized && ride.hasFinancialOutcome !== true) {
    throw policyError("ride_not_backend_finalized", 409);
  }

  const distanceMi = [
    ride.actualDistanceMiles,
    ride.backendActualDistanceMiles,
    ride.backendDistanceMiles,
    ride.estimatedDistanceMiles,
    ride.distanceMiles,
  ].map(finiteNonNegative).find((value) => value !== null);
  if (distanceMi === undefined) throw policyError("ride_distance_unavailable", 409);

  const rideType = typeof ride.rideType === "string" ? ride.rideType.trim() : "";
  if (!rideType) throw policyError("ride_type_unavailable", 409);
  return { distanceMi, rideType };
}

function base64urlDecode(value) {
  try {
    return Buffer.from(value, "base64url");
  } catch {
    throw policyError("invalid_booking_token", 401);
  }
}

function constantTimeEqual(left, right) {
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  return a.length === b.length && timingSafeEqual(a, b);
}

function normalizeEmail(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

export function verifyWebBookingToken({ token, secret, expected, nowSeconds = Math.floor(Date.now() / 1000) }) {
  if (!secret) throw policyError("web_booking_not_configured", 503);
  if (typeof token !== "string" || !token.includes(".")) throw policyError("missing_booking_token", 401);
  const [encodedPayload, suppliedSignature, ...extra] = token.split(".");
  if (!encodedPayload || !suppliedSignature || extra.length) throw policyError("invalid_booking_token", 401);

  const expectedSignature = createHmac("sha256", secret).update(encodedPayload).digest("base64url");
  if (!constantTimeEqual(suppliedSignature, expectedSignature)) throw policyError("invalid_booking_token", 401);

  let claims;
  try {
    claims = JSON.parse(base64urlDecode(encodedPayload).toString("utf8"));
  } catch {
    throw policyError("invalid_booking_token", 401);
  }

  if (!Number.isFinite(claims.exp) || claims.exp < nowSeconds) throw policyError("expired_booking_token", 401);
  if (claims.exp > nowSeconds + 15 * 60) throw policyError("invalid_booking_token_expiry", 401);

  const comparisons = {
    action: String(expected.action || ""),
    code: String(expected.code || ""),
    email: normalizeEmail(expected.email),
    bookingId: String(expected.bookingId || ""),
    rideId: String(expected.rideId || ""),
    rideType: String(expected.rideType || ""),
    distanceMi: finiteNonNegative(expected.distanceMi),
  };
  const claimValues = {
    action: String(claims.action || ""),
    code: String(claims.code || ""),
    email: normalizeEmail(claims.email),
    bookingId: String(claims.bookingId || ""),
    rideId: String(claims.rideId || ""),
    rideType: String(claims.rideType || ""),
    distanceMi: finiteNonNegative(claims.distanceMi),
  };

  for (const key of Object.keys(comparisons)) {
    if (comparisons[key] !== claimValues[key]) throw policyError("booking_token_mismatch", 403);
  }
  return claims;
}

export function createWebBookingTokenForTest(claims, secret) {
  const encodedPayload = Buffer.from(JSON.stringify(claims)).toString("base64url");
  const signature = createHmac("sha256", secret).update(encodedPayload).digest("base64url");
  return `${encodedPayload}.${signature}`;
}

export { normalizeEmail, policyError };
