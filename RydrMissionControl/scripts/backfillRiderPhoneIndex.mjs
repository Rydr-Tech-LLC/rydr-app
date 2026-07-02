import { cert, getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const projectId = process.env.FIREBASE_ADMIN_PROJECT_ID;
const clientEmail = process.env.FIREBASE_ADMIN_CLIENT_EMAIL;
const privateKey = process.env.FIREBASE_ADMIN_PRIVATE_KEY?.replace(/\\n/g, "\n");

if (!projectId || !clientEmail || !privateKey) {
  throw new Error(
    "Missing Firebase Admin credentials. Set FIREBASE_ADMIN_PROJECT_ID, " +
      "FIREBASE_ADMIN_CLIENT_EMAIL, and FIREBASE_ADMIN_PRIVATE_KEY."
  );
}

if (!getApps().length) {
  initializeApp({ credential: cert({ projectId, clientEmail, privateKey }) });
}

const db = getFirestore();

function normalizeE164(value) {
  const digits = String(value ?? "").replace(/\D/g, "");
  if (digits.length === 11 && digits.startsWith("1")) return `+${digits}`;
  if (digits.length === 10) return `+1${digits}`;
  return null;
}

const ridersSnap = await db.collection("riders").get();
let written = 0;
let skipped = 0;

for (const riderDoc of ridersSnap.docs) {
  const data = riderDoc.data();
  const phone = normalizeE164(data.phoneE164 ?? data.phoneNumber);
  if (!phone) {
    skipped += 1;
    continue;
  }

  const batch = db.batch();
  batch.set(db.collection("riders").doc(riderDoc.id), { phoneNumber: phone, phoneE164: phone }, { merge: true });
  batch.set(db.collection("riderPhoneIndex").doc(phone), {
    uid: riderDoc.id,
    createdAt: FieldValue.serverTimestamp()
  });
  await batch.commit();
  written += 1;
}

console.log(`Backfill complete. Indexed ${written} riders. Skipped ${skipped} riders without valid US phone numbers.`);
