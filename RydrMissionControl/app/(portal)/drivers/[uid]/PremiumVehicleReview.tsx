"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
const documents = [
  ["driverLicense", "Current Georgia driver license", true],
  ["backgroundScreening", "Annual criminal, driving-history and sex-offender screening", true],
  ["carrierAuthority", "Georgia Class B Limousine Carrier Certificate", false],
  ["commercialInsurance", "Commercial insurance covering Rydr operations", true],
  ["limoRegistration", "Georgia Limousine registration / LM plate", true],
  ["forHireQualification", "DDS For-Hire endorsement OR qualifying background certification", true],
  ["safetyInspection", "Annual Georgia DPS vehicle inspection", true],
  ["carrierRegistration", "GIMC or applicable UCR registration", true],
  ["carrierMarkings", "Required vehicle carrier identification markings", false],
  ["professionalService", "Professional service training and conduct review", false],
  ["airportAuthorization", "ATL permit / decal / transponder (airport pickups only)", true]
] as const;
export default function PremiumVehicleReview({ uid, initial, assessment, specifications, vehicleBodyStyle }: { uid: string; initial: any; assessment: any; specifications?: any; vehicleBodyStyle?: string }) {
  const router = useRouter();
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const date = (value: unknown) => typeof value === "string" ? value.slice(0, 10) : "";
  return <section className="rounded-2xl border border-line bg-white p-5 space-y-4">
    <h2 className="text-lg font-semibold">Prestine vehicle approval</h2>
    <p className="text-sm text-muted">Prestine accepts any color. New approvals require model year {assessment.minimumYear} or newer; existing vehicle approvals receive two additional years. Executive requires black exterior, black leather or vegan-leather interior, professional service and verified commercial documents. Executive uses a five-year vehicle age limit and remains paused until funding approval.</p>
    <p className="rounded-xl bg-amber-50 p-3 text-sm">SUV and Sedan describe the vehicle body, not its passenger capacity. A five-seat luxury SUV can serve Prestine SUV. XL separately requires six rider seats plus the driver. Library eligibility is a model recommendation; approve this specific vehicle here to enable its Prestine ride type in the driver app.</p>
    <div className="text-sm">Prestine: {assessment.prestine.eligible ? "Qualified" : assessment.prestine.issues.join(" · ")}<br />Executive: {assessment.executive.eligible ? "Verification ready (service remains paused)" : assessment.executive.issues.join(" · ")}</div>
    <form className="space-y-3" onSubmit={async event => {
      event.preventDefault(); setBusy(true); setMessage("");
      const form = new FormData(event.currentTarget);
      const checked = (key: string) => form.get(key) === "on";
      const payload: any = { bodyType: form.get("bodyType"), specificationEvidence: String(form.get("specificationEvidence") ?? ""), seatCapacity: Number(form.get("seatCapacity")), conditionEvidence: form.get("conditionEvidence"), conditionExpiresAt: form.get("conditionExpiresAt"), documents: {} };
      for (const key of ["luxuryVehicleApproved", "conditionApproved", "blackLeatherInteriorApproved", "insuranceCoversRydr", "carrierIdentityMatched", "temporaryLimoRegistration", "approvePrestine"]) payload[key] = checked(key);
      for (const [key] of documents) payload.documents[key] = { verified: checked(`${key}.verified`), reference: form.get(`${key}.reference`), expiresAt: form.get(`${key}.expiresAt`), completedAt: form.get(`${key}.completedAt`) };
      for (const field of ["combinedLimit", "bodilyPerPerson", "bodilyPerAccident", "propertyDamage"]) payload.documents.commercialInsurance[field] = Number(form.get(field) ?? 0);
      try {
        const response = await fetch(`/api/drivers/${uid}/premium-review`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) });
        const data = await response.json(); if (!response.ok) throw new Error(data.error);
        setMessage("Vehicle approval saved. The driver app receives the approved Prestine SUV or Sedan ride type."); router.refresh();
      } catch (error) { setMessage(error instanceof Error ? error.message : "Review failed"); }
      finally { setBusy(false); }
    }}>
      <label className="block">Vehicle category <select name="bodyType" defaultValue={initial.bodyType ?? (["sedan", "suv"].includes(vehicleBodyStyle ?? "") ? vehicleBodyStyle : "")} className="border rounded p-2 ml-2"><option value="">Choose body style</option><option value="sedan">Prestine Sedan</option><option value="suv">Prestine SUV</option></select></label>
      <p className="text-xs text-muted">VIN / library seats: {specifications?.seatCategory ?? "Unknown"}; luxury classification: {specifications?.luxuryClassification ?? "unverified"}. Verify the exact configuration; do not infer capacity from SUV body style.</p>
      <label className="block text-sm">Seating and luxury evidence reference<input name="specificationEvidence" className="border rounded p-2 w-full" defaultValue={initial.specificationEvidence ?? specifications?.evidenceReference ?? ""} placeholder="Reviewed manufacturer / VIN configuration evidence" /></label>
      <label className="block text-sm">Seats including driver <input className="border rounded p-2 ml-2" name="seatCapacity" type="number" min="5" max="8" required defaultValue={initial.seatCapacity ?? specifications?.seatCapacity ?? ""} /></label>
      {([ ["luxuryVehicleApproved", "Approved luxury make/model"], ["conditionApproved", "Vehicle condition verified"], ["blackLeatherInteriorApproved", "Black leather / vegan-leather interior verified (Executive)"], ["insuranceCoversRydr", "Commercial insurance expressly covers Rydr Executive operations"], ["carrierIdentityMatched", "Carrier certificate, insured name and reviewed vehicle/plate match"], ["temporaryLimoRegistration", "Valid temporary limousine registration verified (only if no LM plate yet)"], ["approvePrestine", "Approve vehicle for Prestine"] ] as const).map(([key, label]) => <label className="block text-sm" key={key}><input type="checkbox" name={key} defaultChecked={key === "approvePrestine" ? Boolean(initial.prestineApprovedAt) : initial[key] === true} /> {label}</label>)}
      <label className="block text-sm">Condition evidence reference <input className="border rounded p-2 w-full" name="conditionEvidence" defaultValue={initial.conditionReview?.reference ?? ""} placeholder="Reviewed document, inspection or photo reference" /></label>
      <label className="block text-sm">Condition approval expires <input className="border rounded p-2 ml-2" name="conditionExpiresAt" type="date" defaultValue={date(initial.conditionReview?.expiresAt)} /></label>
      <details className="rounded-xl border border-line p-3"><summary className="cursor-pointer font-medium">Executive verification — service remains disabled</summary>
      <p className="text-sm text-muted">Verify the documents against the issuing authority and the named carrier/vehicle. Enter the private document or storage reference; do not enter passwords or credentials. Missing or expired evidence blocks Executive eligibility.</p>
      {documents.map(([key, label, expires]) => <fieldset className="border rounded-xl p-3 space-y-2" key={key}><legend className="text-sm font-medium">{label}</legend><label className="text-sm"><input type="checkbox" name={`${key}.verified`} defaultChecked={initial.documents?.[key]?.status === "verified"} /> Verified</label><input aria-label={`${label} evidence`} className="border rounded p-2 w-full" name={`${key}.reference`} placeholder="Evidence reference / certificate number" defaultValue={initial.documents?.[key]?.reference ?? ""} />{["backgroundScreening", "safetyInspection"].includes(key) && <label className="block text-sm">Report / inspection completed <input aria-label={`${label} completion date`} className="border rounded p-2" type="date" name={`${key}.completedAt`} defaultValue={date(initial.documents?.[key]?.completedAt)} /></label>}{expires && <input aria-label={`${label} expiry`} className="border rounded p-2" type="date" name={`${key}.expiresAt`} defaultValue={date(initial.documents?.[key]?.expiresAt)} />}</fieldset>)}
      <fieldset className="border rounded-xl p-3"><legend>Commercial insurance limits (USD)</legend>{([ ["combinedLimit", "Combined single limit"], ["bodilyPerPerson", "Bodily injury per person"], ["bodilyPerAccident", "Bodily injury per accident"], ["propertyDamage", "Property damage"] ] as const).map(([key, label]) => <label key={key} className="block text-sm">{label}<input name={key} type="number" min="0" className="border rounded p-2 ml-2" defaultValue={initial.documents?.commercialInsurance?.[key] ?? 0} /></label>)}</fieldset>
      </details>
      <button disabled={busy} className="rounded bg-rydr-burgundy text-white px-4 py-2">{busy ? "Saving…" : "Save verification"}</button>
      {message && <p role="status" className="text-sm">{message}</p>}
    </form>
  </section>;
}
