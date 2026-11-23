const assert = require("node:assert/strict");
const { test } = require("node:test");
const { reviewDriverProof } = require("../lib/services/documentReviewService");

const vin = "1HGBH41JXMN109186";
const profile = {
  firstName: "Jamie",
  lastName: "Example",
  license: { number: "012345678", state: "GA" },
  vehicle: { vin, make: "Chevrolet", model: "Equinox", year: 2022 }
};
const license = `RIVERSIDE, RI 02901
GEORGIA
DRIVER’S LICENSE
4d DL NO. 012345678
9 CLASS C
4a ISS 06/07/2024
4b EXP 06/07/2099
1 EXAMPLE
2 JAMIE`;
const insurance = `Auto Insurance Identification Card
Policy Information
Policy Number: AB-123456
Named Insured
Jamie Q Example
Effective Date: 01/15/2024
Expiration Date: 01/15/2099
Vehicle: 2022 CHEVROLET EQUINOX
VIN: ${vin}`;
const registration = `STATE OF GEORGIA MOTOR VEHICLE REGISTRATION
EXPIRATION
DATE 6/27/2099
MAKE
CHEV
MODEL EQUINOX
YR 2022
VIN ${vin}
INSURANCE STATUS Valid`;

test("license reads the issuing header, class, dates and complete license number", () => {
  const { extractedFields, decision } = reviewDriverProof("driverLicense", license, profile);
  assert.deepEqual(extractedFields, {
    documentType: "driverLicense", licenseClass: "C", state: "GA", issuanceDate: "2024-06-07",
    expirationDate: "2099-06-07", licenseNumber: "012345678", name: "JAMIE EXAMPLE"
  });
  assert.equal(decision.status, "approved", decision.reviewReason);
  assert.equal(reviewDriverProof("driverLicense", license.replace("GEORGIA", "RHODE ISLAND"), profile).decision.status, "needs_review");
  assert.equal(reviewDriverProof("driverLicense", license.replace("DRIVER’S LICENSE", "IDENTIFICATION CARD"), profile).decision.status, "needs_review");
  assert.equal(reviewDriverProof("driverLicense", license.replace("GEORGIA", ""), profile).extractedFields.state, undefined);
});

test("insurance reads the policy fields without mistaking labels for names or numbers", () => {
  const { extractedFields, decision } = reviewDriverProof("insurance", insurance, profile);
  assert.deepEqual(extractedFields, {
    documentType: "insurance", insurancePolicyNumber: "AB-123456", effectiveDate: "2024-01-15",
    expirationDate: "2099-01-15", vin, policyholderFirstName: "Jamie", policyholderLastName: "Example",
    vehicleYear: "2022", vehicleMake: "Chevrolet", vehicleModel: "Equinox"
  });
  assert.equal(decision.status, "approved", decision.reviewReason);
  const missing = reviewDriverProof("insurance", insurance.replace("Policy Number: AB-123456\n", "").replace("Jamie Q Example\n", ""), profile);
  assert.equal(missing.extractedFields.insurancePolicyNumber, undefined);
  assert.equal(missing.extractedFields.policyholderFirstName, undefined);
  assert.equal(missing.decision.status, "needs_review");
  assert.equal(reviewDriverProof("insurance", insurance.replace(vin, "1M8GDM9AXKP042788"), profile).decision.status, "needs_review");
  assert.equal(reviewDriverProof("insurance", insurance + "\nMake Ford", profile).decision.status, "needs_review");
});

test("registration checks the printed VIN, make, model, year and expiration", () => {
  const { extractedFields, decision } = reviewDriverProof("registration", registration, profile);
  assert.deepEqual(extractedFields, {
    documentType: "registration", expirationDate: "2099-06-27",
    vin, vehicleMake: "CHEV", vehicleModel: "EQUINOX", vehicleYear: "2022"
  });
  assert.equal(decision.status, "approved", decision.reviewReason);
  assert.equal(reviewDriverProof("registration", registration.replace("EQUINOX", "TRAVERSE"), profile).decision.status, "needs_review");
  assert.equal(reviewDriverProof("registration", registration.replace("YR 2022", ""), profile).decision.status, "needs_review");
  assert.equal(reviewDriverProof("registration", registration.replace("6/27/2099", "2/30/2099"), profile).decision.status, "needs_review");
  assert.equal(reviewDriverProof("registration", registration.replace("6/27/2099", "6/27/2020"), profile).decision.status, "expired");
});

test("unreadable and incomplete images enter manual review", () => {
  for (const kind of ["driverLicense", "registration", "insurance"]) {
    assert.equal(reviewDriverProof(kind, "", profile).decision.status, "needs_review");
  }
  assert.equal(reviewDriverProof("driverLicense", license.replace("9 CLASS C", ""), profile).decision.status, "needs_review");
  assert.equal(reviewDriverProof("insurance", insurance.replace("Effective Date: 01/15/2024", ""), profile).decision.status, "needs_review");
});
