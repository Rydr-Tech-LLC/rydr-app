import type { DocumentReference } from "firebase-admin/firestore";
import { FieldValue } from "firebase-admin/firestore";

// Outside drivers/<uid>: recursive profile removal must not erase vehicle history.
export async function preserveAccountVehicleHistory(ref: DocumentReference, profile: Record<string, unknown>, adminUid: string, requestId: string) {
  const archive = ref.firestore.collection("accountVehicleArchives").doc(ref.id);
  const history = await ref.collection("vehicleArchive").get();
  const records = history.docs.map(doc => ({ id: `history_${doc.id}`, data: doc.data() }));
  if (profile.vehicle && typeof profile.vehicle === "object") records.push({ id: "current", data: { vehicle: profile.vehicle } });
  const saved = profile.savedVehicles;
  if (saved && typeof saved === "object") {
    for (const [id, vehicle] of Object.entries(saved)) records.push({ id: `saved_${id}`, data: { vehicle } });
  }
  // Await every write before permitting any destructive account operation.
  for (const record of records) await archive.collection("vehicles").doc(record.id).set(record.data);
  await archive.set({ driverUid: ref.id, adminUid, requestId, archivedAt: FieldValue.serverTimestamp(), vehicleRecordCount: records.length }, { merge: true });
}
