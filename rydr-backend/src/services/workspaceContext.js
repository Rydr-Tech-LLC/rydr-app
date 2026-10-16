const {
  currentWorkspace,
  runInWorkspace,
} = require("../../firebase/functions/src/services/workspaceRuntime");
const {
  workspaceDefinition,
  accountWorkspace,
} = require("../../firebase/functions/src/services/workspacePolicy");
function workspaceRouting(req, res, next) {
  const match = req.url.match(/^\/workspaces\/([^/]+)(\/.*|$)/);
  if (!match) return runInWorkspace("test", next);
  try {
    workspaceDefinition(match[1]);
    req.url = match[2] || "/";
    req.rydrWorkspace = match[1];
    return runInWorkspace(match[1], next);
  } catch {
    return res.status(404).json({ error: "invalid_workspace" });
  }
}
async function assertAccountWorkspace(uid, phone, verifiedProjectId) {
  const { getControlFirestore } = require("../config/firebase");
  const policy = (
    await getControlFirestore()
      .collection("operationalSecurity")
      .doc("liveBetaAccess")
      .get()
  ).data();
  if (accountWorkspace(uid, phone, policy, verifiedProjectId) !== currentWorkspace())
    throw Object.assign(new Error("account_workspace_mismatch"), {
      statusCode: 403,
    });
}
module.exports = {
  currentWorkspace,
  runInWorkspace,
  workspaceRouting,
  assertAccountWorkspace,
};
