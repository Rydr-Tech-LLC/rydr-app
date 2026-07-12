//
//  NameDOBView.swift
//  Rydr Driver
//
//  Step 1 of driver signup: "Tell us about yourself" — first/last name and
//  date of birth. Extracted out of DriverSignupCoordinator.swift and
//  restyled to match the premium onboarding mockups (icon-prefixed fields,
//  18+ notice, reassurance card, gradient Continue button, shared step
//  indicator).
//

import SwiftUI

struct NameDOBView: View {
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var dob: Date

    var currentStep: Int = 1
    var totalSteps: Int = 8

    var onNext: () -> Void

    @FocusState private var focusedField: Field?
    private enum Field { case first, last }

    private var minimumDOB: Date {
        Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date()
    }
    private var maximumDOB: Date {
        Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    }
    private var isOldEnough: Bool { dob <= maximumDOB }
    private var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
        && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
        && isOldEnough
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                DriverOnboardingStepIndicator(currentStep: currentStep, totalSteps: totalSteps, stepTitle: "Legal Name")

                logoLockup

                VStack(spacing: 8) {
                    Text("Enter Your Legal Name")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Styles.rydrGradient)
                    Text("Use the name exactly as it appears on your driver license. This is used for identity verification, payouts, and background screening.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                VStack(spacing: 14) {
                    iconField(icon: "person.fill", placeholder: "Legal First Name", text: $firstName)
                        .focused($focusedField, equals: .first)
                    iconField(icon: "person.fill", placeholder: "Legal Last Name", text: $lastName)
                        .focused($focusedField, equals: .last)

                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.gray)
                        DatePicker("", selection: $dob, in: ...maximumDOB, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )

                    if !isOldEnough {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("You must be 18 or older to drive with Rydr.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                SignupContinueButton(title: "Continue", isEnabled: isValid, action: onNext)

                SignupInfoCard(
                    icon: "lock.shield.fill",
                    title: "Legal name required",
                    message: "Google or Apple may show a nickname. Rydr uses the legal name you enter here for verification and screening."
                )

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
        }
        .background(Color(.systemBackground))
        .hideKeyboardOnTap()
    }

    private var logoLockup: some View {
        VStack(spacing: 4) {
            Image("Rydr - Driver")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rydr Driver logo")
    }

    private func iconField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(.gray)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.words)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}
