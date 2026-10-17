import { documentDeclines } from "./documentReviewFeedback";
import { createHash } from "node:crypto";
import { db, FieldValue, Timestamp } from "../admin";
import { evaluateDriverCompliance, timestamp, georgiaDate } from "./driverCompliancePolicy";
import { sendPushToUser } from "./notificationSender";

function baseApprovalAllowsDriving(driver: Record<string, any>) {
  return !["rejected", "needs_attention"].includes(driver.driverApprovalStatus) && (driver.driverApprovalStatus === "approved" || driver.isApproved === true)
    && !["suspended", "removed", "deletion_requested"].includes(driver.accountStatus)
    && driver.safetyReviewStatus !== "suspended" && driver.safetyHold !== true;
}

export async function reconcileDriverCompliance(uid: string, policy?: Record<string, any>, nowMillis = Date.now()) {
  const config = policy ?? (await db.collection("platformConfig").doc("driverCompliance").get()).data() ?? {};
  const ref = db.collection("drivers").doc(uid);
  const now = nowMillis;
  const result = await db.runTransaction(async tx => {
    const snap = await tx.get(ref);
    if (!snap.exists) return null;
    const driver = snap.data() ?? {};
    const compliance = evaluateDriverCompliance(driver, config, now);
    const update: Record<string, any> = {
      documentComplianceHold: compliance.documentHold,
      documentComplianceExpiredKinds: compliance.expiredKinds,
      documentComplianceVerificationKinds: compliance.unverifiedKinds,
      documentComplianceVerified: Object.fromEntries(compliance.documents.map(doc => [doc.kind, doc.verifiedCurrent])),
      documentComplianceDeadlines: Object.fromEntries(compliance.documents.map(doc => [doc.kind, doc.deadline == null ? null : Timestamp.fromMillis(doc.deadline)])),
      backgroundCheckHold: compliance.backgroundHold,
      complianceRequirements: { backgroundChecksRequired: compliance.backgroundChecksRequired, backgroundCheckRequirementVersion: compliance.backgroundRequirementVersion },
      documentComplianceSummary: { documents: compliance.documents, needsReviewKinds: compliance.needsReviewKinds, expiringKinds: compliance.expiringKinds },
      canGoOnline: baseApprovalAllowsDriving(driver) && compliance.drivingAllowed
    };
    const changed = Object.entries(update).some(([key, value]) => JSON.stringify(driver[key]) !== JSON.stringify(value));
    if (changed) tx.update(ref, { ...update, complianceEvaluatedAt: FieldValue.serverTimestamp() });
    if (!compliance.drivingAllowed) {
      tx.set(db.collection("driver_status").doc(uid), { isOnline: false, online: false, availabilityStatus: "offline", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      tx.set(db.collection("publicDriverProfiles").doc(uid), { isOnline: false, online: false, availabilityStatus: "offline", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      if (driver.isOnline === true || driver.online === true) tx.update(ref, { isOnline: false, online: false, availabilityStatus: "offline" });
    }
    return { driver, compliance };
  });
  if (!result) return;
  const { driver, compliance } = result;
  const activeReminderIds = new Set<string>();
  for (const declined of documentDeclines(driver)) {
    const id = 'document_declined_' + createHash('sha256').update(`${declined.kind}|${declined.revision}|${declined.reason}`).digest('hex');
    activeReminderIds.add(id);
    await sendPushToUser({ audience: 'driver', uid, notificationId: id, title: `${declined.label}: new upload needed`, body: `${declined.reason} Open Documents in Rydr to upload a replacement for review.`, route: { type: 'driverDocumentReminder', target: 'documents' } });
  }

  for (const document of compliance.documents) {
    if (!document.reminderStage) continue;
    const hour = Number(new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", hour: "numeric", hourCycle: "h23" }).format(new Date(now)));
    const key = createHash("sha256").update(`${document.kind}|${document.expirationDate}|${document.reminderStage}`).digest("hex");
    activeReminderIds.add(`document_${key}`);
    if (!document.expired && (hour < 9 || hour > 18)) continue;
    await sendPushToUser({ audience: "driver", uid, notificationId: `document_${key}`, title: document.expired ? `${document.label} expired` : `${document.label} expires soon`, body: document.expired ? `Your ${document.label.toLowerCase()} has expired. Driving is temporarily paused. Upload a current replacement in Documents; access returns after verification.` : `Your ${document.label.toLowerCase()} expires ${document.expirationDate}${document.daysLeft === 0 ? " (today)" : ""}. Upload a current replacement before that date to keep driving.`, route: { type: "driverDocumentReminder", target: "documents" } });
  }
  if (compliance.unverifiedKinds.some(kind => !compliance.expiredKinds.includes(kind))) {
    activeReminderIds.add("documents_verification_required_open_pilot_v1");
    await sendPushToUser({ audience: "driver", uid, notificationId: "documents_verification_required_open_pilot_v1", title: "Document verification required", body: "Current verified license, insurance and registration dates are required before driving in the open pilot. Upload your current documents; driving access returns after verification and required screening.", route: { type: "driverDocumentReminder", target: "documents" } });
  }
  const screening = driver.backgroundScreening ?? {};
  const screeningDeadline = Math.min(timestamp(screening.validUntil), timestamp(screening.completedAt) + 366 * 86400000);
  const screeningExpiry = Number.isFinite(screeningDeadline) ? georgiaDate(screeningDeadline - 1) : null;
  const screeningDays = screeningExpiry ? Math.round((Date.parse(screeningExpiry) - Date.parse(georgiaDate(now))) / 86400000) : null;
  const screeningExpired = Number.isFinite(screeningDeadline) && screeningDeadline <= now;
  if (compliance.backgroundChecksRequired && screening.status === "passed" && screeningExpiry && screeningDays != null && screeningDays <= 30) {
    const stage = screeningExpired ? "expired" : screeningDays <= 1 ? "1_day" : screeningDays <= 7 ? "7_days" : "30_days";
    const key = createHash("sha256").update(`${screeningExpiry}|${stage}`).digest("hex");
    activeReminderIds.add(`screening_expiry_${key}`);
    await sendPushToUser({ audience: "driver", uid, notificationId: `screening_expiry_${key}`, title: screeningExpired ? "Background screening renewal required" : "Background screening expires soon", body: `Your verified screening is valid through ${screeningExpiry}. Complete a new screening through Rydr’s approved provider to ${screeningExpired ? "restore" : "keep"} driving access.`, route: { type: "driverScreeningRequired", target: "documents" } });
  }
  if (compliance.backgroundHold && !screeningExpired) {
    activeReminderIds.add(`background_required_${createHash("sha256").update(compliance.backgroundRequirementVersion).digest("hex")}`);
    await sendPushToUser({ audience: "driver", uid, notificationId: `background_required_${createHash("sha256").update(compliance.backgroundRequirementVersion).digest("hex")}`, title: "Background check required", body: "A completed, verified background check is required before driving in the open pilot. Beta approval does not replace this requirement. Open Documents for your screening status and next steps.", route: { type: "driverScreeningRequired", target: "documents" } });
  }
  // Renewals and newer reminder stages invalidate queued pushes from old dates.
  const pending = await ref.collection("notifications").where("pushStatus", "in", ["pending", "retry_pending", "awaiting_device"]).get();
  for (const notification of pending.docs) {
    if ((/^(document_|documents_verification_|screening_expiry_|background_required_)/.test(notification.id) && !activeReminderIds.has(notification.id)) || (notification.id.startsWith("compliance_restored_") && (!compliance.drivingAllowed || !baseApprovalAllowsDriving(driver)))) {
      await notification.ref.set({ pushStatus: "superseded" }, { merge: true });
    }
  }
  if ((driver.documentComplianceHold === true || driver.backgroundCheckHold === true) && compliance.drivingAllowed && baseApprovalAllowsDriving(driver)) {
    const id = createHash("sha256").update(JSON.stringify(compliance.documents.map(doc => [doc.kind, doc.expirationDate])) + String(driver.backgroundScreening?.validUntil ?? "")).digest("hex");
    await sendPushToUser({ audience: "driver", uid, notificationId: `compliance_restored_${id}`, title: "Document checks cleared", body: "Your updated documents and required screening have been verified. You can go online once all remaining account checks are cleared.", route: { type: "driverDocumentReminder", target: "documents" } });
  }
}
