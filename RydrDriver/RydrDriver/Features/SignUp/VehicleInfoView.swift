//
//  VehicleInfoView.swift
//  Rydr Driver
//
//  Step 5 of driver signup: Vehicle & Documents. Extracted out of
//  DriverSignupCoordinator.swift and restyled to match the premium
//  onboarding mockup (icon-prefixed fields, fuel-type segmented control,
//  eligibility banner, two-column upload boxes, reassurance card, shared
//  step indicator).
//

import SwiftUI
import PhotosUI

struct VehicleInfoView: View {
    @Binding var make: String
    @Binding var model: String
    @Binding var year: String
    @Binding var fuelType: String
    @Binding var plate: String
    @Binding var registrationDoc: PhotosPickerItem?
    @Binding var insuranceCard: PhotosPickerItem?

    var currentStep: Int = 5
    var totalSteps: Int = 8

    var onNext: () -> Void

    private var eligibility: DriverVehicleEligibility {
        DriverVehicleEligibility.evaluate(make: make, model: model, year: year, fuelType: fuelType)
    }

    private var isValid: Bool {
        !make.trimmingCharacters(in: .whitespaces).isEmpty
        && !model.trimmingCharacters(in: .whitespaces).isEmpty
        && !year.trimmingCharacters(in: .whitespaces).isEmpty
        && !plate.trimmingCharacters(in: .whitespaces).isEmpty
        && registrationDoc != nil && insuranceCard != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                DriverOnboardingStepIndicator(currentStep: currentStep, totalSteps: totalSteps, stepTitle: "Vehicle & Documents")

                VStack(spacing: 8) {
                    Text("Vehicle & Documents")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Styles.rydrGradient)
                    Text("Tell us about the vehicle you'll be driving with Rydr.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    HStack {
                        Image(systemName: "car.fill").foregroundColor(.gray)
                        TextField("Make", text: $make)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))

                    HStack {
                        Image(systemName: "car.side.fill").foregroundColor(.gray)
                        TextField("Model", text: $model)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))

                    HStack {
                        Image(systemName: "calendar").foregroundColor(.gray)
                        TextField("Year", text: $year).keyboardType(.numberPad)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))

                    Picker("Fuel type", selection: $fuelType) {
                        ForEach(DriverVehicleFuelType.allCases) { type in
                            Text(type.rawValue).tag(type.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Image(systemName: "number").foregroundColor(.gray)
                        TextField("Plate Number", text: $plate)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Styles.rydrGradient)
                        Text("Eligible ride types").font(.headline)
                    }
                    if eligibility.eligibleRideTypes.isEmpty {
                        Text("Manual review required before this vehicle can receive standard Rydr requests.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            ForEach(eligibility.eligibleRideTypes, id: \.self) { rideType in
                                Text(rideType)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.red.opacity(0.14)))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))

                HStack(spacing: 14) {
                    PhotosPicker(selection: $registrationDoc, matching: .images) {
                        UploadBox(label: registrationDoc == nil ? "Upload Registration" : "Registration ✓", systemImage: registrationDoc == nil ? "doc.fill" : "checkmark.circle.fill")
                    }
                    PhotosPicker(selection: $insuranceCard, matching: .images) {
                        UploadBox(label: insuranceCard == nil ? "Upload Insurance" : "Insurance ✓", systemImage: insuranceCard == nil ? "doc.fill" : "checkmark.circle.fill")
                    }
                }

                SignupContinueButton(title: "Continue", isEnabled: isValid, action: onNext)

                SignupInfoCard(
                    icon: "lock.shield.fill",
                    title: "Your information is secure",
                    message: "Vehicle documents are encrypted and used only to confirm your eligibility to drive."
                )

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
        }
        .background(Color(.systemBackground))
        .hideKeyboardOnTap()
    }
}
