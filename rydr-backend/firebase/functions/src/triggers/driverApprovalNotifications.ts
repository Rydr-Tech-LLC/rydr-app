// Driver approval decision push notification trigger.
//
// Mission Control's `app/api/drivers/[uid]/decision/route.ts` is the only
// writer of `driverApprovalStatus` (Firestore rules treat it as a
// backend-owned field — see `backendOwnedProfileFields()`). This trigger
// watches for that write and lets the driver know the outcome, closing the
// loop on Part 10's approval workflow without the admin having to do
// anything beyond clicking Approve/Reject/Needs Attention in Mission
// Control.

import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { sendPushToUser } from "../services/notificationSender";

interface DriverDoc {
  driverApprovalStatus?: "pending" | "needs_attention" | "approved" | "rejected";
  rejectionReason?: string;
}

export const onDriverApprovalDecision = onDocumentUpdated("drivers/{uid}", async (event) => {
  const before = event.data?.before.data() as DriverDoc | undefined;
  const after = event.data?.after.data() as DriverDoc | undefined;
  if (!before || !after) return;
  if (before.driverApprovalStatus === after.driverApprovalStatus) return;

  const uid = event.params.uid;

  switch (after.driverApprovalStatus) {
    case "approved":
      await sendPushToUser({
        audience: "driver",
        uid,
        title: "You're approved to drive with Rydr",
        body: "Your account passed beta review. You can go online whenever you're ready.",
        route: { type: "driverApprovalDecision", target: "dashboard" }
      });
      break;
    case "rejected":
      await sendPushToUser({
        audience: "driver",
        uid,
        title: "Update on your Rydr application",
        body: after.rejectionReason || "We weren't able to approve your account for this beta. Check your email for details.",
        route: { type: "driverApprovalDecision", target: "onboardingStatus" }
      });
      break;
    case "needs_attention":
      await sendPushToUser({
        audience: "driver",
        uid,
        title: "Action needed on your Rydr application",
        body: "We need a bit more information before we can approve your account.",
        route: { type: "driverApprovalDecision", target: "onboardingStatus" }
      });
      break;
    default:
      break;
  }
});
