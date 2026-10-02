import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { sendPushToUser } from "../services/notificationSender";

export const onCashHubBillingUpdated = onDocumentWritten("drivers/{driverId}/cashHubBilling/{periodId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!after || before?.status === after.status && before?.remainingCents === after.remainingCents) return;
  const remaining = Math.max(0, Number(after.remainingCents) || 0);
  const collected = Math.max(0, Number(after.collectedCents) || 0);
  const dollars = (cents: number) => `$${(cents / 100).toFixed(2)}`;
  let title = "CashRydr Hub monthly fee";
  let body = `${dollars(remaining)} will be collected from eligible Rydr Dispatch earnings.`;
  if (after.status === "partially_collected") body = `${dollars(collected)} collected from Dispatch earnings; ${dollars(remaining)} remains.`;
  if (after.status === "collected") { title = "CashRydr Hub fee paid"; body = "Your monthly CashRydr Hub access is active."; }
  if (after.status === "past_due") { title = "CashRydr Hub access paused"; body = "No card was charged. Complete a Rydr Dispatch ride to pay the remaining fee and restore access."; }
  await sendPushToUser({
    audience: "driver",
    uid: event.params.driverId,
    title,
    body,
    route: { type: "cashHubUpdate", target: "cashHub" }
  });
});
