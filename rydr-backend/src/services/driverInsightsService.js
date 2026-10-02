const { getFirestore } = require("../config/firebase");
function millis(v) { return v?.toMillis?.() ?? (Number(v?._seconds) * 1000 || 0); }
async function driverEarningsSummary({ uid, db = getFirestore(), now = new Date() }) {
  const [rides, requests] = await Promise.all([
    db.collection("rides").where("driverId", "==", uid).where("status", "==", "completed").orderBy("updatedAt", "desc").limit(200).get(),
    db.collection("rideRequests").where("driverId", "==", uid).limit(200).get()
  ]);
  const today = new Date(now); today.setHours(0,0,0,0); const month = new Date(now.getFullYear(), now.getMonth(), 1); const week = new Date(today); week.setDate(today.getDate() - ((today.getDay()+6)%7));
  let todayCents=0, weekCents=0, monthCents=0; const recentTrips=[];
  for (const doc of rides.docs) { const d=doc.data(); const cents=Number(d.driverPayoutCents)||0; const when=millis(d.completedAt ?? d.updatedAt); if(when>=month.getTime())monthCents+=cents;if(when>=week.getTime())weekCents+=cents;if(when>=today.getTime())todayCents+=cents;if(recentTrips.length<5)recentTrips.push({id:doc.id,pickup:d.pickup??"Pickup",dropoff:d.dropoff??"Drop-off",fareCents:cents,completedAt:when?new Date(when).toISOString():null}); }
  let accepted=0, declined=0; for(const doc of requests.docs){const s=String(doc.data().status||"").toLowerCase();if(s==="accepted")accepted++;else if(s==="declined"||s==="missed")declined++;}
  return { todayCents, weekCents, monthCents, acceptanceRate: accepted+declined ? accepted/(accepted+declined):null, completionRate: accepted ? Math.min(1,rides.size/accepted):null, recentTrips };
}
module.exports={driverEarningsSummary};
