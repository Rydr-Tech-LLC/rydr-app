function seatCount(value) {
  if (typeof value !== 'number' && typeof value !== 'string') return null;
  if (!/^\d{1,2}$/.test(String(value).trim())) return null;
  const count = Number(value);
  return Number.isInteger(count) && count >= 2 && count <= 99 ? count : null;
}
function seatCategory(value) { const count=seatCount(value); return count == null ? 'Unknown' : count >= 8 ? '8+' : String(count); }
function normalizeSpecifications(input = {}, actorUid) {
  const count = seatCount(input.seatCapacity);
  if (input.seatCapacity !== undefined && input.seatCapacity !== null && input.seatCapacity !== '' && count == null) throw new Error('Enter an exact seating capacity, including the driver.');
  const luxury = ['luxury','standard','unverified'].includes(input.luxuryClassification) ? input.luxuryClassification : 'unverified';
  const evidence = typeof input.evidenceReference === 'string' ? input.evidenceReference.trim().slice(0,1000) : '';
  const verified = input.verified === true;
  if (verified && (!evidence || count == null)) throw new Error('Verified specifications require seating capacity and a manufacturer/VIN evidence reference.');
  return { seatCapacity: count, seatCategory: seatCategory(count), luxuryClassification: luxury, evidenceReference: evidence, verified,
    verifiedBy: verified ? actorUid : null, verifiedAt: verified ? new Date().toISOString() : null };
}
function exactLibraryEntry(entries, vehicle) {
  const clean=value=>String(value??'').trim().replace(/\s+/g,' ').toLowerCase();
  const matches=entries.filter(e=>clean(e.make)===clean(vehicle.make)&&clean(e.model)===clean(vehicle.model)&&Number(vehicle.year)>=Number(e.yearStart)&&Number(vehicle.year)<=Number(e.yearEnd)&&(!e.trim||clean(e.trim)===clean(vehicle.trim)));
  matches.sort((a,b)=>Number(!!b.trim)-Number(!!a.trim)||(a.yearEnd-a.yearStart)-(b.yearEnd-b.yearStart));
  if(!matches.length)return null;
  const best=matches[0];const peers=matches.filter(e=>!!e.trim===!!best.trim&&e.yearEnd-e.yearStart===best.yearEnd-best.yearStart);
  if(peers.some(e=>JSON.stringify(e.specifications??{})!==JSON.stringify(best.specifications??{})||JSON.stringify(e.eligibleRideTypes??[])!==JSON.stringify(best.eligibleRideTypes??[])))return null;
  return best;
}
function resolveSpecifications(vehicle, entry) {
  const reported=seatCount(vehicle.vinReportedSeatCapacity);
  const reviewed=entry?.specifications?.verified===true?seatCount(entry.specifications.seatCapacity):null;
  const conflict=reported!=null&&reviewed!=null&&reported!==reviewed;
  const count=conflict?null:reported??reviewed;
  return { seatCapacity:count, seatCategory:seatCategory(count), passengerCapacity:count==null?null:count-1,
    vinReportedSeatCapacity:reported, vinReportedSeatRows:seatCount(vehicle.vinReportedSeatRows),
    source:conflict?'conflicting_sources':reported!=null?'nhtsa':reviewed!=null?'reviewed_library':'unknown',
    requiresReview:conflict||count==null, conflict,
    luxuryClassification:entry?.specifications?.verified===true?entry.specifications.luxuryClassification??'unverified':'unverified',
    libraryVehicleId:entry?.vehicleId??null, evidenceReference:entry?.specifications?.evidenceReference??null };
}
function xlCapacityAllowed(specifications) {return specifications?.conflict!==true && Number.isInteger(specifications?.seatCapacity) && specifications.seatCapacity >=7 && specifications.seatCapacity <=8 && ['nhtsa','reviewed_library'].includes(specifications.source);}
module.exports={seatCount,seatCategory,normalizeSpecifications,exactLibraryEntry,resolveSpecifications,xlCapacityAllowed};
