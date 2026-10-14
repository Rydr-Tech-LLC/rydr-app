"use client";
export default function VehicleSpecificationFields({ value, onChange }: { value: any; onChange: (value: any) => void }) {
  const update=(key:string,item:unknown)=>onChange({...value,[key]:item});
  return <fieldset className="rounded-lg border border-line bg-grouped p-4 space-y-3">
    <legend className="text-xs font-semibold">Seating &amp; luxury classification</legend>
    <p className="text-xs text-muted">Seats include the driver. Use a separate trim/year entry when configurations differ. An SUV is not automatically XL; luxury classification does not approve an individual driver for Prestine.</p>
    <div className="grid gap-3 sm:grid-cols-2">
      <label className="text-xs">Exact seats including driver<input type="number" min="4" max="99" value={value.seatCapacity ?? ""} onChange={e=>update("seatCapacity",e.target.value)} placeholder="Unknown until verified" className="mt-1 w-full rounded border border-line p-2" /><span className="text-muted">Shown as 4, 5, 6, 7, or 8+; enter the exact count.</span></label>
      <label className="text-xs">Luxury classification<select value={value.luxuryClassification ?? "unverified"} onChange={e=>update("luxuryClassification",e.target.value)} className="mt-1 w-full rounded border border-line p-2"><option value="unverified">Not reviewed</option><option value="standard">Standard</option><option value="luxury">Luxury</option></select></label>
    </div>
    <label className="block text-xs">Manufacturer specification / VIN evidence reference<input value={value.evidenceReference ?? ""} onChange={e=>update("evidenceReference",e.target.value)} placeholder="Manufacturer specification URL or reviewed document reference" className="mt-1 w-full rounded border border-line p-2" /></label>
    <label className="block text-xs"><input type="checkbox" checked={value.verified === true} onChange={e=>update("verified",e.target.checked)} /> I verified this configuration and classification against the source.</label>
  </fieldset>;
}
