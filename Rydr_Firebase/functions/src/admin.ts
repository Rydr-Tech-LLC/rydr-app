import * as admin from "firebase-admin";

// Cloud Functions runs inside Google's infrastructure with ambient
// Application Default Credentials (the metadata server), so — unlike
// Mission Control on Vercel — there is no "missing credentials at build
// time" hazard here. A single eager `initializeApp()` at module load is
// the standard, safe pattern for Cloud Functions.
if (admin.apps.length === 0) {
  admin.initializeApp();
}

export const db = admin.firestore();
export const storage = admin.storage();
export const FieldValue = admin.firestore.FieldValue;
export const Timestamp = admin.firestore.Timestamp;
