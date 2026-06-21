const DISCOVERY_ROOT = "https://app.ticketmaster.com/discovery/v2";
const DEFAULT_CITY = "Atlanta";
const DEFAULT_STATE = "GA";
const DEFAULT_COUNTRY = "US";

const categoryMap = {
  all: undefined,
  featured: undefined,
  music: "Music",
  sports: "Sports",
  arts: "Arts & Theatre",
  family: "Family",
  comedy: "Comedy",
  festivals: "Festival"
};

function getAPIKey() {
  return process.env.TICKETMASTER_API_KEY;
}

function buildError(message, statusCode = 500, details = undefined) {
  const error = new Error(message);
  error.statusCode = statusCode;
  if (details) {
    error.details = details;
  }
  return error;
}

function firstVenue(event) {
  return event?._embedded?.venues?.[0] || {};
}

function bestImage(images = []) {
  if (!Array.isArray(images) || images.length === 0) {
    return null;
  }

  const preferred = images.find((image) => image.ratio === "16_9" && image.width >= 640);
  const largest = images
    .filter((image) => image.url)
    .sort((a, b) => (b.width || 0) * (b.height || 0) - (a.width || 0) * (a.height || 0))[0];

  return (preferred || largest || images[0]).url || null;
}

function priceSummary(event) {
  const range = Array.isArray(event.priceRanges) ? event.priceRanges[0] : null;
  if (!range) {
    return null;
  }

  return {
    min: typeof range.min === "number" ? range.min : null,
    max: typeof range.max === "number" ? range.max : null,
    currency: range.currency || "USD"
  };
}

function normalizeEvent(event) {
  const venue = firstVenue(event);
  const classification = event.classifications?.[0] || {};
  const segmentName = classification.segment?.name;
  const genreName = classification.genre?.name;
  const localDate = event.dates?.start?.localDate || null;
  const localTime = event.dates?.start?.localTime || null;
  const dateText = [localDate, localTime].filter(Boolean).join(" ");

  return {
    id: event.id,
    title: event.name,
    category: segmentName || genreName || "Event",
    genre: genreName || null,
    dateText,
    localDate,
    localTime,
    venueName: venue.name || "Venue TBA",
    city: venue.city?.name || DEFAULT_CITY,
    state: venue.state?.stateCode || DEFAULT_STATE,
    address: venue.address?.line1 || null,
    latitude: venue.location?.latitude ? Number(venue.location.latitude) : null,
    longitude: venue.location?.longitude ? Number(venue.location.longitude) : null,
    imageURL: bestImage(event.images),
    ticketURL: event.url || null,
    price: priceSummary(event)
  };
}

async function ticketmasterFetch(path, params) {
  const apiKey = getAPIKey();
  if (!apiKey) {
    throw buildError("Ticketmaster API key is not configured.", 503);
  }

  const url = new URL(`${DISCOVERY_ROOT}${path}`);
  url.searchParams.set("apikey", apiKey);

  Object.entries(params || {}).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== "") {
      url.searchParams.set(key, value);
    }
  });

  const response = await fetch(url);
  const responseText = await response.text();
  let body = {};

  if (responseText) {
    try {
      body = JSON.parse(responseText);
    } catch {
      body = {};
    }
  }

  if (!response.ok) {
    const message =
      body?.fault?.faultstring ||
      body?.fault?.faultstring?.message ||
      body?.message ||
      body?.error_description ||
      body?.error ||
      "Ticketmaster request failed.";

    throw buildError(message, response.status, {
      provider: "ticketmaster",
      upstreamStatus: response.status,
      upstreamStatusText: response.statusText,
      upstreamBody: responseText.slice(0, 500)
    });
  }

  return body;
}

async function getEvents(options = {}) {
  const categoryKey = String(options.category || "featured").toLowerCase();
  const size = Math.min(Math.max(Number(options.size) || 20, 1), 50);
  const city = options.city || DEFAULT_CITY;
  const stateCode = options.stateCode || DEFAULT_STATE;
  const classificationName = categoryMap[categoryKey];

  const payload = await ticketmasterFetch("/events.json", {
    city,
    stateCode,
    countryCode: options.countryCode || DEFAULT_COUNTRY,
    keyword: options.keyword,
    classificationName,
    size,
    sort: "date,asc"
  });

  const events = payload?._embedded?.events || [];
  return {
    city,
    stateCode,
    events: events.map(normalizeEvent).filter((event) => event.id && event.title)
  };
}

async function getEventById(id) {
  const payload = await ticketmasterFetch(`/events/${encodeURIComponent(id)}.json`);
  return payload?.id ? normalizeEvent(payload) : null;
}

module.exports = {
  getEvents,
  getEventById
};
