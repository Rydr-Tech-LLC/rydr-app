const {test}=require('node:test');const assert=require('node:assert/strict');const {migrationReadiness}=require('../connectMigration');
test('migration planning reads every payout page and never permits automatic ID replacement',async()=>{
 let pages=0;const stripe={accounts:{retrieve:async()=>({id:'acct_owned',type:'express'})},balance:{retrieve:async()=>({available:[{amount:0}],pending:[{amount:10}]})},payouts:{list:async p=>{pages++;return p.starting_after?{data:[{id:'po_later',status:'in_transit'}],has_more:false}:{data:[{id:'po_first',status:'paid'}],has_more:true};}}};
 const plan=await migrationReadiness({stripe,profile:{stripeAccountId:'acct_owned',availableBalance:2,hasActiveRide:true}});
 assert.equal(pages,2);assert.equal(plan.automaticMigrationAllowed,false);assert.deepEqual(plan.blockers,['unsettled_stripe_balance','payout_in_flight','unsettled_driver_earnings','driver_must_be_offline_without_active_ride']);
});
test('no Stripe account is created or closed for a fresh or already managed driver',async()=>{
 assert.equal((await migrationReadiness({stripe:{},profile:{}})).action,'new_managed_account');
 assert.equal((await migrationReadiness({stripe:{accounts:{retrieve:async()=>({controller:{requirement_collection:'application',stripe_dashboard:{type:'none'}}})}},profile:{stripeAccountId:'acct_managed'}})).action,'already_managed');
});
