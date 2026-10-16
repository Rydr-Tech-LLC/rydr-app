"use strict";
const { AsyncLocalStorage } = require("node:async_hooks");
const { workspaceDefinition } = require("./workspacePolicy");
const storage = new AsyncLocalStorage();
function currentWorkspace() {
  return storage.getStore() || "test";
}
function runInWorkspace(id, callback) {
  workspaceDefinition(id);
  return storage.run(id, callback);
}
module.exports = { currentWorkspace, runInWorkspace };
