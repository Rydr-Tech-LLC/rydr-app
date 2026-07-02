const admin = require("firebase-admin");

let app;
let db;

function getCredential() {
  const projectId = process.env.FIREBASE_ADMIN_PROJECT_ID || process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_ADMIN_CLIENT_EMAIL || process.env.FIREBASE_CLIENT_EMAIL;
  const privateKey = process.env.FIREBASE_ADMIN_PRIVATE_KEY || process.env.FIREBASE_PRIVATE_KEY;

  if (projectId && clientEmail && privateKey) {
    return admin.credential.cert({
      projectId,
      clientEmail,
      privateKey: privateKey.replace(/\\n/g, "\n")
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
  const projectId = process.env.FIREBASE_ADMIN_PROJECT_ID || process.env.FIREBASE_PROJECT_ID;
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
