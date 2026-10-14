const {test}=require('node:test');const assert=require('node:assert/strict');const {spawn}=require('node:child_process');const net=require('node:net');const os=require('node:os');const path=require('node:path');
test('promotion endpoints reject unauthenticated access before contacting Firebase or Stripe',async()=>{
 const port=await new Promise(resolve=>{const server=net.createServer();server.listen(0,'127.0.0.1',()=>{const p=server.address().port;server.close(()=>resolve(p));});});
 const child=spawn(process.execPath,[path.join(__dirname,'../index.js')],{cwd:os.tmpdir(),env:{PATH:process.env.PATH,PORT:String(port),STRIPE_SECRET_KEY:'sk_test_no_network',STRIPE_PUBLISHABLE_KEY:'pk_test_no_network',STRIPE_MODE:'test',RYDR_INTERNAL_SERVICE_TOKEN:'fixture-internal-token'},stdio:['ignore','pipe','pipe']});
 try{
  await new Promise((resolve,reject)=>{const timeout=setTimeout(()=>reject(Error('Service startup timeout')),10000);child.once('exit',code=>{clearTimeout(timeout);reject(Error(`Service exited ${code}`));});child.stdout.on('data',b=>{if(b.toString().includes('Server running')){clearTimeout(timeout);resolve();}});});
  const base=`http://127.0.0.1:${port}`;
  for(const [url,options] of [['/promotions/account',{}],['/promotions/enroll',{method:'POST',headers:{'content-type':'application/json'},body:'{"code":"FAKE","audience":"drivers"}'}],['/internal/rides/ride/promotions/settle',{method:'POST'}]]){
   const response=await fetch(base+url,options);assert.equal(response.status,401,url);
  }
  const invalid=await fetch(base+'/internal/rides/bad%20id/promotions/settle',{method:'POST',headers:{'x-rydr-internal-token':'fixture-internal-token'}});assert.equal(invalid.status,400);
 }finally{child.kill('SIGTERM');await new Promise(resolve=>child.exitCode!=null?resolve():child.once('exit',resolve));}
});
