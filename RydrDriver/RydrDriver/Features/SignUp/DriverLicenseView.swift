//
//  DriverLicenseView.swift
//  Rydr Driver
//
//  Step 4 of driver signup: Driver's License capture. Extracted out of
//  DriverSignupCoordinator.swift and restyled to match the premium
//  onboarding mockup (icon-prefixed fields, two-column front/back upload
//  boxes, reassurance card, shared step indicator).
//

import SwiftUI
import PhotosUI

struct DriverLicenseView: View {
    @Binding var licenseNumber: String
    @Binding var licenseState: String
    @Binding var front: PhotosPickerItem?
    @Binding var back: PhotosPickerItem?

    var currentStep: Int = 4
    var totalSteps: Int = 8

    var onNext: () -> Void

    private let states = ["AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID","IL","IN","IA","KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT","VA","WA","WV","WI","WY"]

    private var isValid: Bool {
        !licenseNumber.trimmingCharacters(in: .whitespaces).isEmpty
        && !licenseState.isEmpty
        && front != nil && back != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                DriverOnboardingStepIndicator(currentStep: currentStep, totalSteps: totalSteps, stepTitle: "Driver's License")

                VStack(spacing: 8) {
                    Text("Driver's License")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Styles.rydrGradient)
                    Text("We need a quick photo of your license, front and back.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    HStack {
                        Image(systemName: "creditcard.fill").foregroundColor(.gray)
                        TextField("License Number", text: $licenseNumber)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))

                    HStack {
                        Image(systemName: "map.fill").foregroundColor(.gray)
                        Menu {
                            ForEach(states, id: \.self) { abbr in Button(abbr) { licenseState = abbr } }
                        } label: {
                            HStack {
                                Text(licenseState.isEmpty ? "State" : licenseState)
                                    .foregroundColor(licenseState.isEmpty ? .secondary : .primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                }

                HStack(spacing: 14) {
                    PhotosPicker(selection: $front, matching: .images) {
                        UploadBox(label: front == nil ? "Upload Front" : "Front ✓", systemImage: front == nil ? "camera.fill" : "checkmark.circle.fill")
                    }
                    PhotosPicker(selection: $back, matching: .images) {
                        UploadBox(label: back == nil ? "Upload Back" : "Back ✓", systemImage: back == nil ? "camera.fill" : "checkmark.circle.fill")
                    }
                }

                SignupContinueButton(title: "Continue", isEnabled: isValid, action: onNext)

                SignupInfoCard(
                    icon: "lock.shield.fill",
                    title: "Your information is secure",
                    message: "License photos are encrypted in transit and only used to verify your eligibility to drive."
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
