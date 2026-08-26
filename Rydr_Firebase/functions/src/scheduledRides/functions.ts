import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
  createScheduledRideRequestForUser,
  previewScheduledRidePriceForUser,
  respondToScheduledRideForUser,
  selectScheduledRideOfferForUser
} from "./service";

function uid(auth: { uid: string } | undefined): string {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in is required.");
  return auth.uid;
}

export const previewScheduledRidePrice = onCall((request) => previewScheduledRidePriceForUser(uid(request.auth), request.data));
export const createScheduledRideRequest = onCall((request) => createScheduledRideRequestForUser(uid(request.auth), request.data));
export const respondToScheduledRide = onCall((request) => respondToScheduledRideForUser(uid(request.auth), request.data));
export const selectScheduledRideOffer = onCall((request) => selectScheduledRideOfferForUser(uid(request.auth), request.data));
