import "server-only";
import type { DocumentData } from "firebase-admin/firestore";
import { adminDb } from "./firebaseAdmin";
import type { ActiveRideSummary } from "./activeRideTypes";

const ACTIVE_RIDE_STATUSES = [
  "pending",
  "accepted",
  "enRouteToPickup",
  "navigatingToPickup",
  "arrived",
  "arrivedAtPickup",
  "waitingForRider",
  "inProgress",
  "in_progress",
  "navigatingToStop",
  "arrivedAtStop",
  "waitingAtStop",
  "navigatingToDropoff",
  "dropoffArrived"
];

type ParticipantField = "riderId" | "driverId";

export async function findActiveRideForRider(uid: string) {
  return findActiveRide("riderId", uid);
}

export async function findActiveRideForDriver(uid: string) {
  return findActiveRide("driverId", uid);
}

async function findActiveRide(field: ParticipantField, uid: string): Promise<ActiveRideSummary | null> {
  const snapshots = await Promise.all(
    chunks(ACTIVE_RIDE_STATUSES, 10).map((statuses) =>
      adminDb
        .collection("rides")
        .where(field, "==", uid)
        .where("status", "in", statuses)
        .limit(10)
        .get()
    )
  );

  const rides = snapshots
    .flatMap((snap) => snap.docs)
    .map((doc) => summarizeRide(doc.id, doc.data()))
    .sort((a, b) => (b.updatedAtMillis ?? 0) - (a.updatedAtMillis ?? 0));

  return rides[0] ?? null;
}

function chunks<T>(items: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < items.length; index += size) {
    result.push(items.slice(index, index + size));
  }
  return result;
}

function summarizeRide(id: string, data: DocumentData): ActiveRideSummary {
  return {
    id,
    status: String(data.status ?? "unknown"),
    riderId: typeof data.riderId === "string" ? data.riderId : undefined,
    driverId: typeof data.driverId === "string" ? data.driverId : undefined,
    pickup: locationLabel(data.pickup),
    dropoff: locationLabel(data.dropoff),
    updatedAtMillis: timestampMillis(data.updatedAt)
  };
}

function locationLabel(raw: unknown): string | undefined {
  if (typeof raw === "string" && raw.trim()) return raw.trim();
  if (!raw || typeof raw !== "object") return undefined;
  const data = raw as Record<string, unknown>;
  const value = data.address ?? data.name ?? data.title ?? data.formattedAddress ?? data.label;
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function timestampMillis(raw: unknown): number | undefined {
  if (!raw || typeof raw !== "object") return undefined;
  const value = raw as { toMillis?: () => number; toDate?: () => Date };
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value.toDate === "function") return value.toDate().getTime();
  return undefined;
}
