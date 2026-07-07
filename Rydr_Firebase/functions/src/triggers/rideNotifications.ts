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
}

function normalizeStatus(status: RideStatus | undefined): string {
  return (status ?? "").trim();
}

const ARRIVED_STATUSES = new Set(["arrived", "arrivedAtPickup", "waitingForRider"]);
const IN_PROGRESS_STATUSES = new Set(["inProgress", "in_progress"]);
const CANCELLED_STATUSES = new Set(["cancelled", "riderCancelled", "driverCancelled", "adminCancelled"]);

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
