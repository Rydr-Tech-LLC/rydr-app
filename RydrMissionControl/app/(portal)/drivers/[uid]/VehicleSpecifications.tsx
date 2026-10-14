"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
export default function VehicleSpecifications({uid, specs, vehicle}:{uid:string;specs:any;vehicle:any}) {
 const router=useRouter();const [busy,setBusy]=useState(false);const [message,setMessage]=useState('');
 return <section className="rounded-lg border border-line bg-white p-5 space-y-3"><h2 className="text-sm font-semibold">Vehicle specifications for approval</h2>
 <div className="grid gap-3 sm:grid-cols-3 text-xs"><p><strong>Total seats including driver</strong><br/>{specs.seatCategory} {specs.seatCapacity!=null&&`(${specs.seatCapacity} total)`}<br/>{specs.passengerCapacity!=null?`${specs.passengerCapacity} rider seats`:'Capacity needs verification'}</p><p><strong>Luxury classification</strong><br/>{specs.luxuryClassification === 'unverified' ? 'Not reviewed' : specs.luxuryClassification}<br/>Prestine still requires vehicle-specific approval.</p><p><strong>Evidence</strong><br/>{specs.source.replaceAll('_',' ')}<br/>{specs.evidenceReference??'No library evidence recorded'}</p></div>
 {specs.conflict&&<p role="alert" className="text-xs text-rydr-red">VIN and library seating disagree. Resolve the configuration before approval.</p>}
 <p className="text-xs text-muted">VIN data may omit seats and does not establish luxury status. Unknown capacity requires manufacturer evidence. XL requires 7–8 total seats; 8+ alone is not sufficient.</p>
 <div className="flex gap-3"><button disabled={busy||!vehicle?.vin} className="rounded border border-line px-3 py-2 text-xs" onClick={async()=>{setBusy(true);setMessage('');try{const r=await fetch(`/api/drivers/${uid}/vehicle-specifications`,{method:'POST'});const data=await r.json();if(!r.ok)setMessage(data.error);else{setMessage('VIN seating details refreshed.');router.refresh();}}catch{setMessage('Could not refresh specifications.');}finally{setBusy(false);}}}>{busy?'Checking VIN…':'Refresh VIN specifications'}</button><Link className="rounded border border-line px-3 py-2 text-xs" href={`/vehicle-library?make=${encodeURIComponent(vehicle?.make??'')}&model=${encodeURIComponent(vehicle?.model??'')}`}>Review matching library entries</Link></div>{message&&<p role="status" className="text-xs">{message}</p>}
 </section>;
}
