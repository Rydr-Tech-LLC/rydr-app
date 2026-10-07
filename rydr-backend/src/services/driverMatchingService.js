const { tierFor } = require("./rideFinancialService");

const DEFAULT_MAX_PICKUP_DISTANCE_MILES = 30;
const DEFAULT_RESULT_LIMIT = 20;
const LONG_RIDE_THRESHOLD_MILES = 15;
const SHORT_RIDE_FALLBACK_MILES = 11;

function coordinate(value) {
  if (!value || typeof value !== "object") return null;
  const latitude = Number(value.latitude ?? value.lat);
  const longitude = Number(value.longitude ?? value.lng);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
  return { latitude, longitude };
}

function profileCoordinate(profile) {
  return coordinate(profile?.approximateLocation)
    || coordinate(profile?.location)
    || coordinate(profile?.geoPoint)
    || coordinate(profile);
}

function distanceMiles(a, b) {
  if (!a || !b) return Number.POSITIVE_INFINITY;
  const radius = 3958.7613;
  const radians = (degrees) => degrees * Math.PI / 180;
  const dLat = radians(b.latitude - a.latitude);
  const dLng = radians(b.longitude - a.longitude);
  const h = Math.sin(dLat / 2) ** 2
    + Math.cos(radians(a.latitude)) * Math.cos(radians(b.latitude)) * Math.sin(dLng / 2) ** 2;
  return radius * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function canonicalRideTypes(profile) {
  const values = profile?.eligibleRideTypes
    ?? profile?.selectedRideTypes
    ?? profile?.rideTypes
    ?? profile?.supportedRideTypes
    ?? [];
  return new Set((Array.isArray(values) ? values : []).map(tierFor));
}

function temporarilyDisabled(profile, rideType) {
  const disabled = Array.isArray(profile?.temporarilyDisabledRideTypes)
    ? profile.temporarilyDisabledRideTypes
    : [];
  return disabled.some((value) => tierFor(value) === tierFor(rideType));
}

function project(point, referenceLatitude) {
  return {
    x: point.longitude * 69 * Math.cos(referenceLatitude * Math.PI / 180),
    y: point.latitude * 69
  };
}

function projectedRouteProgress(point, start, end) {
  const p = project(point, start.latitude);
  const a = project(start, start.latitude);
  const b = project(end, start.latitude);
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  if (dx === 0 && dy === 0) return 0;
  return ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy);
}

function distanceFromPointToSegmentMiles(point, start, end) {
  const progress = Math.max(0, Math.min(1, projectedRouteProgress(point, start, end)));
  const p = project(point, start.latitude);
  const a = project(start, start.latitude);
  const b = project(end, start.latitude);
  const projected = { x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress };
  return Math.hypot(p.x - projected.x, p.y - projected.y);
}

function preferenceMatch({ profile, driverCoordinate, pickup, dropoff, routeDistanceMiles }) {
  const filters = profile?.rideFilters;
  if (!filters || typeof filters !== "object") return "strict";

  if (filters.workZoneEnabled === true) {
    const radiusMiles = Number(filters.workZoneRadiusMiles);
    if (!Number.isFinite(radiusMiles) || radiusMiles <= 0) return "rejected";
    if (distanceMiles(driverCoordinate, pickup) > radiusMiles) return "rejected";
    if (!dropoff || distanceMiles(driverCoordinate, dropoff) > radiusMiles) return "rejected";
  }

  const wantsLong = filters.prioritizeLongerRides === true;
  const wantsShort = filters.prioritizeShorterRides === true || filters.avoidShortPickups === true;
  let match = "strict";
  if (wantsLong && !wantsShort && routeDistanceMiles < LONG_RIDE_THRESHOLD_MILES) return "rejected";
  if (wantsShort && !wantsLong) {
    if (routeDistanceMiles >= LONG_RIDE_THRESHOLD_MILES) return "rejected";
    if (routeDistanceMiles >= SHORT_RIDE_FALLBACK_MILES) match = "fallback";
  }

  if (filters.destinationModeEnabled !== true) return match;
  const destination = coordinate(filters.destinationCoordinate) || coordinate(filters.destinationGeoPoint);
  if (!destination || !dropoff) return "rejected";
  const progress = projectedRouteProgress(dropoff, driverCoordinate, destination);
  if (progress < 0 || progress > 1) return "rejected";
  const allowedCorridorMiles = Number.isFinite(Number(filters.destinationCorridorMiles))
    ? Number(filters.destinationCorridorMiles)
    : 5;
  const movesTowardDestination = distanceMiles(dropoff, destination) <= distanceMiles(pickup, destination);
  const staysInCorridor = distanceFromPointToSegmentMiles(dropoff, driverCoordinate, destination) <= allowedCorridorMiles;
  return movesTowardDestination && staysInCorridor ? match : "rejected";
}

function matchReasons(profile, match, distanceToPickupMiles) {
  const reasons = ["eligible"];
  if (Number(profile?.rating || 0) >= 4.8) reasons.push("high_rating");
  const filters = profile?.rideFilters;
  const hasActivePreference = filters?.workZoneEnabled === true
    || filters?.destinationModeEnabled === true
    || filters?.prioritizeLongerRides === true
    || filters?.prioritizeShorterRides === true
    || filters?.avoidShortPickups === true;
  if (match === "strict" && hasActivePreference) reasons.push("driver_preferences");
  if (profile?.rideFilters?.destinationModeEnabled === true) reasons.push("destination_corridor");
  if (distanceToPickupMiles <= 5) reasons.push("near_pickup");
  return reasons;
}

function findBestDrivers({
  rideType,
  pickupCoordinate,
  dropoffCoordinate,
  routeDistanceMiles,
  candidates,
  requireOnline = true,
  maxPickupDistanceMiles = DEFAULT_MAX_PICKUP_DISTANCE_MILES,
  maxResults = DEFAULT_RESULT_LIMIT
}) {
  const pickup = coordinate(pickupCoordinate);
  const dropoff = coordinate(dropoffCoordinate);
  const tripMiles = Number(routeDistanceMiles);
  if (!rideType || !pickup || !dropoff || !Number.isFinite(tripMiles) || tripMiles <= 0) return [];

  return (Array.isArray(candidates) ? candidates : [])
    .map((candidate) => ({ id: String(candidate?.id || candidate?.driverId || ""), profile: candidate?.profile || candidate }))
    .filter((candidate) => candidate.id && candidate.profile && candidate.profile.standardDispatchEnabled !== false)
    .filter((candidate) => !requireOnline || candidate.profile.isOnline === true)
    .filter((candidate) => !requireOnline || ["available", "onCurrentRide"].includes(String(candidate.profile.availabilityStatus || "available")))
    .filter((candidate) => {
      const types = canonicalRideTypes(candidate.profile);
      return (types.size === 0 || types.has(tierFor(rideType))) && !temporarilyDisabled(candidate.profile, rideType);
    })
    .map((candidate) => {
      const location = profileCoordinate(candidate.profile);
      const distanceToPickupMiles = distanceMiles(location, pickup);
      const match = location ? preferenceMatch({
        profile: candidate.profile,
        driverCoordinate: location,
        pickup,
        dropoff,
        routeDistanceMiles: tripMiles
      }) : "rejected";
      const rawRating = Number(candidate.profile.rating);
      const rating = Number.isFinite(rawRating) ? rawRating : 5;
      const score = Math.max(1, Math.min(100, Math.round(100 - distanceToPickupMiles * 6 + (rating - 4.5) * 18)));
      return {
        ...candidate,
        location,
        distanceToPickupMiles,
        preferenceMatch: match,
        matchScore: score,
        matchReasons: matchReasons(candidate.profile, match, distanceToPickupMiles)
      };
    })
    .filter((candidate) => candidate.location
      && candidate.distanceToPickupMiles <= maxPickupDistanceMiles
      && candidate.preferenceMatch !== "rejected")
    .sort((left, right) => {
      if (left.preferenceMatch !== right.preferenceMatch) return left.preferenceMatch === "strict" ? -1 : 1;
      if (left.matchScore !== right.matchScore) return right.matchScore - left.matchScore;
      if (left.distanceToPickupMiles !== right.distanceToPickupMiles) return left.distanceToPickupMiles - right.distanceToPickupMiles;
      const ratingDifference = Number(right.profile.rating || 0) - Number(left.profile.rating || 0);
      return ratingDifference || left.id.localeCompare(right.id);
    })
    .slice(0, Math.max(0, Math.min(Number(maxResults) || DEFAULT_RESULT_LIMIT, DEFAULT_RESULT_LIMIT)));
}

module.exports = {
  DEFAULT_MAX_PICKUP_DISTANCE_MILES,
  DEFAULT_RESULT_LIMIT,
  coordinate,
  distanceMiles,
  findBestDrivers,
  preferenceMatch,
  profileCoordinate
};
