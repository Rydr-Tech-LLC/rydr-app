"use client";
import {useWorkspaceRouter as useRouter} from "@/components/WorkspaceContext";
import { useState } from "react";

type Vehicle = { id: string; make?: string; model?: string; year?: string | number; vin?: string; plate?: string; color?: string };
type Archive = { id: string; vehicle: Vehicle; action: string; date: string; actor?: string; reason?: string };
export default function DriverVehicles({ uid, vehicles, archive }: { uid: string; vehicles: Vehicle[]; archive: Archive[] }) {
  const router = useRouter();
  const [selected, setSelected] = useState<Vehicle | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  async function remove() {
    if (!selected) return;
    setBusy(true); setError("");
    try {
      const response = await fetch(`/api/drivers/${uid}/vehicles`, { method: "DELETE", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ vehicleId: selected.id, vin: selected.vin, plate: selected.plate, reason }) });
      const body = await response.json();
      if (!response.ok) { setError(body.error ?? "Removal failed."); return; }
      setSelected(null); setReason(""); router.refresh();
    } catch { setError("Could not reach the server. Try again."); }
    finally { setBusy(false); }
  }
  return <section className="rounded-lg border border-line bg-white p-5 space-y-4">
    <h2 className="text-sm font-semibold">Vehicles &amp; security archive</h2>
    <p className="text-xs text-muted">Removal preserves the vehicle, VIN and plate in the staff-only archive. Current vehicles can only be removed when the driver is offline with no assigned rides.</p>
    <div className="grid gap-3 sm:grid-cols-2">{vehicles.map(vehicle => <div key={vehicle.id} className="rounded-lg border border-line bg-grouped p-3 space-y-2">
      <p className="text-xs font-semibold">{vehicle.id === "current" ? "Current" : "Saved"} · {[vehicle.year, vehicle.make, vehicle.model].filter(Boolean).join(" ")}</p>
      <p className="text-xs">VIN: {vehicle.vin || "Not recorded"}<br />Plate: {vehicle.plate || "Not recorded"}<br />Color: {vehicle.color || "Not recorded"}</p>
      <button className="rounded-md border border-rydr-burgundy px-3 py-1.5 text-xs text-rydr-burgundy" onClick={() => {setSelected(vehicle); setError(""); setReason("");}}>Remove vehicle</button>
    </div>)}</div>
    {selected && <div className="rounded-lg border border-rydr-burgundy p-3 space-y-3" role="dialog" aria-label="Confirm vehicle removal">
      <p className="text-sm">Remove {selected.make} {selected.model}, plate {selected.plate}? Its security record will remain archived.{selected.id === "current" && " Driving access will require another approved current vehicle."}</p>
      <label className="block text-xs">Removal reason<textarea value={reason} onChange={e=>setReason(e.target.value)} maxLength={1000} className="mt-1 w-full rounded-md border border-line p-2" /></label>
      <div className="flex gap-2"><button disabled={busy || !reason.trim()} onClick={remove} className="rounded-md bg-rydr-burgundy px-3 py-2 text-xs text-white disabled:opacity-40">{busy ? "Removing…" : "Confirm removal"}</button><button disabled={busy} onClick={()=>setSelected(null)} className="rounded-md border border-line px-3 py-2 text-xs">Cancel</button></div>
    </div>}
    {error && <p role="alert" className="text-xs text-rydr-red">{error}</p>}
    <details><summary className="cursor-pointer text-sm font-semibold">Vehicle and plate history ({archive.length})</summary>
      <div className="mt-3 overflow-x-auto"><table className="w-full text-left text-xs"><thead><tr><th>Date (UTC)</th><th>Vehicle / VIN</th><th>Plate</th><th>Event / actor</th><th>Reason</th></tr></thead><tbody>{archive.map(record=><tr key={record.id} className="border-t border-line"><td className="py-3 pr-3">{record.date}</td><td className="pr-3">{[record.vehicle.year,record.vehicle.make,record.vehicle.model].filter(Boolean).join(" ")}<br />{record.vehicle.vin || "VIN not recorded"}</td><td className="pr-3">{record.vehicle.plate || "Not recorded"}</td><td className="pr-3">{record.action.replaceAll("_"," ")}<br />{record.actor || "System history"}</td><td>{record.reason || "—"}</td></tr>)}</tbody></table>{!archive.length && <p className="py-3 text-muted">Changes and removals will appear here. Older vehicle details cannot be reconstructed if they were overwritten before history tracking began.</p>}</div>
    </details>
  </section>;
}
