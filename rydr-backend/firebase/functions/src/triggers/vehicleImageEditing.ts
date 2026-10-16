import { onRequest } from "../workspaceFunctions";
import { defineSecret } from "firebase-functions/params";
import { db, storage, controlFirebaseAuth } from "../admin";
import { VEHICLE_COLORS } from "../types";
import { editVehicleBackground } from "../services/vehicleImageEditing";
const key = defineSecret("OPENAI_API_KEY");
export const editVehicleLibraryBackground = onRequest({ secrets: [key], timeoutSeconds: 300, memory: "1GiB", maxInstances: 2, concurrency: 1 }, async (request, response) => {
  response.set("Cache-Control", "no-store");
  if (request.method !== "POST") { response.status(405).json({ error: "Use POST." }); return; }
  let decoded;
  try { decoded = await controlFirebaseAuth().verifySessionCookie((request.headers.authorization ?? "").replace(/^Bearer /, ""), true); }
  catch { response.status(401).json({ error: "Mission Control authentication required." }); return; }
  if (!(decoded.role === "admin" || decoded.admin === true) || !/@rydr-go\.com$/i.test(decoded.email ?? "")) { response.status(403).json({ error: "Administrator access required." }); return; }
  const { vehicleId, color, prompt } = request.body ?? {};
  if (typeof vehicleId !== "string" || !/^[a-z0-9_\-]{1,200}$/i.test(vehicleId) || (color && !(VEHICLE_COLORS as readonly string[]).includes(color)) || typeof prompt !== "string" || prompt.length > 1500) { response.status(400).json({ error: "Select a valid vehicle image and enter a prompt under 1500 characters." }); return; }
  try {
    const ref = db.collection("vehicleLibrary").doc(vehicleId);
    const entry = (await ref.get()).data();
    const path = color ? entry?.colorImages?.[color] : entry?.defaultImage;
    if (typeof path !== "string" || !path.startsWith("vehicle-library/")) { response.status(404).json({ error: "Upload or select a library image first." }); return; }
    const file = storage.bucket().file(path); const [metadata] = await file.getMetadata();
    if (Number(metadata.size) > 5 * 1024 * 1024) { response.status(400).json({ error: "Source image exceeds 5MB." }); return; }
    const [data] = await file.download();
    const edited = await editVehicleBackground({ data, contentType: metadata.contentType ?? "" }, key.value(), prompt);
    await db.collection("audits").add({ action: "Vehicle image background preview generated", targetType: "vehicleLibrary", targetId: vehicleId, adminUid: decoded.uid, color: color ?? null, sourcePath: path, prompt, createdAt: new Date() });
    response.type(edited.contentType).send(edited.data);
  } catch (error) { response.status(422).json({ error: error instanceof Error ? error.message : "Background editing failed." }); }
});
