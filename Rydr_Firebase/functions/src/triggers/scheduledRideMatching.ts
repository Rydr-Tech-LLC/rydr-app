// Scheduled Rides backend (Sprint 1, ene) — this is the contract
// `ScheduledRideManager.swift` was built ahead of (see its "CONTRACT STATUS"
// note). Once these functions are deployed, flip
// `ScheduledRideManager.useMockData` to `false` and the same UI code talks
// to real Firestore documents instead of a client-side simulation.
//
// Ownership split enforced here (matches the header comments in
// ScheduledRide.swift / ScheduledRideManager.swift):
//   - Rider app writes ONLY: the initial create (rider-allowed fields),
//     `riderSelectedOfferId` (a proposal, not a lock), and
//     `status: "cancelledByRider"`.
//   - Everything else — `offers`, `assignedDriverId`, `lockedPriceCents`,
//     `acceptedOfferId`, and every other status value — is written only
//     from here. firestore.rules enforces this server-side; these
//     functions are what actually needs to hold up that promise.

import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { db, FieldValue, Timestamp } from "../admin";
import { matchDrivers, MatchedDriver, OFFER_TTL_SECONDS } from "../services/scheduledRideMatchingService";

const OFFER_SLOT_IDS = ["offer_0", "offer_1", "offer_2"];
// How long a rider has to pick from ready offers (Choose My Driver) before
// the request is treated as expired. Deliberately longer than the ~90s
// on-demand offer window — this is a ride the rider may have scheduled for
// later and isn't necessarily staring at the app when offers land.
const RIDER_CHOICE_WINDOW_MS = 10 * 60 * 1000;
// Safety net for a request that never got matched at all (e.g. a failed
// trigger execution) — shouldn't normally be hit since onCreate resolves
// synchronously, but without this a broken request would sit in
// "pendingOffers" forever with no retry path for the rider.
const STUCK_PENDING_WINDOW_MS = 5 * 60 * 1000;

interface ScheduledRideRequestDoc {
  riderId?: string;
  rideType?: string;
  mode?: "quickSchedule" | "chooseMyDriver";
  status?: string;
  pickupCoordinate?: { lat?: number; lng?: number };
  pickupGeoPoint?: FirebaseFirestore.GeoPoint;
  estimatedDistanceMiles?: number;
  estimatedDurationMinutes?: number;
  riderSelectedOfferId?: string;
  assignedDriverId?: string;
  updatedAt?: FirebaseFirestore.Timestamp;
  createdAt?: FirebaseFirestore.Timestamp;
}

function pickupLatLng(data: ScheduledRideRequestDoc): { lat: number; lng: number } | null {
  const coord = data.pickupCoordinate;
  if (coord && typeof coord.lat === "number" && typeof coord.lng === "number") {
    return { lat: coord.lat, lng: coord.lng };
  }
  const geo = data.pickupGeoPoint;
  if (geo) return { lat: geo.latitude, lng: geo.longitude };
  return null;
}

async function writeOfferSlots(requestRef: FirebaseFirestore.DocumentReference, matches: MatchedDriver[]): Promise<string[]> {
  const offersRef = requestRef.collection("offers");
  const now = Timestamp.now();
  const expiresAt = Timestamp.fromMillis(now.toMillis() + OFFER_TTL_SECONDS * 1000);
  const batch = db.batch();
  const writtenIds: string[] = [];

  OFFER_SLOT_IDS.forEach((slotId, index) => {
    const slotRef = offersRef.doc(slotId);
    const match = matches[index];
    if (!match) {
      // Fewer matches than slots (e.g. a re-match after a cancellation with
      // only one driver left) — clear any stale offer left in this slot so
      // the client's oldest-first, limit-3 listener never shows a driver
      // who is no longer actually offered.
      batch.delete(slotRef);
      return;
    }
    batch.set(slotRef, {
      driverId: match.driverId,
      driverName: match.driverName,
      driverProfileImage: match.driverProfileImage,
      carImage: match.carImage,
      carMakeModel: match.carMakeModel,
      rating: match.rating,
      ratingCount: match.ratingCount,
      perMile: match.perMile,
      perMinute: match.perMinute,
      lockedPriceCents: match.lockedPriceCents,
      distanceMiles: match.distanceMiles,
      offeredAt: now,
      expiresAt
    });
    writtenIds.push(slotId);
  });

  await batch.commit();
  return writtenIds;
}

/** Runs matching for a request and applies the result: quickSchedule
 * auto-locks the nearest match immediately; chooseMyDriver surfaces up to
 * three offers and waits on the rider. Shared by the initial create and by
 * a driver-cancellation re-match so both paths behave identically. */
async function runMatchingAndApply(
  requestRef: FirebaseFirestore.DocumentReference,
  data: ScheduledRideRequestDoc,
  options: { excludeDriverIds?: string[] } = {}
): Promise<void> {
  const pickup = pickupLatLng(data);
  const rideType = data.rideType ?? "Rydr Go";
  const distanceMiles = data.estimatedDistanceMiles ?? 0;
  const durationMinutes = data.estimatedDurationMinutes ?? 0;

  if (!pickup) {
    await requestRef.set({ status: "cancelledNoDrivers", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return;
  }

  let matches: MatchedDriver[] = [];
  try {
    matches = await matchDrivers({
      rideType,
      pickupLat: pickup.lat,
      pickupLng: pickup.lng,
      distanceMiles,
      durationMinutes,
      excludeDriverIds: options.excludeDriverIds
    });
  } catch (err) {
    console.error("scheduledRideMatching: matchDrivers failed", requestRef.id, err);
  }

  if (matches.length === 0) {
    await requestRef.set({ status: "cancelledNoDrivers", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return;
  }

  const offerIds = await writeOfferSlots(requestRef, matches);

  if (data.mode === "quickSchedule") {
    const best = matches[0];
    await requestRef.set({
      assignedDriverId: best.driverId,
      lockedPriceCents: best.lockedPriceCents,
      acceptedOfferId: offerIds[0] ?? null,
      status: "priceLocked",
      updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });
    return;
  }

  // chooseMyDriver: clear any stale proposal from a previous round (e.g. a
  // re-match after the rider's originally chosen driver cancelled) so it
  // never gets reprocessed against the new offers by the update trigger.
  await requestRef.set({
    status: "awaitingRiderChoice",
    riderSelectedOfferId: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp()
  }, { merge: true });
}

export const onScheduledRideRequestCreated = onDocumentCreated(
  "scheduledRideRequests/{requestId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const data = snapshot.data() as ScheduledRideRequestDoc;
    // Only ever act on a fresh rider-created request. Defensive: the rider
    // app only ever creates with this status, but a stray write shouldn't
    // trigger a live match run.
    if (data.status !== "pendingOffers") return;
    await runMatchingAndApply(snapshot.ref, data);
  }
);

export const onScheduledRideRequestUpdated = onDocumentUpdated(
  "scheduledRideRequests/{requestId}",
  async (event) => {
    const before = event.data?.before.data() as ScheduledRideRequestDoc | undefined;
    const after = event.data?.after.data() as ScheduledRideRequestDoc | undefined;
    const ref = event.data?.after.ref;
    if (!before || !after || !ref) return;

    // Rider proposed an offer (Choose My Driver). This field is the one
    // thing a rider is allowed to write on selection — it does NOT lock
    // anything by itself; this is what actually confirms it.
    const proposedOfferId = after.riderSelectedOfferId;
    const proposalChanged = proposedOfferId && proposedOfferId !== before.riderSelectedOfferId;
    const awaitingRiderInput = after.status === "awaitingRiderChoice" || after.status === "driverCancelledFindingReplacement";
    if (proposalChanged && awaitingRiderInput) {
      const offerSnap = await ref.collection("offers").doc(proposedOfferId).get();
      if (!offerSnap.exists) {
        console.warn("scheduledRideMatching: rider selected an offer that no longer exists", ref.id, proposedOfferId);
        return;
      }
      const offer = offerSnap.data() as { driverId: string; lockedPriceCents: number };
      await ref.set({
        assignedDriverId: offer.driverId,
        lockedPriceCents: offer.lockedPriceCents,
        acceptedOfferId: proposedOfferId,
        status: "confirmed",
        updatedAt: FieldValue.serverTimestamp()
      }, { merge: true });
      return;
    }

    // A driver cancelled a locked/confirmed scheduled ride. There is no
    // real driver-side integration for this yet (per Ashank/James's note —
    // the driver app is also still mock-first), but the contract needs to
    // be correct now: whenever that write path exists, it only has to set
    // this one status, and re-matching (excluding the driver who cancelled)
    // happens automatically from here.
    const driverJustCancelled = before.status !== "driverCancelledFindingReplacement" && after.status === "driverCancelledFindingReplacement";
    if (driverJustCancelled) {
      await runMatchingAndApply(ref, after, {
        excludeDriverIds: before.assignedDriverId ? [before.assignedDriverId] : undefined
      });
    }

    // Rider cancelling (`cancelledByRider`) is the one other status the
    // rider app writes directly — intentionally a no-op here, nothing
    // further needs to happen server-side.
  }
);

/** Safety-net sweep: expires requests that never got a driver at all
 * (stuck "pendingOffers" past a short window — should be rare, since
 * onCreate resolves synchronously) and requests with ready offers the
 * rider never acted on within the choice window. Both land the request in
 * a state `ScheduledRideStatus.offersRetry` recognizes, so the "Try Again"
 * affordance in ScheduledRideConfirmationView picks it up correctly. */
export const onScheduledRideExpirationSweep = onSchedule("every 5 minutes", async () => {
  const now = Date.now();

  const stuckPending = await db.collection("scheduledRideRequests")
    .where("status", "==", "pendingOffers")
    .get();
  const staleChoice = await db.collection("scheduledRideRequests")
    .where("status", "==", "awaitingRiderChoice")
    .get();

  const batch = db.batch();
  let writes = 0;

  stuckPending.forEach((doc) => {
    const updatedAtMillis = (doc.data().updatedAt as FirebaseFirestore.Timestamp | undefined)?.toMillis()
      ?? (doc.data().createdAt as FirebaseFirestore.Timestamp | undefined)?.toMillis()
      ?? 0;
    if (now - updatedAtMillis >= STUCK_PENDING_WINDOW_MS) {
      batch.set(doc.ref, { status: "cancelledNoDrivers", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      writes += 1;
    }
  });

  staleChoice.forEach((doc) => {
    const updatedAtMillis = (doc.data().updatedAt as FirebaseFirestore.Timestamp | undefined)?.toMillis() ?? 0;
    if (now - updatedAtMillis >= RIDER_CHOICE_WINDOW_MS) {
      batch.set(doc.ref, { status: "expired", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      writes += 1;
    }
  });

  if (writes > 0) await batch.commit();
});
