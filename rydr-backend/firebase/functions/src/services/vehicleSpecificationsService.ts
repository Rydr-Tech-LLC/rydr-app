import { vehicleLibraryService } from "./vehicleLibraryService";
import { exactLibraryEntry, resolveSpecifications } from "./vehicleSpecificationPolicy";
export async function getVehicleSpecificationMatch(vehicle: Record<string, any>) {
  const entries = await vehicleLibraryService.findCandidates(vehicle.make, vehicle.model);
  const entry = exactLibraryEntry(entries, vehicle);
  return { specifications: resolveSpecifications(vehicle, entry), eligibleRideTypes: entry?.eligibleRideTypes ?? [] };
}
