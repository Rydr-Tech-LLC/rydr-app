"use strict";
let load = (id) => require(id);
function configureWorkspaceSDK(loader) { load = loader; }
const PROJECTS = Object.freeze({test: "rydr-test-c7ec1", "live-beta": "rydrapp-c7ec1"});
function projectForWorkspace(workspace) {
  if (!Object.hasOwn(PROJECTS, workspace)) throw new Error("invalid_workspace");
  return PROJECTS[workspace];
}
function workspaceFromProject(projectId) {
  const entry = Object.entries(PROJECTS).find(([, id]) => id === projectId);
  if (!entry) throw Object.assign(new Error("untrusted_auth_project"), {statusCode: 401});
  return entry[0];
}
const federatedApps = new WeakMap();
const firestoreClients = new WeakMap();
const storageClients = new WeakMap();
function appForWorkspace(workspace, baseApp) {
  const {getApp, getApps, initializeApp} = load("firebase-admin/app");
  const base = baseApp || getApp();
  const projectId = projectForWorkspace(workspace);
  if (base.options.projectId === projectId || process.env.GCLOUD_PROJECT === projectId && base.name === "[DEFAULT]") return base;
  const name = `rydr-workspace-${workspace}`;
  const existing = getApps().find(app => app.name === name);
  if (existing) return existing;
  const federation = workspace === "test"
    ? require("./workspaceCredential").federatedTestCredential(base.options.credential,load) : null;
  const app = initializeApp({
    credential: federation?.credential || base.options.credential,
    ...(federation ? {serviceAccountId: federation.serviceAccountId} : {}),
    projectId,
    storageBucket: `${projectId}.firebasestorage.app`,
  }, name);
  if (federation) federatedApps.set(app, federation);
  return app;
}
function authForWorkspace(workspace, baseApp) {
  return load("firebase-admin/auth").getAuth(appForWorkspace(workspace, baseApp));
}
function firestoreForWorkspace(workspace, baseApp) {
  const app = appForWorkspace(workspace, baseApp);
  const databaseId = workspace === "test" ? "(default)" : "live-beta";
  const federation = federatedApps.get(app);
  if (!federation) return load("firebase-admin/firestore").getFirestore(app, databaseId);
  if (!firestoreClients.has(app)) {
    const {Firestore} = load("@google-cloud/firestore");
    firestoreClients.set(app, new Firestore({projectId: projectForWorkspace(workspace), databaseId,
      auth: federation.googleAuth}));
  }
  return firestoreClients.get(app);
}
function storageForWorkspace(workspace, baseApp) {
  const app = appForWorkspace(workspace, baseApp);
  const federation = federatedApps.get(app);
  if (!federation) return load("firebase-admin/storage").getStorage(app);
  if (!storageClients.has(app)) {
    const {Storage} = load("@google-cloud/storage");
    const client = new Storage({projectId: projectForWorkspace(workspace), authClient: federation.authClient});
    storageClients.set(app, {bucket: (name) => client.bucket(name || app.options.storageBucket)});
  }
  return storageClients.get(app);
}
async function verifyWorkspaceToken(token, workspace, baseApp, allowStaff = false) {
  try {
    const auth = authForWorkspace(workspace, baseApp);
    const decoded = await auth.verifyIdToken(token, true);
    const user = await auth.getUser(decoded.uid);
    if (user.disabled) throw Object.assign(new Error("account_disabled"), {statusCode:403});
    return {decoded, user, staff: false};
  } catch (error) {
    if (!allowStaff || workspace === "live-beta") throw error;
    const auth = authForWorkspace("live-beta", baseApp);
    const decoded = await auth.verifyIdToken(token, true);
    if (decoded.admin !== true && decoded.role !== "admin") throw error;
    const user = await auth.getUser(decoded.uid);
    if (user.disabled) throw Object.assign(new Error("account_disabled"), {statusCode:403});
    return {decoded, user, staff: true};
  }
}
module.exports = {configureWorkspaceSDK, PROJECTS, projectForWorkspace, workspaceFromProject, appForWorkspace, authForWorkspace, firestoreForWorkspace, storageForWorkspace, verifyWorkspaceToken};
