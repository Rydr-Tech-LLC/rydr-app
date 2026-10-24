const {
  applicationDefault,
  cert,
  getApp,
  getApps,
  initializeApp
} = require("firebase-admin/app");
const {
  FieldValue,
  GeoPoint,
  Timestamp,
  getFirestore: getAdminFirestore
} = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { getAuth } = require("firebase-admin/auth");

// Keep the service layer's established `admin.firestore.Timestamp`-style API
// while using Firebase Admin 14's modular entry points underneath.
const {configureWorkspaceSDK, appForWorkspace, authForWorkspace, appCheckForWorkspace, firestoreForWorkspace, storageForWorkspace, projectForWorkspace}=require("../../firebase/functions/src/services/firebaseWorkspace");
configureWorkspaceSDK(require);
function workspace(){return require("../services/workspaceContext").currentWorkspace();}
function firestoreFor(appInstance) { return firestoreForWorkspace(workspace(),appInstance); }
firestoreFor.FieldValue = FieldValue;
firestoreFor.GeoPoint = GeoPoint;
firestoreFor.Timestamp = Timestamp;

const admin = {
  credential: { applicationDefault, cert },
  get apps() { return getApps(); },
  app: getApp,
  initializeApp,
  firestore: firestoreFor,
  storage: (appInstance) => storageForWorkspace(workspace(),appInstance),
  auth: (appInstance) => authForWorkspace(workspace(),appInstance),
  appCheck: (appInstance) => appCheckForWorkspace(workspace(), appInstance)
};

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
    db = getAdminFirestore(app);
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
  db = getAdminFirestore(app);

  return { app, db };
}

function getFirestore() {
  const {app}=initializeFirebase();
  return firestoreFor(app);
}

function getStorageBucket() {
  initializeFirebase();
  return admin.storage().bucket();
}

function storageBucketCandidates() {
  const projectId = projectForWorkspace(workspace());
  return [
    workspace() === "live-beta" ? process.env.FIREBASE_STORAGE_BUCKET : null,
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
  getControlFirestore: () => { const {app}=initializeFirebase(); return getAdminFirestore(app); },
  getStorageBucket,
  getStorageBucketsForReads
};
