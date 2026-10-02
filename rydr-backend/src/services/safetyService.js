const { admin, getFirestore } = require("../config/firebase");
function error(message, statusCode) { const err = new Error(message); err.statusCode = statusCode; return err; }
function text(value, max) { return typeof value === "string" ? value.trim().slice(0, max) : ""; }

async function createSafetyReport({ uid, payload, db = getFirestore() }) {
  const rideId = text(payload?.rideId, 160); const cashHubRequestId = text(payload?.cashHubRequestId, 160);
  let evidence = {}; let reporterRole;
  if (rideId) {
    const snap = await db.collection("rides").doc(rideId).get();
    if (!snap.exists) throw error("Ride not found", 404);
    const ride = snap.data();
    reporterRole = uid === ride.riderId ? "rider" : uid === ride.driverId ? "driver" : null;
    if (!reporterRole) throw error("Only ride participants may report this ride", 403);
    evidence = { rideId, riderId: ride.riderId, driverId: ride.driverId, rideStatus: ride.status, rideType: ride.rideType, pickup: ride.pickup ?? null, dropoff: ride.dropoff ?? null };
  } else if (cashHubRequestId) {
    const snap = await db.collection("cashRydrRequests").doc(cashHubRequestId).get();
    if (!snap.exists) throw error("Cash Hub request not found", 404);
    const request = snap.data();
    reporterRole = uid === request.riderUid ? "rider" : uid === request.connectedDriverUid || uid === request.acceptedByUid ? "driver" : null;
    const conversationId = text(payload?.cashHubConversationId, 160);
    if (!reporterRole && conversationId) {
      const conversation = await db.collection("cashHubConversations").doc(conversationId).get();
      if (conversation.exists && conversation.data().requestId === cashHubRequestId && [conversation.data().riderUid, conversation.data().driverUid].includes(uid)) reporterRole = uid === conversation.data().riderUid ? "rider" : "driver";
    }
    if (!reporterRole && request.status === "open") {
      const driver = await db.collection("drivers").doc(uid).get();
      if (driver.exists && driver.data().cashHubTermsAccepted === true) reporterRole = "driver";
    }
    if (!reporterRole) throw error("Only request participants may report it", 403);
    evidence = { cashHubRequestId, cashHubConversationId: conversationId || null, riderId: request.riderUid, driverId: request.connectedDriverUid ?? request.acceptedByUid ?? null, cashHubStatus: request.status };
  } else throw error("A rideId or cashHubRequestId is required", 400);
  const description = text(payload?.description, 4000);
  if (description.length < 12) throw error("More report detail is required", 400);
  const ref = db.collection("safetyReports").doc(); const now = admin.firestore.Timestamp.now();
  await ref.create({ id: ref.id, ...evidence, reportType: text(payload?.reportType, 100) || "Safety concern", description, reporterUid: uid, reporterRole, status: "open", source: "rydr_backend", createdAt: now, updatedAt: now });
  return { reportId: ref.id };
}

async function createSafetyAppeal({ uid, payload, db = getFirestore() }) {
  const penaltyId = text(payload?.penaltyId, 160); const reason = text(payload?.reason, 4000);
  if (!penaltyId || reason.length < 20) throw error("Penalty and appeal detail are required", 400);
  const penaltySnap = await db.collection("driverSafetyPenalties").doc(penaltyId).get();
  if (!penaltySnap.exists || penaltySnap.data().driverId !== uid) throw error("Penalty not found", 404);
  const penalty = penaltySnap.data(); const ref = db.collection("driverSafetyPenaltyAppeals").doc(); const now = admin.firestore.Timestamp.now();
  await ref.create({ penaltyId, driverId: uid, rideId: penalty.rideId ?? null, riderReportId: penalty.riderReportId ?? null, category: penalty.category ?? "other", reason, status: "submitted", source: "rydr_backend", createdAt: now, updatedAt: now });
  return { appealId: ref.id };
}
module.exports = { createSafetyReport, createSafetyAppeal };
