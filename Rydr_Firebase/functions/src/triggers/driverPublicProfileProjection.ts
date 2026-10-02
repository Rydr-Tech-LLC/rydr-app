import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { db, FieldValue } from "../admin";

export const onDriverPublicProfileProjection = onDocumentWritten("drivers/{uid}", async (event) => {
  const driver = event.data?.after.data();
  const uid = event.params.uid;
  const ref = db.collection("publicDriverProfiles").doc(uid);
  const cashHubRef = db.collection("cashHubDriverProfiles").doc(uid);
  if (!driver) {
    await Promise.all([ref.delete().catch(() => undefined), cashHubRef.delete().catch(() => undefined)]);
    return;
  }
  const fullName = String(driver.displayName ?? [driver.firstName, driver.lastName].filter(Boolean).join(" ") ?? "Rydr Driver").trim();
  const displayName = fullName.split(/\s+/)[0] || "Rydr Driver";
  const vehicle = driver.vehicle ?? {};
  await ref.set({
    uid,
    displayName,
    vehicleSummary: [vehicle.color, vehicle.year, vehicle.make, vehicle.model].filter(Boolean).join(" "),
    vehicleColor: vehicle.color ?? "",
    vehicleImageURL: vehicle.imageURL ?? driver.vehicleImageURL ?? "",
    tierRates: driver.tierRates ?? {},
    rideFilters: driver.rideFilters ?? {},
    eligibleRideTypes: driver.qualifiedRideTypes ?? driver.supportedRideTypes ?? [],
    profilePhotoURL: driver.profilePhotoURL ?? "",
    rating: driver.rating ?? 5,
    ratingCount: driver.ratingCount ?? 0,
    compliments: driver.compliments ?? [],
    updatedAt: FieldValue.serverTimestamp(),
    projectionOwner: "firebase_function"
  }, { merge: true });

  const configSnap = await db.collection("platformConfig").doc("cashRydrHub").get();
  const config = configSnap.exists ? configSnap.data() ?? {} : {};
  const currentTermsVersion = String(config.cashHubTermsVersion ?? "legacy");
  const acceptedTermsVersion = String(driver.cashHubTermsVersion ?? "");
  const approvalStatus = String(driver.driverApprovalStatus ?? driver.approvalStatus ?? "pending").toLowerCase();
  const accountStatus = String(driver.accountStatus ?? "").toLowerCase();
  const safetyReviewStatus = String(driver.safetyReviewStatus ?? "").toLowerCase();
  const approved = approvalStatus === "approved" || driver.isApproved === true;
  const safe = !["suspended", "deletion_requested", "removed"].includes(accountStatus)
    && safetyReviewStatus !== "suspended"
    && driver.safetyHold !== true;
  const accessStatus = String(driver.cashHubAccessStatus ?? "").toLowerCase();
  const accessActive = config.termsAcceptanceEnabled === true
    && driver.cashHubTermsAccepted === true
    && driver.cashHubOptedOut !== true
    && !["delinquent", "past_due", "review_required", "suspended", "revoked", "optedout", "opted_out"].includes(accessStatus)
    && (acceptedTermsVersion === currentTermsVersion || (!acceptedTermsVersion && currentTermsVersion === "legacy"));
  const vehicleInfo = [vehicle.color, vehicle.year, vehicle.make, vehicle.model].filter(Boolean).join(" ");
  await cashHubRef.set({
    driverUid: uid,
    driverName: fullName || "Cash Hub Driver",
    profilePhotoURL: driver.profilePhotoURL ?? driver.photoURL ?? "",
    vehicleInfo,
    cashHubRating: Number(driver.cashHubRating ?? driver.rating ?? 5),
    isIdentityVerified: driver.identityVerified === true || driver.stripeIdentityStatus === "verified",
    isLicenseVerified: driver.isLicenseVerified === true || driver.driverLicenseStatus === "approved",
    isRydrVerifiedDriver: approved && safe,
    isOnline: driver.isOnline === true && accessActive && approved && safe,
    availabilityStatus: driver.isOnline === true && accessActive && approved && safe
      ? String(driver.availabilityStatus ?? "available")
      : "offline",
    projectionOwner: "firebase_function",
    updatedAt: FieldValue.serverTimestamp()
  }, { merge: true });
});
