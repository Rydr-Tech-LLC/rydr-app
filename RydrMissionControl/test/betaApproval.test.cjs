const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const ts=require('typescript');
require.extensions['.ts']=(m,f)=>m._compile(ts.transpileModule(fs.readFileSync(f,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,f);
const {betaApprovedTemplate}=require('../src/services/notifications/templates/betaApproved.ts');
const links={riderTestFlightUrl:'https://testflight.apple.com/join/m7YMYqCn',driverTestFlightUrl:'https://testflight.apple.com/join/vGTnKeBV',discordInviteUrl:'https://discord.gg/kfUz52849',discordChannelUrl:'https://discord.com/channels/1521954500498165840/1530594332778954923'};
for(const role of ['rider','driver'])test(`${role} approval contains only the matching app and includes Discord join and support links`,()=>{
 const result=betaApprovedTemplate({...links,role,firstName:'<Tester>'});
 const own=role==='rider'?links.riderTestFlightUrl:links.driverTestFlightUrl;
 const other=role==='rider'?links.driverTestFlightUrl:links.riderTestFlightUrl;
 for(const content of [result.html,result.text]){assert.ok(content.includes(own));assert.ok(!content.includes(other));assert.ok(content.includes(links.discordInviteUrl));assert.ok(content.includes(links.discordChannelUrl));}
 assert.ok(result.html.includes('&lt;Tester&gt;'));assert.ok(!result.html.includes('<Tester>'));
});
test('Discord alone is not treated as an available app download',()=>{const r=betaApprovedTemplate({role:'rider',discordInviteUrl:links.discordInviteUrl});assert.match(r.html,/send the TestFlight download link/);assert.doesNotMatch(r.html,/Use the button below to open TestFlight/);});
