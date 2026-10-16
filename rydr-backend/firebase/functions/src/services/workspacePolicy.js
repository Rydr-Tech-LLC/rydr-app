"use strict";
const { phoneHash } = require("./liveBetaAccessPolicy");
const WORKSPACES = Object.freeze({
  test: {
    id: "test",
    databaseId: "(default)",
    stripeMode: "test",
    label: "Test",
  },
  "live-beta": {
    id: "live-beta",
    databaseId: "live-beta",
    stripeMode: "live",
    label: "Live Beta",
  },
});
function workspaceDefinition(id) {
  const value = Object.hasOwn(WORKSPACES, id) ? WORKSPACES[id] : null;
  if (!value) {
    const e = new Error("invalid_workspace");
    e.statusCode = 400;
    throw e;
  }
  return value;
}
function accountWorkspace(uid, phone, policy, verifiedProjectId) {
  if (policy?.authSeparationEnabled === true) {
    const {workspaceFromProject} = require("./firebaseWorkspace");
    const workspace = workspaceFromProject(verifiedProjectId);
    // Legacy Test identities in the Live project remain quarantined until migration retirement.
    if (workspace === "live-beta" && policy.blockedAuthUids?.includes(uid))
      throw Object.assign(new Error("legacy_test_identity_not_live"), {statusCode: 403});
    return workspace;
  }
  if (
    !policy ||
    policy.configured !== true ||
    !Array.isArray(policy.blockedAuthUids) ||
    !Array.isArray(policy.blockedPhoneHashes)
  )
    throw Object.assign(new Error("workspace_policy_unavailable"), {
      statusCode: 503,
    });
  const hash = phoneHash(phone);
  return policy.blockedAuthUids.includes(uid) ||
    (hash && policy.blockedPhoneHashes.includes(hash))
    ? "test"
    : "live-beta";
}
function workspaceServiceURL(base, id) {
  const url = String(base)
    .replace(/\/+$/, "")
    .replace(/\/workspaces\/(test|live-beta)$/, "");
  return url + "/workspaces/" + workspaceDefinition(id).id;
}
module.exports = {
  WORKSPACES,
  workspaceDefinition,
  accountWorkspace,
  workspaceServiceURL,
};
