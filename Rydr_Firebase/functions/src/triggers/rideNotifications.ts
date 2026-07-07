// Ride lifecycle + payment status push notification triggers.
//
// These are the server-side notification senders required by Part 9 of the
// beta hardening sprint: "Ride accepted", "Driver arrived", "Ride started",
// "Ride completed", "Ride cancelled", "Payment failed". They fire on the
// SAME `rides/{rideId}` document the driver app authoritatively writes and
// the rider app listens to (FirestoreRideService.rideLifecycleStream),
// so notifications are always a reflection of real, persisted state —
// never of client-side simulation.

import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { sendPushToUser } from "../services/notificationSender";
import { db, FieldValue } from "../admin";

type RideStatus =
  | "pending"
  | "accepted"
  | "enRouteToPickup"
  | "arrived"
  | "arrivedAtPickup"
  | "waitingForRider"
  | "inProgress"
  | "in_progress"
  | "completed"
  | "cancelled"
  | "riderCancelled"
  | "driverCancelled"
  | "adminCancelled"
  | "declined"
  | string;

type PaymentStatus = "pending" | "processing" | "succeeded" | "failed" | "refunded" | string;

interface RideDoc {
  riderId?: string;
  driverId?: string;
  status?: RideStatus;
  paymentStatus?: PaymentStatus;
  driverName?: string;
  riderName?: string;
  pickup?: string;
  dropoff?: string;
  driverLocation?: CoordinateLike;
  pickupCoordinate?: CoordinateLike;
  pickupGeoPoint?: CoordinateLike;
  pickupEtaTwoMinuteNotifiedAt?: unknown;
}

interface CoordinateLike {
  lat?: number;
  lng?: number;
  latitude?: number;
  longitude?: number;
}

function normalizeStatus(status: RideStatus | undefined): string {
  return (status ?? "").trim();
}

function coordinate(raw: CoordinateLike | undefined): { lat: number; lng: number } | null {
  if (!raw) return null;
  const lat = typeof raw.lat === "number" ? raw.lat : raw.latitude;
  const lng = typeof raw.lng === "number" ? raw.lng : raw.longitude;
  if (typeof lat !== "number" || typeof lng !== "number") return null;
  return { lat, lng };
}

function distanceMeters(from: { lat: number; lng: number }, to: { lat: number; lng: number }): number {
  const earthRadiusMeters = 6371000;
  const dLat = ((to.lat - from.lat) * Math.PI) / 180;
  const dLng = ((to.lng - from.lng) * Math.PI) / 180;
  const fromLat = (from.lat * Math.PI) / 180;
  const toLat = (to.lat * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(fromLat) * Math.cos(toLat) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return earthRadiusMeters * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function pickupEtaSeconds(after: RideDoc): number | null {
  const driver = coordinate(after.driverLocation);
  const pickup = coordinate(after.pickupCoordinate ?? after.pickupGeoPoint);
  if (!driver || !pickup) return null;
  const meters = distanceMeters(driver, pickup);
  if (meters <= 20) return 0;
  return Math.ceil(meters / 8.0);
}

const ARRIVED_STATUSES = new Set(["arrived", "arrivedAtPickup", "waitingForRider"]);
const IN_PROGRESS_STATUSES = new Set(["inProgress", "in_progress"]);
const CANCELLED_STATUSES = new Set(["cancelled", "riderCancelled", "driverCancelled", "adminCancelled"]);
const EN_ROUTE_TO_PICKUP_STATUSES = new Set(["accepted", "enRouteToPickup", "navigatingToPickup"]);

/**
 * Fires on every write to `rides/{rideId}`. Only acts on the specific
 * status/paymentStatus *transitions* that matter — re-saves of an already
 * "completed" ride, location pings, etc. must never re-fire a push.
 */
export const onRideUpdated = onDocumentUpdated("rides/{rideId}", async (event) => {
  const before = event.data?.before.data() as RideDoc | undefined;
  const after = event.data?.after.data() as RideDoc | undefined;
  if (!before || !after) return;

  const rideId = event.params.rideId;
  const riderId = after.riderId;
  const driverId = after.driverId;

  const beforeStatus = normalizeStatus(before.status);
  const afterStatus = normalizeStatus(after.status);
  const beforePayment = before.paymentStatus ?? "pending";
  const afterPayment = after.paymentStatus ?? "pending";

  // --- Ride lifecycle transitions (rider-facing) ---
  if (beforeStatus !== afterStatus && riderId) {
    if (afterStatus === "accepted" || afterStatus === "enRouteToPickup") {
      await sendPushToUser({
        audience: "rider",
        uid: riderId,
        title: "Driver on the way",
        body: after.driverName ? `${after.driverName} accepted your ride and is heading your way.` : "A driver accepted your ride request.",
        route: { type: "rideAccepted", target: "activeRide", rideId }
      });
    } else if (ARRIVED_STATUSES.has(afterStatus) && !ARRIVED_STATUSES.has(beforeStatus)) {
      await sendPushToUser({
        audience: "rider",
        uid: riderId,
        title: "Your driver has arrived",
        body: "Your driver is waiting at the pickup location.",
        route: { type: "driverArrived", target: "activeRide", rideId }
      });
    } else if (IN_PROGRESS_STATUSES.has(afterStatus) && !IN_PROGRESS_STATUSES.has(beforeStatus)) {
      await sendPushToUser({
        audience: "rider",
        uid: riderId,
        title: "Ride started",
        body: "Enjoy the ride — we'll let you know when you arrive.",
        route: { type: "rideStarted", target: "activeRide", rideId }
      });
    } else if (afterStatus === "completed" && beforeStatus !== "completed") {
      await sendPushToUser({
        audience: "rider",
        uid: riderId,
        title: "Ride completed",
        body: "Your ride is complete. We're processing your payment now.",
        route: { type: "rideCompleted", target: "rideReceipt", rideId }
      });
      if (driverId) {
        await sendPushToUser({
          audience: "driver",
          uid: driverId,
          title: "Ride completed",
          body: "Nice work — the ride has been marked complete.",
          route: { type: "rideCompleted", target: "rideSummary", rideId }
        });
      }
    } else if (CANCELLED_STATUSES.has(afterStatus) && !CANCELLED_STATUSES.has(beforeStatus)) {
      const cancelledByDriver = afterStatus === "driverCancelled";
      const cancelledByAdmin = afterStatus === "adminCancelled";
      if (riderId) {
        await sendPushToUser({
          audience: "rider",
          uid: riderId,
          title: "Ride cancelled",
          body: cancelledByDriver
            ? "Your driver cancelled this ride. Choose another nearby driver to keep going."
            : cancelledByAdmin
              ? "Support cancelled this ride. Open Rydr to request another ride."
              : "Your ride was cancelled.",
          route: { type: "rideCancelled", target: "home", rideId }
        });
      }
      if (driverId && !cancelledByDriver) {
        await sendPushToUser({
          audience: "driver",
          uid: driverId,
          title: "Ride cancelled",
          body: "The rider cancelled this ride. Sorry for the inconvenience. We'll keep looking for nearby requests.",
          route: { type: "rideCancelled", target: "dashboard", rideId }
        });
      }
    }
  }

  if (
    riderId &&
    EN_ROUTE_TO_PICKUP_STATUSES.has(afterStatus) &&
    !after.pickupEtaTwoMinuteNotifiedAt
  ) {
    const etaSeconds = pickupEtaSeconds(after);
    if (etaSeconds !== null && etaSeconds > 0 && etaSeconds <= 120) {
      await sendPushToUser({
        audience: "rider",
        uid: riderId,
        title: "Driver is close",
        body: after.driverName
          ? `${after.driverName} is about 2 minutes away.`
          : "Your driver is about 2 minutes away.",
        route: { type: "driverArrived", target: "activeRide", rideId }
      });
      await db.collection("rides").doc(rideId).set({
        pickupEtaTwoMinuteNotifiedAt: FieldValue.serverTimestamp()
      }, { merge: true });
    }
  }

  // --- Payment status transitions ---
  if (beforePayment !== afterPayment) {
    if (afterPayment === "failed" && riderId) {
      await sendPushToUser({
        audience: "rider",
        uid: riderId,
        title: "Payment failed",
        body: "We couldn't charge your payment method. Tap to retry or update your card.",
        route: { type: "paymentFailed", target: "paymentFailed", rideId }
      });
      if (driverId) {
        await sendPushToUser({
          audience: "driver",
          uid: driverId,
          title: "Payment pending",
          body: "The rider's payment didn't go through yet. We're waiting on them to retry.",
          route: { type: "paymentPending", target: "paymentPending", rideId }
        });
      }
    } else if ((afterPayment === "pending" || afterPayment === "processing") && afterStatus === "completed" && driverId) {
      // Ride completed but payment hasn't settled yet — keep the driver informed.
      await sendPushToUser({
        audience: "driver",
        uid: driverId,
        title: "Payment pending",
        body: "Awaiting rider payment for this completed ride.",
        route: { type: "paymentPending", target: "paymentPending", rideId }
      });
    }
  }
});
