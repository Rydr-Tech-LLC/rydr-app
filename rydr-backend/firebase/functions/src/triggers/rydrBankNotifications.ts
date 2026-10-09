import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { sendPushToUser } from "../services/notificationSender";

interface RydrBankSummaryFields {
  eligibleCount?: number;
  codesEarned?: number;
  codesAvailable?: number;
}

interface UserDoc {
  rydrBank?: RydrBankSummaryFields;
}

interface RydrBankCodeDoc {
  code?: string;
  status?: string;
  rewardLabel?: string;
}

function numberValue(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

export const onRydrBankSummaryUpdated = onDocumentUpdated("users/{uid}", async (event) => {
  const before = event.data?.before.data() as UserDoc | undefined;
  const after = event.data?.after.data() as UserDoc | undefined;
  if (!before || !after) return;

  const uid = event.params.uid;
  const beforeEarned = numberValue(before.rydrBank?.codesEarned);
  const afterEarned = numberValue(after.rydrBank?.codesEarned);
  const beforeAvailable = numberValue(before.rydrBank?.codesAvailable);
  const afterAvailable = numberValue(after.rydrBank?.codesAvailable);

  if (afterEarned > beforeEarned) {
    await sendPushToUser({
      audience: "rider",
      uid,
      title: "RydrBank complete",
      body: "You completed your RydrBank progress and earned a free ride code.",
      route: { type: "rydrBankCompleted", target: "rydrBank" }
    });
    return;
  }

  if (afterAvailable > beforeAvailable) {
    await sendPushToUser({
      audience: "rider",
      uid,
      title: "New RydrBank code",
      body: "A new free ride code is available in your RydrBank.",
      route: { type: "rydrBankCode", target: "rydrBank" }
    });
  }
});

export const onRydrBankCodeCreated = onDocumentCreated("users/{uid}/rydrBankCodes/{codeId}", async (event) => {
  const code = event.data?.data() as RydrBankCodeDoc | undefined;
  if (!code || code.status !== "active") return;

  await sendPushToUser({
    audience: "rider",
    uid: event.params.uid,
    title: "New RydrBank code",
    body: code.rewardLabel
      ? `${code.rewardLabel} is ready in your RydrBank.`
      : "A free ride code is ready in your RydrBank.",
    route: { type: "rydrBankCode", target: "rydrBank", requestId: event.params.codeId }
  });
});
