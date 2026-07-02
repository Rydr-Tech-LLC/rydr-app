const admin = require("firebase-admin");

let app;
let db;

function getCredential() {
  const { FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY } = process.env;

  if (FIREBASE_PROJECT_ID && FIREBASE_CLIENT_EMAIL && FIREBASE_PRIVATE_KEY) {
    return admin.credential.cert({
      projectId: FIREBASE_PROJECT_ID,
      clientEmail: FIREBASE_CLIENT_EMAIL,
      privateKey: FIREBASE_PRIVATE_KEY.replace(/\\n/g, "\n")
    });
  }

  return admin.credential.applicationDefault();
}

function initializeFirebase() {
  if (app && db) {
    return { app, db };
  }

  if (admin.apps.length > 0) {
    app = admin.app();
    db = admin.firestore();
    return { app, db };
  }

  const options = {
    credential: getCredential()
  };

  if (process.env.FIREBASE_DATABASE_URL) {
    options.databaseURL = process.env.FIREBASE_DATABASE_URL;
  }

  if (process.env.FIREBASE_STORAGE_BUCKET) {
    options.storageBucket = process.env.FIREBASE_STORAGE_BUCKET;
  }

  app = admin.initializeApp(options);
  db = admin.firestore();

  return { app, db };
}

function getFirestore() {
  return initializeFirebase().db;
}

function getStorageBucket() {
  initializeFirebase();
  return admin.storage().bucket();
}

function storageBucketCandidates() {
  const projectId = process.env.FIREBASE_PROJECT_ID;
  return [
    process.env.FIREBASE_STORAGE_BUCKET,
    projectId ? `${projectId}.firebasestorage.app` : null,
    projectId ? `${projectId}.appspot.com` : null
  ].filter(Boolean);
}

function getStorageBucketsForReads() {
  initializeFirebase();
  const names = storageBucketCandidates();
  const uniqueNames = Array.from(new Set(names));

  if (uniqueNames.length === 0) {
    return [admin.storage().bucket()];
  }

  return uniqueNames.map((name) => admin.storage().bucket(name));
}

module.exports = {
  admin,
  initializeFirebase,
  getFirestore,
  getStorageBucket,
  getStorageBucketsForReads
};
