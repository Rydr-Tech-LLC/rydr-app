import { bindPrestineLibrary } from "./prestineLibraryPolicy";
import { vehicleLibraryService } from "./vehicleLibraryService";
import { exactLibraryEntry, resolveSpecifications } from "./vehicleSpecificationPolicy";
export async function getVehicleSpecificationMatch(vehicle: Record<string, any>) {
  const entries = typeof vehicle.make === "string" && vehicle.make.trim() && typeof vehicle.model === "string" && vehicle.model.trim()
    ? await vehicleLibraryService.findCandidates(vehicle.make, vehicle.model) : [];
  const entry = exactLibraryEntry(entries, vehicle);
  return { libraryEligibility: bindPrestineLibrary(vehicle, entry), specifications: resolveSpecifications(vehicle, entry), eligibleRideTypes: entry?.eligibleRideTypes ?? [] };
}
