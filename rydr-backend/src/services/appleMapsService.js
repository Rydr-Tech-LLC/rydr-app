const crypto = require("node:crypto");

const APPLE_MAPS_ROOT = "https://maps-api.apple.com/v1";
const DEVELOPER_TOKEN_TTL_SECONDS = 15 * 60;
const ACCESS_TOKEN_REFRESH_BUFFER_SECONDS = 60;

let accessTokenCache = null;

function buildError(message, statusCode = 500, details = undefined) {
  const error = new Error(message);
  error.statusCode = statusCode;
  if (details) error.details = details;
  return error;
}

function appleMapsConfig() {
  const teamId = String(process.env.APPLE_MAPS_TEAM_ID || "").trim();
  const keyId = String(process.env.APPLE_MAPS_KEY_ID || "").trim();
  const privateKey = String(process.env.APPLE_MAPS_PRIVATE_KEY || "").replace(/\\n/g, "\n").trim();

  const missing = [];
  if (!teamId) missing.push("APPLE_MAPS_TEAM_ID");
  if (!keyId) missing.push("APPLE_MAPS_KEY_ID");
  if (!privateKey) missing.push("APPLE_MAPS_PRIVATE_KEY");
  if (missing.length > 0) {
    throw buildError("Apple Maps Server API is not configured.", 503, { missing });
  }

  return { teamId, keyId, privateKey };
}

function base64UrlJson(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function createDeveloperToken(options = {}) {
  const config = options.config || appleMapsConfig();
  const nowSeconds = options.nowSeconds || Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: config.keyId, typ: "JWT" };
  const payload = {
    iss: config.teamId,
    iat: nowSeconds,
    exp: nowSeconds + DEVELOPER_TOKEN_TTL_SECONDS,
    scope: "server_api"
  };
  const unsignedToken = `${base64UrlJson(header)}.${base64UrlJson(payload)}`;

  let signature;
  try {
    signature = crypto.sign("sha256", Buffer.from(unsignedToken), {
      key: config.privateKey,
      dsaEncoding: "ieee-p1363"
    });
  } catch (error) {
    throw buildError("APPLE_MAPS_PRIVATE_KEY is not a valid Apple Maps .p8 key.", 503);
  }

  return `${unsignedToken}.${signature.toString("base64url")}`;
}

async function parseAppleResponse(response) {
  const text = await response.text();
  let body = {};
  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      body = {};
    }
  }

  if (!response.ok) {
    const message = body.message || body.error || "Apple Maps request failed.";
    const statusCode = response.status === 429 ? 503 : response.status;
    throw buildError(message, statusCode, {
      provider: "apple_maps",
      upstreamStatus: response.status,
      upstreamStatusText: response.statusText,
      upstreamDetails: body.details
    });
  }

  return body;
}

async function getAccessToken(options = {}) {
  const fetchImpl = options.fetchImpl || globalThis.fetch;
  const config = options.config || appleMapsConfig();
  const nowMillis = options.nowMillis || Date.now();
  const cacheKey = `${config.teamId}:${config.keyId}`;

  if (
    !options.forceRefresh &&
    accessTokenCache?.cacheKey === cacheKey &&
    accessTokenCache.expiresAtMillis > nowMillis + ACCESS_TOKEN_REFRESH_BUFFER_SECONDS * 1000
  ) {
    return accessTokenCache.token;
  }

  const developerToken = createDeveloperToken({
    config,
    nowSeconds: Math.floor(nowMillis / 1000)
  });
  const response = await fetchImpl(`${APPLE_MAPS_ROOT}/token`, {
    headers: { Authorization: `Bearer ${developerToken}` }
  });
  const payload = await parseAppleResponse(response);
  if (!payload.accessToken) {
    throw buildError("Apple Maps did not return an access token.", 502);
  }

  const expiresInSeconds = Math.max(1, Number(payload.expiresInSeconds) || 1800);
  accessTokenCache = {
    cacheKey,
    token: payload.accessToken,
    expiresAtMillis: nowMillis + expiresInSeconds * 1000
  };
  return payload.accessToken;
}

function coordinateString(coordinate) {
  return `${coordinate.latitude},${coordinate.longitude}`;
}

async function appleMapsFetch(path, params, options = {}) {
  const fetchImpl = options.fetchImpl || globalThis.fetch;
  const accessToken = await getAccessToken({ fetchImpl });
  const url = new URL(`${APPLE_MAPS_ROOT}${path}`);
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== "") {
      url.searchParams.set(key, String(value));
    }
  });

  let response = await fetchImpl(url, {
    headers: { Authorization: `Bearer ${accessToken}` }
  });
  if (response.status === 401) {
    const refreshedToken = await getAccessToken({ fetchImpl, forceRefresh: true });
    response = await fetchImpl(url, {
      headers: { Authorization: `Bearer ${refreshedToken}` }
    });
  }
  return parseAppleResponse(response);
}

function normalizeRoute(payload, route) {
  const steps = (route.stepIndexes || [])
    .map((index) => payload.steps?.[index])
    .filter(Boolean)
    .map((step) => ({
      instructions: step.instructions || "",
      distanceMeters: Number(step.distanceMeters) || 0,
      durationSeconds: Number(step.durationSeconds) || 0,
      path: payload.stepPaths?.[step.stepPathIndex] || []
    }));

  const polyline = [];
  steps.forEach((step) => {
    step.path.forEach((point) => {
      const previous = polyline[polyline.length - 1];
      if (!previous || previous.latitude !== point.latitude || previous.longitude !== point.longitude) {
        polyline.push(point);
      }
    });
  });

  const distanceMeters = Number(route.distanceMeters) || 0;
  const durationSeconds = Number(route.durationSeconds) || 0;
  return {
    name: route.name || null,
    distanceMeters,
    distanceMiles: distanceMeters / 1609.344,
    durationSeconds,
    durationMinutes: durationSeconds / 60,
    transportType: route.transportType || "AUTOMOBILE",
    hasTolls: route.hasTolls ?? null,
    steps,
    polyline
  };
}

async function getDirections({ origin, destination, departureDate, requestsAlternateRoutes = false }, options = {}) {
  const payload = await appleMapsFetch("/directions", {
    origin: coordinateString(origin),
    destination: coordinateString(destination),
    departureDate,
    transportType: "Automobile",
    requestsAlternateRoutes,
    lang: "en-US"
  }, options);

  const routes = (payload.routes || []).map((route) => normalizeRoute(payload, route));
  if (routes.length === 0) throw buildError("Apple Maps could not find a route.", 422);
  return {
    provider: "apple_maps",
    calculatedAt: new Date().toISOString(),
    origin: payload.origin || origin,
    destination: payload.destination || destination,
    route: routes[0],
    alternateRoutes: routes.slice(1)
  };
}

function resetAccessTokenCache() {
  accessTokenCache = null;
}

module.exports = {
  createDeveloperToken,
  getAccessToken,
  getDirections,
  normalizeRoute,
  resetAccessTokenCache
};
