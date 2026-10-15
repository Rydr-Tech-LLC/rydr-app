import { isDeepStrictEqual } from "node:util";
import { db } from "../admin";
import { getVehicleSpecificationMatch } from "./vehicleSpecificationsService";
import { evaluateVehicleEligibility } from "./vehicleEligibilityService";
import { selectedVehicleKey } from "./prestineLibraryPolicy";

export async function refreshDriverVehicleEligibility(ref: FirebaseFirestore.DocumentReference): Promise<FirebaseFirestore.DocumentData | null | undefined> {
  const initial = await ref.get();
  const driver = initial.data();
  if (!driver?.vehicle) return driver;
  const match = await getVehicleSpecificationMatch(driver.vehicle);
  const config = await db.collection("platformConfig").doc("rydrExecutive").get();
  return db.runTransaction(async tx => {
    const current = await tx.get(ref);
    const data = current.data();
    // A replacement vehicle gets its own trigger; never publish the old one's qualification.
    if (!data?.vehicle || selectedVehicleKey(data.vehicle) !== selectedVehicleKey(driver.vehicle)) return null;
    const vehicle = { ...data.vehicle, specifications: match.specifications, libraryEligibility: match.libraryEligibility };
    const eligibility = evaluateVehicleEligibility({ ...vehicle, vehicle, libraryRideTypes: match.eligibleRideTypes, approvedRideTypes: data.approvedRideTypes, premiumReview: data.premiumReview, executiveConfig: config.data() ?? {}, rating: data.rating });
    const selected = (data.selectedRideTypes ?? []).filter((type: string) => eligibility.rideTypes.includes(type));
    const updated = { ...data, vehicle, qualifiedRideTypes: eligibility.rideTypes, supportedRideTypes: eligibility.rideTypes, selectedRideTypes: selected,
      vehicleEligibility: { ...data.vehicleEligibility, ...eligibility, matchedVehicleId: match.libraryEligibility.libraryVehicleId }, premiumEligibility: eligibility.premium };
    if (!isDeepStrictEqual(data.vehicle, vehicle) || !isDeepStrictEqual(data.qualifiedRideTypes, updated.qualifiedRideTypes)
      || !isDeepStrictEqual(data.supportedRideTypes, updated.supportedRideTypes) || !isDeepStrictEqual(data.selectedRideTypes, selected)
      || !isDeepStrictEqual(data.vehicleEligibility, updated.vehicleEligibility) || !isDeepStrictEqual(data.premiumEligibility, updated.premiumEligibility)) {
      tx.update(ref, { vehicle, qualifiedRideTypes: updated.qualifiedRideTypes, supportedRideTypes: updated.supportedRideTypes, selectedRideTypes: selected, vehicleEligibility: updated.vehicleEligibility, premiumEligibility: updated.premiumEligibility });
    }
    return updated;
  });
}
