const { admin, getFirestore } = require('../config/firebase');
const { advanceRideDispatch } = require('./rideDispatchService');
const { promoteNextQueuedRide } = require('./driverQueueService');

// Offers and accepted queues must advance even when both phones are suspended.
async function maintainRideRequests({ db = getFirestore(), now = admin.firestore.Timestamp.now() } = {}) {
  const expired = await db.collection('rideRequests').where('status', '==', 'pending').where('offerExpiresAt', '<=', now).limit(100).get();
  const results = [];
  for (const doc of expired.docs) {
    try {
      const result = await advanceRideDispatch({ rideId: doc.id, actorRole: 'rider', actorUid: doc.data().riderId,
        reason: 'expired', requestId: `sweep_${doc.id}_${doc.data().dispatchAttemptNumber || 1}`, db });
      results.push({ rideId: doc.id, status: result.status });
    } catch (err) { results.push({ rideId: doc.id, error: err.message }); }
  }
  const staleAt = admin.firestore.Timestamp.fromMillis(now.toMillis() - 15 * 60000);
  const abandoned = await db.collection('rideRequests').where('status', 'in', ['authorizing', 'authorizationFailed']).where('updatedAt', '<=', staleAt).limit(100).get();
  for (const doc of abandoned.docs) {
    await db.runTransaction(async tx => {
      const snap = await tx.get(doc.ref);
      if (!['authorizing', 'authorizationFailed'].includes(snap.data()?.status)) return;
      if (snap.data()?.scheduledRideId) tx.set(db.collection('scheduledRideRequests').doc(snap.data().scheduledRideId), {
        status: 'expired', terminalReason: 'card_authorization_expired', updatedAt: now
      }, { merge: true });
      tx.set(doc.ref, { status: 'expired', dispatchStatus: 'expired', updatedAt: now }, { merge: true });
      tx.set(db.collection('authorizationReleaseJobs').doc(doc.id), { rideId: doc.id, status: 'pending', createdAt: now });
    });
  }
  const queued = await db.collection('rides').where('driverQueueStatus', '==', 'queued').where('status', '==', 'accepted').limit(100).get();
  for (const driverId of new Set(queued.docs.map(doc => doc.data().driverId).filter(Boolean))) {
    try { await promoteNextQueuedRide({ driverId, requestId: `sweep_queue_${Math.floor(now.toMillis() / 60000)}`, db }); }
    catch (err) { if (err.statusCode !== 409) results.push({ driverId, error: err.message }); }
  }
  return { results };
}
module.exports = { maintainRideRequests };
