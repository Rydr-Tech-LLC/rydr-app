import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { sendPushToUser } from "../services/notificationSender";

interface ScheduledRideRequest {
  riderId?: string;
  assignedDriverId?: string;
  pickup?: string;
  status?: string;
}

export const onScheduledRideOpportunityCreated = onDocumentCreated(
  "scheduledRideRequests/{requestId}/opportunities/{driverId}",
  async (event) => {
    const opportunity = event.data?.data();
    if (!opportunity || opportunity.status !== "available") return;
    await sendPushToUser({
      audience: "driver",
      uid: event.params.driverId,
      title: "Scheduled ride opportunity",
      body: `A future ${opportunity.rideType ?? "Rydr"} trip is available.`,
      route: { type: "scheduledRideUpdate", target: "scheduledRides", requestId: event.params.requestId }
    });
  }
);

export const onScheduledRideUpdated = onDocumentUpdated(
  "scheduledRideRequests/{requestId}",
  async (event) => {
    const before = event.data?.before.data() as ScheduledRideRequest | undefined;
    const after = event.data?.after.data() as ScheduledRideRequest | undefined;
    if (!before || !after || before.status === after.status) return;
    const requestId = event.params.requestId;

    if (after.status === "replacementSearching" && before.assignedDriverId && before.assignedDriverId !== after.assignedDriverId) {
      await sendPushToUser({
        audience: "driver",
        uid: before.assignedDriverId,
        title: "Scheduled ride reassigned",
        body: "You were not online in time to protect the scheduled pickup, so Rydr started on-time replacement matching.",
        route: { type: "scheduledRideUpdate", target: "scheduledRides", requestId }
      });
    }

    if (after.riderId) {
      const riderMessage: Record<string, string> = {
        awaitingRiderSelection: "Drivers responded to your scheduled ride. Choose a driver.",
        confirmed: "Your scheduled ride is confirmed.",
        replacementSearching: "Your original driver was not available in time. Rydr is finding an on-time replacement at your locked price.",
        dispatchFallbackSearching: "Your scheduled request is now searching through regular Rydr dispatch for the closest available driver.",
        dispatchFallbackActivating: "Your scheduled request is moving into regular Rydr dispatch.",
        replacementApprovalRequired: "A replacement driver is available for your approval.",
        active: "Your scheduled ride is now active.",
        cancelled: "Your scheduled ride was cancelled.",
        expired: "Your scheduled ride could not be activated. Open the app for options."
      };
      const body = riderMessage[after.status ?? ""];
      if (body) {
        await sendPushToUser({
          audience: "rider",
          uid: after.riderId,
          title: "Scheduled ride update",
          body,
          route: { type: "scheduledRideUpdate", target: "scheduledRides", requestId }
        });
      }
    }

    if (after.assignedDriverId) {
      const driverMessage: Record<string, string> = {
        confirmed: "A scheduled ride has been added to your schedule.",
        checkInRequired: "Check in for your upcoming scheduled pickup.",
        active: "Your scheduled pickup is ready in Rydr Dispatch.",
        cancelled: "The rider cancelled this scheduled trip."
      };
      const body = driverMessage[after.status ?? ""];
      if (body) {
        await sendPushToUser({
          audience: "driver",
          uid: after.assignedDriverId,
          title: "Scheduled ride update",
          body,
          route: { type: "scheduledRideUpdate", target: "scheduledRides", requestId }
        });
      }
    }
  }
);
