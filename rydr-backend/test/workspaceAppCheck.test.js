const {test} = require('node:test');
const assert = require('node:assert/strict');
const {configureWorkspaceSDK, appCheckForWorkspace} = require('../firebase/functions/src/services/firebaseWorkspace');

test('App Check validates only the selected workspace project, including concurrent requests', async () => {
  const live = {name:'[DEFAULT]', options:{projectId:'rydrapp-c7ec1'}};
  const sandbox = {name:'rydr-workspace-test', options:{projectId:'rydr-test-c7ec1'}};
  configureWorkspaceSDK(id => {
    if(id === 'firebase-admin/app') return {getApp:()=>live, getApps:()=>[live,sandbox]};
    if(id === 'firebase-admin/app-check') return {getAppCheck:app=>({
      verifyToken: async token => {
        await new Promise(resolve=>setImmediate(resolve));
        if(token !== app.options.projectId) throw new Error('wrong_project');
        return {appId:app.options.projectId};
      }
    })};
    throw new Error('Unexpected SDK dependency: '+id);
  });
  try {
    await Promise.all(Array.from({length:12}, async (_,index)=>{
      const workspace = index%2 ? 'test' : 'live-beta';
      const expected = workspace==='test' ? sandbox : live;
      const other = workspace==='test' ? live : sandbox;
      const check = appCheckForWorkspace(workspace);
      assert.equal((await check.verifyToken(expected.options.projectId)).appId,expected.options.projectId);
      await assert.rejects(check.verifyToken(other.options.projectId),/wrong_project/);
    }));
    assert.throws(()=>appCheckForWorkspace('invalid'),/invalid_workspace/);
  } finally { configureWorkspaceSDK(require); }
});
