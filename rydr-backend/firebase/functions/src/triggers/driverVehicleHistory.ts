import { createHash } from "crypto";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { db, FieldValue } from "../admin";
const signature = (v: any) => JSON.stringify([v?.vin, v?.plate, v?.make, v?.model, v?.year, v?.color]);
export const onDriverVehicleHistoryChanged = onDocumentWritten({ document: "drivers/{uid}", retry: true }, async event => {
  const before = event.data?.before.data() ?? {};
  const after = event.data?.after.data() ?? {};
  const previous: Record<string, any> = { current: before.vehicle, ...(before.savedVehicles ?? {}) };
  const next: Record<string, any> = { current: after.vehicle, ...(after.savedVehicles ?? {}) };
  for (const id of new Set([...Object.keys(previous), ...Object.keys(next)])) {
    if (signature(previous[id]) === signature(next[id])) continue;
    const ref = db.collection("drivers").doc(event.params.uid).collection("vehicleArchive");
    for (const [state, vehicle] of [["before_change", previous[id]], ["after_change", next[id]]] as const) {
      if (!vehicle?.make && !vehicle?.vin && !vehicle?.plate) continue;
      const key = createHash("sha256").update(`${event.id}:${id}:${state}`).digest("hex");
      await ref.doc(key).create({ driverUid: event.params.uid, vehicleId: id, vehicle, action: state, source: "vehicle_change_history", eventId: event.id, changedAt: event.time, recordedAt: FieldValue.serverTimestamp() }).catch(error => { if (error.code !== 6) throw error; });
    }
  }
});
